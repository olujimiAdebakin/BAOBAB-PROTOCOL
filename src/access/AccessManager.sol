// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {RoleRegistry} from "./RoleRegistry.sol";
import {SecurityBase} from "../security/SecurityBase.sol";

/**
 * @title AccessManager
 * @author BAOBAB Protocol
 * @notice Central access control for all protocol contracts
 * @dev Role-based access control with hierarchical permissions
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                       ACCESS MANAGER
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
contract AccessManager is SecurityBase {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Role memberships: role => account => isMember
    mapping(bytes32 => mapping(address => bool)) private _roles;

    /// @notice Role admin: role => adminRole (who can grant/revoke this role)
    mapping(bytes32 => bytes32) private _roleAdmins;

    /// @notice Account roles: account => roles[]
    mapping(address => bytes32[]) private _accountRoles;

    /// @notice Role members: role => members[]
    mapping(bytes32 => address[]) private _roleMembers;

    /// @notice Protocol owner (highest authority)
    address public owner;

    /// @notice Pending owner for two-step transfer
    address public pendingOwner;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error AccessManager__OnlyOwner();
    error AccessManager__MissingRole(bytes32 role);
    error AccessManager__AlreadyHasRole();
    error AccessManager__UnauthorizedRoleAdmin();
    error AccessManager__CannotRevokeOwnRole();
    error AccessManager__InvalidAddress();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor(address _owner) {
        if (_owner == address(0)) revert AccessManager__InvalidAddress();

        owner = _owner;

        // Grant owner the OWNER_ROLE
        _grantRole(RoleRegistry.OWNER_ROLE, _owner);

        // Set OWNER_ROLE as admin of all roles
        _setRoleAdmin(RoleRegistry.OWNER_ROLE, RoleRegistry.OWNER_ROLE);
        _setRoleAdmin(RoleRegistry.ADMIN_ROLE, RoleRegistry.OWNER_ROLE);
        _setRoleAdmin(RoleRegistry.GUARDIAN_ROLE, RoleRegistry.OWNER_ROLE);
        _setRoleAdmin(RoleRegistry.KEEPER_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.LIQUIDATOR_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.ORACLE_UPDATER_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.MARKET_MAKER_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.FEE_MANAGER_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.BASKET_MANAGER_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.EVENT_SETTLER_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.PAUSER_ROLE, RoleRegistry.GUARDIAN_ROLE);
        _setRoleAdmin(RoleRegistry.UPGRADER_ROLE, RoleRegistry.OWNER_ROLE);
        _setRoleAdmin(RoleRegistry.TRADING_OPERATOR_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.VAULT_OPERATOR_ROLE, RoleRegistry.ADMIN_ROLE);
        _setRoleAdmin(RoleRegistry.RISK_MANAGER_ROLE, RoleRegistry.ADMIN_ROLE);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert AccessManager__OnlyOwner();
        _;
    }

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) {
            revert AccessManager__MissingRole(role);
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      ROLE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Grant role to account
     * @param role Role to grant
     * @param account Account receiving role
     * @dev Only callable by role admin
     */
    function grantRole(bytes32 role, address account) external {
        if (!hasRole(_roleAdmins[role], msg.sender)) {
            revert AccessManager__UnauthorizedRoleAdmin();
        }
        _grantRole(role, account);
    }

    /**
     * @notice Revoke role from account
     * @param role Role to revoke
     * @param account Account losing role
     * @dev Only callable by role admin
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
     * @notice Renounce own role
     * @param role Role to renounce
     * @dev Account voluntarily gives up role
     */
    function renounceRole(bytes32 role) external {
        _revokeRole(role, msg.sender);
    }

    /**
     * @notice Batch grant roles
     * @param roles Array of roles to grant
     * @param accounts Array of accounts receiving roles
     */
    function batchGrantRoles(bytes32[] calldata roles, address[] calldata accounts) external {
        require(roles.length == accounts.length, "Length mismatch");

        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(_roleAdmins[roles[i]], msg.sender)) {
                revert AccessManager__UnauthorizedRoleAdmin();
            }
            _grantRole(roles[i], accounts[i]);
        }
    }

    /**
     * @notice Batch revoke roles
     * @param roles Array of roles to revoke
     * @param accounts Array of accounts losing roles
     */
    function batchRevokeRoles(bytes32[] calldata roles, address[] calldata accounts) external {
        require(roles.length == accounts.length, "Length mismatch");

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

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    OWNERSHIP TRANSFER
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Start ownership transfer (step 1 of 2)
     * @param newOwner New owner address
     * @dev Two-step process for safety
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert AccessManager__InvalidAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /**
     * @notice Accept ownership transfer (step 2 of 2)
     * @dev Must be called by pending owner
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert AccessManager__OnlyOwner();

        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        // Transfer OWNER_ROLE
        _revokeRole(RoleRegistry.OWNER_ROLE, oldOwner);
        _grantRole(RoleRegistry.OWNER_ROLE, owner);

        emit OwnershipTransferred(oldOwner, owner);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal grant role function
     * @param role Role to grant
     * @param account Account receiving role
     */
    function _grantRole(bytes32 role, address account) internal {
        if (_roles[role][account]) revert AccessManager__AlreadyHasRole();

        _roles[role][account] = true;
        _accountRoles[account].push(role);
        _roleMembers[role].push(account);

        emit RoleGranted(role, account, msg.sender);
    }

    /**
     * @notice Internal revoke role function
     * @param role Role to revoke
     * @param account Account losing role
     */
    function _revokeRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) return;

        _roles[role][account] = false;

        // Remove from account roles
        bytes32[] storage accountRoles = _accountRoles[account];
        for (uint256 i = 0; i < accountRoles.length; i++) {
            if (accountRoles[i] == role) {
                accountRoles[i] = accountRoles[accountRoles.length - 1];
                accountRoles.pop();
                break;
            }
        }

        // Remove from role members
        address[] storage members = _roleMembers[role];
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == account) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }

        emit RoleRevoked(role, account, msg.sender);
    }

    /**
     * @notice Set role admin
     * @param role Role to configure
     * @param adminRole Admin role for this role
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        bytes32 previousAdminRole = _roleAdmins[role];
        _roleAdmins[role] = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if account has role
     * @param role Role to check
     * @param account Account to check
     * @return bool True if account has role
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    /**
     * @notice Get role admin
     * @param role Role to query
     * @return bytes32 Admin role identifier
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32) {
        return _roleAdmins[role];
    }

    /**
     * @notice Get all roles for an account
     * @param account Account to query
     * @return roles Array of role identifiers
     */
    function getAccountRoles(address account) external view returns (bytes32[] memory roles) {
        return _accountRoles[account];
    }

    /**
     * @notice Get all members of a role
     * @param role Role to query
     * @return members Array of addresses
     */
    function getRoleMembers(bytes32 role) external view returns (address[] memory members) {
        return _roleMembers[role];
    }

    /**
     * @notice Get role member count
     * @param role Role to query
     * @return count Number of members
     */
    function getRoleMemberCount(bytes32 role) external view returns (uint256 count) {
        return _roleMembers[role].length;
    }

    /**
     * @notice Check if account has any of the roles
     * @param roles Array of roles to check
     * @param account Account to check
     * @return bool True if account has at least one role
     */
    function hasAnyRole(bytes32[] calldata roles, address account) external view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(roles[i], account)) return true;
        }
        return false;
    }

    /**
     * @notice Check if account has all roles
     * @param roles Array of roles to check
     * @param account Account to check
     * @return bool True if account has all roles
     */
    function hasAllRoles(bytes32[] calldata roles, address account) external view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(roles[i], account)) return false;
        }
        return true;
    }
}
