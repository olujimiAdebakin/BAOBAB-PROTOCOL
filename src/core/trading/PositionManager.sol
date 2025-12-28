// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../security/SecurityBase.sol";
import {AutoDeleverageEngine} from "../trading/engines/AutoDeleverageEngine.sol";
import {ICircuitBreaker} from "../../interfaces/ICircuitBreaker.sol";
import {IEmergencyPauser} from "../../interfaces/IEmergencyPauser.sol";
import {IVolumeTracker} from "../../interfaces/IVolumeTracker.sol"; 
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";
import {ModuleIds} from "../../libraries/utils/ModuleIds.sol";
import {RateLimiter} from "../../security/RateLimiter.sol";
// import {FeeDistributor} from "../../fees/FeeDistributor.sol";
import {FeeCalculator} from "../../fees/FeeCalculator.sol";
import {IncentiveManager} from "../../fees/IncentiveManager.sol";
import {MarketRegistry} from "../markets/MarketRegistry.sol";
import {SafeTransfer} from "../../libraries/utils/SafeTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FundingEngine} from "./FundingRateEngine.sol";
// import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
// import {OrderStorage} from  "../data/OrderStorage.sol";

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
    IVolumeTracker public volumeTracker;
    MarketRegistry public marketRegistry;
    FundingEngine public fundingEngine;
    // IPriceFeed public priceFeed;
    // FeeDistributor public feeDistributor;



    using AddressUtils for address;
    using ModuleIds for *;

        // Example market IDs (adjust based on your system)
    bytes32 constant ETH_USD = keccak256(abi.encodePacked("ETH-USD"));
    bytes32 constant BTC_USD = keccak256(abi.encodePacked("BTC-USD"));

    // ══════════════════════════════════════════════════════════════════════════
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

    mapping(address => int256) public totalRealizedPnL;

    // /// @notice Auto-deleverage engine for risk management
    // AutoDeleverageEngine public adlEngine;

    // /// @notice Oracle registry contract for price feeds
    // address public oracleRegistry;

    /// @notice Trading engine contract (authorized caller)
    address public tradingEngine;

    /// @notice Liquidation engine contract (authorized caller)
    address public liquidationEngine;

    /// @notice Protocol admin address
    address public BaobabAdmin;

    /// @notice Counter for generating unique position IDs
    uint256 private _positionIdCounter;

    // address public fundingEngine;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    event PositionIncreased(
    bytes32 indexed positionId,
    address indexed trader,
    uint256 additionalSize,
    uint256 additionalCollateral,
    uint256 newEntryPrice,
    uint16 newLeverage,
    uint256 timestamp
);


    event PositionDecreased(
    bytes32 indexed positionId,
    address indexed trader,
    uint256 reduceSize,
    uint256 withdrawCollateral,
    int256 realizedPnL,
    uint256 timestamp
);

event PnLRealized(
    bytes32 indexed positionId,
    address indexed trader,
    int256 realizedPnL,
    uint256 timestamp
);

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
 * @notice Emitted when a trader withdraws excess collateral from an open position
 * @param positionId Unique identifier of the position
 * @param trader Address of the position owner
 * @param amount Amount of collateral withdrawn (in quote asset units)
 * @param remainingCollateral Remaining collateral after withdrawal
 * @param timestamp Block timestamp when withdrawal occurred
 */
