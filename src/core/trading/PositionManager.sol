// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../security/SecurityBase.sol";
import {AutoDeleverageEngine} from "../trading/engines/AutoDeleverageEngine.sol";

/**
 * @title PositionManager
 * @author BAOBAB Protocol
 * @notice Core contract managing perpetual positions, margin, PnL, and liquidation
 * @dev Integrates with AutoDeleverageEngine for ADL queue updates. Uses market-specific risk tiers.
 * 
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                      POSITION MANAGER - FLOW DOCUMENTATION
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 * 
 * POSITION LIFECYCLE FLOW:
 * 
 * 1. POSITION OPENING:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Trading Engine  │ →  │ PositionManager  │ →  │ Risk Validation     │ →  │ Position Created│
 *    │ (openPosition)  │    │ (openPosition)   │    │ (leverage, margin)  │    │ & Events Emitted│
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 * 
 * 2. POSITION MANAGEMENT:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Trading Engine  │ →  │ PositionManager  │ →  │ PnL Calculation     │ →  │ Position Updated│
 *    │ (modifyPosition)│    │ (modifyPosition) │    │ & State Update      │    │ & Portfolio Sync│
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 * 
 * 3. RISK MANAGEMENT:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Price Updates   │ →  │ PositionManager  │ →  │ Liquidation Check   │ →  │ ADL Engine     │
 *    │ (oracle)        │    │ (updatePosition) │    │ & Margin Validation │    │ (if needed)     │
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 * 
 * 4. POSITION CLOSING:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Trading/Liquid. │ →  │ PositionManager  │ →  │ Final PnL Calc      │ →  │ Position Closed │
 *    │ Engine          │    │ (closePosition)  │    │ & Cleanup           │    │ & Funds Settled │
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 * 
 * KEY COMPONENTS:
 * - Market Risk Tiers: HIGH (0.5% MMR), MEDIUM (0.75% MMR), LOW (1% MMR)
 * - Dynamic Liquidation: Price-based using market-specific maintenance margin
 * - Portfolio Tracking: Real-time collateral and PnL aggregation per trader
 * - Open Interest: Market and side-specific position tracking
 * - ADL Integration: Auto-deleverage queue management for risk reduction
 * 
 * RISK PARAMETERS PER TIER:
 * ┌─────────────┬────────────┬────────────┬──────────────┐
 * │ Liquidity   │ MMR        │ IMR        │ Max Leverage │
 * │ Tier        │ (BPS)      │ (BPS)      │              │
 * ├─────────────┼────────────┼────────────┼──────────────┤
 * │ HIGH        │ 50 (0.5%)  │ 100 (1%)   │ 100x         │
 * │ MEDIUM      │ 75 (0.75%) │ 150 (1.5%) │ 66x          │
 * │ LOW         │ 100 (1%)   │ 200 (2%)   │ 50x          │
 * └─────────────┴────────────┴────────────┴──────────────┘
 */

