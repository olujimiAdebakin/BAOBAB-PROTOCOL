# BAOBAB Perpetual Decentralized Exchange (perp-dex) 🌳

## Overview
The BAOBAB Protocol is a sophisticated decentralized exchange (DEX) designed for perpetual futures trading, leveraging Solidity smart contracts on the Ethereum Virtual Machine (EVM). It features a robust architecture for managing perpetual positions, dynamic fee distribution, granular access control, and advanced risk management mechanisms like Auto-Deleveraging (ADL) and Circuit Breakers.

## Features
- **Role-Based Access Control**: A hierarchical permission system (`AccessManager`) securing critical protocol operations with roles like `OWNER_ROLE`, `ADMIN_ROLE`, `GUARDIAN_ROLE`, and specialized operational roles.
- **Dynamic Fee Distribution**: Flexible fee (`FeeDistributor`) allocation across liquidity providers, insurance funds, staking rewards, and protocol treasury, with real-time adjustments and emergency controls.
- **Advanced Position Management**: Core logic (`PositionManager`) for opening, modifying, and closing perpetual positions, including cross-margin support, liquidation mechanisms, and real-time PnL tracking.
- **Automated Risk Management**: An `AutoDeleverageEngine` for mitigating systemic risk by automatically deleveraging profitable opposing positions to cover liquidation shortfalls, protecting the insurance fund.
- **Rate Limiting & Security**: A multi-layered `RateLimiter` protecting against spam and economic attacks, alongside `EmergencyPauser` for protocol-wide and module-specific halts.
- **Oracle Integration**: Centralized `OracleRegistry` for managing primary and fallback price feeds, ensuring reliable and robust price data for all markets.
- **Funding Rate Mechanism**: An `FundingRateEngine` to ensure price stability between perpetual contracts and underlying assets through periodic funding payments based on open interest imbalance.
- **Gas-Optimized Libraries**: Utilization of custom libraries (`FixedPointMath`, `PercentageMath`, `ArrayUtils`, `BaobabMath`, `TimeUtils`) for efficient and precise on-chain calculations.

## Getting Started
To set up and interact with the BAOBAB Protocol smart contracts locally, follow these steps.

### Installation
1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    cd BAOBAB-PROTOCOL
    ```
2.  **Install Dependencies**:
    The project uses Foundry (or Hardhat as an alternative, but Foundry is assumed here due to `.sol` files and typical DeFi development).
    -   Install Foundry:
        ```bash
        curl -L https://foundry.paradigm.xyz | bash
        foundryup
        ```
    -   Install Node.js dependencies for any scripts or Hardhat configuration:
        ```bash
        npm install
        # or
        yarn install
        ```
3.  **Build Contracts**:
    Compile the Solidity smart contracts:
    ```bash
    forge build
    ```
4.  **Run Tests (Optional but Recommended)**:
    Execute the test suite to ensure everything is functioning correctly:
    ```bash
    forge test
    ```
5.  **Deploy to a Local Network (e.g., Anvil)**:
    Start a local Anvil instance:
    ```bash
    anvil
    ```
    Then, deploy your contracts. This typically involves using Foundry scripts (`forge script`) or Hardhat deploy (`npx hardhat deploy`). For example:
    ```bash
    forge script script/DeployProtocol.s.sol --rpc-url http://127.0.0.1:8545 --private-key <YOUR_PRIVATE_KEY> --broadcast
    ```
    Replace `<YOUR_PRIVATE_KEY>` with a private key for a funded account on your local Anvil instance.

### Environment Variables
For local development and deployment, the following environment variables (or direct parameters in deployment scripts) are typically required:

-   `ADMIN_ADDRESS`: The address designated as the initial protocol administrator.
    *   Example: `0x...`
-   `MULTISIG_ADDRESS`: The address designated as the protocol's multi-signature wallet for critical operations.
    *   Example: `0x...`
-   `ORACLE_REGISTRY_ADDRESS`: Address of the deployed `OracleRegistry` contract.
    *   Example: `0x...`
-   `ADL_ENGINE_ADDRESS`: Address of the deployed `AutoDeleverageEngine` contract.
    *   Example: `0x...`
-   `FUNDING_ENGINE_ADDRESS`: Address of the deployed `FundingEngine` contract.
    *   Example: `0x...`
-   `CIRCUIT_BREAKER_ADDRESS`: Address of the deployed `CircuitBreaker` contract.
    *   Example: `0x...`
-   `EMERGENCY_PAUSER_ADDRESS`: Address of the deployed `EmergencyPauser` contract.
    *   Example: `0x...`
-   `RATE_LIMITER_ADDRESS`: Address of the deployed `RateLimiter` contract.
    *   Example: `0x...`
-   `SETTLEMENT_TOKEN_ADDRESS`: Address of the primary ERC-20 token used for settlement (e.g., USDC).
    *   Example: `0x...`
-   `LIQUIDITY_VAULT_ADDRESS`: Address of the `LiquidityVault` contract.
    *   Example: `0x...`
-   `INSURANCE_FUND_ADDRESS`: Address of the `InsuranceVault` contract.
    *   Example: `0x...`
-   `TREASURY_ADDRESS`: Address of the `TreasuryVault` contract or designated treasury.
    *   Example: `0x...`
-   `STAKING_REWARDS_ADDRESS`: Address of the staking rewards contract.
    *   Example: `0x...`

## Usage
Interacting with the BAOBAB Protocol typically involves calling public or external functions on the deployed smart contracts. This can be done via various tools:

1.  **Foundry's `cast` CLI**: For direct command-line interaction and scripting.
    ```bash
    # Example: Granting a role to an address using cast
    # Assume AccessManager is deployed at $ACCESS_MANAGER_ADDRESS
    # and you have ADMIN_PRIVATE_KEY
    cast send $ACCESS_MANAGER_ADDRESS "grantRole(bytes32,address)" \
      "0x..." $(cast --to-checksum-address 0x...) \
      --private-key $ADMIN_PRIVATE_KEY \
      --rpc-url $RPC_URL
    ```

2.  **Web3.js or Ethers.js**: For integrating with decentralized applications (dApps) in JavaScript/TypeScript.
    ```javascript
    // Example (Ethers.js): Interacting with AccessManager
    import { ethers } from "ethers";
    import AccessManagerABI from "./abi/AccessManager.json"; // Your generated ABI

    const provider = new ethers.JsonRpcProvider("YOUR_RPC_URL");
    const wallet = new ethers.Wallet("YOUR_PRIVATE_KEY", provider);
    const accessManager = new ethers.Contract("ACCESS_MANAGER_ADDRESS", AccessManagerABI, wallet);

    async function grantAdminRole(accountToGrant) {
        const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
        const tx = await accessManager.grantRole(ADMIN_ROLE, accountToGrant);
        await tx.wait();
        console.log(`Role granted in transaction: ${tx.hash}`);
    }

    // Call the function
    grantAdminRole("0xSomeAddress").catch(console.error);
    ```

3.  **Frontend Applications**: Connecting wallets like MetaMask to a dApp interface built with frameworks like React, Vue, or Angular, which then use Web3 libraries to interact with the contracts.

## API Documentation

### Contract Addresses
After deployment to a specific network (e.g., Ethereum Mainnet, Polygon, Arbitrum, or a local development chain), the addresses of the deployed smart contracts will be known. These addresses serve as the "base URLs" for interaction, and all function calls are directed to these specific contract instances. ABIs (Application Binary Interfaces) for each contract are used to encode and decode function calls and data.

### Endpoints

#### AccessManager
**Overview**: Centralized role-based access control (RBAC) system for the entire BAOBAB Protocol, implementing hierarchical role permissions.

##### external grantRole(bytes32 role, address account)
**Request**:
```
// Function parameters:
// role: bytes32 - The role identifier (e.g., RoleRegistry.ADMIN_ROLE).
// account: address - The address to receive the role.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__UnauthorizedRoleAdmin()`: Caller lacks administrative rights for the specified role.
- `AccessManager__AlreadyHasRole()`: The account already possesses the role.
- `AccessManager__InvalidAddress()`: The provided account address is the zero address.

