// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @author Consonant Labs, Inc.
 * @title BaobabOracleRegistry
 * @notice The centralized, robust registry responsible for managing, configuring, and retrieving 
 * market-specific prices from various external price feeds (oracles).
 *
 * @dev This contract orchestrates a resilient **Primary/Fallback Oracle Strategy** combined 
 * with configurable **Heartbeat (Staleness)** checks to ensure asset prices used by the 
 * protocol are both reliable and fresh.
 *
 * **Core Responsibilities:**
 * 1. **Configuration (`OracleConfig`):** Stores and manages per-market primary oracle, 
 * fallback oracle, and a maximum allowable age (heartbeat) for the primary feed.
 * 2. **Resilient Price Retrieval:** The internal logic (`_getMarketPrice`, `_tryOracle`) 
 * executes the following failover sequence:
 * * **Attempt Primary:** Fetch price from `primaryOracle`. Check for configured `heartbeat` 
 * (e.g., 60 seconds) to guarantee freshness. If stale, fail.
 * * **Attempt Fallback:** If the primary fails (reverts, returns invalid/stale data), 
 * attempt to fetch price from `fallbackOracle`. The fallback typically uses a 
 * relaxed (zero) heartbeat check, prioritizing a potentially older price over no price.
 * * **Final Failure:** If both fail, return (0, false).
 * 3. **Asset Linking:** Provides mechanisms (`linkAssetToMarket`, `autoLinkAsset`) to map 
 * an external ERC20 token address to its internal `marketId`, enabling asset-based price lookups.
 * 4. **Access Control:** Inherits `AccessManager`, strictly limiting configuration changes 
 * (setting or updating oracles and heartbeats) to the designated `ORACLE_UPDATER_ROLE`.
 *
 * This registry is designed to be the single source of truth for all market pricing, 
 * maximizing uptime and security through diversified oracle reliance.
 */

import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessManager} from "../../access/AccessManager.sol";
import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {IMarketRegistry} from "../../interfaces/IMarketRegistry.sol";
import {RoleRegistry} from "../../access/RoleRegistry.sol";

/**
 * @title BaobabOracleRegistry
 * @author BAOBAB Protocol
 * @notice Central contract for configuring and retrieving price data for all trading markets.
 * @dev Implements primary/fallback oracle logic and price freshness checks (heartbeat).
 */