event CollateralWithdrawn(
    bytes32 indexed positionId,
    address indexed trader,
    uint256 amount,
    uint256 remainingCollateral,
    uint256 timestamp
);

    /**
     * @notice Emitted when funding is applied to a position
     * @param positionId Unique identifier for the position
     * @param fundingAmount Funding payment amount (positive = paid, negative = received)
     * @param newFundingIndex New funding index after application
     */
    event FundingPaid(bytes32 indexed positionId, int256 fundingAmount, int256 newFundingIndex);

    /**
     * @notice Emitted when funding is settled for a position
     * @param positionId Unique identifier for the position
     * @param fundingPayment Total funding payment settled
     */
    event FundingSettled(bytes32 indexed positionId, int256 fundingPayment,  uint256 timestamp);

    event FeeCollected(
    address indexed trader,
    uint256 amount,
    string reason
);

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

    error PositionManager__OnlyFundingEngine();

    error PositionManager__InvalidReduction();
    error PositionManager__ReductionExceedsPosition(uint256 reduceSize, uint256 currentSize);
    error PositionManager__InsufficientAllowance();
    error PositionManager__InvalidPosition();
    error PositionManager__InvalidTrader();
    error PositionManager__MarketConcentrationExceeded(bytes32 marketId, uint256 currentBps, uint256 limitBps);
    error PositionManager__MarketPositionExceedsHistory(uint256 notional, uint256 maxAllowed);
    error PositionManager__PositionExceedsVolumeLimit(uint256 notional, uint256 maxAllowed);
    error PositionManager__NewTraderLimitExceeded(uint256 notional, uint256 limit);
    error PositionManager__InsufficientMarginAfterWithdrawal();
    // error PositionManager__InvalidPosition();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the PositionManager with required dependencies
     * @dev Sets up admin, oracle registry, and ADL engine. Initializes default risk configs.
     * @param _admin Protocol admin address
     * @param _adlEngine Auto-deleverage engine contract address
     */
    constructor(
        address _admin,
        // address _oracleRegistry,
        address _adlEngine,
        address _fundingEngine,
        address _circuitBreaker,
        address _emergencyPauser,
        address _incentiveManager,
        address _feeCalculator,
        address _marketRegistry,
        address _volumeTracker
    ) {
        // if (_admin == address(0) || _oracleRegistry == address(0) || _adlEngine == address(0))
        //     revert PositionManager__Unauthorized();

        // Use library functions for validation
        _admin.validateNotZero();
        // _oracleRegistry.validateContract();
        _adlEngine.validateContract();
        _fundingEngine.validateContract();
        _circuitBreaker.validateContract();
        _emergencyPauser.validateContract();
        _incentiveManager.validateContract();
        _feeCalculator.validateContract();
        _marketRegistry.validateContract();
        _volumeTracker.validateContract();
        _fundingEngine.validateContract();

        BaobabAdmin = _admin;
        // oracleRegistry = _oracleRegistry;
        adlEngine = AutoDeleverageEngine(_adlEngine);
        fundingEngine = FundingEngine(_fundingEngine);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        emergencyPauser = IEmergencyPauser(_emergencyPauser);
        incentiveManager = IncentiveManager(_incentiveManager);
        feeCalculator = FeeCalculator(_feeCalculator);
        marketRegistry = MarketRegistry(_marketRegistry);
        volumeTracker = IVolumeTracker(_volumeTracker);

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
    modifier onlyPerpEngine() {
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
        if (msg.sender != address(fundingEngine)) revert PositionManager__OnlyFundingEngine();
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
        uint256 fundingInterval
    ) external onlyAdmin whenNotEmergencyPaused whenCircuitActivated(marketId) {
        marketConfig[marketId] = MarketConfig({
            maxLeverage: maxLev,
            mmrBps: mmr,
            maxFundingRateBps: maxFund,
            fundingEnabled: fundEnabled,
            fundingInterval: fundingInterval
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
        fundingEngine = FundingEngine(_fundingEngine);
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                                    POSITION LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    /**
     * @notice Calculate funding owed for a position based on AFPU changes
     * @dev Uses position size and last recorded funding index to compute owed amount
     * @param positionId Unique identifier for the position
     * @return fundingOwed Funding payment owed (positive = pay, negative = receive)
     */
    function _calculateFundingOwed(bytes32 positionId) internal view returns (int256) {
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) return 0;
    
    // Get current AFPU index from FundingEngine
    int256 currentCumulativeFee = fundingEngine.getCumulativeFunding(
        posData.position.marketId
        );

    //    (,, int256 currentCumulative) = fundingEngine.readFundingState(posData.position.marketId);

    
    // Funding owed = (Current index - Last recorded index) × Position size
    int256 fundingOwed = (currentCumulativeFee - posData.position.lastCumulativeFunding) 
        * int256(posData.position.size) / int256(1e18); // Divide by precision
    
    // Adjust for position side
    // Positive funding rate = longs pay shorts
    if (posData.position.side == CommonStructs.Side.LONG) {
        return fundingOwed;  // Long pays positive funding
    } else {
        return -fundingOwed; // Short receives (negative means credit)
    }
}

    /**
     * @notice Settle funding payments for a position
     * @dev Calculates funding owed and adjusts position collateral accordingly
     * @param positionId Unique identifier for the position
     * @return fundingPayment Total funding payment settled (positive = paid, negative = received)
     *
     * Requirements:
     * - Caller must be the FundingEngine
     * - Position must exist
     *
     * Emits {FundingSettled} event on success
     */
 function settlePositionFunding(bytes32 positionId) 
    public
    onlyPerpEngine
    returns (int256 fundingPayment) 
{
    PositionData storage posData = positions[positionId];
    require(posData.position.openedAt != 0, "Position not found");
    
    // Calculate funding
    fundingPayment = _calculateFundingOwed(positionId);
    
    //  Apply to collateral (internal accounting)
    if (fundingPayment > 0) {
        posData.position.collateral -= uint256(fundingPayment);  // OWES
    } else if (fundingPayment < 0) {
        posData.position.collateral += uint256(-fundingPayment); // RECEIVES
    }
    
    // Update AFPU snapshot
    posData.position.lastCumulativeFunding = 
        fundingEngine.getCumulativeFunding(posData.position.marketId);
    
    emit FundingSettled(positionId, fundingPayment, block.timestamp);
    return fundingPayment;
}


function openPosition(
    address trader,
    bytes32 marketId,
    CommonStructs.Side side,
    CommonStructs.Position memory position,
    uint256 size,
    uint256 collateral,
    uint256 entryPrice,
    uint16 leverage
) external onlyPerpEngine whenCircuitActivated(marketId) nonReentrant returns (bytes32 positionId) {
    
    //  CommonStructs.Position storage position = positionData.position;
     position.lastCumulativeFunding = fundingEngine.getCumulativeFunding(marketId);
    // Basic validation
    if (size == 0) revert PositionManager__InvalidSize();
    if (collateral == 0) revert PositionManager__InsufficientCollateral();

    // Get market config and validate
    MarketRiskConfig memory config = marketRiskConfigs[marketId];
    if (!config.isActive) revert PositionManager__MarketNotConfigured();
    if (leverage > config.maxLeverage) revert PositionManager__LeverageExceedsMax();

    // Calculate notional and check limits
    // Calculates the total value of the position (notional) and ensures it respects volume and market-specific limits.
    uint256 notional = (size * entryPrice) / 1e18;
    _checkVolumeBasedLimits(trader, marketId, notional);
    _checkMarketSpecificLimits(trader, marketId, notional);

    // Calculate and deduct fees
    // This shouldnt be handled by PostionManager but for now we do it here
    address quoteAsset = marketRegistry.getQuoteAsset(marketId);
    uint256 takerFee = feeCalculator.calculateTradingFeeTaker(
        quoteAsset, 
        trader, 
        notional
        );
    
    if (takerFee > collateral) revert PositionManager__InsufficientCollateralForFee();
    collateral -= takerFee;

    // Check margin requirements
    // Ensures the collateral left after fees is enough for initial margin.
    uint256 requiredInitialMargins = (notional * config.initialMarginBps) / 10000;
    if (collateral < requiredInitialMargins) revert PositionManager__InsufficientInitialMargin();

    // Record trade volume
    // Tracks trade volume for incentive programs if applicable.
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(
            trader, 
            marketId, 
            notional
            );
    }
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(trader, notional);
    }

    // Generate position 
    // Creates a unique position ID and initializes the position data structure.
    // Unique ID for the position, and ownership tracking.
    positionId = keccak256(abi.encodePacked(
        trader, 
        marketId, 
        _positionIdCounter++, 
        block.timestamp
        ));

    positionOwner[positionId] = trader;

    // Calculate liquidation price
    // Determines the price at which the position would be liquidated based on maintenance margin.
    // Calculates where the position will be liquidated based on risk parameters.
    uint256 liquidPrice = _calculateLiquidationPrice(
        marketId, 
        side, 
        entryPrice, 
        collateral, 
        size
        );

    // Create position
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
        lastCumulativeFunding: fundingEngine.getCumulativeFunding(marketId), 
        unrealizedPnL: 0,
        liquidationPrice: liquidPrice,
        openedAt: block.timestamp
    });

    // Store position data
    positions[positionId] = PositionData({
        position: pos,
        lastUpdateTime: block.timestamp,
        accumulatedFunding: 0,
        isLiquidatable: false,
        inADLQueue: false
    });

    // Update mappings
    userPositions[trader].push(positionId);
    marketPositions[marketId].push(positionId);
    openInterest[marketId][side] += size;

    // Update systems
    _updatePortfolio(trader);
    adlEngine.updateADLQueue(
        marketId, 
        positionId, 
        trader, 
        side, 0, 
        leverage
        );

    // Emit events
    emit PositionOpened(
        positionId, 
        trader, 
        marketId, 
        side, 
        size, 
        entryPrice, 
        leverage
        );

    emit ADLQueueStatusChanged(positionId, false, 0);
}