##### external revokeRole(bytes32 role, address account)
**Request**:
```
// Function parameters:
// role: bytes32 - The role identifier to revoke.
// account: address - The address that will lose the role.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__UnauthorizedRoleAdmin()`: Caller lacks administrative rights for the specified role.
- `AccessManager__CannotRevokeOwnRole()`: Attempted to revoke caller's own role (use `renounceRole` instead).
- `AccessManager__InvalidAddress()`: The provided account address is the zero address.

##### external renounceRole(bytes32 role)
**Request**:
```
// Function parameters:
// role: bytes32 - The role identifier to renounce.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__CannotRevokeOwnRole()`: Internal error, as this function is designed for self-revocation.

##### external batchGrantRoles(bytes32[] calldata roles, address[] calldata accounts)
**Request**:
```
// Function parameters:
// roles: bytes32[] - An array of role identifiers to grant.
// accounts: address[] - An array of addresses to receive the roles.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__InvalidAddress()`: The `roles` and `accounts` arrays have mismatched lengths, or an account is the zero address.
- `AccessManager__UnauthorizedRoleAdmin()`: Caller lacks administrative rights for one or more specified roles.
- `AccessManager__AlreadyHasRole()`: An account already possesses a role being granted.

##### external batchRevokeRoles(bytes32[] calldata roles, address[] calldata accounts)
**Request**:
```
// Function parameters:
// roles: bytes32[] - An array of role identifiers to revoke.
// accounts: address[] - An array of addresses that will lose the roles.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__InvalidAddress()`: The `roles` and `accounts` arrays have mismatched lengths, or an account is the zero address.
- `AccessManager__UnauthorizedRoleAdmin()`: Caller lacks administrative rights for one or more specified roles.
- `AccessManager__CannotRevokeOwnRole()`: Attempted to revoke caller's own role within the batch.

##### external setRoleAdmin(bytes32 role, bytes32 newAdminRole)
**Request**:
```
// Function parameters:
// role: bytes32 - The role whose admin is being set.
// newAdminRole: bytes32 - The new role that will be able to manage the target role.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__OnlyOwner()`: Only the protocol owner can call this function.

##### external transferOwnership(address newOwner)
**Request**:
```
// Function parameters:
// newOwner: address - The address proposed to become the new owner.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__OnlyOwner()`: Only the current owner can initiate transfer.
- `AccessManager__InvalidAddress()`: The `newOwner` address is the zero address.

##### external acceptOwnership()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessManager__OnlyOwner()`: Only the proposed `pendingOwner` can accept ownership.
- `AccessManager__NoPendingOwner()`: No pending owner has been set.

##### public view hasRole(bytes32 role, address account)
**Request**:
```
// Function parameters:
// role: bytes32 - The role identifier to check.
// account: address - The address to check for the role.
```
**Response**:
```
// Returns: bool - True if the account has the role, false otherwise.
```
**Errors**:
- None.

#### ProtocolOwner
**Overview**: Provides owner-specific administrative functions for global protocol configurations, such as managing treasury, vaults, and emergency controls.

##### external setTreasury(address newTreasury)
**Request**:
```
// Function parameters:
// newTreasury: address - The new address for the protocol treasury.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can call this function.
- `ProtocolOwner__InvalidAddress()`: The `newTreasury` address is the zero address.

##### external setInsuranceVault(address newVault)
**Request**:
```
// Function parameters:
// newVault: address - The new address for the insurance vault.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can call this function.
- `ProtocolOwner__InvalidAddress()`: The `newVault` address is the zero address.

