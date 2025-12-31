// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @author Consonant Labs, Inc.
 * @title BaobabOracleSecurity
 * @notice The mandatory, central security layer for all price data consumption within the protocol.
 * @dev This contract acts as a gateway, providing a single function (`getValidatedPrice`) 
 * that all protocol modules (e.g., liquidation, margin, perpetuals) must call to retrieve 
 * an asset's price, ensuring a high level of risk mitigation.
 *
 * **Security Enforcement Sequence (`getValidatedPrice`):** 
 * 1. **Circuit Breaker Check:** Reverts if the global or asset-specific Circuit Breaker 
 * (`ICircuitBreaker`) is tripped, preventing the use of unsafe prices.
 * 2. **Global Pause Check:** Reverts if price feeds are globally paused by the owner (`priceFeedsActive`).
 * 3. **Market/Asset Status:** Checks if the target market is active in the `ORACLE_REGISTRY`.
 * 4. **Price Validity:** Fetches price and metadata. Reverts if price is non-positive or fetch fails.
 * 5. **Global Staleness Check (`maxStalenessPeriod`):** Enforces a protocol-wide maximum age (default 1 hour) 
 * on the price, independent of the Oracle Registry's internal heartbeat.
 * 6. **Confidence Check (`PriceUse`):** Enforces usage-specific constraints on oracle confidence 
 * (e.g., lower confidence is allowed for simple spot checks, but higher confidence is strictly 
 * required for high-risk actions like liquidations).
 *
 * **Critical Design Feature: Contextual Confidence**
 * The `PriceUse` enum forces callers to specify *how* the price will be used, allowing the security 
 * layer to apply dynamic, risk-based confidence requirements (e.g., LIQUIDATION requires 
 * confidence {bps}).
 */

import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";
import {IOracleRegistry} from "../../interfaces/IOracleRegistry.sol";
import {ICircuitBreaker} from "../../interfaces/ICircuitBreaker.sol";
// import {CircuitBreaker} from "../../security/CircuitBreaker.sol";

/**
 * @title BaobabOracleSecurity
 * @notice Central security layer enforcing oracle safety guarantees.
 * @dev All protocol components MUST consume prices from here.
 */