function modifyPosition(
    bytes32 positionId,
    int256 sizeDelta,
    int256 collateralDelta,
    uint256 currentPrice
)
    external
    onlyPerpEngine
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{
     settlePositionFunding(positionId);

    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    int256 currentPnL = _calculateUnrealizedPnL(pos, currentPrice);

    // Handle size changes
    if (sizeDelta != 0) {
        if (sizeDelta > 0) {
            // Increase position
            uint256 notional = (uint256(sizeDelta) * currentPrice) / 1e18;
            
            // Check volume limits for increase
            _checkVolumeBasedLimits(pos.trader, pos.marketId, notional);
            _checkMarketSpecificLimits(pos.trader, pos.marketId, notional);

            // Calculate and deduct fees
            address quoteAsset = marketRegistry.getQuoteAsset(pos.marketId);
            uint256 takerFee = feeCalculator.calculateTradingFeeTaker(quoteAsset, pos.trader, notional);
            
            if (takerFee > pos.collateral) revert PositionManager__InsufficientCollateralForFee();
            pos.collateral -= takerFee;

            // Record trade volume
            if (address(volumeTracker) != address(0)) {
                volumeTracker.recordTrade(pos.trader, pos.marketId, notional);
            }
            if (address(incentiveManager) != address(0)) {
                incentiveManager.recordTrade(pos.trader, notional);
            }

            // Update position size
            pos.size += uint256(sizeDelta);
            openInterest[pos.marketId][pos.side] += uint256(sizeDelta);
        } else {
            // Decrease position
            uint256 reduction = uint256(-sizeDelta);
            if (reduction > pos.size) revert PositionManager__InvalidSize();
            
            uint256 proportion = (reduction * 1e18) / pos.size;
            realizedPnL = (currentPnL * int256(proportion)) / 1e18;

            pos.size -= reduction;
            openInterest[pos.marketId][pos.side] -= reduction;
        }
    }

    // Handle collateral changes
    if (collateralDelta != 0) {
        if (collateralDelta > 0) {
            pos.collateral += uint256(collateralDelta);
        } else {
            uint256 withdrawal = uint256(-collateralDelta);
            if (withdrawal > pos.collateral) revert PositionManager__InsufficientCollateral();
            pos.collateral -= withdrawal;
        }
    }

    // Update position state
    pos.liquidationPrice = _calculateLiquidationPrice(
        pos.marketId,
        pos.side,
        pos.entryPrice,
        pos.collateral,
        pos.size
    );

    posData.lastUpdateTime = block.timestamp;
    _updatePositionState(positionId, currentPrice);

    emit PositionModified(positionId, pos.size, pos.collateral, realizedPnL);
}