##### external setFeeRecipient(address newRecipient)
**Request**:
```
// Function parameters:
// newRecipient: address - The new address for the fee recipient.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can call this function.
- `ProtocolOwner__InvalidAddress()`: The `newRecipient` address is the zero address.

##### external toggleProtocolPause()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can toggle the pause state.

##### external enableEmergencyWithdrawal()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can enable emergency withdrawal.

##### external disableEmergencyWithdrawal()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can disable emergency withdrawal.

##### external recoverFunds(address token, address to, uint256 amount)
**Request**:
```
// Function parameters:
// token: address - The address of the ERC20 token to recover.
// to: address - The recipient address for the recovered tokens.
// amount: uint256 - The amount of tokens to recover.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can recover funds.
- `ProtocolOwner__EmergencyWithdrawalNotEnabled()`: Emergency withdrawal mode is not active.
- `ProtocolOwner__InvalidAddress()`: The `to` address is the zero address.
- `Transfer failed`: ERC20 transfer operation failed.

##### external recoverETH(address payable to, uint256 amount)
**Request**:
```
// Function parameters:
// to: address payable - The recipient address for the recovered ETH.
// amount: uint256 - The amount of ETH to recover.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ProtocolOwner__OnlyOwner()`: Only the protocol owner can recover ETH.
- `ProtocolOwner__EmergencyWithdrawalNotEnabled()`: Emergency withdrawal mode is not active.
- `ProtocolOwner__InvalidAddress()`: The `to` address is the zero address.
- `ETH transfer failed`: Native ETH transfer operation failed.

##### external view isPaused()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// Returns: bool - True if the protocol is paused, false otherwise.
```
**Errors**:
- None.

##### external view isEmergencyWithdrawalEnabled()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// Returns: bool - True if emergency withdrawal is enabled, false otherwise.
```
**Errors**:
- None.

##### external view getProtocolConfig()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// Returns:
// _treasury: address - The current treasury address.
// _insuranceVault: address - The current insurance vault address.
// _feeRecipient: address - The current fee recipient address.
// _paused: bool - The current protocol pause state.
// _emergencyEnabled: bool - The current emergency withdrawal state.
```
**Errors**:
- None.

#### FeeDistributor
**Overview**: Manages the distribution of collected fees across various protocol components (LP rewards, insurance, treasury, stakers, burn).

##### external distributeFees(uint256 amount)
**Request**:
```
// Function parameters:
// amount: uint256 - The total fee amount in settlement token decimals to be distributed.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `SecurityBase__ContractPaused()`: The contract or module is paused by `EmergencyPauser`.
- `FeeDistributor__DistributionPaused()`: Fee distributions are explicitly paused.
- `FeeDistributor__UnauthorizedDistributor()`: The caller is not an authorized distributor or `DEFAULT_ADMIN_ROLE`.
- `FeeDistributor__InsufficientAmount()`: The `amount` is less than `MIN_DISTRIBUTION_AMOUNT`.
- `Distribution overflow`: The sum of calculated shares exceeds the original amount.
- `DistributionFailed(address recipient, uint256 amount, string reason)`: An internal transfer to a recipient failed.

##### external distributeFeesBatch(uint256[] calldata amounts)
**Request**:
```
// Function parameters:
// amounts: uint256[] - An array of fee amounts to distribute in a single transaction.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `SecurityBase__ContractPaused()`: The contract or module is paused by `EmergencyPauser`.
- `FeeDistributor__DistributionPaused()`: Fee distributions are explicitly paused.
- `FeeDistributor__UnauthorizedDistributor()`: The caller is not an authorized distributor or `DEFAULT_ADMIN_ROLE`.
- `No valid amounts`: No valid amounts were provided in the array (all were below `MIN_DISTRIBUTION_AMOUNT` or array was empty).
- Other errors from `distributeFees` might propagate.

##### external claimMakerRebates()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `SecurityBase__ContractPaused()`: The contract or module is paused by `EmergencyPauser`.
- `No rebates available`: The caller has no pending maker rebates to claim.

##### external setFeeSplit(CommonStructs.FeeDistribution calldata newSplit)
**Request**:
```
// Function parameters:
// newSplit: CommonStructs.FeeDistribution - The new fee distribution configuration.
//   - treasuryBps: uint16 - Protocol revenue share in basis points.
//   - lpBps: uint16 - Liquidity provider fee share in basis points.
//   - insuranceBps: uint16 - Insurance fund fee share in basis points.
//   - stakersBps: uint16 - NFT stakers reward share in basis points.
//   - burnBps: uint16 - Token burn allocation in basis points.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `FEE_MANAGER_ROLE`.
- `FeeDistributor__InvalidFeeDistribution()`: The sum of `newSplit` basis points does not equal 10,000 (100%).

##### external setLiquidityVault(address newVault)
**Request**:
```
// Function parameters:
// newVault: address - The new address for the liquidity vault.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `DEFAULT_ADMIN_ROLE`.
- `AddressUtils: ZeroAddress`: The `newVault` address is the zero address.

##### external setInsuranceFund(address newFund)
**Request**:
```
// Function parameters:
// newFund: address - The new address for the insurance fund.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `DEFAULT_ADMIN_ROLE`.
- `AddressUtils: ZeroAddress`: The `newFund` address is the zero address.

##### external setTreasury(address newTreasury)
**Request**:
```
// Function parameters:
// newTreasury: address - The new address for the protocol treasury.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `TREASURY_ROLE`.
- `AddressUtils: ZeroAddress`: The `newTreasury` address is the zero address.

##### external setStakingRewards(address newContract)
**Request**:
```
// Function parameters:
// newContract: address - The new address for the staking rewards contract.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `DEFAULT_ADMIN_ROLE`.
- `AddressUtils: ZeroAddress`: The `newContract` address is the zero address.

