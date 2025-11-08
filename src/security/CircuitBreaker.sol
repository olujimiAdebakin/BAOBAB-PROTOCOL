// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SecurityBase} from "./SecurityBase.sol";

/**
 * @title CircuitBreaker
 * @author BAOBAB Protocol
 * @notice Automatically halts trading during extreme volatility or anomalous conditions
 * @dev Monitors price movements, volume spikes, and liquidation cascades
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                       CIRCUIT BREAKER
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
contract CircuitBreaker is SecurityBase {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Configuration for circuit breaker thresholds
     * @param maxPriceDeviationBps Maximum price change before halt (basis points, e.g., 1000 = 10%)
     * @param maxVolumeSpikeBps Maximum volume spike before halt (basis points)
     * @param maxLiquidationRateBps Maximum liquidation ratio before halt (basis points)
     * @param cooldownPeriod Minimum time circuit must stay open after reset (seconds)
     * @param observationWindow Time window for monitoring (seconds)
     * @param isEnabled Whether circuit breaker is active
     */
    struct CircuitBreakerConfig {
        uint16 maxPriceDeviationBps;
        uint16 maxVolumeSpikeBps;
        uint16 maxLiquidationRateBps;
        uint256 cooldownPeriod;
        uint256 observationWindow;
        bool isEnabled;
    }

    /**
     * @notice Market-specific circuit breaker state
     * @param marketId Market identifier
     * @param isTripped Whether circuit is currently tripped
     * @param tripReason Reason for circuit trip
     * @param tripTime When circuit was tripped
     * @param lastResetTime Last time circuit was reset
     * @param tripCount Number of times tripped
     * @param referencePrice Price at start of observation window (18 decimals)
     * @param referenceVolume Volume at start of observation window (18 decimals)
     */
    struct CircuitState {
        bytes32 marketId;
        bool isTripped;
        TripReason tripReason;
        uint256 tripTime;
        uint256 lastResetTime;
        uint256 tripCount;
        uint256 referencePrice;
        uint256 referenceVolume;
    }

    /**
     * @notice Reasons for circuit breaker activation
     */
    enum TripReason {
        NONE,
        PRICE_DEVIATION,
        VOLUME_SPIKE,
        LIQUIDATION_CASCADE,
        ORACLE_FAILURE,
        MANUAL_HALT
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Global circuit breaker configuration
    CircuitBreakerConfig public config;

    /// @notice Per-market circuit breaker states
    mapping(bytes32 => CircuitState) public circuitStates;

    /// @notice Authorized addresses that can reset circuits
    mapping(address => bool) public guardians;

    /// @notice Protocol admin
    address public admin;

    /// @notice Global emergency halt (affects all markets)
    bool public globalHalt;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event CircuitTripped(bytes32 indexed marketId, TripReason reason, uint256 timestamp);

    event CircuitReset(bytes32 indexed marketId, address indexed resetter, uint256 timestamp);

    event ConfigUpdated(uint16 maxPriceDeviationBps, uint16 maxVolumeSpikeBps, uint16 maxLiquidationRateBps);

    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
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

    constructor(address _admin) {
        if (_admin == address(0)) revert CircuitBreaker__InvalidConfig();

        admin = _admin;
        guardians[_admin] = true;

        // Default configuration
        config = CircuitBreakerConfig({
            maxPriceDeviationBps: 1000, // 10% price swing
            maxVolumeSpikeBps: 30000, // 300% volume spike
            maxLiquidationRateBps: 2000, // 20% liquidation ratio
            cooldownPeriod: 15 minutes,
            observationWindow: 5 minutes,
            isEnabled: true
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyAdmin() {
        if (msg.sender != admin) revert CircuitBreaker__OnlyAdmin();
        _;
    }

    modifier onlyGuardian() {
        if (!guardians[msg.sender]) revert CircuitBreaker__OnlyGuardian();
        _;
    }

    modifier whenCircuitNotTripped(bytes32 marketId) {
        if (globalHalt) revert CircuitBreaker__GlobalHaltActive();
        if (circuitStates[marketId].isTripped) {
            revert CircuitBreaker__CircuitTripped(marketId);
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    MONITORING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if price movement exceeds threshold
     * @param marketId Market to check
     * @param currentPrice Current market price (18 decimals)
     * @return bool True if circuit should trip
     */
    function checkPriceDeviation(bytes32 marketId, uint256 currentPrice) public returns (bool) {
        if (!config.isEnabled) return false;

        CircuitState storage state = circuitStates[marketId];

        // Initialize reference price if first check
        if (state.referencePrice == 0) {
            state.referencePrice = currentPrice;
            return false;
        }

        // Calculate deviation
        uint256 deviation;
        if (currentPrice > state.referencePrice) {
            deviation = ((currentPrice - state.referencePrice) * 10000) / state.referencePrice;
        } else {
            deviation = ((state.referencePrice - currentPrice) * 10000) / state.referencePrice;
        }

        // Trip if deviation exceeds threshold
        if (deviation > config.maxPriceDeviationBps) {
            _tripCircuit(marketId, TripReason.PRICE_DEVIATION);
            return true;
        }

        return false;
    }

    /**
     * @notice Check if volume spike exceeds threshold
     * @param marketId Market to check
     * @param currentVolume Current trading volume (18 decimals)
     * @return bool True if circuit should trip
     */
    function checkVolumeSpike(bytes32 marketId, uint256 currentVolume) public returns (bool) {
        if (!config.isEnabled) return false;

        CircuitState storage state = circuitStates[marketId];

        // Initialize reference volume if first check
        if (state.referenceVolume == 0) {
            state.referenceVolume = currentVolume;
            return false;
        }

        // Calculate spike
        if (currentVolume > state.referenceVolume) {
            uint256 spike = ((currentVolume - state.referenceVolume) * 10000) / state.referenceVolume;

            if (spike > config.maxVolumeSpikeBps) {
                _tripCircuit(marketId, TripReason.VOLUME_SPIKE);
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Check if liquidation ratio exceeds threshold
     * @param marketId Market to check
     * @param totalPositions Total open positions (18 decimals)
     * @param liquidatedPositions Positions liquidated (18 decimals)
     * @return bool True if circuit should trip
     */
    function checkLiquidationCascade(bytes32 marketId, uint256 totalPositions, uint256 liquidatedPositions)
        public
        returns (bool)
    {
        if (!config.isEnabled || totalPositions == 0) return false;

        uint256 liquidationRatio = (liquidatedPositions * 10000) / totalPositions;

        if (liquidationRatio > config.maxLiquidationRateBps) {
            _tripCircuit(marketId, TripReason.LIQUIDATION_CASCADE);
            return true;
        }

        return false;
    }

    /**
     * @notice Manually trip circuit breaker
     * @param marketId Market to halt
     * @dev Only callable by guardians
     */
    function manualHalt(bytes32 marketId) external onlyGuardian {
        _tripCircuit(marketId, TripReason.MANUAL_HALT);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      RESET FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Reset circuit breaker for a market
     * @param marketId Market to reset
     * @param newReferencePrice New baseline price (18 decimals)
     * @dev Only callable by guardians after cooldown period
     */
    function resetCircuit(bytes32 marketId, uint256 newReferencePrice) external onlyGuardian {
        CircuitState storage state = circuitStates[marketId];

        if (!state.isTripped) revert CircuitBreaker__CircuitNotTripped();

        // Ensure cooldown period has elapsed
        if (block.timestamp < state.tripTime + config.cooldownPeriod) {
            revert CircuitBreaker__CooldownNotElapsed();
        }

        state.isTripped = false;
        state.tripReason = TripReason.NONE;
        state.lastResetTime = block.timestamp;
        state.referencePrice = newReferencePrice;
        state.referenceVolume = 0;

        emit CircuitReset(marketId, msg.sender, block.timestamp);
    }

    /**
     * @notice Toggle global emergency halt
     * @dev Only callable by admin
     */
    function toggleGlobalHalt() external onlyAdmin {
        globalHalt = !globalHalt;
        emit GlobalHaltToggled(globalHalt);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update circuit breaker configuration
     * @param _maxPriceDeviationBps New max price deviation (basis points)
     * @param _maxVolumeSpikeBps New max volume spike (basis points)
     * @param _maxLiquidationRateBps New max liquidation ratio (basis points)
     */
    function updateConfig(uint16 _maxPriceDeviationBps, uint16 _maxVolumeSpikeBps, uint16 _maxLiquidationRateBps)
        external
        onlyAdmin
    {
        config.maxPriceDeviationBps = _maxPriceDeviationBps;
        config.maxVolumeSpikeBps = _maxVolumeSpikeBps;
        config.maxLiquidationRateBps = _maxLiquidationRateBps;

        emit ConfigUpdated(_maxPriceDeviationBps, _maxVolumeSpikeBps, _maxLiquidationRateBps);
    }

    /**
     * @notice Add guardian address
     * @param guardian Address to add
     */
    function addGuardian(address guardian) external onlyAdmin {
        guardians[guardian] = true;
        emit GuardianAdded(guardian);
    }

    /**
     * @notice Remove guardian address
     * @param guardian Address to remove
     */
    function removeGuardian(address guardian) external onlyAdmin {
        guardians[guardian] = false;
        emit GuardianRemoved(guardian);
    }

    /**
     * @notice Toggle circuit breaker on/off
     */
    function toggleCircuitBreaker() external onlyAdmin {
        config.isEnabled = !config.isEnabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal function to trip circuit breaker
     * @param marketId Market to halt
     * @param reason Reason for halt
     */
    function _tripCircuit(bytes32 marketId, TripReason reason) internal {
        CircuitState storage state = circuitStates[marketId];

        state.isTripped = true;
        state.tripReason = reason;
        state.tripTime = block.timestamp;
        state.tripCount++;

        emit CircuitTripped(marketId, reason, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if circuit is tripped for a market
     * @param marketId Market to check
     * @return bool True if circuit is tripped
     */
    function isCircuitTripped(bytes32 marketId) external view returns (bool) {
        return globalHalt || circuitStates[marketId].isTripped;
    }

    /**
     * @notice Get circuit state for a market
     * @param marketId Market to query
     * @return CircuitState Circuit state struct
     */
    function getCircuitState(bytes32 marketId) external view returns (CircuitState memory) {
        return circuitStates[marketId];
    }
}
