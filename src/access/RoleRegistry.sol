// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title RoleRegistry
 * @author BAOBAB Protocol
 * @notice Defines all protocol roles and their permissions
 * @dev Uses keccak256 hashes for role identifiers (OpenZeppelin pattern)
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                       ROLE REGISTRY
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
library RoleRegistry {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      PROTOCOL ROLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Protocol owner - highest authority (multi-sig)
     * @dev Can grant/revoke all roles, emergency functions, protocol upgrades
     */
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /**
     * @notice Protocol admin - day-to-day operations
     * @dev Can configure parameters, add markets, update fees
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @notice Guardian - emergency response
     * @dev Can pause modules, trigger circuit breakers, emergency withdrawals
     */
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    /**
     * @notice Keeper - automated bot operations
     * @dev Can execute orders, liquidations, funding payments, ADL
     */
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /**
     * @notice Liquidator - execute liquidations
     * @dev Can liquidate underwater positions, earn liquidation fees
     */
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /**
     * @notice Oracle updater - price feed management
     * @dev Can update oracle prices (for trusted oracles)
     */
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");

    /**
     * @notice Market maker - DAO market making bot
     * @dev Can place/cancel orders on behalf of protocol treasury
     */
    bytes32 public constant MARKET_MAKER_ROLE = keccak256("MARKET_MAKER_ROLE");

    /**
     * @notice Fee manager - fee collection and distribution
     * @dev Can collect fees, distribute to vaults, trigger buybacks
     */
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /**
     * @notice Basket manager - manage tokenized baskets
     * @dev Can create baskets, rebalance, add/remove components
     */
    bytes32 public constant BASKET_MANAGER_ROLE = keccak256("BASKET_MANAGER_ROLE");

    /**
     * @notice Event settler - settle prediction markets
     * @dev Can report event outcomes, trigger settlements
     */
    bytes32 public constant EVENT_SETTLER_ROLE = keccak256("EVENT_SETTLER_ROLE");

    /**
     * @notice Pauser - emergency pause authority
     * @dev Can pause/unpause specific modules (lower authority than GUARDIAN)
     */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @notice Upgrader - contract upgrade authority
     * @dev Can upgrade proxy implementations (should be timelock)
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    MODULE-SPECIFIC ROLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Trading engine operator
     * @dev Can manage trading engine parameters, order types
     */
    bytes32 public constant TRADING_OPERATOR_ROLE = keccak256("TRADING_OPERATOR_ROLE");

    /**
     * @notice Vault operator
     * @dev Can manage vault parameters, LP rewards
     */
    bytes32 public constant VAULT_OPERATOR_ROLE = keccak256("VAULT_OPERATOR_ROLE");

    /**
     * @notice Risk manager
     * @dev Can update risk parameters, leverage limits, margin requirements
     */
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    ROLE DESCRIPTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get human-readable role description
     * @param role Role identifier
     * @return description Role description string
     */
    function getRoleDescription(bytes32 role) internal pure returns (string memory description) {
        if (role == OWNER_ROLE) return "Protocol Owner - Full Control";
        if (role == ADMIN_ROLE) return "Protocol Admin - Daily Operations";
        if (role == GUARDIAN_ROLE) return "Guardian - Emergency Response";
        if (role == KEEPER_ROLE) return "Keeper - Automated Operations";
        if (role == LIQUIDATOR_ROLE) return "Liquidator - Position Liquidations";
        if (role == ORACLE_UPDATER_ROLE) return "Oracle Updater - Price Feeds";
        if (role == MARKET_MAKER_ROLE) return "Market Maker - DAO Trading Bot";
        if (role == FEE_MANAGER_ROLE) return "Fee Manager - Revenue Distribution";
        if (role == BASKET_MANAGER_ROLE) return "Basket Manager - Index Management";
        if (role == EVENT_SETTLER_ROLE) return "Event Settler - Prediction Markets";
        if (role == PAUSER_ROLE) return "Pauser - Emergency Pause";
        if (role == UPGRADER_ROLE) return "Upgrader - Contract Upgrades";
        if (role == TRADING_OPERATOR_ROLE) return "Trading Operator - Trading Parameters";
        if (role == VAULT_OPERATOR_ROLE) return "Vault Operator - Vault Management";
        if (role == RISK_MANAGER_ROLE) return "Risk Manager - Risk Parameters";
        
        return "Unknown Role";
    }

    /**
     * @notice Get role authority level (higher = more power)
     * @param role Role identifier
     * @return level Authority level (0-100)
     */
    function getRoleAuthorityLevel(bytes32 role) internal pure returns (uint8 level) {
        if (role == OWNER_ROLE) return 100;           // Highest authority
        if (role == ADMIN_ROLE) return 80;
        if (role == GUARDIAN_ROLE) return 70;
        if (role == UPGRADER_ROLE) return 60;
        if (role == RISK_MANAGER_ROLE) return 50;
        if (role == TRADING_OPERATOR_ROLE) return 40;
        if (role == VAULT_OPERATOR_ROLE) return 40;
        if (role == FEE_MANAGER_ROLE) return 40;
        if (role == BASKET_MANAGER_ROLE) return 30;
        if (role == MARKET_MAKER_ROLE) return 30;
        if (role == EVENT_SETTLER_ROLE) return 30;
        if (role == PAUSER_ROLE) return 25;
        if (role == ORACLE_UPDATER_ROLE) return 20;
        if (role == KEEPER_ROLE) return 15;
        if (role == LIQUIDATOR_ROLE) return 10;       // Lowest authority
        
        return 0; // Unknown role
    }

    /**
     * @notice Check if role can grant another role
     * @param grantor Role attempting to grant
     * @param grantee Role being granted
     * @return bool True if grantor has sufficient authority
     */
    function canGrantRole(bytes32 grantor, bytes32 grantee) internal pure returns (bool) {
        // Only OWNER can grant OWNER role
        if (grantee == OWNER_ROLE) return grantor == OWNER_ROLE;
        
        // Higher authority can grant lower authority roles
        return getRoleAuthorityLevel(grantor) > getRoleAuthorityLevel(grantee);
    }

    /**
     * @notice Get all protocol roles
     * @return roles Array of all role identifiers
     */
    function getAllRoles() internal pure returns (bytes32[] memory roles) {
        roles = new bytes32[](15);
        roles[0] = OWNER_ROLE;
        roles[1] = ADMIN_ROLE;
        roles[2] = GUARDIAN_ROLE;
        roles[3] = KEEPER_ROLE;
        roles[4] = LIQUIDATOR_ROLE;
        roles[5] = ORACLE_UPDATER_ROLE;
        roles[6] = MARKET_MAKER_ROLE;
        roles[7] = FEE_MANAGER_ROLE;
        roles[8] = BASKET_MANAGER_ROLE;
        roles[9] = EVENT_SETTLER_ROLE;
        roles[10] = PAUSER_ROLE;
        roles[11] = UPGRADER_ROLE;
        roles[12] = TRADING_OPERATOR_ROLE;
        roles[13] = VAULT_OPERATOR_ROLE;
        roles[14] = RISK_MANAGER_ROLE;
    }

    /**
     * @notice Get role by name
     * @param roleName Role name as string
     * @return role Role identifier
     */
    function getRoleByName(string memory roleName) internal pure returns (bytes32 role) {
        return keccak256(abi.encodePacked(roleName));
    }
}