##### external setEmergencyTreasury(address newEmergencyTreasury)
**Request**:
```
// Function parameters:
// newEmergencyTreasury: address - The new address for the emergency treasury.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `EMERGENCY_ADMIN` role.
- `AddressUtils: ZeroAddress`: The `newEmergencyTreasury` address is the zero address.

##### external setDistributionsPaused(bool paused)
**Request**:
```
// Function parameters:
// paused: bool - `true` to pause distributions, `false` to unpause.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `EMERGENCY_ADMIN` role.

##### external setAuthorizedDistributor(address distributor, bool authorized)
**Request**:
```
// Function parameters:
// distributor: address - The address to authorize or unauthorize.
// authorized: bool - `true` to authorize, `false` to unauthorize.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `DEFAULT_ADMIN_ROLE`.

##### external emergencyWithdraw()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `EMERGENCY_ADMIN` role.
- `Not in emergency`: Distributions are not currently paused.
- `Emergency treasury not set`: The `emergencyTreasury` address is the zero address.
- `No funds to withdraw`: The contract balance of the settlement token is zero.

##### external view getCurrentSplit()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// Returns: CommonStructs.FeeDistribution memory - The current fee distribution configuration.
//   - treasuryBps: uint16
//   - lpBps: uint16
//   - insuranceBps: uint16
//   - stakersBps: uint16
//   - burnBps: uint16
```
**Errors**:
- None.

##### external view getFeeStatistics()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// Returns: CommonStructs.FeeStats memory - Comprehensive fee distribution statistics.
//   - totalLpFees: uint256
//   - totalInsuranceFees: uint256
//   - totalTreasuryFees: uint256
//   - totalStakerFees: uint256
//   - totalBurned: uint256
//   - failedDistributions: uint256
```
**Errors**:
- None.

##### external view getContractBalance()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// Returns: uint256 - The current settlement token balance held by the contract.
```
**Errors**:
- None.

##### external view isAuthorizedDistributor(address distributor)
**Request**:
```
// Function parameters:
// distributor: address - The address to check for authorization.
```
**Response**:
```
// Returns: bool - True if the address is an authorized distributor or has DEFAULT_ADMIN_ROLE.
```
**Errors**:
- None.

##### external view getPendingMakerRebates(address trader)
**Request**:
```
// Function parameters:
// trader: address - The trader's address to query.
```
**Response**:
```
// Returns: uint256 - The amount of pending maker rebates for the trader.
```
**Errors**:
- None.

#### PositionManager
**Overview**: The core contract for managing perpetual futures positions, including opening, modifying, closing, and tracking margin, PnL, and liquidation status. Integrates with ADL and circuit breaker systems.

##### external openPosition(address trader, bytes32 marketId, CommonStructs.Side side, uint256 size, uint256 collateral, uint256 entryPrice, uint16 leverage)
**Request**:
```
// Function parameters:
// trader: address - The address of the position owner.
// marketId: bytes32 - Unique identifier for the market.
// side: CommonStructs.Side - The direction of the position (LONG or SHORT).
// size: uint256 - The size of the position in base asset units (18 decimals).
// collateral: uint256 - The collateral amount in quote asset units (18 decimals).
// entryPrice: uint256 - The entry price for the position (18 decimals).
// leverage: uint16 - The leverage multiplier for the position (e.g., 10 for 10x).
```
**Response**:
```
// Returns: bytes32 - The unique identifier for the newly created position.
```
**Errors**:
- `PositionManager__OnlyTradingEngine()`: Only the authorized trading engine can call this function.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: A circuit breaker is active for the market or globally.
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `PositionManager__InvalidSize()`: The `size` parameter is zero.
- `PositionManager__InsufficientCollateral()`: The `collateral` parameter is zero.
- `PositionManager__MarketNotConfigured()`: The market specified by `marketId` is not configured or is inactive.
- `PositionManager__LeverageExceedsMax()`: The requested `leverage` exceeds the maximum allowed for the market.
- `PositionManager__InsufficientInitialMargin()`: The provided `collateral` does not meet the initial margin requirement.

##### external modifyPosition(bytes32 positionId, int256 sizeDelta, int256 collateralDelta, uint256 currentPrice)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Unique identifier of the position to modify.
// sizeDelta: int256 - Change in position size (positive for increase, negative for decrease).
// collateralDelta: int256 - Change in collateral (positive for add, negative for remove).
// currentPrice: uint256 - Current market price for PnL calculation (18 decimals).
```
**Response**:
```
// Returns: int256 - Realized profit/loss from the modification (0 for simple size/collateral adjustment).
```
**Errors**:
- `PositionManager__OnlyTradingEngine()`: Only the authorized trading engine can call this function.
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active (market-specific allowed for reducing exposure).
- `PositionManager__PositionNotFound()`: The specified `positionId` does not exist.
- `PositionManager__InvalidSize()`: Attempted to reduce position size beyond its current value.
- `PositionManager__InsufficientCollateral()`: Attempted to withdraw more collateral than available.

##### external closePosition(bytes32 positionId, uint256 closePrice)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Unique identifier of the position to close.
// closePrice: uint256 - The price at which to close the position (18 decimals).
```
**Response**:
```
// Returns: int256 - The final realized profit/loss from the closure.
```
**Errors**:
- `PositionManager__OnlyTradingEngine()`: Only the authorized trading engine can call this function.
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active.
- `PositionManager__PositionNotFound()`: The specified `positionId` does not exist.

