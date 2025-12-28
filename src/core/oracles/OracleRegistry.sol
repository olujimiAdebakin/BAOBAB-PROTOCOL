// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title OracleRegistry
 * @notice Central registry mapping asset → primary + fallback price feeds
 * @dev Only OracleSecurity.sol and governance can modify
 */
contract OracleRegistry is AccessControl {
    bytes32 public constant ORACLE_MANAGER = keccak256("ORACLE_MANAGER");

    /// @notice Primary oracle for each asset (asset => feed)
    mapping(address => IPriceFeed) public primaryOracle;

    /// @notice Fallback oracle (used if primary fails validation)
    mapping(address => IPriceFeed) public fallbackOracle;

    /// @notice Is asset officially supported?
    mapping(address => bool) public isSupportedAsset;

    /// @notice Supported assets list
    address[] public supportedAssets;

    event OracleSet(address indexed asset, address primary, address fallbackOracle);
    event AssetSupportToggled(address indexed asset, bool supported);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_MANAGER, admin);
    }

    function setOracle(
        address asset,
        IPriceFeed primary,
        IPriceFeed secondaryOracle
    ) external onlyRole(ORACLE_MANAGER) {
        primaryOracle[asset] = primary;
        fallbackOracle[asset] = secondaryOracle;

        if (!isSupportedAsset[asset]) {
            isSupportedAsset[asset] = true;
            supportedAssets.push(asset);
            emit AssetSupportToggled(asset, true);
        }

        emit OracleSet(asset, address(primary), address(secondaryOracle));
    }

    function toggleAssetSupport(address asset, bool supported) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isSupportedAsset[asset] = supported;
        emit AssetSupportToggled(asset, supported);
    }

    function getPrice(address asset) external view returns (int256 price, bool success) {
        if (!isSupportedAsset[asset]) return (0, false);

        IPriceFeed primary = primaryOracle[asset];
        if (address(primary) != address(0)) {
            try primary.latestAnswer() returns (int256 p) {
                if (p > 0) return (p, true);
            } catch {}
        }

        IPriceFeed secondaryOracle = fallbackOracle[asset];
        if (address(secondaryOracle) != address(0)) {
            try secondaryOracle.latestAnswer() returns (int256 p) {
                if (p > 0) return (p, true);
            } catch {}
        }

        return (0, false);
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }
}