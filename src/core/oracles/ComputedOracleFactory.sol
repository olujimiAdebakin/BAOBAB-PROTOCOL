// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
import {ComputedOracle} from "./adapters/ComputedOracle.sol";
// import { BaobabOracleRegistry} from "./OracleRegistry.sol";
import {IOracleRegistry} from "../../interfaces/IOracleRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";

/**
 * @title ComputedOracleFactory
 * @notice Factory for deploying and registering new instances of ComputedOracle.sol.
 * @dev Centralizes deployment logic and ensures new oracles are immediately registered.
 */
contract ComputedOracleFactory is Ownable {
    using AddressUtils for address;
    // The OracleRegistry is immutable because the Factory must always register to the same central hub.
    //      BaobabOracleRegistry public immutable ORACLE_REGISTRY;

    IOracleRegistry public immutable iORACLE_REGISTRY;

    event ComputedOracleCreated(
        address indexed targetAssetAddress,
        address indexed computedOracleAddress,
        address inputAssetA,
        address inputAssetB
    );

    error ComputedOracleFactory__ZeroAddressRegistry();
    error ComputedOracleFactory__InvalidInputAsset(address asset);

    constructor(address oracleRegistry_, address initialOwner) Ownable(initialOwner) {
        if (oracleRegistry_ == address(0)) {
            revert ComputedOracleFactory__ZeroAddressRegistry();
        }
        //   ORACLE_REGISTRY = BaobabOracleRegistry(oracleRegistry_);
        iORACLE_REGISTRY = IOracleRegistry(oracleRegistry_);
    }

    /**
     * @notice Deploys a new ComputedOracle instance and immediately registers it
     * with the OracleRegistry under the specified targetAssetAddress.
     * @dev Only the owner (governance) can call this.
     * @param targetAssetAddress The address representing the derived asset (e.g., the synthetic token address).
     * @param feedA The address of the primary input feed (Asset A, e.g., ETH/USD).
     * @param feedB The address of the secondary input feed (Asset B, e.g., BTC/USD).
     * @return computedOracleAddress The address of the newly deployed ComputedOracle contract.
     */
    function deployAndRegisterOracle(
        address targetAssetAddress,
        address feedA,
        address feedB,
        ComputedOracle.Operation operation,
        uint256 heartbeat
    ) external onlyOwner returns (address computedOracleAddress) {
        // INPUT VALIDATION
        feedA.validateNotZero();
        feedB.validateNotZero();
        targetAssetAddress.validateNotZero();

        // DEPLOY THE NEW ORACLE INSTANCE
        // The `new` keyword executes the constructor of ComputedOracle.sol.
        // The newly deployed contract automatically inherits the security configuration (A, B, Registry)
       
        ComputedOracle newOracle = new ComputedOracle(feedA, feedB, operation);

        computedOracleAddress = address(newOracle);

        // REGISTER WITH ORACLE REGISTRY

        // Assuming OracleRegistry has a function to set the primary feed for an asset.
        iORACLE_REGISTRY.setOracle(
            targetAssetAddress, 
            newOracle, 
            IPriceFeed(address(0)),
            heartbeat
            );

        emit ComputedOracleCreated(targetAssetAddress, computedOracleAddress, feedA, feedB);
        return computedOracleAddress;
    }
}
