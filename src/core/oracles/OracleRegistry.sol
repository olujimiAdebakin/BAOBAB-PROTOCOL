// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessManager} from "../../access/AccessManager.sol";
import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {IMarketRegistry} from "../../interfaces/IMarketRegistry.sol";


contract BaobabOracleRegistry is AccessManager {
    // ============ Constants ============
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    
    // ============ Structs ============
    struct OracleConfig {
        IPriceFeed primaryOracle;
        IPriceFeed fallbackOracle;
        bool isActive;
        uint256 heartbeat;
    }

    // ============ State ============
    IMarketRegistry public immutable MARKET_REGISTRY;
    
    // marketId → OracleConfig
    mapping(bytes32 => OracleConfig) private _marketOracles;
    
    // asset address → marketId (for easy lookup)
    mapping(address => bytes32) private _assetToMarketId;

    // asset baseAsset → marketId (for easy lookup)
    mapping(bytes32 => bytes32) private _baseAssetHashToMarketId;
    
    // All markets with oracles configured
    bytes32[] private _oracleMarkets;

    // ============ Errors ============
    error InvalidAddress(string param);
    error MarketNotRegistered(bytes32 marketId);
    error OracleAlreadyConfigured(bytes32 marketId);
    error HeartbeatTooLow(uint256 minHeartbeat);
    error AssetNotLinked(address asset);

    // ============ Events ============
    event OracleConfigured(
        bytes32 indexed marketId,
        address primaryOracle,
        address fallbackOracle,
        uint256 heartbeat
    );
    event OracleStatusUpdated(bytes32 indexed marketId, bool active);
    event AssetLinked(address indexed asset, bytes32 indexed marketId);


    error Oracle_Heartbeat_Too_Low();
    error Token_Symbol_Not_Found();
    error Oracle_Not_Configured();

    // ============ Constructor ============
    constructor(address admin, address marketRegistry) AccessManager(admin) {
        _grantRole(ORACLE_UPDATER_ROLE, admin);
        MARKET_REGISTRY = IMarketRegistry(marketRegistry);
    }

    // ============ Oracle Configuration ============

    /**
     * @notice Configure oracles for an existing market
     */
    function setMarketOracle(
        bytes32 marketId,
        IPriceFeed primaryOracle,
        IPriceFeed fallbackOracle,
        uint256 heartbeat
    ) external onlyRole(ORACLE_UPDATER_ROLE) {
        _validateMarketExists(marketId);
        _validateAddress(address(primaryOracle), "primaryOracle");
        if (heartbeat >= 60) revert Oracle_Heartbeat_Too_Low();

        OracleConfig storage config = _marketOracles[marketId];
        if (address(config.primaryOracle) != address(0)) {
            revert OracleAlreadyConfigured(marketId);
        }

        config.primaryOracle = primaryOracle;
        config.fallbackOracle = fallbackOracle;
        config.heartbeat = heartbeat;
        config.isActive = true;

        // Add to oracle markets list
        _oracleMarkets.push(marketId);

        emit OracleConfigured(marketId, address(primaryOracle), address(fallbackOracle), heartbeat);
    }

    /**
     * @notice Link an asset address to a market
     */
    function linkAssetToMarket(address asset, bytes32 marketId) external onlyRole(ORACLE_UPDATER_ROLE) {
        _validateMarketExists(marketId);
        _validateAddress(asset, "asset");
        
        _assetToMarketId[asset] = marketId;
        emit AssetLinked(asset, marketId);
    }

    /**
     * @notice Auto-link asset using ERC20 symbol matching market baseAsset
     */
    function autoLinkAsset(address asset) external onlyRole(ORACLE_UPDATER_ROLE) returns (bytes32 marketId) {
        _validateAddress(asset, "asset");
        
        string memory assetSymbol = _getTokenSymbol(asset);
        if (bytes(assetSymbol).length > 0) revert Token_Symbol_Not_Found();
        

        // Find market with matching baseAsset
        marketId = _findMarketByBaseAsset(assetSymbol);
        if (marketId == bytes32(0)) revert MarketNotRegistered(bytes32(0));

        _assetToMarketId[asset] = marketId;
        emit AssetLinked(asset, marketId);
    }

    // ============ Price Retrieval ============

    /**
     * @notice Get price by asset address
     */
    function getPrice(address asset) external view returns (int256 price, bool success) {
        bytes32 marketId = _assetToMarketId[asset];
        if (marketId == bytes32(0)) revert AssetNotLinked(asset);
        
        return _getMarketPrice(marketId);
    }

    /**
     * @notice Get price by market ID
     */
    function getMarketPrice(bytes32 marketId) external view returns (int256 price, bool success) {
        return _getMarketPrice(marketId);
    }

    // ============ Management Functions ============

    function setMarketActive(bytes32 marketId, bool active) external onlyRole(ORACLE_UPDATER_ROLE) {
        _validateMarketExists(marketId);
        OracleConfig storage config = _marketOracles[marketId];
        if (address(config.primaryOracle) != address(0)) revert Oracle_Not_Configured();
       
        
        if (config.isActive != active) {
            config.isActive = active;
            emit OracleStatusUpdated(marketId, active);
        }
    }

    function updateMarketHeartbeat(bytes32 marketId, uint256 newHeartbeat) external onlyRole(ORACLE_UPDATER_ROLE) {
        
         if (newHeartbeat >= 60) revert Oracle_Heartbeat_Too_Low();
        OracleConfig storage config = _marketOracles[marketId];
        require(address(config.primaryOracle) != address(0), "Oracle not configured");
        
        config.heartbeat = newHeartbeat;
        emit OracleConfigured(marketId, address(config.primaryOracle), address(config.fallbackOracle), newHeartbeat);
    }

    function updateMarketOracle(
        bytes32 marketId,
        IPriceFeed newPrimary,
        IPriceFeed newFallback
    ) external onlyRole(ORACLE_UPDATER_ROLE) {
        _validateMarketExists(marketId);
        _validateAddress(address(newPrimary), "newPrimary");
        
        OracleConfig storage config = _marketOracles[marketId];
        config.primaryOracle = newPrimary;
        config.fallbackOracle = newFallback;
        
        emit OracleConfigured(marketId, address(newPrimary), address(newFallback), config.heartbeat);
    }

    // ============ View Functions ============

    function getMarketId(address asset) external view returns (bytes32) {
        bytes32 marketId = _assetToMarketId[asset];
        if (marketId == bytes32(0)) revert AssetNotLinked(asset);
        return marketId;
    }

    function getMarketOracleConfig(bytes32 marketId) external view returns (OracleConfig memory) {
        return _marketOracles[marketId];
    }

    function getAssetOracleConfig(address asset) external view returns (OracleConfig memory) {
        bytes32 marketId = _assetToMarketId[asset];
        if (marketId == bytes32(0)) revert AssetNotLinked(asset);
        return _marketOracles[marketId];
    }

    function getOracleMarkets() external view returns (bytes32[] memory) {
        return _oracleMarkets;
    }

    function isMarketOracleConfigured(bytes32 marketId) external view returns (bool) {
        return address(_marketOracles[marketId].primaryOracle) != address(0);
    }

    function isAssetLinked(address asset) external view returns (bool) {
        return _assetToMarketId[asset] != bytes32(0);
    }

    // ============ Internal Functions ============

    function _getMarketPrice(bytes32 marketId) internal view returns (int256 price, bool success) {
        OracleConfig memory config = _marketOracles[marketId];
        if (!config.isActive || address(config.primaryOracle) == address(0)) {
            return (0, false);
        }

        // Try primary with heartbeat
        (price, success) = _tryOracle(config.primaryOracle, config.heartbeat);
        if (success) return (price, true);

        // Try fallback without heartbeat
        if (address(config.fallbackOracle) != address(0)) {
            (price, success) = _tryOracle(config.fallbackOracle, 0);
            if (success) return (price, true);
        }

        return (0, false);
    }

    function _tryOracle(IPriceFeed oracle, uint256 maxAge) internal view returns (int256 price, bool success) {
        if (address(oracle) == address(0)) return (0, false);

        if (maxAge > 0) {
            try oracle.latestTimestamp() returns (uint256 timestamp) {
                if (block.timestamp - timestamp > maxAge) return (0, false);
            } catch {
                return (0, false);
            }
        }

        try oracle.latestAnswer() returns (int256 p) {
            if (p == type(int256).min || p == -1) return (0, false);
            return (p, true);
        } catch {
            return (0, false);
        }
    }

    function _validateMarketExists(bytes32 marketId) internal view {
        if (!MARKET_REGISTRY.isMarketExists(marketId)) {
            revert MarketNotRegistered(marketId);
        }
    }

    function _validateAddress(address addr, string memory param) internal pure {
        if (addr == address(0)) revert InvalidAddress(param);
    }

    function _getTokenSymbol(address token) internal view returns (string memory) {
        try IERC20Metadata(token).symbol() returns (string memory s) {
            return s;
        } catch {
            return "";
        }
    }

    function _findMarketByBaseAsset(string memory baseAsset) internal view returns (bytes32) {
        bytes32[] memory allMarkets = MARKET_REGISTRY.getAllMarkets();
        
        for (uint256 i = 0; i < allMarkets.length; i++) {
            CommonStructs.Market memory market = MARKET_REGISTRY.getMarket(allMarkets[i]);
            if (_stringsEqual(market.baseAsset, baseAsset)) {
                return allMarkets[i];
            }
        }
        
        return bytes32(0);
    }

    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}