contract BaobabOracleSecurity is Ownable {
    using AddressUtils for address;

    // === Add enum to declare usage context ===
    enum PriceUse {
        SPOT, // UI, balances, reports (confidence==0 allowed)
        PERP_TRADE, // position open/increase (confidence ≤ 50 bps)
        LIQUIDATION, // liquidations (confidence ≤ 25 bps)
        FUNDING // funding rate calc (confidence==0 allowed)
    }

    // ============================
    // Immutable Dependencies
    // ============================

    IOracleRegistry public immutable ORACLE_REGISTRY;
    ICircuitBreaker public immutable CIRCUIT_BREAKER;

    // ============================
    // Global Risk Parameters
    // ============================

    uint256 public maxStalenessPeriod = 3600; // 1 hour default
    bool public priceFeedsActive = true;

    // ============================
    // Errors
    // ============================

    error OracleSecurity__FeedsPaused();
    error OracleSecurity__InactiveAsset(address asset);
    error OracleSecurity__InvalidPrice(address asset);
    error OracleSecurity__StalePrice(uint256 lastUpdated, uint256 maxStaleness);
    error OracleSecurity__NoValidTimestamp(address asset);
    error OracleSecurity__CircuitBroken(address asset);
    error OracleSecurity__ConfidenceTooHigh(uint256 confidence, PriceUse use);
    error OracleSecurity__ConfidenceRequired(PriceUse use);

    // ============================
    // Events
    // ============================

    event MaxStalenessUpdated(uint256 newPeriod);
    event PriceFeedsToggled(bool active);

    // ============================
    // Constructor
    // ============================

    constructor(address oracleRegistry, address circuitBreaker, address initialOwner) Ownable(initialOwner) {
        oracleRegistry.validateNotZero();
        circuitBreaker.validateNotZero();

        ORACLE_REGISTRY = IOracleRegistry(oracleRegistry);
        CIRCUIT_BREAKER = ICircuitBreaker(circuitBreaker);
    }

    // =========================================================================
    // EXTERNAL API
    // =========================================================================

    /**
     * @notice Returns a fully validated, protocol-safe price.
     */
    function getValidatedPrice(address asset, PriceUse use) external view returns (int256) {
        if (CIRCUIT_BREAKER.globalHalt()) {
            revert OracleSecurity__CircuitBroken(asset);
        }
        if (CIRCUIT_BREAKER.isAnyCircuitTripped()) {
            revert OracleSecurity__CircuitBroken(asset);
        }
        bytes32 marketId = ORACLE_REGISTRY.getMarketId(asset);

        if (CIRCUIT_BREAKER.isCircuitTripped(marketId)) {
            revert OracleSecurity__CircuitBroken(asset);
        }
        _enforceGlobalGuards();

        IOracleRegistry.OracleConfig memory oracleConfig = _loadActiveOracle(asset);

        require(oracleConfig.isActive, "Oracle inactive");

        // Fetch price and extended data from registry (assuming it returns confidence too)
        (int256 price, bool success, uint256 confidence, uint256 lastUpdated) = _fetchPriceAndMetadata(asset);

         _fetchPrice(asset);
        // uint256 lastUpdated = _resolveLastUpdated(oracleConfig, asset);

        if (!success || price <= 0) {
            revert OracleSecurity__InvalidPrice(asset);
        }

        _enforceStaleness(lastUpdated);

        _enforceConfidence(use, confidence);

        return price;
    }

    // =========================================================================
    // VIEW HELPERS (Useful for other modules & off-chain)
    // =========================================================================

    function isAssetUsable(address asset) external view returns (bool) {
        if (!priceFeedsActive) return false;

        IOracleRegistry.OracleConfig memory oracleConfig = ORACLE_REGISTRY.getOracleConfig(asset);

        if (!oracleConfig.isActive) return false;

        uint256 lastUpdated = _tryResolveTimestamp(oracleConfig);
        if (lastUpdated == 0) return false;

        return (block.timestamp - lastUpdated) <= maxStalenessPeriod;
    }

    function getLastUpdateTimestamp(address asset) external view returns (uint256) {
        IOracleRegistry.OracleConfig memory oracleConfig = ORACLE_REGISTRY.getOracleConfig(asset);

        uint256 ts = _tryResolveTimestamp(oracleConfig);
        if (ts == 0) revert OracleSecurity__NoValidTimestamp(asset);

        return ts;
    }

    // =========================================================================
    // INTERNAL SECURITY GUARDS
    // =========================================================================

    //  fetch price, success, confidence, timestamp
    function _fetchPriceAndMetadata(address asset)
        internal
        view
        returns (int256 price, bool success, uint256 confidence, uint256 lastUpdated)
    {
        // Grab oracle config
        // IOracleRegistry.OracleConfig memory oracleConfig = ORACLE_REGISTRY.getOracleConfig(asset);


           (price, success, confidence, lastUpdated) = ORACLE_REGISTRY.getPrice(asset);

        // Try primary oracle first
        // if (address(oracleConfig.primaryOracle) != address(0)) {
        //     try oracleConfig.primaryOracle.latestRoundData() returns (
        //         uint80, int256 p, uint256, uint256 updatedAt, uint80, uint256 bConf
        //     ) {
        //         return (p, p > 0, bConf, updatedAt);
        //     } catch {}
        // }

        // // Try fallback oracle
        // if (address(oracleConfig.fallbackOracle) != address(0)) {
        //     try oracleConfig.fallbackOracle.latestRoundData() returns (
        //         uint80, int256 p, uint256, uint256 updatedAt, uint80, uint256 bConf
        //     ) {
        //         return (p, p > 0, bConf, updatedAt);
        //     } catch {}
        // }

         _fetchPrice(asset); // will revert if price invalid

       return (price, true, confidence, lastUpdated);
    }

    function _enforceConfidence(PriceUse use, uint256 confidence) internal pure {
        if (confidence == 0) {
            // Chainlink or unknown confidence
            if (use == PriceUse.SPOT || use == PriceUse.FUNDING) return;
            revert OracleSecurity__ConfidenceRequired(use);
        }

        if (use == PriceUse.PERP_TRADE) {
            if (confidence > 50) revert OracleSecurity__ConfidenceTooHigh(confidence, use);
        }

        if (use == PriceUse.LIQUIDATION) {
            if (confidence > 25) revert OracleSecurity__ConfidenceTooHigh(confidence, use);
        }

            // SPOT and FUNDING do not enforce upper limit but i added some logic to skip
        if (use == PriceUse.SPOT || use == PriceUse.FUNDING) return;

    
    }

    function _enforceGlobalGuards() internal view {
        if (!priceFeedsActive) {
            revert OracleSecurity__FeedsPaused();
        }
    }

    function _loadActiveOracle(address asset) internal view returns (IOracleRegistry.OracleConfig memory) {
        IOracleRegistry.OracleConfig memory oracleConfig = ORACLE_REGISTRY.getOracleConfig(asset);

        if (!oracleConfig.isActive) {
            revert OracleSecurity__InactiveAsset(asset);
        }

        return oracleConfig;
    }

    function _fetchPrice(address asset) internal view returns (int256) {
        (int256 price, bool success, uint256 confidence, uint256 lastUpdated) = ORACLE_REGISTRY.getPrice(asset);

        if (!success || price <= 0) {
            revert OracleSecurity__InvalidPrice(asset);
        }

        _enforceConfidence(PriceUse.PERP_TRADE, confidence);
        _enforceStaleness(lastUpdated);

        return price;
    }

    function _resolveLastUpdated(IOracleRegistry.OracleConfig memory oracleConfig, address asset)
        internal
        view
        returns (uint256)
    {
        uint256 ts = _tryResolveTimestamp(oracleConfig);

        if (ts == 0) {
            revert OracleSecurity__NoValidTimestamp(asset);
        }

        return ts;
    }

    function _tryResolveTimestamp(IOracleRegistry.OracleConfig memory oracleConfig) internal view returns (uint256) {
        if (address(oracleConfig.primaryOracle) != address(0)) {
            try oracleConfig.primaryOracle.latestTimestamp() returns (uint256 ts) {
                if (ts != 0) return ts;
            } catch {}
        }

        if (address(oracleConfig.fallbackOracle) != address(0)) {
            try oracleConfig.fallbackOracle.latestTimestamp() returns (uint256 ts) {
                return ts;
            } catch {}
        }

        return 0;
    }

    function _enforceStaleness(uint256 lastUpdated) internal view {
        if (block.timestamp - lastUpdated > maxStalenessPeriod) {
            revert OracleSecurity__StalePrice(lastUpdated, maxStalenessPeriod);
        }
    }

    // =========================================================================
    // ADMIN CONTROLS
    // =========================================================================

    function setMaxStalenessPeriod(uint256 newPeriod) external onlyOwner {
        maxStalenessPeriod = newPeriod;
        emit MaxStalenessUpdated(newPeriod);
    }

    function togglePriceFeeds(bool active) external onlyOwner {
        priceFeedsActive = active;
        emit PriceFeedsToggled(active);
    }
}