// ============================================================================
// POSITION MODIFICATION FUNCTIONS
// ============================================================================

function increasePosition(
    bytes32 positionId,
    uint256 additionalSize,
    uint256 additionalCollateral,
    uint256 currentPrice
) 
    external 
    onlyPerpEngine
    whenNotEmergencyPaused
    nonReentrant 
{
     // Settle funding BEFORE increase
    settlePositionFunding(positionId);
    _validateIncreaseInputs(additionalSize, additionalCollateral);
    
    PositionData storage positionData = positions[positionId];
    CommonStructs.Position storage position = positionData.position;
    _validatePositionForIncrease(positionId, position);
    
    _processPositionIncrease(
        positionId, 
        positionData, 
        position,
        additionalSize, 
        additionalCollateral, 
        currentPrice
        );
}

function decreasePosition(
    bytes32 positionId,
    uint256 reduceSize,
    uint256 withdrawCollateral
)
    external
    onlyPerpEngine
    whenNotEmergencyPaused
    nonReentrant
{
     // Settle funding BEFORE increase
    settlePositionFunding(positionId);
    _validateDecreaseInputs(reduceSize, withdrawCollateral);
    
    PositionData storage positionData = positions[positionId];
    CommonStructs.Position storage position = positionData.position;
    _validatePositionForDecrease(positionId, position, reduceSize);
    
    _processPositionDecrease(
        positionId, 
        positionData, 
        position, 
        reduceSize, 
        withdrawCollateral
        );
}

// ============================================================================
// POSITION CLOSING FUNCTIONS
// ============================================================================

function closePosition(bytes32 positionId, uint256 closePrice)
    external
    onlyLiquidationEngine
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{
      // Settle funding BEFORE increase
    settlePositionFunding(positionId);

    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    
    // Calculate final PnL
    int256 finalPnL = _calculateUnrealizedPnL(pos, closePrice);
    uint256 notional = (pos.size * closePrice) / 1e18;

    // Record close volume
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(pos.trader, pos.marketId, notional);
    }
    
    // Calculate maker fee
    address quoteAsset = marketRegistry.getQuoteAsset(pos.marketId);
    int256 makerFeeRebate = feeCalculator.calculateTradingFeeMaker(
        quoteAsset, 
        pos.trader, 
        notional
        );
        
    uint256 makerFee = makerFeeRebate >= 0 ? uint256(makerFeeRebate) : 0;

    // Deduct fees from PnL or collateral
    if (finalPnL >= int256(makerFee)) {
        realizedPnL = finalPnL - int256(makerFee);
    } else {
        uint256 additionalFee = uint256(int256(makerFee) - finalPnL);
        if (additionalFee > pos.collateral) revert PositionManager__InsufficientCollateral();
        pos.collateral -= additionalFee;
        realizedPnL = finalPnL - int256(makerFee);
    }

    // Record for incentives
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(pos.trader, notional);
    }

    // Update open interest
    openInterest[pos.marketId][pos.side] -= pos.size;

    // Clean up position data
    _removeUserPosition(pos.trader, positionId);
    
    if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }

    emit PositionClosed(positionId, pos.trader, closePrice, realizedPnL, false);
    delete positions[positionId];
    _updatePortfolio(pos.trader);

    return realizedPnL;
}

function forceClosePosition(bytes32 positionId, uint256 executionPrice, bool isLiquidation)
    external
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{

    settlePositionFunding(positionId);

    // Only ADL engine or liquidation engine can call this
    if (msg.sender != address(adlEngine) && msg.sender != liquidationEngine) {
        revert PositionManager__Unauthorized();
    }
    
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    realizedPnL = _calculateUnrealizedPnL(pos, executionPrice);

    // Update open interest
    openInterest[pos.marketId][pos.side] -= pos.size;
    
    // Clean up position data
    _removeUserPosition(pos.trader, positionId);
    
    if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }

    emit PositionClosed(positionId, pos.trader, executionPrice, realizedPnL, isLiquidation);
    delete positions[positionId];
    _updatePortfolio(pos.trader);

    return realizedPnL;
}

// ============================================================================
// POSITION STATE FUNCTIONS
// ============================================================================

function updatePositionState(bytes32 positionId, uint256 currentPrice)
    external
    onlyPerpEngine
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
{
    _updatePositionState(positionId, currentPrice);
}

function updateAccumulatedFunding(bytes32 posId, int256 newAccumulatedFunding)
    external
    onlyFundingEngine
    whenGlobalCircuitActivated
    whenNotEmergencyPaused
{
    PositionData storage positionData = positions[posId];
    positionData.accumulatedFunding = newAccumulatedFunding;
}


// ============================================================================
// INTERNAL HELPER FUNCTIONS
// ============================================================================

/**
 * @notice Internal function to completely close a position during size reduction
 * @dev Handles full position closure when reduceSize brings size to zero.
 *      Updates open interest, removes from mappings/ADL queue, emits events,
 *      deletes position storage, and updates portfolio. Called from _processPositionDecrease.
 * @param positionId Unique position identifier
 * @param trader Address of the position owner
 * @param realizedPnL Realized profit/loss from the closure
 */