##### external forceClosePosition(bytes32 positionId, uint256 executionPrice, bool isLiquidation)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Unique identifier of the position to force-close.
// executionPrice: uint256 - The price at which to close the position (18 decimals).
// isLiquidation: bool - `true` if this closure is due to liquidation, `false` for ADL.
```
**Response**:
```
// Returns: int256 - The final realized profit/loss from the forced closure.
```
**Errors**:
- `PositionManager__Unauthorized()`: Only the `AutoDeleverageEngine` or `LiquidationEngine` can call this function.
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active.
- `PositionManager__PositionNotFound()`: The specified `positionId` does not exist.

##### external updatePositionState(bytes32 positionId, uint256 currentPrice)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Unique identifier of the position to update.
// currentPrice: uint256 - Current market price to recalculate PnL and liquidation status (18 decimals).
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active.

##### external updateAccumulatedFunding(bytes32 posId, int256 newAccumulatedFunding)
**Request**:
```
// Function parameters:
// posId: bytes32 - Unique identifier of the position.
// newAccumulatedFunding: int256 - The new accumulated funding amount for the position.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `PositionManage__OnlyFundingEngine()`: Only the authorized funding engine can call this function.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active.
- `PositionManager__Paused()`: The protocol or position manager module is paused.

##### external setMarketRiskConfig(bytes32 marketId, PositionManager.LiquidityTier liquidityTier, uint16 maintenanceMarginBps, uint16 initialMarginBps, uint16 maxLeverage)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Unique identifier for the market to configure.
// liquidityTier: PositionManager.LiquidityTier - The risk classification tier (HIGH, MEDIUM, LOW).
// maintenanceMarginBps: uint16 - Maintenance Margin Rate in basis points (e.g., 50 for 0.5%).
// initialMarginBps: uint16 - Initial Margin Rate in basis points (e.g., 100 for 1%).
// maxLeverage: uint16 - Maximum allowed leverage for the market (e.g., 100 for 100x).
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `PositionManager__OnlyAdmin()`: Only the protocol administrator can call this function.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: A circuit breaker is active for the market or globally.
- `PositionManager__InvalidSize()`: Invalid margin rates (zero, or IMR not > MMR) or invalid max leverage (0 or >100).

##### external setMarketConfig(bytes32 marketId, uint16 maxLev, uint16 mmr, uint16 maxFund, bool fundEnabled, uint256 interval)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Unique identifier for the market.
// maxLev: uint16 - Maximum allowed leverage for the market.
// mmr: uint16 - Maintenance margin requirement in basis points.
// maxFund: uint16 - Maximum funding rate per interval in basis points.
// fundEnabled: bool - Whether funding payments are active for this market.
// interval: uint256 - Time interval for funding updates in seconds.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `PositionManager__OnlyAdmin()`: Only the protocol administrator can call this function.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: A circuit breaker is active for the market or globally.

##### external setTradingEngine(address _tradingEngine)
**Request**:
```
// Function parameters:
// _tradingEngine: address - The address of the authorized trading engine contract.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `PositionManager__OnlyAdmin()`: Only the protocol administrator can call this function.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active.
- `AddressUtils: ZeroAddress`: The `_tradingEngine` address is the zero address.
- `AddressUtils: NotAContract`: The `_tradingEngine` address is not a contract.

##### external setLiquidationEngine(address _liquidationEngine)
**Request**:
```
// Function parameters:
// _liquidationEngine: address - The address of the authorized liquidation engine contract.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `PositionManager__OnlyAdmin()`: Only the protocol administrator can call this function.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active.
- `AddressUtils: ZeroAddress`: The `_liquidationEngine` address is the zero address.
- `AddressUtils: NotAContract`: The `_liquidationEngine` address is not a contract.

##### external setFundingEngine(address _fundingEngine)
**Request**:
```
// Function parameters:
// _fundingEngine: address - The address of the authorized funding engine contract.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `PositionManager__OnlyAdmin()`: Only the protocol administrator can call this function.
- `PositionManager__Paused()`: The protocol or position manager module is paused.
- `PositionManager__CircuitBroken()`: The global circuit breaker is active.
- `AddressUtils: ZeroAddress`: The `_fundingEngine` address is the zero address.
- `AddressUtils: NotAContract`: The `_fundingEngine` address is not a contract.

##### external view getPosition(bytes32 positionId)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Unique position identifier.
```
**Response**:
```
// Returns: PositionData memory - Full position data structure, including runtime state.
//   - position: CommonStructs.Position
//     - positionId: bytes32
//     - marketId: bytes32
//     - trader: address
//     - side: CommonStructs.Side
//     - size: uint256
//     - collateral: uint256
//     - entryPrice: uint256
//     - leverage: uint16
//     - lastFundingIndex: int256
//     - unrealizedPnL: int256
//     - liquidationPrice: uint256
//     - openedAt: uint256
//   - lastUpdateTime: uint256
//   - accumulatedFunding: int256
//   - isLiquidatable: bool
//   - inADLQueue: bool
```
**Errors**:
- None.

##### external view getPositionOwner(bytes32 positionId)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Unique position identifier.
```
**Response**:
```
// Returns: address - Address of the position owner.
```
**Errors**:
- None.

##### external view getPositionSize(bytes32 positionId)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Unique position identifier.
```
**Response**:
```
// Returns: uint256 - Current position size in base asset units.
```
**Errors**:
- None.

##### external view getUserPositions(address trader)
**Request**:
```
// Function parameters:
// trader: address - Address of the trader.
```
**Response**:
```
// Returns: bytes32[] memory - An array of position IDs owned by the trader.
```
**Errors**:
- None.

##### external view getPortfolio(address trader)
**Request**:
```
// Function parameters:
// trader: address - Address of the trader.
```
**Response**:
```
// Returns: CommonStructs.Portfolio memory - Portfolio summary for the trader.
//   - trader: address
//   - totalCollateral: uint256
//   - totalUnrealizedPnL: int256
//   - marginRatio: uint256
//   - positionCount: uint256
//   - lastUpdateTime: uint256
```
**Errors**:
- None.