contract PositionManager is SecurityBase {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          ENUMS & STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Liquidity tier determines risk parameters (MMR, IMR, max leverage)
     * @dev Three tiers with different risk profiles for market classification
     * - HIGH: Blue-chip assets (BTC, ETH) with lowest margin requirements
     * - MEDIUM: Established altcoins with moderate risk
     * - LOW: Events/illiquid markets with highest margin requirements
     */
    enum LiquidityTier {
        HIGH,   // 0.5% MMR (BTC, ETH) - Highest liquidity, lowest risk
        MEDIUM, // 0.75% MMR (altcoins) - Moderate liquidity and risk  
        LOW     // 1% MMR (events, illiquid) - Lowest liquidity, highest risk
    }

    /**
     * @notice Extended position with runtime state and funding tracking
     * @dev Contains core position data plus dynamic state for risk management
     * @param position Core position structure from CommonStructs
     * @param lastUpdateTime Timestamp of last position state update
     * @param accumulatedFunding Total funding payments accumulated
     * @param isLiquidatable Flag indicating if position can be liquidated
     * @param inADLQueue Flag indicating if position is in auto-deleverage queue
     */
    struct PositionData {
        CommonStructs.Position position;
        uint256 lastUpdateTime;
        int256 accumulatedFunding;
        bool isLiquidatable;
        bool inADLQueue;
    }

    /**
     * @notice Market-specific risk configuration
     * @dev Defines risk parameters per market based on liquidity tier
     * @param liquidityTier Risk classification tier
     * @param maintenanceMarginBps Maintenance Margin Rate in basis points (e.g., 50 = 0.5%)
     * @param initialMarginBps Initial Margin Rate in basis points (e.g., 100 = 1%)
     * @param maxLeverage Maximum allowed leverage for the market
     * @param isActive Flag indicating if market is active for trading
     */
    struct MarketRiskConfig {
        LiquidityTier liquidityTier;
        uint16 maintenanceMarginBps;
        uint16 initialMarginBps;
        uint16 maxLeverage;
        bool isActive;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Mapping of position ID to position data
    mapping(bytes32 => PositionData) public positions;
    
    /// @notice Mapping of trader address to their position IDs
    mapping(address => bytes32[]) public userPositions;
    
    /// @notice Mapping of market ID to position IDs in that market
    mapping(bytes32 => bytes32[]) public marketPositions;
    
    /// @notice Mapping of market ID and side to total open interest
    mapping(bytes32 => mapping(CommonStructs.Side => uint256)) public openInterest;
    
    /// @notice Mapping of market ID to risk configuration
    mapping(bytes32 => MarketRiskConfig) public marketRiskConfigs;
    
    /// @notice Mapping of trader address to their portfolio summary
    mapping(address => CommonStructs.Portfolio) public portfolios;

    /// @notice Auto-deleverage engine for risk management
    AutoDeleverageEngine public adlEngine;
    
    /// @notice Oracle registry contract for price feeds
    address public oracleRegistry;
    
    /// @notice Trading engine contract (authorized caller)
    address public tradingEngine;
    
    /// @notice Liquidation engine contract (authorized caller)  
    address public liquidationEngine;
    
    /// @notice Protocol admin address
    address public BaobabAdmin;

    /// @notice Counter for generating unique position IDs
    uint256 private _positionIdCounter;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new position is opened
     * @param positionId Unique identifier for the position
     * @param trader Address of the position owner
     * @param marketId Market identifier
     * @param side LONG or SHORT position
     * @param size Position size in base asset units
     * @param entryPrice Entry price in quote asset units
     * @param leverage Leverage used (e.g., 10 for 10x)
     */
    event PositionOpened(
        bytes32 indexed positionId,
        address indexed trader,
        bytes32 indexed marketId,
        CommonStructs.Side side,
        uint256 size,
        uint256 entryPrice,
        uint16 leverage
    );

    /**
     * @notice Emitted when a position is modified (size/collateral change)
     * @param positionId Unique identifier for the position
     * @param newSize New position size after modification
     * @param newCollateral New collateral amount after modification  
     * @param realizedPnL Realized profit/loss from the modification
     */
    event PositionModified(bytes32 indexed positionId, uint256 newSize, uint256 newCollateral, int256 realizedPnL);
    
    /**
     * @notice Emitted when a position is closed
     * @param positionId Unique identifier for the position
     * @param trader Address of the position owner
     * @param closePrice Closing price in quote asset units
     * @param realizedPnL Final realized profit/loss
     * @param isLiquidation Flag indicating if closure was due to liquidation
     */
    event PositionClosed(bytes32 indexed positionId, address indexed trader, uint256 closePrice, int256 realizedPnL, bool isLiquidation);
    
    /**
     * @notice Emitted when a position is liquidated
     * @param positionId Unique identifier for the position
     * @param trader Address of the position owner
     * @param liquidator Address of the liquidator
     * @param liquidationPrice Price at which liquidation occurred
     * @param liquidationFee Fee paid to the liquidator
     */
    event PositionLiquidated(bytes32 indexed positionId, address indexed trader, address indexed liquidator, uint256 liquidationPrice, uint256 liquidationFee);
    
    /**
     * @notice Emitted when funding is applied to a position
     * @param positionId Unique identifier for the position
     * @param fundingAmount Funding payment amount (positive = paid, negative = received)
     * @param newFundingIndex New funding index after application
     */
    event FundingPaid(bytes32 indexed positionId, int256 fundingAmount, int256 newFundingIndex);
    
    /**
     * @notice Emitted when a position's ADL queue status changes
     * @param positionId Unique identifier for the position
     * @param inQueue Flag indicating if position is in ADL queue
     * @param adlScore ADL risk score used for queue prioritization
     */
    event ADLQueueStatusChanged(bytes32 indexed positionId, bool inQueue, uint256 adlScore);
    
    /**
     * @notice Emitted when market risk parameters are configured
     * @param marketId Market identifier
     * @param tier Liquidity tier assigned to the market
     * @param mmrBps Maintenance Margin Rate in basis points
     * @param maxLev Maximum allowed leverage
     */
    event MarketRiskConfigured(bytes32 indexed marketId, LiquidityTier tier, uint16 mmrBps, uint16 maxLev);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when caller is not the authorized trading engine
    error PositionManager__OnlyTradingEngine();
    
    /// @notice Thrown when caller is not the authorized liquidation engine  
    error PositionManager__OnlyLiquidationEngine();
    
    /// @notice Thrown when caller is not the protocol admin
    error PositionManager__OnlyAdmin();
    
    /// @notice Thrown when position ID does not exist
    error PositionManager__PositionNotFound();
    
    /// @notice Thrown when collateral is insufficient for the operation
    error PositionManager__InsufficientCollateral();
    
    /// @notice Thrown when position size is invalid (zero or too large)
    error PositionManager__InvalidSize();
    
    /// @notice Thrown when attempting to liquidate a non-liquidatable position
    error PositionManager__PositionNotLiquidatable();
    
    /// @notice Thrown when caller is not authorized for the operation
    error PositionManager__Unauthorized();
    
    /// @notice Thrown when market risk configuration is not found
    error PositionManager__MarketNotConfigured();
    
    /// @notice Thrown when requested leverage exceeds market maximum
    error PositionManager__LeverageExceedsMax();
    
    /// @notice Thrown when initial margin requirements are not met
    error PositionManager__InsufficientInitialMargin();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the PositionManager with required dependencies
     * @dev Sets up admin, oracle registry, and ADL engine. Initializes default risk configs.
     * @param _admin Protocol admin address
     * @param _oracleRegistry Oracle registry contract address
     * @param _adlEngine Auto-deleverage engine contract address
     */
    constructor(address _admin, address _oracleRegistry, address _adlEngine) {
        if (_admin == address(0) || _oracleRegistry == address(0) || _adlEngine == address(0))
            revert PositionManager__Unauthorized();

        BaobabAdmin = _admin;
        oracleRegistry = _oracleRegistry;
        adlEngine = AutoDeleverageEngine(_adlEngine);

        _setDefaultRiskConfigs();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Restrict access to only the trading engine
     * @dev Used for position opening/modification functions
     */
    modifier onlyTradingEngine() {
        if (msg.sender != tradingEngine) revert PositionManager__OnlyTradingEngine();
        _;
    }

    /**
     * @notice Restrict access to only the liquidation engine
     * @dev Used for position liquidation functions
     */
    modifier onlyLiquidationEngine() {
        if (msg.sender != liquidationEngine) revert PositionManager__OnlyLiquidationEngine();
        _;
    }

    /**
     * @notice Restrict access to only the protocol admin
     * @dev Used for configuration and setup functions
     */
    modifier onlyAdmin() {
        if (msg.sender != BaobabAdmin) revert PositionManager__OnlyAdmin();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Configure risk parameters for a specific market
     * @dev Sets market-specific margin requirements and leverage limits based on liquidity tier
     * @param marketId Market identifier to configure
     * @param liquidityTier Risk classification tier (HIGH/MEDIUM/LOW)
     * @param maintenanceMarginBps Maintenance Margin Rate in basis points (e.g., 50 = 0.5%)
     * @param initialMarginBps Initial Margin Rate in basis points (e.g., 100 = 1%)
     * @param maxLeverage Maximum allowed leverage for the market
     * 
     * Requirements:
     * - Caller must be admin
     * - Margin rates must be valid (non-zero, IMR > MMR)
     * - Max leverage must be between 1 and 100
     * 
     * Emits {MarketRiskConfigured} event on success
     */
    function setMarketRiskConfig(
        bytes32 marketId,
        LiquidityTier liquidityTier,
        uint16 maintenanceMarginBps,
        uint16 initialMarginBps,
        uint16 maxLeverage
    ) external onlyAdmin {
        if (maintenanceMarginBps == 0 || initialMarginBps <= maintenanceMarginBps || maxLeverage == 0 || maxLeverage > 100)
            revert PositionManager__InvalidSize();

        marketRiskConfigs[marketId] = MarketRiskConfig({
            liquidityTier: liquidityTier,
            maintenanceMarginBps: maintenanceMarginBps,
            initialMarginBps: initialMarginBps,
            maxLeverage: maxLeverage,
            isActive: true
        });

        emit MarketRiskConfigured(marketId, liquidityTier, maintenanceMarginBps, maxLeverage);
    }

    /**
     * @notice Set the trading engine address
     * @dev Trading engine is authorized to open/modify positions
     * @param _tradingEngine Address of the trading engine contract
     */
    function setTradingEngine(address _tradingEngine) external onlyAdmin {
        tradingEngine = _tradingEngine;
    }

    /**
     * @notice Set the liquidation engine address  
     * @dev Liquidation engine is authorized to liquidate positions
     * @param _liquidationEngine Address of the liquidation engine contract
     */
    function setLiquidationEngine(address _liquidationEngine) external onlyAdmin {
        liquidationEngine = _liquidationEngine;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    POSITION LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Open a new perpetual position
     * @dev Creates a new position with validation for leverage, margin, and market configuration
     * @param trader Address of the position owner
     * @param marketId Market identifier
     * @param side LONG or SHORT position direction
     * @param size Position size in base asset units
     * @param collateral Collateral amount in quote asset units
     * @param entryPrice Entry price in quote asset units
     * @param leverage Leverage multiplier (e.g., 10 for 10x)
     * @return positionId Unique identifier for the created position
     *
     * Flow:
     * 1. Validate input parameters (non-zero size/collateral)
     * 2. Check market is active and configured
     * 3. Verify leverage doesn't exceed market maximum
     * 4. Calculate initial margin requirement and validate collateral
     * 5. Generate unique position ID
     * 6. Calculate liquidation price based on market MMR
     * 7. Store position data and update mappings
     * 8. Update open interest and portfolio
     * 9. Emit PositionOpened event
     *
     * Requirements:
     * - Caller must be trading engine
     * - Market must be active and configured
     * - Leverage must not exceed market maximum
     * - Collateral must meet initial margin requirement
     *
     * Emits {PositionOpened} event on success
     */
    function openPosition(
        address trader,
        bytes32 marketId,
        CommonStructs.Side side,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        uint16 leverage
    ) external onlyTradingEngine nonReentrant returns (bytes32 positionId) {
        if (size == 0) revert PositionManager__InvalidSize();
        if (collateral == 0) revert PositionManager__InsufficientCollateral();

        MarketRiskConfig memory config = marketRiskConfigs[marketId];
        if (!config.isActive) revert PositionManager__MarketNotConfigured();

        if (leverage > config.maxLeverage) revert PositionManager__LeverageExceedsMax();

        uint256 notional = (size * entryPrice) / 1e18;
        uint256 requiredIM = (notional * config.initialMarginBps) / 10000;
        if (collateral < requiredIM) revert PositionManager__InsufficientInitialMargin();

        positionId = keccak256(abi.encodePacked(trader, marketId, _positionIdCounter++, block.timestamp));

        uint256 liqPrice = _calculateLiquidationPrice(marketId, side, entryPrice, collateral, size);

        CommonStructs.Position memory pos = CommonStructs.Position({
            positionId: positionId,
            marketId: marketId,
            trader: trader,
            side: side,
            size: size,
            collateral: collateral,
            entryPrice: entryPrice,
            leverage: leverage,
            lastFundingIndex: 0,
            unrealizedPnL: 0,
            liquidationPrice: liqPrice,
            openedAt: block.timestamp
        });

        positions[positionId] = PositionData({
            position: pos,
            lastUpdateTime: block.timestamp,
            accumulatedFunding: 0,
            isLiquidatable: false,
            inADLQueue: false
        });

        userPositions[trader].push(positionId);
        marketPositions[marketId].push(positionId);
        openInterest[marketId][side] += size;

        _updatePortfolio(trader);

        emit PositionOpened(positionId, trader, marketId, side, size, entryPrice, leverage);
    }

    /**
     * @notice Modify an existing position's size or collateral
     * @dev Allows increasing/decreasing position size or adding/removing collateral
     * @param positionId Unique identifier of the position to modify
     * @param sizeDelta Change in position size (positive = increase, negative = decrease)
     * @param collateralDelta Change in collateral (positive = add, negative = remove)  
     * @param currentPrice Current market price for PnL calculation
     * @return realizedPnL Realized profit/loss from the modification
     *
     * Flow:
     * 1. Validate position exists
     * 2. Calculate current unrealized PnL
     * 3. Process size delta (increase or partial decrease)
     * 4. Process collateral delta (add or remove)
     * 5. Recalculate liquidation price with new parameters
     * 6. Update position state and timestamp
     * 7. Update portfolio summary
     * 8. Emit PositionModified event
     *
     * Requirements:
     * - Caller must be trading engine
     * - Position must exist
     * - Size reduction cannot exceed current position size
     * - Collateral removal cannot exceed available collateral
     *
     * Emits {PositionModified} event on success
     */
    function modifyPosition(
        bytes32 positionId,
        int256 sizeDelta,
        int256 collateralDelta,
        uint256 currentPrice
    ) external onlyTradingEngine nonReentrant returns (int256 realizedPnL) {
        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

        CommonStructs.Position storage pos = posData.position;
        int256 currentPnL = _calculateUnrealizedPnL(pos, currentPrice);

        if (sizeDelta != 0) {
            if (sizeDelta > 0) {
                pos.size += uint256(sizeDelta);
                openInterest[pos.marketId][pos.side] += uint256(sizeDelta);
            } else {
                uint256 reduction = uint256(-sizeDelta);
                if (reduction > pos.size) revert PositionManager__InvalidSize();

                uint256 proportion = (reduction * 1e18) / pos.size;
                realizedPnL = (currentPnL * int256(proportion)) / 1e18;

                pos.size -= reduction;
                openInterest[pos.marketId][pos.side] -= reduction;
            }
        }

        if (collateralDelta != 0) {
            if (collateralDelta > 0) {
                pos.collateral += uint256(collateralDelta);
            } else {
                uint256 withdrawal = uint256(-collateralDelta);
                if (withdrawal > pos.collateral) revert PositionManager__InsufficientCollateral();
                pos.collateral -= withdrawal;
            }
        }

        pos.liquidationPrice = _calculateLiquidationPrice(pos.marketId, pos.side, pos.entryPrice, pos.collateral, pos.size);
        posData.lastUpdateTime = block.timestamp;
        _updatePositionState(positionId, currentPrice);

        emit PositionModified(positionId, pos.size, pos.collateral, realizedPnL);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate liquidation price for a position
     * @dev Uses market-specific MMR to determine price level where position becomes under-collateralized
     * Formula for LONG: LiqPrice = EntryPrice - (Collateral - MMR) / Size
     * Formula for SHORT: LiqPrice = EntryPrice + (Collateral - MMR) / Size
     * @param marketId Market identifier for risk parameters
     * @param side Position direction (LONG/SHORT)
     * @param entryPrice Position entry price
     * @param collateral Collateral amount
     * @param size Position size
     * @return liqPrice Calculated liquidation price
     */
    function _calculateLiquidationPrice(
        bytes32 marketId,
        CommonStructs.Side side,
        uint256 entryPrice,
        uint256 collateral,
        uint256 size
    ) internal view returns (uint256 liqPrice) {
        if (size == 0) return side == CommonStructs.Side.LONG ? 0 : type(uint256).max;

        MarketRiskConfig memory config = marketRiskConfigs[marketId];
        uint16 mmrBps = config.maintenanceMarginBps > 0 ? config.maintenanceMarginBps : 50; // default 0.5%

        uint256 notional = (size * entryPrice) / 1e18;
        uint256 mmr = (notional * mmrBps) / 10000;

        if (collateral <= mmr) {
            return side == CommonStructs.Side.LONG ? 0 : type(uint256).max;
        }

        uint256 buffer = collateral - mmr;
        uint256 priceMove = (buffer * 1e18) / size;

        if (side == CommonStructs.Side.LONG) {
            liqPrice = priceMove >= entryPrice ? 1 : entryPrice - priceMove;
        } else {
            liqPrice = priceMove > type(uint256).max - entryPrice ? type(uint256).max : entryPrice + priceMove;
        }
    }

    /**
     * @notice Calculate unrealized PnL for a position
     * @dev Computes profit/loss based on current price vs entry price
     * For LONG: PnL = (CurrentPrice - EntryPrice) * Size
     * For SHORT: PnL = (EntryPrice - CurrentPrice) * Size
     * @param pos Position storage reference
     * @param price Current market price
     * @return pnl Unrealized profit/loss (positive = profit, negative = loss)
     */
    function _calculateUnrealizedPnL(CommonStructs.Position storage pos, uint256 price) internal view returns (int256) {
        int256 diff = pos.side == CommonStructs.Side.LONG
            ? int256(price) - int256(pos.entryPrice)
            : int256(pos.entryPrice) - int256(price);
        return (diff * int256(pos.size)) / 1e18;
    }

    /**
     * @notice Update trader's portfolio summary
     * @dev Aggregates collateral, PnL, and position count across all trader positions
     * @param trader Address of the trader to update
     */
    function _updatePortfolio(address trader) internal {
        bytes32[] memory ids = userPositions[trader];
        uint256 totalCol = 0;
        int256 totalPnL = 0;
        uint256 count = 0;

        for (uint256 i = 0; i < ids.length; i++) {
            PositionData storage pd = positions[ids[i]];
            if (pd.position.openedAt == 0) continue;
            totalCol += pd.position.collateral;
            totalPnL += pd.position.unrealizedPnL;
            count++;
        }

        uint256 marginRatio = totalCol > 0
            ? ((totalCol + uint256(totalPnL > 0 ? totalPnL : 0)) * 10000) / totalCol
            : 0;

        portfolios[trader] = CommonStructs.Portfolio({
            trader: trader,
            totalCollateral: totalCol,
            totalUnrealizedPnL: totalPnL,
            marginRatio: marginRatio,
            positionCount: count,
            lastUpdateTime: block.timestamp
        });
    }

    /**
     * @notice Remove a position from a trader's position list
     * @dev Used when closing positions to clean up storage
     * @param trader Address of the trader
     * @param positionId ID of the position to remove
     */
    function _removeUserPosition(address trader, bytes32 positionId) internal {
        bytes32[] storage list = userPositions[trader];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == positionId) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }
    }

    /**
     * @notice Set default risk configurations for common markets
     * @dev Can be extended to pre-configure known markets on deployment
     */
    function _setDefaultRiskConfigs() internal {
        // Defaults - can be extended with specific market configurations
        // Example: marketRiskConfigs[keccak256("BTC-USD")] = MarketRiskConfig(...)
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get full position data by ID
     * @param positionId Unique position identifier
     * @return PositionData structure containing position details and state
     */
    function getPosition(bytes32 positionId) external view returns (PositionData memory) {
        return positions[positionId];
    }

    /**
     * @notice Get position size by ID
     * @param positionId Unique position identifier
     * @return size Current position size in base asset units
     */
    function getPositionSize(bytes32 positionId) external view returns (uint256) {
        return positions[positionId].position.size;
    }

    /**
     * @notice Get all position IDs for a trader
     * @param trader Address of the trader
     * @return Array of position IDs owned by the trader
     */
    function getUserPositions(address trader) external view returns (bytes32[] memory) {
        return userPositions[trader];
    }

    /**
     * @notice Get portfolio summary for a trader
     * @param trader Address of the trader
     * @return Portfolio structure with aggregated position data
     */
    function getPortfolio(address trader) external view returns (CommonStructs.Portfolio memory) {
        return portfolios[trader];
    }

    /**
     * @notice Get open interest for a market and side
     * @param marketId Market identifier
     * @param side Position side (LONG/SHORT)
     * @return Total open interest in base asset units
     */
    function getOpenInterest(bytes32 marketId, CommonStructs.Side side) external view returns (uint256) {
        return openInterest[marketId][side];
    }
}