function _closePositionCompletely(
    bytes32 positionId,
    address trader,
    int256 realizedPnL
) internal {
    PositionData storage posData = positions[positionId];
    CommonStructs.Position storage pos = posData.position;
    
    // Update open interest (size already reduced to 0 in _handleSizeReduction)
    if (pos.size > 0) {  // Safety check
        openInterest[pos.marketId][pos.side] -= pos.size;
    }
    
    // Calculate close price (use current price or entry price as fallback)
    uint256 closePrice = pos.entryPrice;  // Fallback - ideally pass currentPrice as param
    
    // Record close volume for incentives/tracking
    uint256 closeNotional = (pos.size * closePrice) / 1e18;
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(trader, pos.marketId, closeNotional);
    }
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(trader, closeNotional);
    }
    
    // Remove from ADL queue if present
    if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }
    
    // Remove from user and market position lists
    _removeUserPosition(trader, positionId);
    _removeMarketPosition(pos.marketId, positionId);
    
    // Emit closure event (non-liquidation)
    emit PositionClosed(positionId, trader, closePrice, realizedPnL, false);
    
    // Delete position storage (gas refund)
    delete positions[positionId];
    
    // Update trader portfolio
    _updatePortfolio(trader);
}

/**
 * @notice Remove position from market's position list
 * @dev Maintains accurate market position tracking for cleanup
 */
function _removeMarketPosition(bytes32 marketId, bytes32 positionId) internal {
    bytes32[] storage marketList = marketPositions[marketId];
    for (uint256 i = 0; i < marketList.length; i++) {
        if (marketList[i] == positionId) {
            marketList[i] = marketList[marketList.length - 1];
            marketList.pop();
            break;
        }
    }
}

function _validateIncreaseInputs(uint256 additionalSize, uint256 additionalCollateral) internal pure {
    if (additionalSize == 0) revert PositionManager__InvalidSize();
    if (additionalCollateral == 0) revert PositionManager__InsufficientCollateral();
}

function _validatePositionForIncrease(bytes32 positionId, CommonStructs.Position storage position) internal view {
    if (positionId != position.positionId) revert PositionManager__InvalidPosition();
    if (position.positionId == bytes32(0)) revert PositionManager__InvalidPosition();
    if (position.trader == address(0)) revert PositionManager__InvalidTrader();
}

function _validateDecreaseInputs(uint256 reduceSize, uint256 withdrawCollateral) internal pure {
    if (reduceSize == 0 && withdrawCollateral == 0) revert PositionManager__InvalidReduction();
}

function _validatePositionForDecrease(bytes32 positionId, CommonStructs.Position storage position, uint256 reduceSize) 
    internal view 
{
    if (positionId == bytes32(0)) revert PositionManager__InvalidPosition();
    if (positionId != position.positionId) revert PositionManager__InvalidPosition();
    if (position.positionId == bytes32(0)) revert PositionManager__InvalidPosition();
    if (position.trader == address(0)) revert PositionManager__InvalidTrader();
    if (reduceSize > position.size) revert PositionManager__ReductionExceedsPosition(reduceSize, position.size);
}

function _processPositionIncrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 additionalSize,
    uint256 additionalCollateral,
    uint256 currentPrice 
) internal {
    // uint256 currentPrice = _getCurrentPrice(position.marketId);
    uint256 additionalNotional = (additionalSize * currentPrice) / 1e18;
    
    _checkIncreaseLimits(position.trader, position.marketId, additionalNotional);
   
    
    uint256 netAdditionalCollateral = _handleIncreaseCollateralAndFees(
        position.trader,
        position.marketId,
        additionalCollateral,
        additionalNotional
    );
    
    _updatePositionAfterIncrease(
        positionId,
        positionData, 
        position, 
        additionalSize, 
        netAdditionalCollateral, 
        additionalNotional, 
        currentPrice
        );

     _updatePositionState(
        positionId, 
        currentPrice
     );

    _updateExternalSystemsAfterIncrease(
        positionId, 
        position, 
        additionalSize, 
        additionalNotional
    );

    emit PositionIncreased(positionId, position.trader, additionalSize, additionalCollateral, position.entryPrice, position.leverage, block.timestamp);
}

function _checkIncreaseLimits(address trader, bytes32 marketId, uint256 additionalNotional) internal view {
    if (address(volumeTracker) == address(0)) return;
    _checkVolumeBasedLimits(trader, marketId, additionalNotional);
    _checkMarketSpecificLimits(trader, marketId, additionalNotional);
}

function _handleIncreaseCollateralAndFees(
    address trader,
    bytes32 marketId,
    uint256 additionalCollateral,
    // uint256 grossAdditionalNotional,
    uint256 additionalNotional
) internal returns (uint256 netAdditionalCollateral) {
    address quoteAsset = marketRegistry.getQuoteAsset(marketId);
    uint256 increaseFee = feeCalculator.calculateTradingFeeTaker(
        quoteAsset,
        trader,
        additionalNotional
    );

    if (increaseFee > additionalCollateral) revert PositionManager__InsufficientCollateralForFee();

    netAdditionalCollateral = additionalCollateral - increaseFee;

    //     if (fee > grossAdditionalCollateral) {
    //     revert PositionManager__InsufficientCollateralForFee();
    // }
    
    // IERC20 collateralToken = IERC20(quoteAsset);
    // uint256 allowance = collateralToken.allowance(trader, address(this));
    // if (allowance < additionalCollateral) {
    //     revert PositionManager__InsufficientAllowance();
    // }
    //    SafeTransfer.safeTransferFrom(
    //     collateralToken, 
    //     msg.sender, 
    //     address(this), 
    //     additionalCollateral
    // );
    
    emit FeeCollected(trader, increaseFee, "position_increase");
    return netAdditionalCollateral;
}