##### external view getOpenInterest(bytes32 marketId, CommonStructs.Side side)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Market identifier.
// side: CommonStructs.Side - Position side (LONG or SHORT).
```
**Response**:
```
// Returns: uint256 - Total open interest for the market and side in base asset units.
```
**Errors**:
- None.

##### external view getMarketPositions(bytes32 marketId)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Market identifier.
```
**Response**:
```
// Returns: bytes32[] memory - An array of all position IDs open in the specified market.
```
**Errors**:
- None.

#### FundingEngine
**Overview**: Calculates and applies periodic funding rates to open perpetual positions based on open interest imbalance, ensuring price convergence between perpetual contracts and underlying assets.

##### external applyFundingRate(bytes32 marketId)
**Request**:
```
// Function parameters:
// marketId: bytes32 - The unique identifier for the target market.
```
**Response**:
```
// Returns: int256 - The calculated funding rate in basis points (BPS) for the period.
```
**Errors**:
- `Only keeper`: Only an address with `KEEPER_ROLE` can call this function.
- `SecurityBase__ContractPaused()`: The contract or module is paused by `EmergencyPauser`.
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `FundingTooSoon()`: The funding period has not yet elapsed since the last application.
- `RateLimitCount(uint256 retryAfter, string reason)`: The caller exceeded the rate limit for `APPLY_FUNDING` operations.

##### external view getCurrentRate(bytes32 marketId)
**Request**:
```
// Function parameters:
// marketId: bytes32 - The unique identifier for the target market.
```
**Response**:
```
// Returns: int256 - The calculated funding rate in basis points (BPS) based on current open interest.
```
**Errors**:
- None (returns 0 if no open interest).

##### external view timeUntilNext(bytes32 marketId)
**Request**:
```
// Function parameters:
// marketId: bytes32 - The unique identifier for the target market.
```
**Response**:
```
// Returns: uint256 - Time in seconds until the next funding period begins, or 0 if funding is overdue.
```
**Errors**:
- None.

#### AutoDeleverageEngine
**Overview**: Automatically force-closes profitable opposing positions when normal liquidations cannot be filled by the market or insurance fund, protecting the protocol's solvency.

##### external executeADL(bytes32 marketId, bytes32 liquidatedPosition, CommonStructs.Side side, uint256 sizeToClose, uint256 executionPrice)
**Request**:
```
// Function parameters:
// marketId: bytes32 - The market identifier where ADL is performed.
// liquidatedPosition: bytes32 - The position ID that triggered the ADL.
// side: CommonStructs.Side - The side (LONG or SHORT) of the position that was liquidated (ADL will target the opposite side).
// sizeToClose: uint256 - The total position size to be covered by deleveraging (18 decimals).
// executionPrice: uint256 - The current execution price for closing positions (18 decimals).
```
**Response**:
```
// Returns: bool - True if the ADL successfully covered the required size, false otherwise.
```
**Errors**:
- `ADL__OnlyLiquidationEngine()`: Only the authorized `LiquidationEngine` can call this function.
- `ADL_ENGINE__Paused()`: The ADL engine or protocol is paused.
- `ReentrancyGuard__ReentrantCall()`: A reentrant call was detected.
- `ADL__ADLNotEnabled()`: ADL is not enabled for the specified market.
- `ADL__InsufficientCandidates()`: There are not enough profitable opposing positions in the queue to cover the `sizeToClose`.
- `InvalidInput()`: `sizeToClose` is zero.
- `RateLimitCount(uint256 retryAfter, string reason)`: The caller (trader whose position is being closed) exceeded the rate limit for `EXECUTE_ADL` operations.

##### external updateADLQueue(bytes32 marketId, bytes32 positionId, address trader, CommonStructs.Side side, uint256 unrealizedPnL, uint16 leverage)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Market identifier.
// positionId: bytes32 - Position identifier.
// trader: address - Trader address.
// side: CommonStructs.Side - Position side.
// unrealizedPnL: uint256 - Current positive unrealized profit for the position (18 decimals).
// leverage: uint16 - Position leverage.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ADL__onlyPositionManager()`: Only the `PositionManager` can update the ADL queue.
- `ADL_ENGINE__Paused()`: The ADL engine or protocol is paused.
- `ADL__CircuitActive()`: A circuit breaker is active for the market or globally.

##### external removeFromADLQueue(bytes32 marketId, bytes32 positionId, CommonStructs.Side side)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Market identifier.
// positionId: bytes32 - Position identifier.
// side: CommonStructs.Side - Position side.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ADL__onlyPositionManager()`: Only the `PositionManager` can remove from the ADL queue.
- `ADL_ENGINE__Paused()`: The ADL engine or protocol is paused.
- `ADL__CircuitActive()`: A circuit breaker is active for the market or globally.

##### external configureADL(bytes32 marketId, uint16 insuranceFundThreshold, uint8 maxPositionsPerADL, uint256 gracePeriod)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Market identifier.
// insuranceFundThreshold: uint16 - Percentage (in basis points) of insurance fund remaining before ADL triggers (e.g., 2000 for 20%).
// maxPositionsPerADL: uint8 - Maximum number of positions to deleverage in a single ADL event.
// gracePeriod: uint256 - Time (in seconds) to attempt normal liquidation before ADL considers activating.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ADL__OnlyAdmin()`: Only the protocol administrator can configure ADL.
- `ADL__InvalidConfig()`: Invalid configuration parameters provided (e.g., `insuranceFundThreshold` too high).

##### external toggleADL(bytes32 marketId)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Market identifier.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `ADL__OnlyAdmin()`: Only the protocol administrator can toggle ADL.
- `ADL_ENGINE__Paused()`: The ADL engine or protocol is paused.

