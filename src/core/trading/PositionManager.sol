// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../security/SecurityBase.sol";
import {AutoDeleverageEngine} from "../trading/engines/AutoDeleverageEngine.sol";
import {ICircuitBreaker} from "../../interfaces/ICircuitBreaker.sol";
import {IEmergencyPauser} from "../../interfaces/IEmergencyPauser.sol";
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";
import {ModuleIds} from "../../libraries/utils/ModuleIds.sol";
import {RateLimiter} from "../../security/RateLimiter.sol";
// import {FeeDistributor} from "../../fees/FeeDistributor.sol";
import {FeeCalculator} from "../../fees/FeeCalculator.sol";
import {IncentiveManager} from "../../fees/IncentiveManager.sol";
import {MarketRegistry} from "../markets/MarketRegistry.sol";

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
    ICircuitBreaker public circuitBreaker;
    IEmergencyPauser public emergencyPauser;
    AutoDeleverageEngine public adlEngine;
    RateLimiter public rateLimiter;
    FeeCalculator public feeCalculator;
    IncentiveManager public incentiveManager;
    MarketRegistry public marketRegistry;
    // FeeDistributor public feeDistributor;

    using AddressUtils for address;
    using ModuleIds for *;

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
        HIGH, // 0.5% MMR (BTC, ETH) - Highest liquidity, lowest risk
        MEDIUM, // 0.75% MMR (altcoins) - Moderate liquidity and risk
        LOW // 1% MMR (events, illiquid) - Lowest liquidity, highest risk

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

    /// @notice Configuration parameters for each perpetual market
    /// @dev Defines leverage limits, margin requirements, and funding behavior
    struct MarketConfig {
        uint16 maxLeverage; // Maximum allowed leverage (e.g., 100 = 100x)
        uint16 mmrBps; // Maintenance margin requirement in basis points (e.g., 50 = 0.5%)
        uint16 maxFundingRateBps; // Maximum funding rate per interval in basis points (e.g., 300 = 0.3%)
        bool fundingEnabled; // Whether funding payments are active for this market
        uint256 fundingInterval; // Time interval for funding updates (in seconds, e.g., 8h = 28800)
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Mapping of position ID to position data
    mapping(bytes32 => PositionData) public positions;

    /// @notice Mapping of trader address to their position IDs
    mapping(address => bytes32[]) public userPositions;

    /// @notice Mapping of position ID to owner address
    mapping(bytes32 => address) positionOwner;

    /// @notice Mapping of market ID to position IDs in that market
    mapping(bytes32 => bytes32[]) public marketPositions;

    /// @notice Mapping of market ID and side to total open interest
    mapping(bytes32 => mapping(CommonStructs.Side => uint256)) public openInterest;

    /// @notice Mapping of market ID to risk configuration
    mapping(bytes32 => MarketRiskConfig) public marketRiskConfigs;

    mapping(bytes32 => MarketConfig) public marketConfig;

    /// @notice Mapping of trader address to their portfolio summary
    mapping(address => CommonStructs.Portfolio) public portfolios;

    // /// @notice Auto-deleverage engine for risk management
    // AutoDeleverageEngine public adlEngine;

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

    address public fundingEngine;

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
    event PositionClosed(
        bytes32 indexed positionId, address indexed trader, uint256 closePrice, int256 realizedPnL, bool isLiquidation
    );

    /**
     * @notice Emitted when a position is liquidated
     * @param positionId Unique identifier for the position
     * @param trader Address of the position owner
     * @param liquidator Address of the liquidator
     * @param liquidationPrice Price at which liquidation occurred
     * @param liquidationFee Fee paid to the liquidator
     */
    event PositionLiquidated(
        bytes32 indexed positionId,
        address indexed trader,
        address indexed liquidator,
        uint256 liquidationPrice,
        uint256 liquidationFee
    );

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
    
    /// @notice Thrown when collateral is insufficient to cover trading fees
    error PositionManager__InsufficientCollateralForFee();

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

    /// @notice Thrown when an operation is attempted while the Emergency Pauser has the contract paused
    error PositionManager__Paused();

    /// @notice Thrown when an operation is attempted while the Circuit Breaker is active
    error PositionManager__CircuitBroken();

    error PositionManage__OnlyFundingEngine();

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
    constructor(
        address _admin,
        address _oracleRegistry,
        address _adlEngine,
        address _fundingEngine,
        address _circuitBreaker,
        address _emergencyPauser,
        address _incentiveManager,
        address _feeCalculator,
        address _marketRegistry
    ) {
        // if (_admin == address(0) || _oracleRegistry == address(0) || _adlEngine == address(0))
        //     revert PositionManager__Unauthorized();

        // Use library functions for validation
        _admin.validateNotZero();
        _oracleRegistry.validateContract();
        _adlEngine.validateContract();
        _fundingEngine.validateContract();
        _circuitBreaker.validateContract();
        _emergencyPauser.validateContract();
        _incentiveManager.validateContract();
        _feeCalculator.validateContract();
        _marketRegistry.validateContract();

        BaobabAdmin = _admin;
        oracleRegistry = _oracleRegistry;
        adlEngine = AutoDeleverageEngine(_adlEngine);
        fundingEngine = _fundingEngine;
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        emergencyPauser = IEmergencyPauser(_emergencyPauser);
        incentiveManager = IncentiveManager(_incentiveManager);
        feeCalculator = FeeCalculator(_feeCalculator);
        marketRegistry = MarketRegistry(_marketRegistry);

        _setDefaultRiskConfigs();
    }

    // ════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if the Pauser contract has paused operations.
     */
    modifier whenNotEmergencyPaused() {
        if (emergencyPauser.protocolPaused() || emergencyPauser.isModulePaused(ModuleIds.POSITION_MANAGER)) {
            revert PositionManager__Paused();
        }
        _;
    }

    /**
     * @notice Ensures the circuit breaker is not triggered for this market or globally.
     * @dev Use this on functions that *add new exposure* — e.g. opening or increasing positions.
     *      If either the global circuit breaker or the market-specific breaker is active,
     *      the transaction will revert.
     * @param marketId The unique identifier of the market to check.
     */
    modifier whenCircuitActivated(bytes32 marketId) {
        // Optionally validate market ID is nonzero
        // marketId.validateNotZero();

        // Prevent any operation if system-wide or market-specific breaker is active
        if (circuitBreaker.globalHalt() || circuitBreaker.isCircuitTripped(marketId)) {
            revert PositionManager__CircuitBroken();
        }
        _;
    }

    /**
     * @notice Ensures only the global circuit breaker state is respected.
     * @dev Use this on functions that *reduce exposure* — e.g. closing or decreasing positions.
     *      Allows users to safely exit markets that are tripped locally while
     *      still respecting global system halts.
     */
    modifier whenGlobalCircuitActivated() {
        if (circuitBreaker.globalHalt()) {
            revert PositionManager__CircuitBroken();
        }
        _;
    }

    /**
     * @notice Restrict access to only the trading engine
     * @dev Used for position opening/modification functions
     */
    modifier onlyTradingEngine() {
        msg.sender.validateNotZero();
        if (msg.sender != tradingEngine) revert PositionManager__OnlyTradingEngine();
        _;
    }

    /**
     * @notice Restrict access to only the liquidation engine
     * @dev Used for position liquidation functions
     */
    modifier onlyLiquidationEngine() {
        msg.sender.validateNotZero();
        if (msg.sender != liquidationEngine) revert PositionManager__OnlyLiquidationEngine();
        _;
    }

    /**
     * @notice Restrict access to only the protocol admin
     * @dev Used for configuration and setup functions
     */
    modifier onlyAdmin() {
        msg.sender.isZeroAssembly();
        if (msg.sender != BaobabAdmin) revert PositionManager__OnlyAdmin();
        _;
    }

    modifier onlyFundingEngine() {
        msg.sender.validateNotZero();
        if (msg.sender == fundingEngine) revert PositionManage__OnlyFundingEngine();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Set IncentiveManager address (admin only)
function setIncentiveManager(address _incentiveManager) external onlyAdmin {
    _incentiveManager.validateNotZero();
    incentiveManager = IncentiveManager(_incentiveManager);
}

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
    ) external onlyAdmin whenNotEmergencyPaused whenCircuitActivated(marketId) {
        if (
            maintenanceMarginBps == 0 || initialMarginBps <= maintenanceMarginBps || maxLeverage == 0
                || maxLeverage > 100
        ) {
            revert PositionManager__InvalidSize();
        }

        marketRiskConfigs[marketId] = MarketRiskConfig({
            liquidityTier: liquidityTier,
            maintenanceMarginBps: maintenanceMarginBps,
            initialMarginBps: initialMarginBps,
            maxLeverage: maxLeverage,
            isActive: true
        });

        emit MarketRiskConfigured(marketId, liquidityTier, maintenanceMarginBps, maxLeverage);
    }

    function setMarketConfig(
        bytes32 marketId,
        uint16 maxLev,
        uint16 mmr,
        uint16 maxFund,
        bool fundEnabled,
        uint256 interval
    ) external onlyAdmin whenNotEmergencyPaused whenCircuitActivated(marketId) {
        marketConfig[marketId] = MarketConfig({
            maxLeverage: maxLev,
            mmrBps: mmr,
            maxFundingRateBps: maxFund,
            fundingEnabled: fundEnabled,
            fundingInterval: interval
        });
    }

    /**
     * @notice Set the trading engine address
     * @dev Trading engine is authorized to open/modify positions
     * @param _tradingEngine Address of the trading engine contract
     */
    function setTradingEngine(address _tradingEngine)
        external
        onlyAdmin
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
    {
        _tradingEngine.validateContract();
        tradingEngine = _tradingEngine;
    }

    /**
     * @notice Set the liquidation engine address
     * @dev Liquidation engine is authorized to liquidate positions
     * @param _liquidationEngine Address of the liquidation engine contract
     */
    function setLiquidationEngine(address _liquidationEngine)
        external
        onlyAdmin
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
    {
        _liquidationEngine.validateContract();
        liquidationEngine = _liquidationEngine;
    }
    /**
     * @notice Set the funding engine address
     * @dev Funding engine is authorized to apply funding payments
     * @param _fundingEngine Address of the funding engine contract
     */

    function setFundingEngine(address _fundingEngine)
        external
        onlyAdmin
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
    {
        _fundingEngine.validateContract();
        fundingEngine = _fundingEngine;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    POSITION LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

 /**
 * @notice Open a new perpetual position with integrated fee calculation and incentive tracking
 * @dev Creates a new position with comprehensive validation including leverage, margin requirements,
 *      market configuration, fee deduction, and incentive program tracking. Automatically handles
 *      collateral adjustment for fees and records trade volume for reward programs.
 * @param trader Address of the position owner (must not be zero address)
 * @param marketId Market identifier (must correspond to an active market)
 * @param side LONG or SHORT position direction (determines profit/loss calculation)
 * @param size Position size in base asset units (must be > 0)
 * @param collateral Collateral amount in quote asset units (must cover fees + margin)
 * @param entryPrice Entry price in quote asset units (must be > 0 and reasonable)
 * @param leverage Leverage multiplier (e.g., 10 for 10x, must not exceed market maximum)
 * @return positionId Unique identifier for the created position (keccak256 hash)
 *
 * @dev Flow:
 * 1. Validate input parameters (non-zero size/collateral, valid market)
 * 2. Check market is active and configured with valid risk parameters
 * 3. Verify leverage doesn't exceed market maximum allowed
 * 4. Calculate taker trading fee and deduct from collateral
 * 5. Validate remaining collateral meets initial margin requirement
 * 6. Generate unique position ID using counter and timestamp
 * 7. Calculate liquidation price based on market maintenance margin ratio
 * 8. Store position data and update trader/market mappings
 * 9. Update open interest and portfolio metrics
 * 10. Record trade volume for incentive rewards (if program active)
 * 11. Initialize position in ADL system with zero PnL
 * 12. Emit PositionOpened and ADLQueueStatusChanged events
 *
 * @dev Requirements:
 * - Caller must be trading engine (onlyTradingEngine modifier)
 * - Market must be active and properly configured
 * - Leverage must not exceed market maximum allowed
 * - Collateral must cover trading fees + initial margin requirement
 * - Size must be positive and within market limits
 * - Global circuit breaker must be active (whenCircuitActivated modifier)
 * - No reentrancy allowed (nonReentrant modifier)
 *
 * @dev Emits:
 * - {PositionOpened} event with position details on success
 * - {ADLQueueStatusChanged} event indicating position not in ADL queue
 * - {TradeRecorded} event via IncentiveManager if program active
 *
 * @dev Reverts with:
 * - PositionManager__InvalidSize if size == 0
 * - PositionManager__InsufficientCollateral if collateral == 0
 * - PositionManager__MarketNotConfigured if market is inactive
 * - PositionManager__LeverageExceedsMax if leverage > market maximum
 * - InsufficientCollateralForFees if takerFee > collateral
 * - PositionManager__InsufficientInitialMargin if collateral < required initial margin
 */
function openPosition(
    address trader,
    bytes32 marketId,
    CommonStructs.Side side,
    uint256 size,
    uint256 collateral,
    uint256 entryPrice,
    uint16 leverage
) external onlyTradingEngine whenCircuitActivated(marketId) nonReentrant returns (bytes32 positionId) {
    // Validate basic input parameters
    if (size == 0) revert PositionManager__InvalidSize();
    if (collateral == 0) revert PositionManager__InsufficientCollateral();

    // Retrieve market risk configuration and validate market is active
    MarketRiskConfig memory config = marketRiskConfigs[marketId];
    if (!config.isActive) revert PositionManager__MarketNotConfigured();

    // Verify leverage does not exceed market maximum allowed
    if (leverage > config.maxLeverage) revert PositionManager__LeverageExceedsMax();

    // Calculate position notional value (size × price)
    uint256 notional = (size * entryPrice) / 1e18;

    // Calculate taker fee for opening a new position
    // Get quote asset from MarketRegistry for FeeCalculator integration
    address quoteAsset = marketRegistry.getQuoteAsset(marketId);
    uint256 takerFee = feeCalculator.calculateTradingFeeTaker(quoteAsset, trader, notional);

    // Validate collateral covers taker fee
    if (takerFee > collateral) revert PositionManager__InsufficientCollateralForFee();
    
    // Deduct fee from collateral before margin check
    collateral -= takerFee;

    // Calculate initial margin requirement and validate remaining collateral
    uint256 requiredIM = (notional * config.initialMarginBps) / 10000;
    if (collateral < requiredIM) revert PositionManager__InsufficientInitialMargin();

    // Record trade volume for incentive rewards if incentive manager is configured
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(trader, notional);
    }

    // Generate unique position ID using counter, timestamp, and trader details
    positionId = keccak256(abi.encodePacked(trader, marketId, _positionIdCounter++, block.timestamp));

    // Store position owner mapping for ownership verification
    positionOwner[positionId] = trader;

    // Calculate liquidation price based on market MMR, position details
    uint256 liqPrice = _calculateLiquidationPrice(marketId, side, entryPrice, collateral, size);

    // Create position struct with all required fields
    CommonStructs.Position memory pos = CommonStructs.Position({
        positionId: positionId,
        marketId: marketId,
        trader: trader,
        side: side,
        size: size,
        collateral: collateral,
        entryPrice: entryPrice,
        leverage: leverage,
        lastFundingIndex: 0,  // Initialize with zero funding
        unrealizedPnL: 0,     // Zero PnL at position opening
        liquidationPrice: liqPrice,
        openedAt: block.timestamp
    });

    // Store position data with initialized state
    positions[positionId] = PositionData({
        position: pos,
        lastUpdateTime: block.timestamp,
        accumulatedFunding: 0,    // No accumulated funding yet
        isLiquidatable: false,    // Position just opened, not liquidatable
        inADLQueue: false         // Not in ADL queue initially
    });

    // Update position mappings for trader and market
    userPositions[trader].push(positionId);
    marketPositions[marketId].push(positionId);
    
    // Update market open interest (total size for this side)
    openInterest[marketId][side] += size;

    // Update trader's portfolio metrics for risk assessment
    _updatePortfolio(trader);

    // Initialize position in ADL system with zero PnL (won't be added to queue)
    adlEngine.updateADLQueue(
        marketId,
        positionId,
        trader,
        side,
        0,                     // Zero unrealized PnL - won't be added to ADL queue
        leverage
    );

    // Emit events for position opening and ADL status
    emit PositionOpened(positionId, trader, marketId, side, size, entryPrice, leverage);
    emit ADLQueueStatusChanged(positionId, false, 0);
}

 /**
 * @notice Modify an existing position's size or collateral with integrated fee calculation
 * @dev Allows increasing/decreasing position size or adding/removing collateral. When increasing
 *      position size, calculates taker fees and deducts from collateral. Records trade volume
 *      for incentive programs. When decreasing size, realizes proportional PnL.
 * @param positionId Unique identifier of the position to modify
 * @param sizeDelta Change in position size (positive = increase, negative = decrease)
 * @param collateralDelta Change in collateral (positive = add, negative = remove)
 * @param currentPrice Current market price for PnL calculation (must be valid price feed)
 * @return realizedPnL Realized profit/loss from the modification (negative = loss, positive = profit)
 *
 * @dev Flow:
 * 1. Validate position exists and retrieve position data
 * 2. Calculate current unrealized PnL based on current price
 * 3. Process size delta:
 *    - If increasing: calculate taker fee, deduct from collateral, record trade for incentives
 *    - If decreasing: realize proportional PnL, update position size
 * 4. Process collateral delta (add or remove)
 * 5. Recalculate liquidation price with new parameters
 * 6. Update position state and timestamp
 * 7. Update portfolio summary
 * 8. Emit PositionModified event
 *
 * @dev Requirements:
 * - Caller must be trading engine (onlyTradingEngine modifier)
 * - Position must exist and be active
 * - Contract must not be emergency paused
 * - Global circuit breaker must be active
 * - No reentrancy allowed
 * - Size reduction cannot exceed current position size
 * - Collateral removal cannot exceed available collateral
 * - Sufficient collateral must cover taker fees for size increases
 *
 * @dev Emits:
 * - {PositionModified} event with updated size, collateral, and realized PnL
 * - {TradeRecorded} event via IncentiveManager if size increased and program active
 *
 * @dev Reverts with:
 * - PositionManager__PositionNotFound if position doesn't exist
 * - PositionManager__InvalidSize if size reduction exceeds current size
 * - PositionManager__InsufficientCollateralForFees if collateral insufficient for taker fees
 * - PositionManager__InsufficientCollateral if collateral removal exceeds available
 */
function modifyPosition(
    bytes32 positionId,
    int256 sizeDelta,
    int256 collateralDelta,
    uint256 currentPrice
)
    external
    onlyTradingEngine
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{
    // Retrieve position data and validate position exists
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    
    // Calculate current unrealized PnL for potential realization on partial close
    int256 currentPnL = _calculateUnrealizedPnL(pos, currentPrice);

    // Process size adjustment (increase or decrease)
    if (sizeDelta != 0) {
        if (sizeDelta > 0) {
            // ============================================
            // INCREASING POSITION SIZE (NEW ENTRY)
            // ============================================
            
            // Calculate notional value of size increase
            uint256 notional = (uint256(sizeDelta) * currentPrice) / 1e18;
            
            // Calculate taker fee for the new position entry
            // Get quote asset from MarketRegistry for FeeCalculator integration
            address quoteAsset = marketRegistry.getQuoteAsset(pos.marketId);
            uint256 takerFee = feeCalculator.calculateTradingFeeTaker(quoteAsset, pos.trader, notional);

            // Validate sufficient collateral to cover taker fee
            if (takerFee > pos.collateral) revert PositionManager__InsufficientCollateralForFee();
            
            // Deduct taker fee from position collateral
            pos.collateral -= takerFee;

            // Record trade volume for incentive rewards if incentive manager is configured
            if (address(incentiveManager) != address(0)) {
                incentiveManager.recordTrade(pos.trader, notional);
            }

            // Update position size and market open interest
            pos.size += uint256(sizeDelta);
            openInterest[pos.marketId][pos.side] += uint256(sizeDelta);
        } else {
            // ============================================
            // DECREASING POSITION SIZE (PARTIAL CLOSE)
            // ============================================
            
            uint256 reduction = uint256(-sizeDelta);
            
            // Validate reduction doesn't exceed current position size
            if (reduction > pos.size) revert PositionManager__InvalidSize();

            // Calculate proportion of position being closed
            uint256 proportion = (reduction * 1e18) / pos.size;
            
            // Realize proportional PnL (profit/loss)
            realizedPnL = (currentPnL * int256(proportion)) / 1e18;

            // Update position size and market open interest
            pos.size -= reduction;
            openInterest[pos.marketId][pos.side] -= reduction;
        }
    }

    // Process collateral adjustment (add or remove)
    if (collateralDelta != 0) {
        if (collateralDelta > 0) {
            // ============================================
            // ADDING COLLATERAL
            // ============================================
            pos.collateral += uint256(collateralDelta);
        } else {
            // ============================================
            // REMOVING COLLATERAL
            // ============================================
            uint256 withdrawal = uint256(-collateralDelta);
            
            // Validate withdrawal doesn't exceed available collateral
            if (withdrawal > pos.collateral) revert PositionManager__InsufficientCollateral();
            
            // Deduct collateral from position
            pos.collateral -= withdrawal;
        }
    }

    // Recalculate liquidation price with updated position parameters
    pos.liquidationPrice = _calculateLiquidationPrice(
        pos.marketId,
        pos.side,
        pos.entryPrice,
        pos.collateral,
        pos.size
    );

    // Update position metadata and state
    posData.lastUpdateTime = block.timestamp;
    _updatePositionState(positionId, currentPrice);

    // Emit event with updated position details
    emit PositionModified(positionId, pos.size, pos.collateral, realizedPnL);
}


/**
 * @notice Close a position completely (regular close) with integrated fee calculation
 * @dev Closes the entire position, calculates final PnL, deducts maker fees, records trade volume
 *      for incentives, updates open interest, and cleans up position data. Also removes position
 *      from ADL queue if present and updates user portfolio.
 * @param positionId Unique identifier of the position to close
 * @param closePrice Price to close at (must be valid market price)
 * @return realizedPnL Final realized profit/loss after fees (negative = loss, positive = profit)
 *
 * @dev Flow:
 * 1. Validate position exists and retrieve position data
 * 2. Calculate final unrealized PnL based on close price
 * 3. Calculate trade notional value for fee and incentive calculations
 * 4. Calculate maker fee (closing = maker order)
 * 5. Deduct fee from realized PnL or collateral (if PnL insufficient)
 * 6. Record trade volume for incentive rewards if program active
 * 7. Update market open interest by removing position size
 * 8. Remove position from user's position list
 * 9. Remove from ADL queue if present and update status
 * 10. Emit PositionClosed event with final details
 * 11. Delete position data from storage to free gas
 * 12. Update user's portfolio summary
 *
 * @dev Requirements:
 * - Caller must be trading engine (onlyTradingEngine modifier)
 * - Position must exist and be active
 * - Contract must not be emergency paused
 * - Global circuit breaker must be active
 * - No reentrancy allowed
 * - Position must not already be liquidated
 *
 * @dev Emits:
 * - {PositionClosed} event with position details and final PnL
 * - {ADLQueueStatusChanged} event if position was in ADL queue
 * - {TradeRecorded} event via IncentiveManager if program active
 *
 * @dev Reverts with:
 * - PositionManager__PositionNotFound if position doesn't exist
 * - PositionManager__InsufficientCollateral if fee deduction exceeds available collateral
 */
function closePosition(bytes32 positionId, uint256 closePrice)
    external
    onlyTradingEngine
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{
    // Retrieve position data and validate position exists
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    
    // ============================================
    // CALCULATE FINAL PNL AND FEES
    // ============================================
    
    // Calculate final unrealized PnL based on close price
    int256 finalPnL = _calculateUnrealizedPnL(pos, closePrice);
    
    // Calculate trade notional value for fee and incentive calculations
    uint256 notional = (pos.size * closePrice) / 1e18;
    
    // Calculate maker fee (closing position acts as maker order)
    // Get quote asset from MarketRegistry for FeeCalculator integration
    address quoteAsset = marketRegistry.getQuoteAsset(pos.marketId);
    int256 makerFeeRebate = feeCalculator.calculateTradingFeeMaker(quoteAsset, pos.trader, notional);
    
    // Convert to absolute fee (negative = rebate, positive = fee)
    uint256 makerFee = makerFeeRebate >= 0 ? uint256(makerFeeRebate) : 0;

    // ============================================
    // DEDUCT FEES FROM PNL OR COLLATERAL
    // ============================================
    
    // Initialize realized PnL as final PnL minus fees
    if (finalPnL >= int256(makerFee)) {
        // Fee can be fully covered by profit
        realizedPnL = finalPnL - int256(makerFee);
    } else {
        // Fee exceeds profit, deduct remaining from collateral
        uint256 additionalFee = uint256(int256(makerFee) - finalPnL);
        
        // Validate sufficient collateral to cover additional fee
        if (additionalFee > pos.collateral) {
            revert PositionManager__InsufficientCollateral();
        }
        
        // Deduct from collateral and set realized PnL to zero (or negative if loss)
        pos.collateral -= additionalFee;
        realizedPnL = finalPnL - int256(makerFee); // This will be negative or zero
    }

    // ============================================
    // RECORD TRADE FOR INCENTIVE REWARDS
    // ============================================
    
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(pos.trader, notional);
    }

    // ============================================
    // UPDATE MARKET OPEN INTEREST
    // ============================================
    
    // Reduce market open interest by the position size
    openInterest[pos.marketId][pos.side] -= pos.size;

    // ============================================
    // REMOVE POSITION FROM USER'S POSITION LIST
    // ============================================
    
    _removeUserPosition(pos.trader, positionId);

    // ============================================
    // HANDLE ADL QUEUE IF POSITION WAS IN QUEUE
    // ============================================
    
    if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }

    // ============================================
    // EMIT CLOSURE EVENT
    // ============================================
    
    emit PositionClosed(positionId, pos.trader, closePrice, realizedPnL, false);

    // ============================================
    // CLEAN UP POSITION DATA
    // ============================================
    
    // Delete position data to recover gas (only after all reads are complete)
    delete positions[positionId];

    // ============================================
    // UPDATE USER PORTFOLIO
    // ============================================
    
    _updatePortfolio(pos.trader);

    return realizedPnL;
}
    /**
     * @notice Force close a position (called by ADL engine)
     * @param positionId Position to close
     * @param executionPrice Price to close at
     * @param isLiquidation Whether this is a liquidation
     * @dev Only callable by ADL engine or liquidation engine
     */
    function forceClosePosition(bytes32 positionId, uint256 executionPrice, bool isLiquidation)
        external
        nonReentrant
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
        returns (int256 realizedPnL)
    {
        // Only ADL engine or liquidation engine can call this
        if (msg.sender != address(adlEngine) && msg.sender != liquidationEngine) {
            revert PositionManager__Unauthorized();
        }

        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

        CommonStructs.Position storage pos = posData.position;

        // Calculate final PnL
        realizedPnL = _calculateUnrealizedPnL(pos, executionPrice);

        // Update open interest
        openInterest[pos.marketId][pos.side] -= pos.size;

        // Remove from user positions
        _removeUserPosition(pos.trader, positionId);

        // Remove from ADL queue if present
        if (posData.inADLQueue) {
            adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
            posData.inADLQueue = false;
            emit ADLQueueStatusChanged(positionId, false, 0);
        }

        // Emit closure event
        emit PositionClosed(positionId, pos.trader, executionPrice, realizedPnL, isLiquidation);

        // Clean up position data
        delete positions[positionId];

        // Update portfolio
        _updatePortfolio(pos.trader);

        return realizedPnL;
    }

    /**
     * @notice Update position state and ADL queue
     * @param positionId Position to update
     * @param currentPrice Current market price
     * @dev Callable by keepers or frontend
     */
    function updatePositionState(bytes32 positionId, uint256 currentPrice)
        external
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
    {
        _updatePositionState(positionId, currentPrice);
    }

    // Update the accumulated funding for a given position ID
    function updateAccumulatedFunding(bytes32 posId, int256 newAccumulatedFunding)
        external
        onlyFundingEngine
        whenGlobalCircuitActivated
        whenNotEmergencyPaused
    {
        PositionData storage positionData = positions[posId];
        positionData.accumulatedFunding = newAccumulatedFunding;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal position state update with ADL integration
     * @param positionId Position to update
     * @param currentPrice Current market price
     * @dev Called by updatePositionState, modifyPosition, closePosition
     */
    function _updatePositionState(bytes32 positionId, uint256 currentPrice) internal {
        PositionData storage posData = positions[positionId];
        if (posData.position.openedAt == 0) return;

        CommonStructs.Position storage pos = posData.position;

        // Update unrealized PnL
        int256 unrealizedPnL = _calculateUnrealizedPnL(pos, currentPrice);
        pos.unrealizedPnL = unrealizedPnL;

        // Update liquidation status
        bool shouldBeLiquidatable = (pos.side == CommonStructs.Side.LONG && currentPrice <= pos.liquidationPrice)
            || (pos.side == CommonStructs.Side.SHORT && currentPrice >= pos.liquidationPrice);

        posData.isLiquidatable = shouldBeLiquidatable;

        posData.lastUpdateTime = block.timestamp;

        // === ADL Queue Logic ===
        if (unrealizedPnL > 0) {
            uint256 pnlUint = uint256(unrealizedPnL);
            uint256 adlScore = pnlUint * pos.leverage;

            adlEngine.updateADLQueue(pos.marketId, positionId, pos.trader, pos.side, pnlUint, pos.leverage);

            if (!posData.inADLQueue) {
                posData.inADLQueue = true;
                emit ADLQueueStatusChanged(positionId, true, adlScore);
            }
        } else {
            if (posData.inADLQueue) {
                adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
                posData.inADLQueue = false;
                emit ADLQueueStatusChanged(positionId, false, 0);
            }
        }
    }

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
    function _calculateUnrealizedPnL(CommonStructs.Position storage pos, uint256 price)
        internal
        view
        returns (int256)
    {
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

        uint256 marginRatio =
            totalCol > 0 ? ((totalCol + uint256(totalPnL > 0 ? totalPnL : int256(0))) * 10000) / totalCol : 0;

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
     * @notice Get the owner of a position by ID
     * @param positionId Unique position identifier
     * @return Address of the position owner
     */
    function getPositionOwner(bytes32 positionId) external view returns (address) {
    return positionOwner[positionId];
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

    function getMarketPositions(bytes32 marketId) external view returns (bytes32[] memory) {
        return marketPositions[marketId];
    }
}
