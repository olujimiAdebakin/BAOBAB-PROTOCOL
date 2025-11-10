// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../security/SecurityBase.sol";
import {AutoDeleverageEngine} from "../trading/engines/AutoDeleverageEngine.sol";

/**
 * @title PositionManager
 * @author BAOBAB Protocol
 * @notice Manages perpetual positions, margin, and PnL calculations
 * @dev Integrates with AutoDeleverageEngine for ADL queue updates
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                      POSITION MANAGER
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
contract PositionManager is SecurityBase {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extended position data with ADL tracking
     * @param position Core position data from CommonStructs
     * @param lastUpdateTime Last time position was updated
     * @param accumulatedFunding Cumulative funding payments
     * @param isLiquidatable Whether position can be liquidated now
     * @param inADLQueue Whether position is in ADL queue
     */
    struct PositionData {
        CommonStructs.Position position;
        uint256 lastUpdateTime;
        int256 accumulatedFunding;
        bool isLiquidatable;
        bool inADLQueue;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice All positions by positionId
    mapping(bytes32 => PositionData) public positions;

    /// @notice User positions mapping (trader => positionIds[])
    mapping(address => bytes32[]) public userPositions;

    /// @notice Market positions mapping (marketId => positionIds[])
    mapping(bytes32 => bytes32[]) public marketPositions;

    /// @notice Total open interest per market per side
    mapping(bytes32 => mapping(CommonStructs.Side => uint256)) public openInterest;

    /// @notice Cross-margin accounts
    mapping(address => CommonStructs.Portfolio) public portfolios;

    /// @notice AutoDeleverageEngine reference
    AutoDeleverageEngine public adlEngine;

    /// @notice Oracle registry for price feeds
    address public oracleRegistry;

    /// @notice Trading engine (authorized to open/modify positions)
    address public tradingEngine;

    /// @notice Liquidation engine (authorized to liquidate)
    address public liquidationEngine;

    /// @notice Protocol admin
    address public BaobabAdmin;

    /// @notice Position ID counter
    uint256 private _positionIdCounter;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event PositionOpened(
        bytes32 indexed positionId,
        address indexed trader,
        bytes32 indexed marketId,
        CommonStructs.Side side,
        uint256 size,
        uint256 entryPrice,
        uint16 leverage
    );

    event PositionModified(bytes32 indexed positionId, uint256 newSize, uint256 newCollateral, int256 realizedPnL);

    event PositionClosed(
        bytes32 indexed positionId, address indexed trader, uint256 closePrice, int256 realizedPnL, bool isLiquidation
    );

    event PositionLiquidated(
        bytes32 indexed positionId,
        address indexed trader,
        address indexed liquidator,
        uint256 liquidationPrice,
        uint256 liquidationFee
    );

    event FundingPaid(bytes32 indexed positionId, int256 fundingAmount, int256 newFundingIndex);

    event ADLQueueStatusChanged(bytes32 indexed positionId, bool inQueue, uint256 adlScore);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error PositionManager__OnlyTradingEngine();
    error PositionManager__OnlyLiquidationEngine();
    error PositionManager__OnlyAdmin();
    error PositionManager__PositionNotFound();
    error PositionManager__InsufficientCollateral();
    error PositionManager__InvalidSize();
    error PositionManager__PositionNotLiquidatable();
    error PositionManager__Unauthorized();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor(address _admin, address _oracleRegistry, address _adlEngine) {
        BaobabAdmin = _admin;
        oracleRegistry = _oracleRegistry;
        adlEngine = AutoDeleverageEngine(_adlEngine);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyTradingEngine() {
        if (msg.sender != tradingEngine) revert PositionManager__OnlyTradingEngine();
        _;
    }

    modifier onlyLiquidationEngine() {
        if (msg.sender != liquidationEngine) revert PositionManager__OnlyLiquidationEngine();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != BaobabAdmin) revert PositionManager__OnlyAdmin();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    POSITION LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Open a new position
     * @param trader Trader address
     * @param marketId Market identifier
     * @param side LONG or SHORT
     * @param size Position size (18 decimals)
     * @param collateral Margin deposited (18 decimals)
     * @param entryPrice Entry price (18 decimals)
     * @param leverage Position leverage (1-100x)
     * @return positionId New position identifier
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

        // Generate position ID
        positionId = keccak256(abi.encodePacked(trader, marketId, _positionIdCounter++, block.timestamp));

        // Calculate liquidation price
        uint256 liquidationPrice = _calculateLiquidationPrice(side, entryPrice, collateral, size, leverage);

        // Create position
        CommonStructs.Position memory newPosition = CommonStructs.Position({
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
            liquidationPrice: liquidationPrice,
            openedAt: block.timestamp
        });

        positions[positionId] = PositionData({
            position: newPosition,
            lastUpdateTime: block.timestamp,
            accumulatedFunding: 0,
            isLiquidatable: false,
            inADLQueue: false
        });

        // Update mappings
        userPositions[trader].push(positionId);
        marketPositions[marketId].push(positionId);
        openInterest[marketId][side] += size;

        // Update portfolio
        _updatePortfolio(trader);

        emit PositionOpened(positionId, trader, marketId, side, size, entryPrice, leverage);
    }

    /**
     * @notice Modify existing position (add/reduce size or collateral)
     * @param positionId Position to modify
     * @param sizeDelta Change in size (positive = increase, negative = decrease)
     * @param collateralDelta Change in collateral
     * @param currentPrice Current market price for PnL calculation
     * @return realizedPnL Realized profit/loss if reducing size
     */
    function modifyPosition(bytes32 positionId, int256 sizeDelta, int256 collateralDelta, uint256 currentPrice)
        external
        onlyTradingEngine
        nonReentrant
        returns (int256 realizedPnL)
    {
        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

        CommonStructs.Position storage pos = posData.position;

        // Calculate current PnL before modification
        int256 currentPnL = _calculateUnrealizedPnL(pos, currentPrice);

        // Handle size change
        if (sizeDelta != 0) {
            if (sizeDelta > 0) {
                // Increase size
                pos.size += uint256(sizeDelta);
                openInterest[pos.marketId][pos.side] += uint256(sizeDelta);
            } else {
                // Reduce size - realize proportional PnL
                uint256 reduction = uint256(-sizeDelta);
                require(reduction <= pos.size, "Reduction exceeds size");

                uint256 proportionClosed = (reduction * 1e18) / pos.size;
                realizedPnL = (currentPnL * int256(proportionClosed)) / 1e18;

                pos.size -= reduction;
                openInterest[pos.marketId][pos.side] -= reduction;
            }
        }

        // Handle collateral change
        if (collateralDelta != 0) {
            if (collateralDelta > 0) {
                pos.collateral += uint256(collateralDelta);
            } else {
                uint256 withdrawal = uint256(-collateralDelta);
                require(withdrawal <= pos.collateral, "Insufficient collateral");
                pos.collateral -= withdrawal;
            }
        }

        // Recalculate liquidation price
        pos.liquidationPrice =
            _calculateLiquidationPrice(pos.side, pos.entryPrice, pos.collateral, pos.size, pos.leverage);

        // Update position
        posData.lastUpdateTime = block.timestamp;
        _updatePositionState(positionId, currentPrice);

        emit PositionModified(positionId, pos.size, pos.collateral, realizedPnL);
    }

    /**
     * @notice Close position completely
     * @param positionId Position to close
     * @param closePrice Closing price
     * @return realizedPnL Final realized profit/loss
     */
    function closePosition(bytes32 positionId, uint256 closePrice)
        external
        onlyTradingEngine
        nonReentrant
        returns (int256 realizedPnL)
    {
        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

        CommonStructs.Position storage pos = posData.position;

        // Calculate final PnL
        realizedPnL = _calculateUnrealizedPnL(pos, closePrice);
        realizedPnL += posData.accumulatedFunding;

        // Update open interest
        openInterest[pos.marketId][pos.side] -= pos.size;

        // Remove from ADL queue if present
        if (posData.inADLQueue) {
            adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        }

        // Remove from user positions
        _removeUserPosition(pos.trader, positionId);

        // Update portfolio
        _updatePortfolio(pos.trader);

        // Delete position
        delete positions[positionId];

        emit PositionClosed(positionId, pos.trader, closePrice, realizedPnL, false);
    }

    /**
     * @notice Force close position (called by ADL or liquidation)
     * @param positionId Position to close
     * @param closePrice Execution price
     * @param isLiquidation Whether this is a liquidation
     * @return realizedPnL Realized profit/loss
     */
    function forceClosePosition(bytes32 positionId, uint256 closePrice, bool isLiquidation)
        external
        nonReentrant
        returns (int256 realizedPnL)
    {
        // Only ADL engine or liquidation engine can force close
        if (msg.sender != address(adlEngine) && msg.sender != liquidationEngine) {
            revert PositionManager__Unauthorized();
        }

        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

        CommonStructs.Position storage pos = posData.position;

        // Calculate final PnL
        realizedPnL = _calculateUnrealizedPnL(pos, closePrice);
        realizedPnL += posData.accumulatedFunding;

        // Update open interest
        openInterest[pos.marketId][pos.side] -= pos.size;

        // Remove from ADL queue
        if (posData.inADLQueue) {
            adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        }

        // Remove from user positions
        _removeUserPosition(pos.trader, positionId);

        // Update portfolio
        _updatePortfolio(pos.trader);

        // Delete position
        delete positions[positionId];

        emit PositionClosed(positionId, pos.trader, closePrice, realizedPnL, isLiquidation);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    POSITION UPDATES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update position state and ADL queue
     * @param positionId Position to update
     * @param currentPrice Current market price
     * @dev Called periodically by keepers or on every trade
     */
    function updatePositionState(bytes32 positionId, uint256 currentPrice) external {
        _updatePositionState(positionId, currentPrice);
    }

    /**
     * @notice Batch update multiple positions
     * @param positionIds Array of position IDs
     * @param currentPrices Array of current prices
     */
    function batchUpdatePositions(bytes32[] calldata positionIds, uint256[] calldata currentPrices) external {
        require(positionIds.length == currentPrices.length, "Length mismatch");

        for (uint256 i = 0; i < positionIds.length; i++) {
            _updatePositionState(positionIds[i], currentPrices[i]);
        }
    }

    /**
     * @notice Apply funding payment to position
     * @param positionId Position to update
     * @param fundingRate Current funding rate (can be negative)
     */
    function applyFunding(bytes32 positionId, int256 fundingRate) external {
        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

        CommonStructs.Position storage pos = posData.position;

        // Calculate funding payment
        int256 fundingPayment = (int256(pos.size) * fundingRate) / 1e18;

        // Apply to position (shorts pay longs when positive, vice versa)
        if (pos.side == CommonStructs.Side.SHORT) {
            fundingPayment = -fundingPayment;
        }

        posData.accumulatedFunding += fundingPayment;
        pos.lastFundingIndex = fundingRate;

        emit FundingPaid(positionId, fundingPayment, fundingRate);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal position state update with ADL integration
     * @param positionId Position to update
     * @param currentPrice Current market price
     */
    function _updatePositionState(bytes32 positionId, uint256 currentPrice) internal {
        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) return;

        CommonStructs.Position storage pos = posData.position;

        // Calculate unrealized PnL
        int256 unrealizedPnL = _calculateUnrealizedPnL(pos, currentPrice);
        pos.unrealizedPnL = unrealizedPnL;

        // Check if liquidatable
        posData.isLiquidatable = currentPrice <= pos.liquidationPrice || currentPrice >= pos.liquidationPrice;

        posData.lastUpdateTime = block.timestamp;

        // Update ADL queue if profitable
        if (unrealizedPnL > 0) {
            uint256 pnlUint = uint256(unrealizedPnL);

            adlEngine.updateADLQueue(pos.marketId, positionId, pos.trader, pos.side, pnlUint, pos.leverage);

            if (!posData.inADLQueue) {
                posData.inADLQueue = true;
                emit ADLQueueStatusChanged(positionId, true, pnlUint * pos.leverage);
            }
        } else {
            // Remove from ADL queue if no longer profitable
            if (posData.inADLQueue) {
                adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
                posData.inADLQueue = false;
                emit ADLQueueStatusChanged(positionId, false, 0);
            }
        }
    }

    /**
     * @notice Calculate unrealized PnL for position
     * @param pos Position data
     * @param currentPrice Current market price
     * @return pnl Unrealized profit/loss (can be negative)
     */
    function _calculateUnrealizedPnL(CommonStructs.Position storage pos, uint256 currentPrice)
        internal
        view
        returns (int256 pnl)
    {
        int256 priceDiff;

        if (pos.side == CommonStructs.Side.LONG) {
            priceDiff = int256(currentPrice) - int256(pos.entryPrice);
        } else {
            priceDiff = int256(pos.entryPrice) - int256(currentPrice);
        }

        pnl = (priceDiff * int256(pos.size)) / 1e18;
    }

    /**
     * @notice Calculate liquidation price
     * @param side Position side
     * @param entryPrice Entry price
     * @param collateral Collateral amount
     * @param size Position size
     * @param leverage Leverage
     * @return liquidationPrice Price at which position gets liquidated
     */
    function _calculateLiquidationPrice(
        CommonStructs.Side side,
        uint256 entryPrice,
        uint256 collateral,
        uint256 size,
        uint16 leverage
    ) internal pure returns (uint256 liquidationPrice) {
        // Maintenance margin = 5% (500 bps)
        uint256 maintenanceMargin = (size * entryPrice * 500) / 10000;

        if (side == CommonStructs.Side.LONG) {
            // Long liquidation: entryPrice - (collateral - maintenanceMargin) / size
            if (collateral <= maintenanceMargin) return 0;
            uint256 buffer = collateral - maintenanceMargin;
            liquidationPrice = entryPrice - ((buffer * 1e18) / size);
        } else {
            // Short liquidation: entryPrice + (collateral - maintenanceMargin) / size
            if (collateral <= maintenanceMargin) return type(uint256).max;
            uint256 buffer = collateral - maintenanceMargin;
            liquidationPrice = entryPrice + ((buffer * 1e18) / size);
        }
    }

    /**
     * @notice Update trader's portfolio state
     * @param trader Trader address
     */
    function _updatePortfolio(address trader) internal {
        bytes32[] memory userPosIds = userPositions[trader];

        uint256 totalCollateral = 0;
        int256 totalUnrealizedPnL = 0;
        uint256 posCount = 0;

        for (uint256 i = 0; i < userPosIds.length; i++) {
            PositionData storage posData = positions[userPosIds[i]];
            if (posData.position.openedAt == 0) continue;

            totalCollateral += posData.position.collateral;
            totalUnrealizedPnL += posData.position.unrealizedPnL;
            posCount++;
        }

        uint256 marginRatio = totalCollateral > 0
            ? ((totalCollateral + uint256(totalUnrealizedPnL > 0 ? totalUnrealizedPnL : int256(0))) * 10000)
                / totalCollateral
            : 0;

        portfolios[trader] = CommonStructs.Portfolio({
            trader: trader,
            totalCollateral: totalCollateral,
            totalUnrealizedPnL: totalUnrealizedPnL,
            marginRatio: marginRatio,
            positionCount: posCount,
            lastUpdateTime: block.timestamp
        });
    }

    /**
     * @notice Remove position from user's position array
     * @param trader Trader address
     * @param positionId Position to remove
     */
    function _removeUserPosition(address trader, bytes32 positionId) internal {
        bytes32[] storage userPosIds = userPositions[trader];

        for (uint256 i = 0; i < userPosIds.length; i++) {
            if (userPosIds[i] == positionId) {
                userPosIds[i] = userPosIds[userPosIds.length - 1];
                userPosIds.pop();
                break;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set trading engine address
     * @param _tradingEngine Trading engine address
     */
    function setTradingEngine(address _tradingEngine) external onlyAdmin {
        tradingEngine = _tradingEngine;
    }

    /**
     * @notice Set liquidation engine address
     * @param _liquidationEngine Liquidation engine address
     */
    function setLiquidationEngine(address _liquidationEngine) external onlyAdmin {
        liquidationEngine = _liquidationEngine;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get position data
     * @param positionId Position identifier
     * @return posData Position data struct
     */
    function getPosition(bytes32 positionId) external view returns (PositionData memory posData) {
        return positions[positionId];
    }

    /**
     * @notice Get position size
     * @param positionId Position identifier
     * @return size Position size
     */
    function getPositionSize(bytes32 positionId) external view returns (uint256 size) {
        return positions[positionId].position.size;
    }

    /**
     * @notice Get all positions for a trader
     * @param trader Trader address
     * @return positionIds Array of position IDs
     */
    function getUserPositions(address trader) external view returns (bytes32[] memory positionIds) {
        return userPositions[trader];
    }

    /**
     * @notice Get portfolio for trader
     * @param trader Trader address
     * @return portfolio Portfolio struct
     */
    function getPortfolio(address trader) external view returns (CommonStructs.Portfolio memory portfolio) {
        return portfolios[trader];
    }

    /**
     * @notice Get open interest for market and side
     * @param marketId Market identifier
     * @param side Position side
     * @return oi Open interest amount
     */
    function getOpenInterest(bytes32 marketId, CommonStructs.Side side) external view returns (uint256 oi) {
        return openInterest[marketId][side];
    }
}
