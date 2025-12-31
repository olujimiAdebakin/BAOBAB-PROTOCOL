// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @author Consonant Labs, Inc.
 * @title ComputedOracleFactory
 * @notice A factory contract responsible for securely deploying and registering
 * instances of the `ComputedOracle.sol` contract.
 *
 * @dev This factory provides a governance/protocol controlled mechanism to create complex 
 * price feeds, such as synthetic assets (e.g., A/B or A*B) derived from two base 
 * price feeds (e.g., ETH/USD and BTC/USD to get ETH/BTC). 
 *
 * **Core Functionality:**
 * 1. **Deployment:** The `deployAndRegisterOracle` function uses the `new` keyword 
 * to deploy a `ComputedOracle` instance, injecting its dependencies (feedA, feedB, operation).
 * 2. **Registration:** Immediately registers the newly deployed `ComputedOracle` 
 * instance as the **primary price feed** for the `targetAssetAddress` within the 
 * central `IOracleRegistry`.
 * 3. **Access Control:** All deployment functions are restricted to the `onlyOwner` 
 * (governance) to maintain tight control over the introduction of new pricing mechanisms, 
 * which is a critical risk vector.
 *
 * By centralizing deployment, the protocol ensures that all computed price feeds 
 * are correctly configured and immediately integrated into the protocol's official 
 * risk and pricing system.
 */


import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
import {ComputedOracle} from "./adapters/ComputedOracle.sol";
// import { BaobabOracleRegistry} from "./OracleRegistry.sol";
import {IOracleRegistry} from "../../interfaces/IOracleRegistry.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";

/**
 * @author Consonant Labs, Inc.
 * @title ComputedOracleFactory
 * @notice Factory for deploying and registering new instances of ComputedOracle.sol.
 * @dev Centralizes deployment logic and ensures new oracles are immediately registered.
 */
contract ComputedOracleFactory is Ownable {
    using AddressUtils for address;
    // The OracleRegistry is immutable because the Factory must always register to the same central hub.
    //      BaobabOracleRegistry public immutable ORACLE_REGISTRY;

    IOracleRegistry public immutable iORACLE_REGISTRY;

    /**
     * @notice Emitted when a new ComputedOracle contract is deployed and successfully registered.
     * @param targetAssetAddress The asset (synthetic token) whose price the new oracle computes.
     * @param computedOracleAddress The address of the newly deployed ComputedOracle instance.
     * @param inputAssetA The address of the primary input feed (Feed A).
     * @param inputAssetB The address of the secondary input feed (Feed B).
     */
    event ComputedOracleCreated(
        address indexed targetAssetAddress,
        address indexed computedOracleAddress,
        address inputAssetA,
        address inputAssetB
    );

    error ComputedOracleFactory__ZeroAddressRegistry();
    error ComputedOracleFactory__InvalidInputAsset(address asset);

    /**
     * @notice Initializes the Factory and sets the immutable Oracle Registry address.
     * @param oracleRegistry_ Address of the central IOracleRegistry contract.
     * @param initialOwner Address to be granted the Ownership role.
     */
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
     * @dev Only the owner (governance) can call this. The ComputedOracle is set as the
     * PRIMARY oracle. The fallback is set to address(0).
     * @param targetAssetAddress The address representing the derived asset (e.g., the synthetic token address).
     * @param feedA The address of the primary input feed (Asset A, e.g., ETH/USD).
     * @param feedB The address of the secondary input feed (Asset B, e.g., BTC/USD).
     * @param operation The computation type to be performed by the oracle (e.g., MULTIPLY or DIVIDE).
     * @param heartbeat The freshness threshold (seconds) for the primary feed.
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
        // Uses the 'new' keyword to deploy the ComputedOracle contract, passing its dependencies
        ComputedOracle newOracle = new ComputedOracle(
            feedA, 
            feedB, 
            operation
            );

        computedOracleAddress = address(newOracle);

        
        // REGISTER WITH ORACLE REGISTRY
        // Atomically registers the new ComputedOracle instance as the PRIMARY oracle for the target asset.
        // Fallback is set to the zero address as ComputedOracles often do not have a direct fallback.
        iORACLE_REGISTRY.setMarketOracle(
            iORACLE_REGISTRY.getMarketId(targetAssetAddress),
            newOracle,
            IPriceFeed(address(0)),
            heartbeat
            );

       // Emit event for logging and off-chain monitoring
        emit ComputedOracleCreated(
            targetAssetAddress, 
            computedOracleAddress, 
            feedA, 
            feedB
            );

        return computedOracleAddress;
    }
}