function _updatePositionAfterIncrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 additionalSize,
    uint256 netAdditionalCollateral,
    uint256 additionalNotional,
    uint256 currentPrice
) internal {
    // Calculate new weighted average entry price
    if (currentPrice == 0) {
        currentPrice = _getCurrentPrice(position.marketId);
    }

    if (position.positionId != positionId) {
        revert PositionManager__InvalidPosition();
    }
    uint256 oldNotional = (position.size * position.entryPrice) / 1e18;
    uint256 newTotalSize = position.size + additionalSize;
    uint256 newEntryPrice = ((oldNotional + additionalNotional) * 1e18) / newTotalSize;
    
    // Update position storage
    position.size = newTotalSize;
    position.entryPrice = newEntryPrice;
    position.collateral += netAdditionalCollateral;
    
    // Recalculate leverage
    uint256 newNotional = (newTotalSize * newEntryPrice) / 1e18;
    position.leverage = uint16((newNotional * 100) / position.collateral);
    
    // Update liquidation price
    position.liquidationPrice = _calculateLiquidationPrice(
        position.marketId,
        position.side,
        newEntryPrice,
        position.collateral,
        newTotalSize
    );
    
    // Update timestamp when state changes
    positionData.lastUpdateTime = block.timestamp;
    
    // Update market open interest
    openInterest[position.marketId][position.side] += additionalSize;
}

function _updateExternalSystemsAfterIncrease(
    bytes32 positionId,
    CommonStructs.Position storage position,
    uint256 additionalSize,
    uint256 additionalNotional
) internal {

    if (additionalSize == 0) revert PositionManager__InvalidSize();

    // Record trade volume
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(position.trader, position.marketId, additionalNotional);
    }
    
    // Update incentive rewards
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(position.trader, additionalNotional);
    }
    
    // Update ADL engine
    PositionData storage positionData = positions[positionId];
    // Update timestamp when state changes
    positionData.lastUpdateTime = block.timestamp;

    adlEngine.updateADLQueue(
        position.marketId,
        positionId,
        position.trader,
        position.side,
        position.unrealizedPnL,
        position.leverage
    );
    
    // Update portfolio
    _updatePortfolio(position.trader);
}

function _processPositionDecrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 reduceSize,
    uint256 withdrawCollateral
) internal {
    uint256 currentPrice = _getCurrentPrice(
        position.marketId
        );

    _updatePositionState(
        positionId, 
        currentPrice
        );
    
    int256 realizedPnL = 0;
    if (reduceSize > 0) {
    // Calculate realized PnL from size reduction
        realizedPnL = _handleSizeReduction(
            positionId, 
            positionData, 
            position, 
            reduceSize, 
            currentPrice
            );
        if (position.size == 0) {
            _closePositionCompletely(
                positionId, 
                position.trader, 
                realizedPnL
                );
            return;
        }
    }
    
    if (withdrawCollateral > 0) {
        _handleCollateralWithdrawal(
            positionId, 
            position, 
            withdrawCollateral
            );
    }
    
      //  Update position state
    _updatePositionAfterDecrease(
        positionId,
        positionData, 
        position, 
        reduceSize, 
        realizedPnL
        );
    
    emit PositionDecreased(positionId, position.trader, reduceSize, withdrawCollateral, realizedPnL, block.timestamp);
    if (realizedPnL != 0) emit PnLRealized(positionId, position.trader, realizedPnL, block.timestamp);
}
function _getCurrentPrice(bytes32 marketId) internal pure returns (uint256) {
    return _getMockPrice(marketId);
}

function _getMockPrice(bytes32 marketId) internal pure returns (uint256) {
    // TODO: Replace with actual oracle implementation
    // This is a temporary mock for development
    

    if (marketId == ETH_USD) return 3000 * 1e18;
    if (marketId == BTC_USD) return 60000 * 1e18;
    return 100 * 1e18;
}

function _handleSizeReduction(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 reduceSize,
    uint256 currentPrice
) internal returns (int256 realizedPnL) {
    require(reduceSize <= position.size, "INVALID_REDUCTION");
    if (positionId != position.positionId) {
        revert PositionManager__InvalidPosition();
    }

    uint256 reductionRatio = (reduceSize * 1e18) / position.size;
    
    realizedPnL = (position.unrealizedPnL * int256(reductionRatio)) / 1e18;
    uint256 reducedNotional = (reduceSize * currentPrice) / 1e18;
    
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(position.trader, position.marketId, reducedNotional);
    }

    // Update timestamp when state changes
    positionData.lastUpdateTime = block.timestamp;
    
    position.size -= reduceSize;
    openInterest[position.marketId][position.side] -= reduceSize;
    position.unrealizedPnL -= realizedPnL;
    
    return realizedPnL;
}


