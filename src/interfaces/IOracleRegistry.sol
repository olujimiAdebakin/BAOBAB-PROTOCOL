// // SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IPriceFeed} from "./IPriceFeed.sol";
// import {BaobabOracleRegistry} from "../core/oracles/OracleRegistry.sol";

interface IOracleRegistry {
    struct OracleConfig {
        IPriceFeed primaryOracle;
        IPriceFeed fallbackOracle;
        bool isActive;
        uint256 heartbeat;
    }

    function getMarketId(address asset) external view returns (bytes32);
    function getPrice(address asset) external view returns (int256 price, bool success, uint256 confidence, uint256 lastUpdated);
    function isSupportedAsset(address asset) external view returns (bool);
    function getOracleConfig(address asset) external view returns (OracleConfig memory);
    // function primaryOracle(address asset) external view returns (IPriceFeed);
    // function assetOracles(address asset) external view returns (OracleConfig memory);
    function setMarketOracle(bytes32 marketId, IPriceFeed primaryOracle, IPriceFeed secondaryOracle, uint256 heartbeat)
        external;
    function setPrimaryOracle(address asset, address oracleAddress) external;
    function toggleAssetSupport(address asset, bool supported) external;
    function ORACLE_UPDATER_ROLE() external view returns (bytes32);
    function ADMIN_ROLE() external view returns (bytes32);
}