##### external view getADLQueue(bytes32 marketId, CommonStructs.Side side)
**Request**:
```
// Function parameters:
// marketId: bytes32 - Market identifier.
// side: CommonStructs.Side - Position side (LONG or SHORT).
```
**Response**:
```
// Returns: ADLCandidate[] memory - An array of ADL candidates, sorted by ADL score (most profitable first).
//   - positionId: bytes32
//   - trader: address
//   - side: CommonStructs.Side
//   - unrealizedPnL: uint256
//   - leverage: uint16
//   - adlScore: uint256
//   - lastUpdateTime: uint256
```
**Errors**:
- None.

##### external view isInADLQueue(bytes32 positionId)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Position identifier.
```
**Response**:
```
// Returns: bool - True if the position is currently in the ADL queue.
```
**Errors**:
- None.

##### external view getADLRank(bytes32 positionId)
**Request**:
```
// Function parameters:
// positionId: bytes32 - Position identifier.
```
**Response**:
```
// Returns: uint256 - The rank of the position in the ADL queue (1 = first to be deleveraged), or 0 if not in queue.
```
**Errors**:
- None.

#### OracleRegistry
**Overview**: Central registry for mapping asset identifiers to their primary and fallback price feeds, ensuring reliable price data for all protocol operations.

##### external setOracle(address asset, IPriceFeed primary, IPriceFeed fallback)
**Request**:
```
// Function parameters:
// asset: address - The address representing the asset (e.g., token address).
// primary: IPriceFeed - The contract address of the primary price feed adapter.
// fallback: IPriceFeed - The contract address of the fallback price feed adapter.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `ORACLE_MANAGER` role.

##### external toggleAssetSupport(address asset, bool supported)
**Request**:
```
// Function parameters:
// asset: address - The address of the asset whose support status is being toggled.
// supported: bool - `true` to enable support, `false` to disable.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `AccessControl: sender missing role`: Caller does not have the `DEFAULT_ADMIN_ROLE`.

##### external view getPrice(address asset)
**Request**:
```
// Function parameters:
// asset: address - The address of the asset to query the price for.
```
**Response**:
```
// Returns:
// price: int256 - The latest validated price (typically 8 decimals). Returns 0 if no valid price can be fetched.
// success: bool - True if a valid price was successfully retrieved from either primary or fallback oracle.
```
**Errors**:
- None (errors are handled internally by attempting fallback, returns `(0, false)` on failure).

##### external view getSupportedAssets()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// Returns: address[] memory - An array of all currently supported asset addresses.
```
**Errors**:
- None.

#### RateLimiter
**Overview**: Implements a multi-layered rate limiting system to protect the protocol against spam, Denial-of-Service (DoS) attacks, and economic manipulation by limiting request frequency and gas consumption per user and operation.

##### public checkRateLimit(address user, bytes32 operationId)
**Request**:
```
// Function parameters:
// user: address - The address of the user initiating the operation.
// operationId: bytes32 - The unique identifier of the operation being performed (e.g., `RateLimitBuckets.PLACE_ORDER`).
```
**Response**:
```
// This function does not return a value on success if limits are not exceeded.
```
**Errors**:
- `RateLimitCount(uint256 retryAfter, string reason)`: The user has exceeded the allowed request count or gas limit for the specified `operationId`. `retryAfter` indicates seconds until the limit resets.

##### external setTieredLimit(string calldata opName, uint256 basic, uint256 premium, uint256 vip, uint256 marketMaker, uint256 timeWindow)
**Request**:
```
// Function parameters:
// opName: string - The human-readable name of the operation (e.g., "PLACE_ORDER").
// basic: uint256 - The maximum requests allowed for 'Basic' tier users within the time window.
// premium: uint256 - The maximum requests allowed for 'Premium' tier users.
// vip: uint256 - The maximum requests allowed for 'VIP' tier users.
// marketMaker: uint256 - The maximum requests allowed for 'MarketMaker' tier users.
// timeWindow: uint256 - The duration (in seconds) for which the request count is tracked.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can configure rate limits.
- `InvalidConfig()`: `timeWindow` is zero.

##### external setGasLimit(string calldata opName, uint256 maxGasPerWindow)
**Request**:
```
// Function parameters:
// opName: string - The human-readable name of the operation.
// maxGasPerWindow: uint256 - The maximum total gas units allowed for this operation within a 5-minute window per user.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can configure gas limits.

##### external upgradeUserTier(address user, RateLimiter.UserTier newTier)
**Request**:
```
// Function parameters:
// user: address - The address of the user whose tier is being updated.
// newTier: RateLimiter.UserTier - The new tier to assign (Basic, Premium, VIP, MarketMaker).
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can upgrade user tiers.
- `ZeroAddress()`: The `user` address is the zero address.

##### external setWhitelist(address account, bool status)
**Request**:
```
// Function parameters:
// account: address - The address to whitelist or unwhitelist.
// status: bool - `true` to whitelist, `false` to remove from whitelist.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can manage the whitelist.

##### external setEmergencyBypass(address account, bool status)
**Request**:
```
// Function parameters:
// account: address - The address to grant or revoke emergency bypass.
// status: bool - `true` to enable bypass, `false` to disable.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can manage emergency bypass.

##### external setKeeperStatus(address account, bool status)
**Request**:
```
// Function parameters:
// account: address - The address to designate as a keeper or remove keeper status.
// status: bool - `true` to mark as keeper, `false` to remove status.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can manage keeper status.