function _handleCollateralWithdrawal(
    bytes32 positionId,
    CommonStructs.Position storage position,
    uint256 withdrawCollateral
) internal {
    if (withdrawCollateral > position.collateral) revert PositionManager__InsufficientCollateral();
    
    uint256 newCollateral = position.collateral - withdrawCollateral;
    uint256 notional = (position.size * position.entryPrice) / 1e18;
    MarketRiskConfig memory config = marketRiskConfigs[position.marketId];
    uint256 requiredIM = (notional * config.initialMarginBps) / 10000;
    
    if (newCollateral < requiredIM) revert PositionManager__InsufficientMarginAfterWithdrawal();
    
    position.collateral = newCollateral;
    address collateralToken = marketRegistry.getQuoteAsset(position.marketId);
    SafeTransfer.safeTransfer(IERC20(collateralToken), msg.sender, withdrawCollateral);

    emit CollateralWithdrawn(positionId, position.trader, withdrawCollateral, position.collateral,
    block.timestamp);
}

function _updatePositionAfterDecrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 reduceSize,
    int256 realizedPnL
) internal {

      _applyRealizedPnLToCollateral(position, realizedPnL);

       totalRealizedPnL[position.trader] += realizedPnL;

//     if (realizedPnL > 0 ){
//    position.collateral += uint256(realizedPnL);
//     } else if (realizedPnL < 0) {
//         // Loss subtracts from collateral
//         uint256 loss = uint256(-realizedPnL);
//         if (loss > position.collateral) {
//             revert PositionManager__InsufficientCollateral();
//         }
//    }
//         position.collateral -= loss;

  


    if (reduceSize > 0) {
        uint256 notional = (position.size * position.entryPrice) / 1e18;
        position.leverage = uint16((notional * 100) / position.collateral);
    }

     uint256 newNotional = (position.size * position.entryPrice) / 1e18;
    position.leverage = uint16((newNotional * 100) / position.collateral);
    
    position.liquidationPrice = _calculateLiquidationPrice(
        position.marketId,
        position.side,
        position.entryPrice,
        position.collateral,
        position.size
    );

    positionData.lastUpdateTime = block.timestamp;
    
    adlEngine.updateADLQueue(
        position.marketId,
        positionId,
        position.trader,
        position.side,
        position.unrealizedPnL,
        position.leverage
    );
    
    _updatePortfolio(position.trader);
}

function _applyRealizedPnLToCollateral(
    CommonStructs.Position storage position, 
    int256 realizedPnL
) internal {
    if (realizedPnL > 0) {
        // Profit: add to collateral
        position.collateral += uint256(realizedPnL);
    } else if (realizedPnL < 0) {
        // Loss: subtract from collateral
        uint256 loss = uint256(-realizedPnL);
        require(loss <= position.collateral, "Insufficient collateral for loss");
        position.collateral -= loss;
    }
    // if realizedPnL == 0,  simply do nothing, No profit/loss realized → collateral stays same
}

// ============================================================================
// LIMIT CHECK FUNCTIONS
// ============================================================================

function _checkMarketSpecificLimits(address trader, bytes32 marketId, uint256 notional) internal view {
    if (address(volumeTracker) == address(0)) return;
    
    uint256 totalVolume30d = volumeTracker.get30DayVolume(trader);
    IVolumeTracker.MarketVolume memory marketVol = volumeTracker.getMarketVolume(trader, marketId);
    uint256 marketVolume30d = marketVol.volume30d;
    
    // Prevent > 50% concentration in one market
    if (totalVolume30d > 0) {
        uint256 concentrationBps = (marketVolume30d * 10000) / totalVolume30d;
        if (concentrationBps > 5000) revert PositionManager__MarketConcentrationExceeded(marketId, concentrationBps, 5000);
    }
    
    // New position can't exceed 20% of existing market volume
    uint256 maxNewPosition = (marketVolume30d * 20) / 100;
    if (notional > maxNewPosition) revert PositionManager__MarketPositionExceedsHistory(notional, maxNewPosition);
}

function _checkVolumeBasedLimits(address trader, bytes32 marketId, uint256 notional) internal view {
    if (address(volumeTracker) == address(0)) return;
    
    uint256 volume30d = volumeTracker.get30DayVolume(trader);
    uint256 lifetimeVolume = volumeTracker.getLifetimeVolume(trader);

    // using marketId to get market-specific volume
    uint256 marketVolume30d = volumeTracker.getMarketVolume(trader, marketId).volume30d;

    
    // Single position cannot exceed 10% of 30-day volume
    uint256 maxSinglePosition = (volume30d * 10) / 100;
    if (notional > maxSinglePosition) revert PositionManager__PositionExceedsVolumeLimit(notional, maxSinglePosition);
    
    // Stricter limits for new traders
    if (lifetimeVolume < 10_000e18) {
        uint256 newTraderLimit = 1_000e18;
        if (notional > newTraderLimit) revert PositionManager__NewTraderLimitExceeded(notional, newTraderLimit);
    }

       // Over-Engineering add market-specific limit
    uint256 maxMarketPosition = (marketVolume30d * 20) / 100;
    if (notional > maxMarketPosition) {
    }
}

// ============================================================================
// POSITION STATE MANAGEMENT
// ============================================================================

