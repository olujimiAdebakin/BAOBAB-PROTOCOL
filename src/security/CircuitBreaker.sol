// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SecurityBase} from "./SecurityBase.sol";
import {CommonStructs} from "../libraries/structs/CommonStructs.sol";
import {AddressUtils} from "../libraries/utils/AddressUtils.sol";

/**
 * @title CircuitBreaker
 * @author BAOBAB Protocol
 * @notice Comprehensive circuit breaker system for trading protection and fee distribution safety
 * @dev Monitors market conditions (price, volume, liquidations) and fee distribution anomalies
 * 
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                  DUAL-LAYER CIRCUIT BREAKER SYSTEM
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 * 
 * TRADING PROTECTION:              FEE DISTRIBUTION PROTECTION:
 * • Price deviation monitoring     • Fee amount anomaly detection
 * • Volume spike detection         • Distribution failure tracking  
 * • Liquidation cascade prevention • Recipient balance limits
 * • Market-specific circuits       • Global fee circuit breaker
 * 
 * @dev Features:
 * • Per-market trading circuit breakers
 * • Global fee distribution protection
 * • Two-tier admin/guardian access control
 * • Configurable thresholds and cooldowns
 * • Comprehensive event logging
 */
contract CircuitBreaker is SecurityBase {
    using CommonStructs for *;
    using AddressUtils for *;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Global circuit breaker configuration for both trading and fee protection
    CommonStructs.CircuitBreakerConfig public config;

    /// @notice Protocol admin with ultimate control over configuration
    address public admin;

    /// @notice Global emergency halt that affects all markets and fee distribution
    bool public globalHalt;

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                                  TRADING PROTECTION STATE
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /// @notice Per-market circuit breaker states for trading protection
    mapping(bytes32 => CommonStructs.CircuitState) public circuitStates;

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                               FEE DISTRIBUTION PROTECTION STATE
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /// @notice Fee distribution circuit breaker state
    CommonStructs.FeeCircuitState public feeCircuitState;

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                                     ACCESS CONTROL STATE
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /// @notice Authorized guardian addresses that can trip/reset circuits
    mapping(address => bool) public guardians;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                                  TRADING PROTECTION EVENTS
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a trading circuit breaker is tripped for a specific market
    event CircuitTripped(bytes32 indexed marketId, CommonStructs.TripReason reason, uint256 timestamp);

    /// @notice Emitted when a trading circuit breaker is reset for a specific market
    event CircuitReset(bytes32 indexed marketId, address indexed resetter, uint256 timestamp);

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                               FEE DISTRIBUTION PROTECTION EVENTS
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when the fee distribution circuit breaker is tripped
    event FeeCircuitTripped(CommonStructs.TripReason reason, uint256 timestamp, uint256 amount);

    /// @notice Emitted when the fee distribution circuit breaker is reset
    event FeeCircuitReset(address indexed resetter, uint256 timestamp);

    /// @notice Emitted when a fee distribution is checked for anomalies
    event FeeDistributionChecked(uint256 feeAmount, bool triggered);

    /// @notice Emitted when a recipient balance exceeds safe limits
    event RecipientBalanceLimitExceeded(address recipient, uint256 currentBalance);

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                                     CONFIGURATION EVENTS
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when circuit breaker configuration is updated
    event ConfigUpdated(
        uint16 maxPriceDeviationBps, 
        uint16 maxVolumeSpikeBps, 
        uint16 maxLiquidationRateBps,
        uint256 maxFeeAmount,
        uint16 maxFeeSpikeBps
    );

    /// @notice Emitted when a guardian is added to the system
    event GuardianAdded(address indexed guardian);

    /// @notice Emitted when a guardian is removed from the system
    event GuardianRemoved(address indexed guardian);

    /// @notice Emitted when global halt state is toggled
    event GlobalHaltToggled(bool halted);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error CircuitBreaker__CircuitTripped(bytes32 marketId);
    error CircuitBreaker__CircuitNotTripped();
    error CircuitBreaker__CooldownNotElapsed();
    error CircuitBreaker__OnlyAdmin();
    error CircuitBreaker__OnlyGuardian();
    error CircuitBreaker__GlobalHaltActive();
    error CircuitBreaker__InvalidConfig();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the CircuitBreaker with default configuration
     * @param _admin The address that will have admin privileges
     * @dev Sets up default thresholds for both trading and fee protection
     *     Grants guardian role to the admin initially
     * 
     */
    constructor(address _admin) {
        _admin.validateNotZero();

        admin = _admin;
        guardians[_admin] = true;

        // Default configuration balancing safety and usability
        
        config = CommonStructs.CircuitBreakerConfig({
            // TRADING PROTECTION CONFIGURATION
            maxPriceDeviationBps: 1000,     // 10% price swing threshold
            maxVolumeSpikeBps: 30000,       // 300% volume spike threshold  
            maxLiquidationRateBps: 2000,    // 20% liquidation ratio threshold
            cooldownPeriod: 15 minutes,     // Minimum time circuit must stay open after reset
            observationWindow: 5 minutes,   // Time window for market condition monitoring
            isEnabled: true,                // Global toggle for trading protection
            
            // FEE DISTRIBUTION PROTECTION CONFIGURATION
            maxFeeAmount: 1_000_000 * 1e6,  // $1M maximum single distribution
            maxFeeSpikeBps: 1000,           // 10x spike from average (1000% = 10x)
            maxConsecutiveFailures: 5,      // 5 consecutive failures trigger circuit
            maxRecipientBalance: 10_000_000 * 1e6, // $10M max per recipient
            feeProtectionEnabled: true      // Global toggle for fee protection
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Restrict access to admin only
     */
    modifier onlyAdmin() {
        if (msg.sender != admin) revert CircuitBreaker__OnlyAdmin();
        _;
    }

    /**
     * @notice Restrict access to guardians only
     */
    modifier onlyGuardian() {
        if (!guardians[msg.sender]) revert CircuitBreaker__OnlyGuardian();
        _;
    }

    /**
     * @notice Ensure circuit is not tripped for specific market
     * @param marketId The market to check
     */
    modifier whenCircuitNotTripped(bytes32 marketId) {
        if (globalHalt) revert CircuitBreaker__GlobalHaltActive();
        if (circuitStates[marketId].isTripped) {
            revert CircuitBreaker__CircuitTripped(marketId);
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                  TRADING PROTECTION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if price movement exceeds threshold and trip circuit if needed
     * @param marketId Market identifier to check
     * @param currentPrice Current market price with 18 decimals
     * @return bool True if circuit was tripped, false otherwise
     * @dev Compares current price to reference price, trips if deviation exceeds maxPriceDeviationBps
     */
    function checkPriceDeviation(bytes32 marketId, uint256 currentPrice) 
        public 
        returns (bool) 
    {
        if (!config.isEnabled) return false;

        CommonStructs.CircuitState storage state = circuitStates[marketId];

        // Initialize reference price on first check for this market
        if (state.referencePrice == 0) {
            state.referencePrice = currentPrice;
            return false;
        }

        // Calculate price deviation in basis points
        uint256 deviation;
        if (currentPrice > state.referencePrice) {
            deviation = ((currentPrice - state.referencePrice) * 10000) / state.referencePrice;
        } else {
            deviation = ((state.referencePrice - currentPrice) * 10000) / state.referencePrice;
        }

        // Trip circuit if deviation exceeds configured threshold
        if (deviation > config.maxPriceDeviationBps) {
            _tripCircuit(marketId, CommonStructs.TripReason.PRICE_DEVIATION);
            return true;
        }

        return false;
    }

    /**
     * @notice Check if volume spike exceeds threshold and trip circuit if needed
     * @param marketId Market identifier to check
     * @param currentVolume Current trading volume with 18 decimals
     * @return bool True if circuit was tripped, false otherwise
     * @dev Monitors volume spikes compared to reference volume
     */
    function checkVolumeSpike(bytes32 marketId, uint256 currentVolume) 
        public 
        returns (bool) 
    {
        if (!config.isEnabled) return false;

        CommonStructs.CircuitState storage state = circuitStates[marketId];

        // Initialize reference volume on first check
        if (state.referenceVolume == 0) {
            state.referenceVolume = currentVolume;
            return false;
        }

        // Calculate volume spike in basis points
        if (currentVolume > state.referenceVolume) {
            uint256 spike = ((currentVolume - state.referenceVolume) * 10000) / state.referenceVolume;

            if (spike > config.maxVolumeSpikeBps) {
                _tripCircuit(marketId, CommonStructs.TripReason.VOLUME_SPIKE);
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Check if liquidation ratio exceeds threshold and trip circuit if needed
     * @param marketId Market identifier to check
     * @param totalPositions Total open positions with 18 decimals
     * @param liquidatedPositions Positions liquidated in current period with 18 decimals
     * @return bool True if circuit was tripped, false otherwise
     * @dev Prevents liquidation cascades by monitoring liquidation rates
     */
    function checkLiquidationCascade(
        bytes32 marketId, 
        uint256 totalPositions, 
        uint256 liquidatedPositions
    ) public returns (bool) {
        if (!config.isEnabled || totalPositions == 0) return false;

        // Calculate liquidation ratio in basis points
        uint256 liquidationRatio = (liquidatedPositions * 10000) / totalPositions;

        if (liquidationRatio > config.maxLiquidationRateBps) {
            _tripCircuit(marketId, CommonStructs.TripReason.LIQUIDATION_CASCADE);
            return true;
        }

        return false;
    }

    /**
     * @notice Manually trip trading circuit breaker for a specific market
     * @param marketId Market identifier to halt
     * @dev Guardian-only function for emergency manual intervention
     */
    function manualHalt(bytes32 marketId) external onlyGuardian {
        _tripCircuit(marketId, CommonStructs.TripReason.MANUAL_HALT);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                               FEE DISTRIBUTION PROTECTION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check fee distribution amount for anomalies and trip circuit if needed
     * @param feeAmount The fee amount being distributed with settlement token decimals
     * @return bool True if circuit was tripped, false otherwise
     * @dev Monitors for absolute amount thresholds and spikes compared to historical average
     */
    function checkFeeDistribution(uint256 feeAmount) public returns (bool) {
        if (!config.feeProtectionEnabled) return false;

        CommonStructs.FeeCircuitState storage state = feeCircuitState;

        // Check 1: Absolute amount threshold protection
        if (feeAmount > config.maxFeeAmount) {
            _tripFeeCircuit(CommonStructs.TripReason.FEE_AMOUNT_ANOMALY, feeAmount);
            return true;
        }

        // Check 2: Spike detection compared to rolling average
        if (state.averageFeeAmount > 0 && feeAmount > state.averageFeeAmount * 10) {
            _tripFeeCircuit(CommonStructs.TripReason.FEE_SPIKE_DETECTED, feeAmount);
            return true;
        }

        // Update rolling average using simple 10-period moving average
        if (state.averageFeeAmount == 0) {
            state.averageFeeAmount = feeAmount;
        } else {
            state.averageFeeAmount = (state.averageFeeAmount * 9 + feeAmount) / 10;
        }

        state.lastFeeAmount = feeAmount;

        emit FeeDistributionChecked(feeAmount, false);
        return false;
    }

    /**
     * @notice Report a distribution failure and trip circuit if too many consecutive failures
     * @return bool True if circuit was tripped due to excessive failures, false otherwise
     * @dev Should be called when a fee distribution to a recipient fails
     */
    function reportDistributionFailure() public returns (bool) {
        if (!config.feeProtectionEnabled) return false;

        CommonStructs.FeeCircuitState storage state = feeCircuitState;
        
        state.consecutiveFailures++;
        
        if (state.consecutiveFailures >= config.maxConsecutiveFailures) {
            _tripFeeCircuit(CommonStructs.TripReason.DISTRIBUTION_FAILURE, 0);
            return true;
        }
        
        return false;
    }

    /**
     * @notice Check if recipient balance exceeds safe limits and trip circuit if needed
     * @param recipient The recipient address to check
     * @param currentBalance Current balance of the recipient with settlement token decimals
     * @return bool True if circuit was tripped, false otherwise
     * @dev Prevents excessive accumulation in recipient contracts that could become attack targets
     */
    function checkRecipientBalance(address recipient, uint256 currentBalance) 
        public 
        returns (bool) 
    {
        if (!config.feeProtectionEnabled) return false;

        if (currentBalance > config.maxRecipientBalance) {
            _tripFeeCircuit(CommonStructs.TripReason.RECIPIENT_BALANCE_LIMIT, currentBalance);
            emit RecipientBalanceLimitExceeded(recipient, currentBalance);
            return true;
        }
        return false;
    }

    /**
     * @notice Reset consecutive distribution failure counter
     * @dev Should be called after successful fee distributions to reset failure tracking
     */
    function resetFailureCounter() public {
        if (feeCircuitState.consecutiveFailures > 0) {
            feeCircuitState.consecutiveFailures = 0;
        }
    }

    /**
     * @notice Manually trip fee distribution circuit breaker
     * @dev Guardian-only function for emergency manual intervention in fee distribution
     */
    function manualHaltFeeDistribution() external onlyGuardian {
        _tripFeeCircuit(CommonStructs.TripReason.MANUAL_HALT, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      RESET FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Reset trading circuit breaker for a specific market
     * @param marketId Market identifier to reset
     * @param newReferencePrice New baseline price with 18 decimals for future deviation calculations
     * @dev Guardian-only function, requires cooldown period to have elapsed
     */
    function resetCircuit(bytes32 marketId, uint256 newReferencePrice) external onlyGuardian {
        CommonStructs.CircuitState storage state = circuitStates[marketId];

        if (!state.isTripped) revert CircuitBreaker__CircuitNotTripped();

        // Ensure cooldown period has elapsed before allowing reset
        if (block.timestamp < state.tripTime + config.cooldownPeriod) {
            revert CircuitBreaker__CooldownNotElapsed();
        }

        state.isTripped = false;
        state.tripReason = CommonStructs.TripReason.NONE;
        state.lastResetTime = block.timestamp;
        state.referencePrice = newReferencePrice;
        state.referenceVolume = 0;

        emit CircuitReset(marketId, msg.sender, block.timestamp);
    }

    /**
     * @notice Reset fee distribution circuit breaker
     * @dev Guardian-only function, no cooldown required for fee circuit resets
     */
    function resetFeeCircuit() external onlyGuardian {
        CommonStructs.FeeCircuitState storage state = feeCircuitState;

        if (!state.isTripped) revert CircuitBreaker__CircuitNotTripped();

        state.isTripped = false;
        state.tripReason = CommonStructs.TripReason.NONE;
        state.consecutiveFailures = 0;
        state.triggeredAmount = 0;

        emit FeeCircuitReset(msg.sender, block.timestamp);
    }

    /**
     * @notice Toggle global emergency halt affecting all markets and fee distribution
     * @dev Admin-only function for extreme emergency scenarios
     */
    function toggleGlobalHalt() external onlyAdmin {
        globalHalt = !globalHalt;
        emit GlobalHaltToggled(globalHalt);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update comprehensive circuit breaker configuration
     * @param _maxPriceDeviationBps New maximum price deviation threshold in basis points
     * @param _maxVolumeSpikeBps New maximum volume spike threshold in basis points
     * @param _maxLiquidationRateBps New maximum liquidation ratio threshold in basis points
     * @param _maxFeeAmount New maximum single fee distribution amount
     * @param _maxFeeSpikeBps New maximum fee spike threshold in basis points
     * @param _maxConsecutiveFailures New maximum consecutive distribution failures before trip
     * @param _maxRecipientBalance New maximum recipient balance limit
     * @dev Admin-only function for system parameter tuning
     */
    function updateConfig(
        uint16 _maxPriceDeviationBps, 
        uint16 _maxVolumeSpikeBps, 
        uint16 _maxLiquidationRateBps,
        uint256 _maxFeeAmount,
        uint16 _maxFeeSpikeBps,
        uint8 _maxConsecutiveFailures,
        uint256 _maxRecipientBalance
    ) external onlyAdmin {
        // Trading protection configuration
        config.maxPriceDeviationBps = _maxPriceDeviationBps;
        config.maxVolumeSpikeBps = _maxVolumeSpikeBps;
        config.maxLiquidationRateBps = _maxLiquidationRateBps;
        
        // Fee distribution protection configuration
        config.maxFeeAmount = _maxFeeAmount;
        config.maxFeeSpikeBps = _maxFeeSpikeBps;
        config.maxConsecutiveFailures = _maxConsecutiveFailures;
        config.maxRecipientBalance = _maxRecipientBalance;

        emit ConfigUpdated(
            _maxPriceDeviationBps, 
            _maxVolumeSpikeBps, 
            _maxLiquidationRateBps,
            _maxFeeAmount,
            _maxFeeSpikeBps
        );
    }

    /**
     * @notice Add a new guardian address
     * @param guardian The address to grant guardian privileges
     * @dev Admin-only function for expanding emergency response team
     */
    function addGuardian(address guardian) external onlyAdmin {
        guardians[guardian] = true;
        emit GuardianAdded(guardian);
    }

    /**
     * @notice Remove a guardian address
     * @param guardian The address to revoke guardian privileges from
     * @dev Admin-only function for access control management
     */
    function removeGuardian(address guardian) external onlyAdmin {
        guardians[guardian] = false;
        emit GuardianRemoved(guardian);
    }

    /**
     * @notice Toggle trading circuit breaker system on/off
     * @dev Admin-only function for temporary system maintenance
     */
    function toggleTradingProtection() external onlyAdmin {
        config.isEnabled = !config.isEnabled;
    }

    /**
     * @notice Toggle fee distribution protection system on/off
     * @dev Admin-only function for temporary system maintenance
     */
    function toggleFeeProtection() external onlyAdmin {
        config.feeProtectionEnabled = !config.feeProtectionEnabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal function to trip trading circuit breaker
     * @param marketId Market identifier to halt
     * @param reason The reason for tripping the circuit
     * @dev Updates circuit state and emits appropriate event
     */
    function _tripCircuit(bytes32 marketId, CommonStructs.TripReason reason) internal {
        CommonStructs.CircuitState storage state = circuitStates[marketId];

        state.isTripped = true;
        state.tripReason = reason;
        state.tripTime = block.timestamp;
        state.tripCount++;

        emit CircuitTripped(marketId, reason, block.timestamp);
    }

    /**
     * @notice Internal function to trip fee distribution circuit breaker
     * @param reason The reason for tripping the circuit
     * @param amount The fee amount that triggered the trip (if applicable)
     * @dev Updates fee circuit state and emits appropriate event
     */
    function _tripFeeCircuit(CommonStructs.TripReason reason, uint256 amount) internal {
        CommonStructs.FeeCircuitState storage state = feeCircuitState;

        state.isTripped = true;
        state.tripReason = reason;  
        state.tripTime = block.timestamp;
        state.triggeredAmount = amount;

        emit FeeCircuitTripped(reason, block.timestamp, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                                  TRADING PROTECTION VIEWS
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Check if circuit is tripped for a specific market
     * @param marketId Market identifier to check
     * @return bool True if circuit is tripped or global halt is active
     */
    function isCircuitTripped(bytes32 marketId) external view returns (bool) {
        return globalHalt || circuitStates[marketId].isTripped;
    }

    /**
     * @notice Get complete circuit state for a specific market
     * @param marketId Market identifier to query
     * @return CircuitState The complete circuit state for the market
     */
    function getCircuitState(bytes32 marketId) external view returns (CommonStructs.CircuitState memory) {
        return circuitStates[marketId];
    }

    // ──────────────────────────────────────────────────────────────────────────────────────────────
    //                               FEE DISTRIBUTION PROTECTION VIEWS
    // ──────────────────────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Check if fee distribution circuit is tripped
     * @return bool True if fee circuit is tripped or global halt is active
     */
    function isFeeCircuitTripped() external view returns (bool) {
        return globalHalt || feeCircuitState.isTripped;
    }

    /**
     * @notice Get complete fee distribution circuit state
     * @return FeeCircuitState The complete fee circuit state
     */
    function getFeeCircuitState() external view returns (CommonStructs.FeeCircuitState memory) {
        return feeCircuitState;
    }

    /**
     * @notice Check if any circuit (trading or fee) is currently tripped
     * @return bool True if any circuit is tripped or global halt is active
     */
    function isAnyCircuitTripped() external view returns (bool) {
        return globalHalt || feeCircuitState.isTripped;
    }
}