##### external setKeeperLimits(string calldata opName, uint256 basic, uint256 premium, uint256 vip, uint256 marketMaker)
**Request**:
```
// Function parameters:
// opName: string - The human-readable name of the operation.
// basic: uint256 - Limit for 'Basic' tier keepers.
// premium: uint256 - Limit for 'Premium' tier keepers.
// vip: uint256 - Limit for 'VIP' tier keepers.
// marketMaker: uint256 - Limit for 'MarketMaker' tier keepers.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can configure keeper limits.

##### external toggleGlobal()
**Request**:
```
// Function parameters:
// None.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can toggle global rate limiting.

##### external transferAdmin(address newAdmin)
**Request**:
```
// Function parameters:
// newAdmin: address - The address to transfer admin privileges to.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the current administrator can transfer admin privileges.
- `ZeroAddress()`: The `newAdmin` address is the zero address.

##### external resetRateLimitState(address user, string calldata opName)
**Request**:
```
// Function parameters:
// user: address - The user address whose rate limit state is to be reset.
// opName: string - The operation name for which the state should be reset.
```
**Response**:
```
// This function does not return a value on success.
```
**Errors**:
- `NotAdmin()`: Only the administrator can reset rate limit states.

##### external view getUserTier(address user)
**Request**:
```
// Function parameters:
// user: address - The user address to query.
```
**Response**:
```
// Returns: RateLimiter.UserTier - The user's current assigned tier.
```
**Errors**:
- None.

##### external view remainingRequests(address user, string calldata opName)
**Request**:
```
// Function parameters:
// user: address - The user address to query.
// opName: string - The operation name to check.
```
**Response**:
```
// Returns: uint256 - Number of remaining requests allowed in the current window. Returns `type(uint256).max` for unlimited.
```
**Errors**:
- None.

##### external view remainingGas(address user, string calldata opName)
**Request**:
```
// Function parameters:
// user: address - The user address to query.
// opName: string - The operation name to check.
```
**Response**:
```
// Returns: uint256 - Remaining gas units available in the current gas tracking window. Returns `type(uint256).max` for unlimited.
```
**Errors**:
- None.

##### external view checkRateLimitView(address user, string calldata opName)
**Request**:
```
// Function parameters:
// user: address - The user address to check.
// opName: string - The operation name to check.
```
**Response**:
```
// Returns:
// allowed: bool - True if the operation would be allowed, false otherwise.
// retryAfter: uint256 - Seconds until the rate limit resets (0 if allowed).
```
**Errors**:
- None.

##### external pure opId(string calldata name)
**Request**:
```
// Function parameters:
// name: string - The operation name as a string.
```
**Response**:
```
// Returns: bytes32 - The keccak256 hash of the operation name, used as an operation ID.
```
**Errors**:
- None.

## Technologies Used

| Category         | Technology                 | Description                                                        |
| :--------------- | :------------------------- | :----------------------------------------------------------------- |
| **Blockchain**   | Solidity                   | Smart contract language for core logic and business rules.         |
| **Development**  | Foundry                    | Fast, portable, and modular toolkit for Ethereum application development. |
| **Standards**    | OpenZeppelin Contracts     | Secure and community-audited smart contract libraries.             |
|                  | EIP-165                    | Standard for smart contract interface detection.                   |
|                  | EIP-712 (Mentioned)        | Structured data hashing for off-chain signatures.                  |
| **Math Libraries** | FixedPointMath             | High-precision fixed-point arithmetic (Q64.96 format).             |
|                  | PercentageMath             | Utilities for percentage and basis point calculations.             |
|                  | BaobabMath                 | Unified math library with protocol-specific utilities.             |
|                  | Statistics                 | Advanced statistical functions for risk management.                |
| **Data Structures** | ArrayUtils                 | Gas-optimized array manipulation utilities.                        |
|                  | SortUtils                  | Efficient sorting algorithms for various data structures.          |
|                  | CommonStructs              | Shared data structures for markets, positions, and orders.         |
|                  | BasketStructs              | Data structures specific to tokenized basket products.             |
|                  | EventStructs               | Data structures for prediction markets.                            |
|                  | TradingStructs             | Data structures specific to trading engines.                       |
| **Security**     | ReentrancyGuard            | Protection against reentrancy attacks.                             |
|                  | AccessControl              | Role-based permissions management.                                 |
|                  | EmergencyPauser            | Coordinated pause system for emergency halts.                      |
|                  | CircuitBreaker             | Automatic halt system for extreme market volatility.               |
|                  | RateLimiter                | Multi-layered protection against spam and abuse.                   |
| **Utilities**    | AddressUtils               | Comprehensive address validation and utility functions.            |
|                  | ModuleIds                  | Centralized registry of module identifiers.                        |
|                  | RateLimitBuckets           | Library for rate-limited action identifiers.                       |
|                  | SafeTransfer               | Gas-optimized, robust ERC20/ETH transfer.                          |
|                  | TimeUtils                  | Comprehensive time utilities and scheduling.                       |

## Contributing
We welcome contributions to the BAOBAB Protocol! If you're interested in improving the platform, please follow these guidelines:

*   **Fork the Repository**: Start by forking the project to your GitHub account.
*   **Create a New Branch**: Use a descriptive branch name (e.g., `feature/add-new-oracle`, `bugfix/fix-liquidation-calc`).
*   **Set Up Development Environment**: Ensure you can build and test the project locally as described in "Getting Started".
*   **Write Clear Code**: Adhere to existing coding styles and best practices.
*   **Add Tests**: All new features or bug fixes should be accompanied by comprehensive unit and integration tests.
*   **Update Documentation**: If your changes affect external APIs or critical logic, update the relevant NatSpec comments and documentation.
*   **Submit a Pull Request**: Provide a detailed description of your changes, the problem it solves, and any relevant test results.

## License
This project is licensed under the BUSL-1.1 and MIT licenses. See the individual contract files for specific SPDX license identifiers.

## Author Info
-   **Olujimi Adebakin**:  [Twitter](https://twitter.com/olujimi_the_dev)

---
