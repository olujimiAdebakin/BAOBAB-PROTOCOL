// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../libraries/structs/CommonStructs.sol";

interface IMarketRegistry {
    // Market registration & management
    function registerMarket(
        string calldata baseAsset,
        string calldata quoteAsset,
        CommonStructs.AssetClass assetClass,
        address oracleAdapter,
        uint16 maxLeverage,
        uint16 maintenanceMarginBps,
        uint16 liquidationFeeBps,
        uint256 maxOpenInterest,
        uint16 tradingFeeBps
    ) external returns (bytes32 marketId);

    /**
     * @notice Resolve marketId by hashed base asset symbol
     * @dev Returns bytes32(0) if not found
     */
    function baseAssetHashToMarketId(bytes32 baseAssetHash) external view returns (bytes32);

    function setQuoteAsset(bytes32 marketId, address quoteAssetAddress) external;

    function setBaseAsset(bytes32 marketId, address baseAssetAddress) external;

    function updateRiskParameters(
        bytes32 marketId,
        uint16 newMaxLeverage,
        uint16 newMaintenanceMarginBps,
        uint16 newLiquidationFeeBps,
        uint256 newMaxOpenInterest,
        uint16 newTradingFeeBps
    ) external;

    function updateOracleAdapter(bytes32 marketId, address newOracleAdapter) external;

    function pauseMarket(bytes32 marketId) external;

    function resumeMarket(bytes32 marketId) external;

    function closeMarket(bytes32 marketId) external;

    // Views
    function getMarket(bytes32 marketId) external view returns (CommonStructs.Market memory);

    function getRiskParameters(bytes32 marketId) external view returns (CommonStructs.RiskParameters memory);

    function getQuoteAsset(bytes32 marketId) external view returns (address);

    function getBaseAsset(bytes32 marketId) external view returns (address);

    function getAllMarkets() external view returns (bytes32[] memory);

    function getMarketCount() external view returns (uint256);

    function isMarketActive(bytes32 marketId) external view returns (bool);

    function isMarketExists(bytes32 marketId) external view returns (bool);
}