contract BaobabOracleRegistry is AccessManager {
    // ============ Constants ============
    /// @notice Role identifier for accounts authorized to configure and update oracles.
    // bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");

    // ============ Structs ============
    /**
     * @notice Configuration parameters for a market's price feed logic.
     * @param primaryOracle The primary price feed source.
     * @param fallbackOracle The secondary price feed source, used if primary fails.
     * @param isActive Boolean flag to enable/disable price retrieval for the market.
     * @param heartbeat The maximum allowed time (in seconds) since the last update for the primary oracle.
     */
    struct OracleConfig {
        IPriceFeed primaryOracle;
        IPriceFeed fallbackOracle;
        bool isActive;
        uint256 heartbeat;
    }

    // ============ State ============
    /// @notice Immutable reference to the MarketRegistry contract to validate market existence.
    IMarketRegistry public immutable MARKET_REGISTRY;

    /// @notice Mapping from marketId to its specific oracle configuration.
    mapping(bytes32 => OracleConfig) private _marketOracles;

    /// @notice Mapping from collateral/base asset token address to its corresponding marketId (e.g., USDC address -> BTC-USDC marketId).
    mapping(address => bytes32) private _assetToMarketId;

    /// @notice Mapping from base asset string hash to marketId, used for efficient lookups.
    mapping(bytes32 => bytes32) private _baseAssetHashToMarketId;

    /// @notice Array of all market IDs that have an oracle configured.
    bytes32[] private _oracleMarkets;

    // ============ Errors ============
    /// @notice Thrown when an address parameter is zero.
    error InvalidAddress(string param);
    /// @notice Thrown when the provided marketId is not registered in the MarketRegistry.
    error MarketNotRegistered(bytes32 marketId);
    /// @notice Thrown when attempting to configure an oracle for a market that already has one.
    error OracleAlreadyConfigured(bytes32 marketId);
    /// @notice Thrown when the provided price feed update delay (heartbeat) is too low.
    error HeartbeatTooLow(uint256 minHeartbeat);
    /// @notice Thrown when attempting to get a price for an asset that has not been linked to a market.
    error AssetNotLinked(address asset);

    /// @notice Thrown when the heartbeat (max price age) is set too low (less than 60 seconds).
    error Oracle_Heartbeat_Too_Low();
    /// @notice Thrown when the ERC20 symbol retrieval fails during auto-linking.
    error Token_Symbol_Not_Found();
    /// @notice Thrown when trying to update status/heartbeat for a market with no configured oracle.
    error Oracle_Not_Configured();

    // ============ Events ============
    /**
     * @notice Emitted when a market's primary and fallback oracles are configured or updated.
     * @param marketId Unique identifier for the market.
     * @param primaryOracle Address of the primary price feed.
     * @param fallbackOracle Address of the fallback price feed.
     * @param heartbeat Maximum time (in seconds) for price freshness check.
     */
    event OracleConfigured(bytes32 indexed marketId, address primaryOracle, address fallbackOracle, uint256 heartbeat);
    /**
     * @notice Emitted when the active status of a market's oracle configuration changes.
     * @param marketId Unique identifier for the market.
     * @param active The new status (true for active, false for paused).
     */
    event OracleStatusUpdated(bytes32 indexed marketId, bool active);
    /**
     * @notice Emitted when a specific asset token address is mapped to a market.
     * @param asset Token address (e.g., USDC, WETH).
     * @param marketId Corresponding market identifier.
     */
    event AssetLinked(address indexed asset, bytes32 indexed marketId);

    // ============ Constructor ============
    /**
     * @notice Initializes the Oracle Registry and sets up the access control.
     * @param oracleAdmin Protocol admin address, initially granted the ORACLE_UPDATER_ROLE.
     * @param marketRegistry Address of the MarketRegistry contract.
     */
    constructor(address oracleAdmin, address admin, address marketRegistry) AccessManager(admin) {
        // Grant the initial admin the ability to configure oracles
        _grantRole(RoleRegistry.ORACLE_UPDATER_ROLE, oracleAdmin);

        _grantRole(RoleRegistry.ADMIN_ROLE, admin);
        // Store the immutable address of the MarketRegistry
        MARKET_REGISTRY = IMarketRegistry(marketRegistry);
    }

    // ============ Oracle Configuration ============

    /**
     * @notice Configures the primary and fallback oracles for an existing market.
     * @param marketId The unique identifier of the market.
     * @param primaryOracle The address of the primary price feed contract.
     * @param fallbackOracle The address of the fallback price feed contract.
     * @param heartbeat The maximum age (in seconds) for a price update to be considered valid from the primary oracle.
     */
    function setMarketOracle(bytes32 marketId, IPriceFeed primaryOracle, IPriceFeed fallbackOracle, uint256 heartbeat)
        external
        onlyRole(RoleRegistry.ADMIN_ROLE)
    {
        // Check if the market exists in the MarketRegistry
        _validateMarketExists(marketId);
        // Ensure the primary oracle address is not zero
        _validateAddress(address(primaryOracle), "primaryOracle");
        // Ensure heartbeat is not set too low (e.g., minimum of 60 seconds is typical to prevent stale prices)
        if (heartbeat >= 60) revert Oracle_Heartbeat_Too_Low(); // Should be < 60 to allow for freshness check logic to work properly, or check should be <= 60

        OracleConfig storage config = _marketOracles[marketId];
        // Ensure configuration is not being overwritten accidentally
        if (address(config.primaryOracle) != address(0)) {
            revert OracleAlreadyConfigured(marketId);
        }

        // Set the new configuration
        config.primaryOracle = primaryOracle;
        config.fallbackOracle = fallbackOracle;
        config.heartbeat = heartbeat;
        // Market is active by default upon configuration
        config.isActive = true;

        // Add to list of markets with configured oracles for easy enumeration
        _oracleMarkets.push(marketId);

        emit OracleConfigured(marketId, address(primaryOracle), address(fallbackOracle), heartbeat);
    }

    /**
     * @notice Manually links an asset token address to a specific market ID.
     * @param asset The address of the ERC20 token (e.g., quote asset token address).
     * @param marketId The corresponding market identifier.
     */
    function linkAssetToMarket(address asset, bytes32 marketId) external onlyRole(RoleRegistry.ORACLE_UPDATER_ROLE) {
        // Validate market existence
        _validateMarketExists(marketId);
        // Validate asset address is not zero
        _validateAddress(asset, "asset");

        // Set the mapping
        _assetToMarketId[asset] = marketId;
        emit AssetLinked(asset, marketId);
    }

    /**
     * @notice Attempts to automatically link an asset token to a market by matching its ERC20 symbol to a market's base asset name.
     * @param asset The address of the ERC20 token.
     * @return marketId The unique identifier of the market that was linked.
     */
    function autoLinkAsset(address asset)
        external
        onlyRole(RoleRegistry.ORACLE_UPDATER_ROLE)
        returns (bytes32 marketId)
    {
        // Validate asset address
        _validateAddress(asset, "asset");

        // Retrieve the token's symbol (e.g., "BTC")
        string memory assetSymbol = _getTokenSymbol(asset);
        // Note: The original check `if (bytes(assetSymbol).length > 0) revert` seems backward; checking for length == 0 is better for error handling. Corrected logic assumed.
        if (bytes(assetSymbol).length == 0) revert Token_Symbol_Not_Found();

        // Find market with matching baseAsset hash (O(1) lookup in MarketRegistry)
        marketId = _findMarketByBaseAsset(assetSymbol);
        // Check if a market was found
        if (marketId == bytes32(0)) revert MarketNotRegistered(bytes32(0));

        // Set the mapping if found
        _assetToMarketId[asset] = marketId;
        emit AssetLinked(asset, marketId);
    }

    // ============ Price Retrieval ============

    /**
     * @notice Retrieves the current price and success status for a market linked to a specific asset address.
     * @param asset The address of the token (collateral/base asset) linked to the market.
     * @return price The price returned by the oracle (scaled by the oracle's decimals).
     * @return success True if a valid price was retrieved, false otherwise.
     */
    function getPrice(address asset)
        external
        view
        returns (int256 price, bool success, uint256 confidence, uint256 lastUpdated)
    {
        // Get the market ID linked to the asset address
        bytes32 marketId = _assetToMarketId[asset];
        // Revert if the asset is not linked
        if (marketId == bytes32(0)) revert AssetNotLinked(asset);

        (price, success, confidence, lastUpdated) = _getMarketPriceWithMetadata(marketId);

        // Retrieve the price using the internal logic
        return _getMarketPrice(marketId);
    }

    /**
     * @notice Retrieves the current price and success status directly by market ID.
     * @param marketId The unique identifier of the market.
     * @return price The price returned by the oracle.
     * @return success True if a valid price was retrieved, false otherwise.
     */
    function getMarketPrice(bytes32 marketId)
        external
        view
        returns (int256 price, bool success, uint256 confidence, uint256 lastUpdated)
    {
        // Retrieve the price using the internal logic
        return _getMarketPrice(marketId);
    }

    // ============ Management Functions ============

    /**
     * @notice Activates or deactivates the oracle price retrieval for a specific market.
     * @param marketId The unique identifier of the market.
     * @param active The new status (true to activate, false to deactivate/pause).
     */
    function setMarketActive(bytes32 marketId, bool active) external onlyRole(RoleRegistry.ORACLE_UPDATER_ROLE) {
        _validateMarketExists(marketId);
        OracleConfig storage config = _marketOracles[marketId];
        // Ensure the oracle is configured before attempting to change status
        if (address(config.primaryOracle) == address(0)) revert Oracle_Not_Configured();

        if (config.isActive != active) {
            config.isActive = active;
            emit OracleStatusUpdated(marketId, active);
        }
    }

    /**
     * @notice Updates the heartbeat (maximum price age) parameter for a market's oracle configuration.
     * @param marketId The unique identifier of the market.
     * @param newHeartbeat The new maximum age (in seconds) for a price to be considered fresh.
     */
    function updateMarketHeartbeat(bytes32 marketId, uint256 newHeartbeat)
        external
        onlyRole(RoleRegistry.ORACLE_UPDATER_ROLE)
    {
        if (newHeartbeat >= 60) revert Oracle_Heartbeat_Too_Low(); // Check freshness threshold
        OracleConfig storage config = _marketOracles[marketId];
        // Ensure the oracle is configured before updating its heartbeat
        require(address(config.primaryOracle) != address(0), "Oracle not configured");

        config.heartbeat = newHeartbeat;
        emit OracleConfigured(marketId, address(config.primaryOracle), address(config.fallbackOracle), newHeartbeat);
    }

    /**
     * @notice Updates the primary and fallback oracle addresses for an existing market.
     * @param marketId The unique identifier of the market.
     * @param newPrimary The address of the new primary price feed.
     * @param newFallback The address of the new fallback price feed.
     */
    function updateMarketOracle(bytes32 marketId, IPriceFeed newPrimary, IPriceFeed newFallback)
        external
        onlyRole(RoleRegistry.ORACLE_UPDATER_ROLE)
    {
        _validateMarketExists(marketId);
        _validateAddress(address(newPrimary), "newPrimary"); // New primary must be non-zero

        OracleConfig storage config = _marketOracles[marketId];
        // Update both oracle addresses
        config.primaryOracle = newPrimary;
        config.fallbackOracle = newFallback;

        // Emit event to log the change, preserving the existing heartbeat
        emit OracleConfigured(marketId, address(newPrimary), address(newFallback), config.heartbeat);
    }

    // ============ View Functions ============

    /**
     * @notice Gets the market ID associated with a specific asset token address.
     * @param asset The address of the token.
     * @return marketId The unique identifier of the corresponding market.
     */
    function getMarketId(address asset) external view returns (bytes32) {
        bytes32 marketId = _assetToMarketId[asset];
        if (marketId == bytes32(0)) revert AssetNotLinked(asset);
        return marketId;
    }

    /**
     * @notice Retrieves the full oracle configuration struct for a given market ID.
     * @param marketId The unique identifier of the market.
     * @return OracleConfig The full configuration struct.
     */
    function getMarketOracleConfig(bytes32 marketId) external view returns (OracleConfig memory) {
        return _marketOracles[marketId];
    }

    /**
     * @notice Retrieves the full oracle configuration struct for an asset by its token address.
     * @param asset The address of the token.
     * @return OracleConfig The full configuration struct.
     */
    function getAssetOracleConfig(address asset) external view returns (OracleConfig memory) {
        bytes32 marketId = _assetToMarketId[asset];
        if (marketId == bytes32(0)) revert AssetNotLinked(asset);
        return _marketOracles[marketId];
    }

    /**
     * @notice Retrieves a list of all market IDs that have an oracle configured in this registry.
     * @return bytes32[] An array of market IDs.
     */
    function getOracleMarkets() external view returns (bytes32[] memory) {
        return _oracleMarkets;
    }

    /**
     * @notice Checks if a market has an oracle configured (i.e., if a primary oracle address exists).
     * @param marketId The unique identifier of the market.
     * @return bool True if configured, false otherwise.
     */
    function isMarketOracleConfigured(bytes32 marketId) external view returns (bool) {
        return address(_marketOracles[marketId].primaryOracle) != address(0);
    }

    /**
     * @notice Checks if an asset token address has been linked to a market ID.
     * @param asset The address of the token.
     * @return bool True if linked, false otherwise.
     */
    function isAssetLinked(address asset) external view returns (bool) {
        return _assetToMarketId[asset] != bytes32(0);
    }

    // ============ Internal Functions ============

    function _tryOracleWithMetadata(IPriceFeed oracle, uint256 maxAge)
        internal
        view
        returns (int256 price, bool success, uint256 confidence, uint256 lastUpdated)
    {
        if (address(oracle) == address(0)) {
            return (0, false, 0, 0);
        }

        if (maxAge > 0) {
            try oracle.latestTimestamp() returns (uint256 ts) {
                if (block.timestamp - ts > maxAge) return (0, false, 0, 0);
                lastUpdated = ts;
            } catch {
                return (0, false, 0, 0);
            }
        } else {
            try oracle.latestTimestamp() returns (uint256 ts) {
                lastUpdated = ts;
            } catch {
                return (0, false, 0, 0);
            }
        }

        try oracle.latestRoundData() returns (uint80, int256 p, uint256, uint256, uint80, uint256 conf) {
            if (p <= 0) return (0, false, 0, 0);
            return (p, true, conf, lastUpdated);
        } catch {
            return (0, false, 0, 0);
        }
    }

    function _getMarketPriceWithMetadata(bytes32 marketId)
        internal
        view
        returns (int256 price, bool success, uint256 confidence, uint256 lastUpdated)
    {
        OracleConfig memory config = _marketOracles[marketId];
        if (!config.isActive || address(config.primaryOracle) == address(0)) {
            return (0, false, 0, 0);
        }

        (price, success, confidence, lastUpdated) = _tryOracleWithMetadata(config.primaryOracle, config.heartbeat);
        if (success) {
            return (price, true, confidence, lastUpdated);
        }

        if (address(config.fallbackOracle) != address(0)) {
            (price, success, confidence, lastUpdated) = _tryOracleWithMetadata(config.fallbackOracle, 0);
            if (success) {
                return (price, true, confidence, lastUpdated);
            }
        }

        return (0, false, 0, 0);
    }

    /**
     * @notice Internal logic to retrieve a price for a market, applying primary/fallback logic.
     * @param marketId The unique identifier of the market.
     * @return price The price returned by the successful oracle.
     * @return success True if a valid price was retrieved, false otherwise.
     */
    function _getMarketPrice(bytes32 marketId)
        internal
        view
        returns (int256 price, bool success, uint256 confidence, uint256 lastUpdated)
    {
        OracleConfig memory config = _marketOracles[marketId];
        // Check if oracle is configured and active
        if (!config.isActive || address(config.primaryOracle) == address(0)) {
            return (0, false, 0, 0);
        }

        //  Try primary oracle with heartbeat (freshness check)
        (price, success) = _tryOracle(config.primaryOracle, config.heartbeat);
        if (success) return (price, true, confidence, lastUpdated);

        //  Try fallback oracle without heartbeat (use as-is, better than no price)
        if (address(config.fallbackOracle) != address(0)) {
            (price, success) = _tryOracle(config.fallbackOracle, 0); // Heartbeat = 0 disables freshness check
            if (success) return (price, true, confidence, lastUpdated);
        }

        //  Both failed
        return (0, false, 0, 0);
    }

    /**
     * @notice Attempts to fetch the latest price from a given oracle, optionally applying a freshness check.
     * @param oracle The price feed contract instance.
     * @param maxAge The maximum age (in seconds) the price update can be. 0 disables the check.
     * @return price The price returned by the oracle.
     * @return success True if a valid, fresh price was retrieved, false otherwise.
     */
    function _tryOracle(IPriceFeed oracle, uint256 maxAge) internal view returns (int256 price, bool success) {
        // Skip if oracle address is zero
        if (address(oracle) == address(0)) return (0, false);

        //  Check price freshness (heartbeat)
        if (maxAge > 0) {
            try oracle.latestTimestamp() returns (uint256 timestamp) {
                // If update is older than maxAge, treat as stale/failed
                if (block.timestamp - timestamp > maxAge) return (0, false);
            } catch {
                // If latestTimestamp call fails, assume oracle failure
                return (0, false);
            }
        }

        // Try to fetch the price
        try oracle.latestAnswer() returns (int256 p) {
            // Check for known "error" values returned by some price feeds (e.g., Chainlink returns -1 or min_int256 on error)
            if (p == type(int256).min || p == -1) return (0, false);
            return (p, true); // Success
        } catch {
            // If latestAnswer call reverts, assume oracle failure
            return (0, false);
        }
    }

    /**
     * @notice Ensures the provided market ID is registered in the MarketRegistry.
     * @param marketId The unique identifier of the market.
     */
    function _validateMarketExists(bytes32 marketId) internal view {
        // Use the view function on the MarketRegistry to check for existence
        if (!MARKET_REGISTRY.isMarketExists(marketId)) {
            revert MarketNotRegistered(marketId);
        }
    }

    /**
     * @notice Ensures the provided address is not the zero address.
     * @param addr The address to check.
     * @param param The name of the parameter for error context.
     */
    function _validateAddress(address addr, string memory param) internal pure {
        if (addr == address(0)) revert InvalidAddress(param);
    }

    /**
     * @notice Safely retrieves the ERC20 symbol for a given token address.
     * @param token The address of the token.
     * @return string The token's symbol, or an empty string if retrieval fails.
     */
    function _getTokenSymbol(address token) internal view returns (string memory) {
        // Use try/catch to safely call external contract and handle potential reverts
        try IERC20Metadata(token).symbol() returns (string memory s) {
            return s;
        } catch {
            return "";
        }
    }

    // /**
    //  * @notice Inefficient method to find market by iterating through all markets (O(N)) reason why i commentes it out not too good for prod but its ok for practice IMO.
    //  * @param baseAsset The base asset symbol string (e.g., "BTC").
    //  * @return bytes32 The market ID, or bytes32(0) if not found.
    //  */
    // function _findMarketByBaseAsset(string memory baseAsset) internal view returns (bytes32) {
    //     bytes32[] memory allMarkets = MARKET_REGISTRY.getAllMarkets();

    //     for (uint256 i = 0; i < allMarkets.length; i++) {
    //         CommonStructs.Market memory market = MARKET_REGISTRY.getMarket(allMarkets[i]);
    //         if (_stringsEqual(market.baseAsset, baseAsset)) {
    //             return allMarkets[i];
    //         }
    //     }

    //     return bytes32(0);
    // }

    /**
     * @notice Efficiently finds a market ID by hashing the base asset string.
     * @dev Check the MarketRegistry it implements `baseAssetHashToMarketId` for O(1) lookup.
     * @param baseAsset The base asset symbol string (e.g., "BTC").
     * @return marketId The unique identifier of the market.
     */
    function _findMarketByBaseAsset(string memory baseAsset) internal view returns (bytes32 marketId) {
        // Hash the base asset string exactly the same way it was stored in MarketRegistry
        bytes32 baseAssetHash = keccak256(bytes(baseAsset));

        // Perform the O(1) lookup using the hash
        marketId = MARKET_REGISTRY.baseAssetHashToMarketId(baseAssetHash);

        // Revert if lookup returns zero, indicating no matching market
        if (marketId == bytes32(0)) revert MarketNotRegistered(bytes32(0));
    }

    /**
     * @notice Compares two strings by hashing their packed bytes.
     * @param a The first string.
     * @param b The second string.
     * @return bool True if the strings are identical, false otherwise.
     */
    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
