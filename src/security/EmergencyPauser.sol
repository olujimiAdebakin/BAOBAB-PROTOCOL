// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SecurityBase} from "./SecurityBase.sol";

/**
 * @title EmergencyPauser
 * @author BAOBAB Protocol
 * @notice Coordinated emergency pause system for protocol-wide or module-specific halts
 * @dev Supports granular pause controls with multi-sig and timelock integration
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                      EMERGENCY PAUSER
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
contract EmergencyPauser is SecurityBase {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Pause configuration for a module
     * @param isPaused Whether module is currently paused
     * @param pausedAt Timestamp when pause was activated
     * @param pausedBy Address that triggered pause
     * @param reason Human-readable reason for pause
     * @param canUnpause Whether module can be unpaused (false = requires upgrade)
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
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Protocol-wide pause (affects all modules)
    bool public protocolPaused;

    /// @notice Per-module pause states
    mapping(bytes32 => PauseState) public modulePauseStates;

    /// @notice Authority levels for addresses
    mapping(address => AuthorityLevel) public authorities;

    /// @notice Admin address
    address public protocolAdmin;

    /// @notice Multi-sig address
    address public multisig;

    /// @notice Timelock delay for unpause operations (seconds)
    uint256 public unpauseDelay;

    /// @notice Scheduled unpause operations
    mapping(bytes32 => uint256) public scheduledUnpauses;

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
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error EmergencyPauser__ProtocolPaused();
    error EmergencyPauser__ModulePaused(bytes32 moduleId);
    error EmergencyPauser__InsufficientAuthority();
    error EmergencyPauser__ModuleNotPaused();
    error EmergencyPauser__CannotUnpause();
    error EmergencyPauser__TimelockNotElapsed();
    error EmergencyPauser__InvalidAddress();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor(address _admin, address _multisig) {
        if (_admin == address(0) || _multisig == address(0)) {
            revert EmergencyPauser__InvalidAddress();
        }

        protocolAdmin = _admin;
        multisig = _multisig;
        unpauseDelay = 24 hours;

        // Grant authorities
        authorities[_admin] = AuthorityLevel.ADMIN;
        authorities[_multisig] = AuthorityLevel.MULTISIG;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyAuthority(AuthorityLevel required) {
        if (uint8(authorities[msg.sender]) < uint8(required)) {
            revert EmergencyPauser__InsufficientAuthority();
        }
        _;
    }

    modifier whenProtocolNotPaused() {
        if (protocolPaused) revert EmergencyPauser__ProtocolPaused();
        _;
    }

    modifier whenModuleNotPaused(bytes32 moduleId) {
        if (modulePauseStates[moduleId].isPaused) {
            revert EmergencyPauser__ModulePaused(moduleId);
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      PAUSE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Pause entire protocol
     * @param reason Reason for emergency pause
     * @dev Only callable by multisig
     */
    function pauseProtocol(string calldata reason) external onlyAuthority(AuthorityLevel.MULTISIG) {
        protocolPaused = true;
        emit ProtocolPaused(msg.sender, reason);
    }

    /**
     * @notice Unpause protocol
     * @dev Only callable by multisig after timelock
     */
    function unpauseProtocol() external onlyAuthority(AuthorityLevel.MULTISIG) {
        protocolPaused = false;
        emit ProtocolUnpaused(msg.sender);
    }

    /**
     * @notice Pause specific module
     * @param moduleId Module identifier (keccak256 of module name)
     * @param reason Reason for pause
     * @param canUnpause Whether module can be unpaused later
     * @dev Guardians can pause, admins can pause with unpause ability
     */
    function pauseModule(bytes32 moduleId, string calldata reason, bool canUnpause)
        external
        onlyAuthority(AuthorityLevel.GUARDIAN)
    {
        PauseState storage state = modulePauseStates[moduleId];

        state.isPaused = true;
        state.pausedAt = block.timestamp;
        state.pausedBy = msg.sender;
        state.reason = reason;
        state.canUnpause = canUnpause;

        emit ModulePaused(moduleId, msg.sender, reason);
    }

    /**
     * @notice Schedule unpause for a module
     * @param moduleId Module to unpause
     * @dev Initiates timelock delay before unpause can execute
     */
    function scheduleUnpause(bytes32 moduleId) external onlyAuthority(AuthorityLevel.ADMIN) {
        PauseState storage state = modulePauseStates[moduleId];

        if (!state.isPaused) revert EmergencyPauser__ModuleNotPaused();
        if (!state.canUnpause) revert EmergencyPauser__CannotUnpause();

        uint256 executeAt = block.timestamp + unpauseDelay;
        scheduledUnpauses[moduleId] = executeAt;

        emit UnpauseScheduled(moduleId, executeAt);
    }

    /**
     * @notice Execute scheduled unpause
     * @param moduleId Module to unpause
     * @dev Can only execute after timelock delay
     */
    function executeUnpause(bytes32 moduleId) external onlyAuthority(AuthorityLevel.ADMIN) {
        uint256 executeAt = scheduledUnpauses[moduleId];

        if (executeAt == 0 || block.timestamp < executeAt) {
            revert EmergencyPauser__TimelockNotElapsed();
        }

        PauseState storage state = modulePauseStates[moduleId];
        state.isPaused = false;

        delete scheduledUnpauses[moduleId];

        emit ModuleUnpaused(moduleId, msg.sender);
    }

    /**
     * @notice Emergency unpause (bypasses timelock)
     * @param moduleId Module to unpause
     * @dev Only callable by multisig in extreme emergencies
     */
    function emergencyUnpause(bytes32 moduleId) external onlyAuthority(AuthorityLevel.MULTISIG) {
        PauseState storage state = modulePauseStates[moduleId];

        if (!state.canUnpause) revert EmergencyPauser__CannotUnpause();

        state.isPaused = false;
        delete scheduledUnpauses[moduleId];

        emit ModuleUnpaused(moduleId, msg.sender);
    }

    /**
     * @notice Emergency unpause protocol (bypasses any timelock)
     * @dev Only multisig in extreme recovery scenarios
     */
    function emergencyUnpauseProtocol() external onlyAuthority(AuthorityLevel.MULTISIG) {
        protocolPaused = false;
        emit ProtocolUnpaused(msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Grant authority to address
     * @param account Address to grant authority
     * @param level Authority level to grant
     */
    function grantAuthority(address account, AuthorityLevel level) external onlyAuthority(AuthorityLevel.MULTISIG) {
        authorities[account] = level;
        emit AuthorityGranted(account, level);
    }

    /**
     * @notice Revoke authority from address
     * @param account Address to revoke
     */
    function revokeAuthority(address account) external onlyAuthority(AuthorityLevel.MULTISIG) {
        authorities[account] = AuthorityLevel.NONE;
        emit AuthorityRevoked(account);
    }

    /**
     * @notice Update unpause delay
     * @param newDelay New delay in seconds
     */
    function setUnpauseDelay(uint256 newDelay) external onlyAuthority(AuthorityLevel.MULTISIG) {
        unpauseDelay = newDelay;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if module is paused (includes protocol-level pause)
     * @param moduleId Module to check
     * @return bool True if paused (either module-specific or protocol-wide)ed
     */
    function isModulePaused(bytes32 moduleId) external view returns (bool) {
        return protocolPaused || modulePauseStates[moduleId].isPaused;
    }

    /**
     * @notice Get pause state for module
     * @param moduleId Module to query
     * @return PauseState Pause state struct
     */
    function getPauseState(bytes32 moduleId) external view returns (PauseState memory) {
        return modulePauseStates[moduleId];
    }

    /**
     * @notice Check authority level for address
     * @param account Address to check
     * @return AuthorityLevel Authority level
     */
    function getAuthority(address account) external view returns (AuthorityLevel) {
        return authorities[account];
    }

    /**
     * @notice Generate module ID from name
     * @param moduleName Module name (e.g., "TradingEngine", "OrderBook")
     * @return bytes32 Module ID
     */
    function getModuleId(string calldata moduleName) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(moduleName));
    }
}
