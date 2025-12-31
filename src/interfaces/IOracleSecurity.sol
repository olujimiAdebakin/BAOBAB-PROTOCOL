// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @author Consonant Labs, Inc.
 * @title IOracleSecurity
 * @notice Interface for the central Baobab Oracle Security Layer.
 * @dev All protocol modules (e.g., liquidations, margins, trading) must fetch prices
 * through this interface to ensure all critical safety and risk checks (Circuit Breakers,
 * Staleness, and Confidence) have been enforced.
 */
interface IOracleSecurity {
    
    /**
     * @notice Defines the context in which a price is being used, allowing the security
     * layer to apply dynamic, risk-based confidence requirements.
     * @dev Confidence is typically measured in basis points (bps).
     */
    enum PriceUse {
        SPOT,         // Low risk. Used for UI/balances. Confidence check is minimal.
        PERP_TRADE,   // Medium risk. Used for opening/increasing positions. Confidence <= 50 bps.
        LIQUIDATION,  // High risk. Used for liquidating collateral. Confidence <= 25 bps.
        FUNDING       // Low risk. Used for funding rate calculations. Confidence check is minimal.
    }

    // ============================
    // State Accessors
    // ============================
    
    function ORACLE_REGISTRY() external view returns (address);
    function CIRCUIT_BREAKER() external view returns (address);
    function maxStalenessPeriod() external view returns (uint256);
    function priceFeedsActive() external view returns (bool);

    // ============================
    // Errors (Required for clear off-chain integration)
    // ============================
    
    error OracleSecurity__FeedsPaused();
    error OracleSecurity__InactiveAsset(address asset);
    error OracleSecurity__InvalidPrice(address asset);
    error OracleSecurity__StalePrice(uint256 lastUpdated, uint256 maxStaleness);
    error OracleSecurity__NoValidTimestamp(address asset);
    error OracleSecurity__CircuitBroken(address asset);
    error OracleSecurity__ConfidenceTooHigh(uint256 confidence, PriceUse use);
    error OracleSecurity__ConfidenceRequired(PriceUse use);
    
    // =========================================================================
    // EXTERNAL API
    // =========================================================================

    /**
     * @notice Returns a fully validated, protocol-safe price for an asset.
     * @dev This is the primary function for price consumption. It runs the price 
     * through ALL security checks: Circuit Breaker, Active Status, Staleness, and 
     * Contextual Confidence. Reverts if any check fails.
     * @param asset The address of the asset (token) whose price is requested.
     * @param use The context defining the risk level of the price consumption (e.g., LIQUIDATION).
     * @return price The fully validated, protocol-safe price (scaled by oracle decimals).
     */
    function getValidatedPrice(address asset, PriceUse use) external view returns (int256 price);

    // =========================================================================
    // VIEW HELPERS (Useful for other modules & off-chain)
    // =========================================================================

    /**
     * @notice Checks if an asset's price is usable based on global status, market status, 
     * and global staleness rules. Useful for pre-flight checks in consuming contracts.
     * @param asset The address of the asset.
     * @return bool True if the asset's price is fresh and feeds are active.
     */
    function isAssetUsable(address asset) external view returns (bool);

    /**
     * @notice Retrieves the timestamp of the last valid price update.
     * @param asset The address of the asset.
     * @return uint256 The block timestamp of the last valid update. Reverts if no valid timestamp is found.
     */
    function getLastUpdateTimestamp(address asset) external view returns (uint256);

    // =========================================================================
    // ADMIN CONTROLS (Governance/Owner)
    // =========================================================================

    /**
     * @notice Sets the protocol-wide maximum allowable age for a price.
     * @param newPeriod The new maximum staleness period in seconds (e.g., 3600 for 1 hour).
     */
    function setMaxStalenessPeriod(uint256 newPeriod) external;

    /**
     * @notice Globally activates or deactivates all price feeds. Emergency kill switch.
     * @param active The new status (true to activate, false to pause).
     */
    function togglePriceFeeds(bool active) external;
    
    // ============================
    // Events
    // ============================

    event MaxStalenessUpdated(uint256 newPeriod);
    event PriceFeedsToggled(bool active);
}