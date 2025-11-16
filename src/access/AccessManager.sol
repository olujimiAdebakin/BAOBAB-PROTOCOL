// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {RoleRegistry} from "./RoleRegistry.sol";
import {SecurityBase} from "../security/SecurityBase.sol";

/**
 * @title AccessManager
 * @author BAOBAB Protocol
 * @notice Centralized role-based access control (RBAC) system for the entire BAOBAB Protocol
 * @dev Implements hierarchical role permissions with OWNER_ROLE as the root authority
 * * ROLE HIERARCHY:
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                            OWNER_ROLE (Root)                            │
 * │  (Ultimate protocol control, can grant/revoke any role)                │
 * ├─────────────────────┬───────────────────────────────────────────────────┤
 * │   ADMIN_ROLE        │                    GUARDIAN_ROLE                  │
 * │ (Daily operations)  │              (Security & emergencies)             │
 * ├─────────────────────┼───────────────────────────────────────────────────┤
 * │ • KEEPER_ROLE       │ • PAUSER_ROLE                                     │
 * │ • LIQUIDATOR_ROLE   │ (Emergency stops)                                 │
 * │ • ORACLE_UPDATER    │                                                   │
 * │ • MARKET_MAKER      │                    UPGRADER_ROLE                  │
 * │ • FEE_MANAGER       │             (Contract upgrades)                   │
 * │ • BASKET_MANAGER    │                                                   │
 * │ • EVENT_SETTLER     │                                                   │
 * │ • TRADING_OPERATOR  │                                                   │
 * │ • VAULT_OPERATOR    │                                                   │
 * │ • RISK_MANAGER      │                                                   │
 * └─────────────────────┴───────────────────────────────────────────────────┘
 * * @dev Features:
 * • Two-step ownership transfer for security
 * • Batch operations for gas efficiency
 * • Comprehensive role membership tracking
 * • Hierarchical admin permissions
 * • Event logging for all access changes
 */
