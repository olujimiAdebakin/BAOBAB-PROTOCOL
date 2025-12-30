// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

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
   

    // ============================
    // Immutable Dependencies
    // ============================

    IOracleRegistry public immutable ORACLE_REGISTRY;
    ICircuitBreaker public immutable CIRCUIT_BREAKER;

    // ============================
    // Global Risk Parameters
    // ============================

    uint256 public maxStalenessPeriod = 3600; // 1 hour
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

    // ============================
    // Events
    // ============================

    event MaxStalenessUpdated(uint256 newPeriod);
    event PriceFeedsToggled(bool active);




    // ============================
    // Constructor
    // ============================

    constructor(address oracleRegistry, address circuitBreaker, address initialOwner)
        Ownable(initialOwner)
    {
        oracleRegistry.validateNotZero();
        
        ORACLE_REGISTRY = IOracleRegistry(oracleRegistry);
        CIRCUIT_BREAKER = ICircuitBreaker(circuitBreaker);
    }

    // =========================================================================
    // EXTERNAL API
    // =========================================================================



    /**
     * @notice Returns a fully validated, protocol-safe price.
     */
    function getValidatedPrice(address asset) external view returns (int256) {
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

        int256 price = _fetchPrice(asset);
        uint256 lastUpdated = _resolveLastUpdated(oracleConfig, asset);

        _enforceStaleness(lastUpdated);

        return price;
    }

    // =========================================================================
    // VIEW HELPERS (Useful for other modules & off-chain)
    // =========================================================================

    function isAssetUsable(address asset) external view returns (bool) {
        if (!priceFeedsActive) return false;

        IOracleRegistry.OracleConfig memory oracleConfig =
            ORACLE_REGISTRY.getOracleConfig(asset);

        if (!oracleConfig.isActive) return false;

        uint256 lastUpdated = _tryResolveTimestamp(oracleConfig);
        if (lastUpdated == 0) return false;

        return (block.timestamp - lastUpdated) <= maxStalenessPeriod;
    }

    function getLastUpdateTimestamp(address asset)
        external
        view
        returns (uint256)
    {
        IOracleRegistry.OracleConfig memory oracleConfig =
            ORACLE_REGISTRY.getOracleConfig(asset);

        uint256 ts = _tryResolveTimestamp(oracleConfig);
        if (ts == 0) revert OracleSecurity__NoValidTimestamp(asset);

        return ts;
    }

    // =========================================================================
    // INTERNAL SECURITY GUARDS
    // =========================================================================

    function _enforceGlobalGuards() internal view {
        if (!priceFeedsActive) {
            revert OracleSecurity__FeedsPaused();
        }
    }

    function _loadActiveOracle(address asset)
        internal
        view
        returns (IOracleRegistry.OracleConfig memory)
    {
        IOracleRegistry.OracleConfig memory oracleConfig =
            ORACLE_REGISTRY.getOracleConfig(asset);

        if (!oracleConfig.isActive) {
            revert OracleSecurity__InactiveAsset(asset);
        }

        return oracleConfig;
    }

    function _fetchPrice(address asset) internal view returns (int256) {
        (int256 price, bool success) = ORACLE_REGISTRY.getPrice(asset);

        if (!success || price <= 0) {
            revert OracleSecurity__InvalidPrice(asset);
        }

        return price;
    }

    function _resolveLastUpdated(
        IOracleRegistry.OracleConfig memory oracleConfig,
        address asset
    ) internal view returns (uint256) {
        uint256 ts = _tryResolveTimestamp(oracleConfig);

        if (ts == 0) {
            revert OracleSecurity__NoValidTimestamp(asset);
        }

        return ts;
    }

    function _tryResolveTimestamp(
        IOracleRegistry.OracleConfig memory oracleConfig
    ) internal view returns (uint256) {
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
