// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title IEmergencyPauser
 * @notice Interface for the EmergencyPauser contract, providing functions for protocol-wide
 * and granular module pausing, as well as authority management.
 */
interface IEmergencyPauser {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS & ENUMS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Pause configuration for a module
     */
    struct PauseState {
        bool isPaused;
        uint256 pausedAt;
        address pausedBy;
        string reason;
        bool canUnpause;
    }

    /**
     * @notice Pause authority levels
     */
    enum AuthorityLevel {
        NONE,
        GUARDIAN, // Can pause modules
        ADMIN, // Can pause/unpause modules
        MULTISIG // Can pause/unpause protocol-wide

    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event ProtocolPaused(address indexed by, string reason);
    event ProtocolUnpaused(address indexed by);
    event ModulePaused(bytes32 indexed moduleId, address indexed by, string reason);
    event ModuleUnpaused(bytes32 indexed moduleId, address indexed by);
    event UnpauseScheduled(bytes32 indexed moduleId, uint256 executeAt);
    event AuthorityGranted(address indexed account, AuthorityLevel level);
    event AuthorityRevoked(address indexed account);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         PAUSE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    function pauseProtocol(string calldata reason) external;
    function unpauseProtocol() external;

    function pauseModule(bytes32 moduleId, string calldata reason, bool canUnpause) external;
    function scheduleUnpause(bytes32 moduleId) external;
    function executeUnpause(bytes32 moduleId) external;
    function emergencyUnpause(bytes32 moduleId) external;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                        ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    function grantAuthority(address account, AuthorityLevel level) external;
    function revokeAuthority(address account) external;
    function setUnpauseDelay(uint256 newDelay) external;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    function protocolPaused() external view returns (bool);
    function modulePauseStates(bytes32 moduleId) external view returns (PauseState memory);
    function authorities(address account) external view returns (AuthorityLevel);
    function admin() external view returns (address);
    function multisig() external view returns (address);
    function unpauseDelay() external view returns (uint256);
    function scheduledUnpauses(bytes32 moduleId) external view returns (uint256);

    function isModulePaused(bytes32 moduleId) external view returns (bool);
    function getPauseState(bytes32 moduleId) external view returns (PauseState memory);
    function getAuthority(address account) external view returns (AuthorityLevel);
    function getModuleId(string calldata moduleName) external pure returns (bytes32);
}