contract AccessManager is SecurityBase {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Tracks role membership: role => account => hasRole
    /// @dev Uses bytes32 role identifiers for gas efficiency vs string comparisons
    mapping(bytes32 => mapping(address => bool)) private _roles;

    /// @notice Defines role hierarchy: role => adminRole
    /// @dev Each role has an admin role that can grant/revoke it. OWNER_ROLE is admin of itself (root).
    mapping(bytes32 => bytes32) private _roleAdmins;

    /// @notice Reverse mapping: account => array of roles they hold
    /// @dev Enables efficient querying of all roles for an account
    mapping(address => bytes32[]) private _accountRoles;

    /// @notice Role membership lists: role => array of members
    /// @dev Enables efficient querying of all members for a role
    mapping(bytes32 => address[]) private _roleMembers;

    /// @notice Protocol owner address with ultimate authority
    /// @dev Initially set to deployer, transferable via two-step process
    address public owner;

    /// @notice Pending owner during two-step ownership transfer
    /// @dev Security measure to prevent accidental ownership transfers
    address public pendingOwner;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a role is granted to an account
    /// @param role The role identifier that was granted
    /// @param account The address that received the role
    /// @param sender The address that executed the grant
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Emitted when a role is revoked from an account
    /// @param role The role identifier that was revoked
    /// @param account The address that lost the role
    /// @param sender The address that executed the revocation
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /// @notice Emitted when a role's admin is changed
    /// @param role The role whose admin was changed
    /// @param previousAdminRole The previous admin role
    /// @param newAdminRole The new admin role
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /// @notice Emitted when ownership transfer is initiated
    /// @param previousOwner The current owner starting transfer
    /// @param newOwner The proposed new owner
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when ownership transfer is completed
    /// @param previousOwner The previous owner address
    /// @param newOwner The new owner address
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when non-owner tries to execute owner-only function
    error AccessManager__OnlyOwner();

    /// @notice Thrown when account lacks required role for operation
    /// @param role The required role that was missing
    error AccessManager__MissingRole(bytes32 role);

    /// @notice Thrown when trying to grant role to account that already has it
    error AccessManager__AlreadyHasRole();

    /// @notice Thrown when non-admin tries to manage a role
    error AccessManager__UnauthorizedRoleAdmin();

    /// @notice Thrown when trying to revoke own role (use renounceRole instead)
    error AccessManager__CannotRevokeOwnRole();

    /// @notice Thrown when provided address is zero address
    error AccessManager__InvalidAddress();

    /// @notice Thrown when pendingOwner is not set for acceptOwnership
    error AccessManager__NoPendingOwner();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the AccessManager with initial owner and role hierarchy
     * @param _owner The initial protocol owner who receives OWNER_ROLE
     * @dev Sets up complete role admin hierarchy.
     */
    constructor(address _owner) {
        if (_owner == address(0)) revert AccessManager__InvalidAddress();

        owner = _owner;

        // Grant initial owner the ultimate OWNER_ROLE
        _grantRole(RoleRegistry.OWNER_ROLE, _owner);

        // ═══════════════════════════════════════════════════════════════════════════════════════════
        //                    ROLE ADMIN HIERARCHY CONFIGURATION
        // ═══════════════════════════════════════════════════════════════════════════════════════════

        // Root authority: OWNER_ROLE manages itself and top-level roles
        _internalSetRoleAdmin(RoleRegistry.OWNER_ROLE, RoleRegistry.OWNER_ROLE);
        _internalSetRoleAdmin(RoleRegistry.ADMIN_ROLE, RoleRegistry.OWNER_ROLE);
        _internalSetRoleAdmin(RoleRegistry.GUARDIAN_ROLE, RoleRegistry.OWNER_ROLE);

        // Operational roles managed by ADMIN_ROLE
        _internalSetRoleAdmin(RoleRegistry.KEEPER_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.LIQUIDATOR_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.ORACLE_UPDATER_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.MARKET_MAKER_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.FEE_MANAGER_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.BASKET_MANAGER_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.EVENT_SETTLER_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.TRADING_OPERATOR_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.VAULT_OPERATOR_ROLE, RoleRegistry.ADMIN_ROLE);
        _internalSetRoleAdmin(RoleRegistry.RISK_MANAGER_ROLE, RoleRegistry.ADMIN_ROLE);

        // Security roles with specialized admin chains
        _internalSetRoleAdmin(RoleRegistry.PAUSER_ROLE, RoleRegistry.GUARDIAN_ROLE); // Guardians control pausing
        _internalSetRoleAdmin(RoleRegistry.UPGRADER_ROLE, RoleRegistry.OWNER_ROLE); // Only owner controls upgrades
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Restricts function to protocol owner only
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert AccessManager__OnlyOwner();
        _;
    }

    /**
     * @notice Restricts function to accounts with specific role
     * @param role The required role identifier
     * @dev Used by protocol contracts to enforce access control.
     * @dev Example: In TradingEngine: `modifier onlyRole(RoleRegistry.TRADING_OPERATOR_ROLE)`
     */
    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) {
            revert AccessManager__MissingRole(role);
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ROLE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Grants a role to an account
     * @param role The role identifier to grant
     * @param account The address to receive the role
     * @dev Caller must have admin rights for the specified role.
     * @dev Emits RoleGranted event on success.
     * @dev Reverts if account already has the role.
     * @dev OWNER_ROLE can grant ADMIN_ROLE, ADMIN_ROLE can grant KEEPER_ROLE.
     */
    function grantRole(bytes32 role, address account) external {
        // Check if caller has admin rights for this role
        if (!hasRole(_roleAdmins[role], msg.sender)) {
            revert AccessManager__UnauthorizedRoleAdmin();
        }
        _grantRole(role, account);
    }

    /**
     * @notice Revokes a role from an account
     * @param role The role identifier to revoke
     * @param account The address to lose the role
     * @dev Caller must have admin rights for the specified role.
     * @dev Cannot revoke own role (use renounceRole instead).
     * @dev Emits RoleRevoked event on success.
     */
    function revokeRole(bytes32 role, address account) external {
        if (!hasRole(_roleAdmins[role], msg.sender)) {
            revert AccessManager__UnauthorizedRoleAdmin();
        }
        if (msg.sender == account) {
            revert AccessManager__CannotRevokeOwnRole();
        }
        _revokeRole(role, account);
    }

    /**
     * @notice Allows an account to voluntarily renounce a role
     * @param role The role identifier to renounce
     * @dev Can be used by accounts to reduce their privileges.
     * @dev Useful for rotating keys or reducing attack surface.
     */
    function renounceRole(bytes32 role) external {
        _revokeRole(role, msg.sender);
    }

    /**
     * @notice Grants multiple roles to multiple accounts in a single transaction
     * @param roles Array of role identifiers to grant
     * @param accounts Array of addresses to receive roles
     * @dev Gas-efficient way to setup multiple role assignments.
     * @dev Caller must have admin rights for all roles being granted.
     * @dev Arrays must be same length.
     */
    function batchGrantRoles(bytes32[] calldata roles, address[] calldata accounts) external {
        if (roles.length != accounts.length) revert AccessManager__InvalidAddress(); // Reused error for length mismatch

        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(_roleAdmins[roles[i]], msg.sender)) {
                revert AccessManager__UnauthorizedRoleAdmin();
            }
            _grantRole(roles[i], accounts[i]);
        }
    }

    /**
     * @notice Revokes multiple roles from multiple accounts in a single transaction
     * @param roles Array of role identifiers to revoke
     * @param accounts Array of addresses to lose roles
     * @dev Gas-efficient way to remove multiple role assignments.
     * @dev Caller must have admin rights for all roles being revoked.
     * @dev Cannot revoke own roles in batch operation.
     */
    function batchRevokeRoles(bytes32[] calldata roles, address[] calldata accounts) external {
        if (roles.length != accounts.length) revert AccessManager__InvalidAddress(); // Reused error for length mismatch

        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(_roleAdmins[roles[i]], msg.sender)) {
                revert AccessManager__UnauthorizedRoleAdmin();
            }
            if (msg.sender == accounts[i]) {
                revert AccessManager__CannotRevokeOwnRole();
            }
            _revokeRole(roles[i], accounts[i]);
        }
    }

    /**
     * @notice Allows the protocol owner to change the admin role for any other role.
     * @param role The role whose admin is being set.
     * @param newAdminRole The new role that will be able to grant/revoke the target role.
     * @dev Only callable by the current protocol owner.
     * @dev Emits RoleAdminChanged event.
     */
    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external onlyOwner {
        _internalSetRoleAdmin(role, newAdminRole);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    OWNERSHIP TRANSFER
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initiates two-step ownership transfer process
     * @param newOwner The address proposed to become new owner
     * @dev Step 1: Current owner proposes new owner.
     * @dev Step 2: Proposed owner calls acceptOwnership().
     * @dev Only callable by current owner.
     * @dev Emits OwnershipTransferStarted event.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert AccessManager__InvalidAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /**
     * @notice Completes ownership transfer process
     * @dev Must be called by the address currently set as pendingOwner.
     * @dev Transfers OWNER_ROLE from old owner to new owner.
     * @dev Emits OwnershipTransferred event.
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert AccessManager__OnlyOwner(); // Reverted to previous error name for consistency
        if (pendingOwner == address(0)) revert AccessManager__NoPendingOwner();

        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        // Transfer the ultimate OWNER_ROLE
        _revokeRole(RoleRegistry.OWNER_ROLE, oldOwner);
        _grantRole(RoleRegistry.OWNER_ROLE, owner);

        emit OwnershipTransferred(oldOwner, owner);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal implementation of role granting
     * @param role The role identifier to grant
     * @param account The address to receive the role
     * @dev Updates all role membership mappings.
     * @dev Emits RoleGranted event.
     * @dev Reverts if account already has the role.
     */
    function _grantRole(bytes32 role, address account) internal {
        if (_roles[role][account]) revert AccessManager__AlreadyHasRole();

        _roles[role][account] = true;

        // Append to account's role list
        _accountRoles[account].push(role);

        // Append to role's member list
        _roleMembers[role].push(account);

        emit RoleGranted(role, account, msg.sender);
    }

    /**
     * @notice Internal implementation of role revocation
     * @param role The role identifier to revoke
     * @param account The address to lose the role
     * @dev Updates all role membership mappings using gas-efficient swap-and-pop pattern.
     * @dev Emits RoleRevoked event.
     * @dev No-op if account doesn't have the role.
     */
    function _revokeRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) return;

        _roles[role][account] = false;

        // Remove from account's role list (O(n) but roles per account should be small)
        bytes32[] storage accountRoles = _accountRoles[account];
        for (uint256 i = 0; i < accountRoles.length; i++) {
            if (accountRoles[i] == role) {
                // Swap with last element and pop (gas efficient)
                accountRoles[i] = accountRoles[accountRoles.length - 1];
                accountRoles.pop();
                break;
            }
        }

        // Remove from role's member list (O(n) but members per role should be manageable)
        address[] storage members = _roleMembers[role];
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == account) {
                // Swap with last element and pop (gas efficient)
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }

        emit RoleRevoked(role, account, msg.sender);
    }

    /**
     * @notice Internal function to set role admin hierarchy
     * @param role The role to configure
     * @param adminRole The admin role that can manage this role
     * @dev Used during constructor and by the external setRoleAdmin function.
     * @dev Emits RoleAdminChanged event.
     */
    function _internalSetRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        bytes32 previousAdminRole = _roleAdmins[role];
        _roleAdmins[role] = adminRole;
        // Avoid emitting the event if the admin role didn't actually change
        if (previousAdminRole != adminRole) {
            emit RoleAdminChanged(role, previousAdminRole, adminRole);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if an account has a specific role
     * @param role The role identifier to check
     * @param account The address to check
     * @return bool True if account has the role, false otherwise
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    /**
     * @notice Gets the admin role for a given role
     * @param role The role to query
     * @return bytes32 The admin role identifier
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32) {
        return _roleAdmins[role];
    }

    /**
     * @notice Gets all roles held by an account
     * @param account The address to query
     * @return roles Array of role identifiers the account holds
     */
    function getAccountRoles(address account) external view returns (bytes32[] memory roles) {
        return _accountRoles[account];
    }

    /**
     * @notice Gets all members of a specific role
     * @param role The role to query
     * @return members Array of addresses that hold the role
     */
    function getRoleMembers(bytes32 role) external view returns (address[] memory members) {
        return _roleMembers[role];
    }

    /**
     * @notice Gets the number of members for a role
     * @param role The role to query
     * @return count The number of accounts that hold this role
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256 count) {
        return _roleMembers[role].length;
    }

    /**
     * @notice Checks if account has any of the specified roles
     * @param roles Array of roles to check
     * @param account The address to check
     * @return bool True if account has at least one of the roles
     */
    function hasAnyRole(bytes32[] calldata roles, address account) external view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(roles[i], account)) return true;
        }
        return false;
    }

    /**
     * @notice Checks if account has all of the specified roles
     * @param roles Array of roles to check
     * @param account The address to check
     * @return bool True if account has all of the roles
     */
    function hasAllRoles(bytes32[] calldata roles, address account) external view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(roles[i], account)) return false;
        }
        return true;
    }
}
