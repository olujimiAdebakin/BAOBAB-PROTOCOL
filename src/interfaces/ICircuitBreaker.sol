// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title ICircuitBreaker
 * @notice Interface for the CircuitBreaker contract, exposing public configuration, state, and control functions.
 */
interface ICircuitBreaker {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS & ENUMS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    enum TripReason {
        NONE,
        PRICE_DEVIATION,
        VOLUME_SPIKE,
        LIQUIDATION_CASCADE,
        ORACLE_FAILURE,
        MANUAL_HALT
    }

    struct CircuitBreakerConfig {
        uint16 maxPriceDeviationBps;
        uint16 maxVolumeSpikeBps;
        uint16 maxLiquidationRateBps;
        uint256 cooldownPeriod;
        uint256 observationWindow;
        bool isEnabled;
    }

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
    //                                    MONITORING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    function checkPriceDeviation(bytes32 marketId, uint256 currentPrice) external returns (bool);
    function checkVolumeSpike(bytes32 marketId, uint256 currentVolume) external returns (bool);
    function checkLiquidationCascade(bytes32 marketId, uint256 totalPositions, uint256 liquidatedPositions)
        external
        returns (bool);

    function manualHalt(bytes32 marketId) external;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      RESET FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    function resetCircuit(bytes32 marketId, uint256 newReferencePrice) external;
    function toggleGlobalHalt() external;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    function updateConfig(uint16 _maxPriceDeviationBps, uint16 _maxVolumeSpikeBps, uint16 _maxLiquidationRateBps)
        external;
    function addGuardian(address guardian) external;
    function removeGuardian(address guardian) external;
    function toggleCircuitBreaker() external;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    function config() external view returns (CircuitBreakerConfig memory);
    function circuitStates(bytes32 marketId) external view returns (CircuitState memory);
    function guardians(address) external view returns (bool);
    function admin() external view returns (address);
    function globalHalt() external view returns (bool);
    function isCircuitTripped(bytes32 marketId) external view returns (bool);
    function getCircuitState(bytes32 marketId) external view returns (CircuitState memory);
}