function _updatePositionState(bytes32 positionId, uint256 currentPrice) internal {
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) return;

    CommonStructs.Position storage pos = posData.position;
    int256 unrealizedPnL = _calculateUnrealizedPnL(pos, currentPrice);
    pos.unrealizedPnL = unrealizedPnL;

    // Update liquidation status
    bool shouldBeLiquidatable = (pos.side == CommonStructs.Side.LONG && currentPrice <= pos.liquidationPrice)
        || (pos.side == CommonStructs.Side.SHORT && currentPrice >= pos.liquidationPrice);
    posData.isLiquidatable = shouldBeLiquidatable;
    posData.lastUpdateTime = block.timestamp;

    // ADL Queue Logic
    if (unrealizedPnL > 0) {
        // int256 pnlUint = unrealizedPnL;
        uint256 adlScore =
            (uint256(unrealizedPnL) * uint256(pos.leverage)) / 100;

        
        adlEngine.updateADLQueue(
            pos.marketId, 
            positionId, 
            pos.trader, 
            pos.side, 
            unrealizedPnL, 
            pos.leverage
            );
        
        if (!posData.inADLQueue) {
            posData.inADLQueue = true;
            emit ADLQueueStatusChanged(positionId, true, adlScore);
        }
    } else if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(
            pos.marketId, 
            positionId, 
            pos.side
            );
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }
}

function _calculateLiquidationPrice(
    bytes32 marketId,
    CommonStructs.Side side,
    uint256 entryPrice,
    uint256 collateral,
    uint256 size
) internal view returns (uint256 liquidPrice) {
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
        liquidPrice = priceMove >= entryPrice ? 1 : entryPrice - priceMove;
    } else {
        liquidPrice = priceMove > type(uint256).max - entryPrice ? type(uint256).max : entryPrice + priceMove;
    }
}

function _calculateUnrealizedPnL(CommonStructs.Position storage pos, uint256 currentPrice) internal view returns (int256) {
    int256 diff = pos.side == CommonStructs.Side.LONG
        ? int256(currentPrice) - int256(pos.entryPrice)
        : int256(pos.entryPrice) - int256(currentPrice);
    return (diff * int256(pos.size)) / 1e18;
}

function _updatePortfolio(address trader) internal {
    // Get all position IDs belonging to this trader
    bytes32[] memory ids = userPositions[trader];

    // Initialize counters
    uint256 totalCol = 0;  // Get all position IDs belonging to this trader
    int256 totalPnL = 0;   // Total paper profit/loss
    uint256 count = 0;    // Number of open positions

    // Loop through each position ID
    for (uint256 i = 0; i < ids.length; i++) {
          // Get the position data using the ID
        PositionData storage pd = positions[ids[i]];
        // Skip deleted/closed positions (openedAt == 0 means empty slot)
        if (pd.position.openedAt == 0) continue;
        // Add this position's values to totals
        totalCol += pd.position.collateral; // Add collateral
        totalPnL += pd.position.unrealizedPnL; // Add paper PnL
        count++;   // Count position
    }

    uint256 marginRatio = totalCol > 0 
    
        ? ((totalCol + uint256(totalPnL > 0 ? totalPnL : int256(0))) * 10000) / totalCol 
        : 0;

    portfolios[trader] = CommonStructs.Portfolio({
        trader: trader,
        totalCollateral: totalCol,
        totalRealizedPnL: totalRealizedPnL[trader],
        totalUnrealizedPnL: totalPnL,
        marginRatio: marginRatio,
        positionCount: count,
        lastUpdateTime: block.timestamp
    });
}

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

function _setDefaultRiskConfigs() internal {
    // Defaults - can be extended with specific market configurations
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

function getPositionNetValue(bytes32 positionId, uint256 currentPrice) external view returns (int256) {
    PositionData storage posData = positions[positionId];
    // Current unrealized PnL
    int256 unrealizedPnL = _calculateUnrealizedPnL(posData.position, currentPrice);
    
    // Pending funding (negative if owed, positive if receiving)
    int256 pendingFunding = _calculateFundingOwed(positionId);
    
    // Net value = collateral + unrealizedPnL - pendingFunding
    return int256(posData.position.collateral) + unrealizedPnL - pendingFunding;
}

function getMarketRiskConfig(bytes32 marketId) 
    external 
    view 
    returns (MarketRiskConfig memory) 
{
    return marketRiskConfigs[marketId];
}

function getPendingFunding(bytes32 positionId) external view returns (int256) {
    return _calculateFundingOwed(positionId);
}

function getFundingOwed(bytes32 positionId) external view returns (int256) {
    return _calculateFundingOwed(positionId);
}

function getPosition(bytes32 positionId) external view returns (PositionData memory) {
    return positions[positionId];
}

function getPositionOwner(bytes32 positionId) external view returns (address) {
    return positionOwner[positionId];
}

function getPositionSize(bytes32 positionId) external view returns (uint256) {
    return positions[positionId].position.size;
}

function getUserPositions(address trader) external view returns (bytes32[] memory) {
    return userPositions[trader];
}

function getPortfolio(address trader) external view returns (CommonStructs.Portfolio memory) {
    return portfolios[trader];
}

function getOpenInterest(bytes32 marketId, CommonStructs.Side side) external view returns (uint256) {
    return openInterest[marketId][side];
}

function getMarketPositions(bytes32 marketId) external view returns (bytes32[] memory) {
    return marketPositions[marketId];
}

function getMarketPositionsBatch(bytes32 marketId) external view returns (bytes32[] memory) {
    return marketPositions[marketId];
}

}