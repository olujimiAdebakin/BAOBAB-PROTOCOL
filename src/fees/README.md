# **BAOBAB Protocol: Decentralized Fee & Incentive Management** 🌳

## Overview
This repository contains the core Solidity smart contracts responsible for managing the BAOBAB Protocol's entire revenue lifecycle. It encompasses dynamic fee calculation, multi-destination fee distribution, and a comprehensive incentive system including trading rewards, referral programs, and liquidity mining. Built with a focus on modularity, security, and gas efficiency, these contracts underpin the economic sustainability and growth of the perpetual decentralized exchange.

## Features
*   **Dynamic Fee Calculation**: Implement real-time, tiered trading fees, maker rebates, and position fees with adjustable volatility multipliers and emergency caps.
*   **Robust Fee Distribution**: Automate the transparent allocation of collected fees to liquidity providers, insurance funds, the protocol treasury, stakers, and a burn address.
*   **Tiered Incentive System**: Reward users based on trading volume and staked BAOBAB tokens, offering discounts and amplified rewards across multiple tiers.
*   **Referral Program**: Enable a transparent, on-chain referral system to incentivize platform growth with configurable referrer shares and referee bonuses.
*   **Comprehensive Revenue Tracking**: Detailed analytics and daily snapshots of all revenue streams, trading volumes, and market-specific performance.
*   **Emergency Controls**: Integrate pausing mechanisms and emergency withdrawal functions for enhanced protocol security and risk management.
*   **Role-Based Access Control**: Secure critical functions with OpenZeppelin's `AccessControl` for granular permission management.

## Getting Started
To get these smart contracts running locally for development, testing, or deployment, follow these steps. This project assumes a standard Solidity development environment, such as [Foundry](https://getfoundry.sh/) or [Hardhat](https://hardhat.org/).

### Installation
1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    cd BAOBAB-PROTOCOL/src/fees
    ```
    _Note: The provided code snippets are from the `src/fees` directory. For a full project setup, you might need to navigate to the root of the cloned repository._

2.  **Install Dependencies**:
    If using Foundry (recommended for Solidity development):
    ```bash
    forge install
    ```
    If using Hardhat (and assuming a `package.json` exists in the root):
    ```bash
    npm install
    # or
    yarn install
    ```

3.  **Build the Contracts**:
    With Foundry:
    ```bash
    forge build
    ```
    With Hardhat:
    ```bash
    npx hardhat compile
    ```

4.  **Run Tests (Optional but Recommended)**:
    With Foundry:
    ```bash
    forge test
    ```
    With Hardhat:
    ```bash
    npx hardhat test
    ```

### Environment Variables
For deployment or interacting with the contracts on a testnet/mainnet, you will need to set up environment variables. Create a `.env` file in your project root (not committed to Git) with the following:

*   `RPC_URL`: Your blockchain node RPC URL (e.g., Alchemy, Infura).
    ```
    RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY"
    ```
*   `PRIVATE_KEY`: Private key of the deployer account (should start with `0x`).
    ```
    PRIVATE_KEY="0x..."
    ```
*   `ETHERSCAN_API_KEY`: (Optional) API key for Etherscan-like block explorers for contract verification.
    ```
    ETHERSCAN_API_KEY="YOUR_ETHERSCAN_API_KEY"
    ```

## Usage
Interacting with the BAOBAB Protocol's fee and incentive contracts involves calling their public and external functions. Below are examples demonstrating common interactions.

### Deploying the Contracts

To deploy the `FeeCalculator` contract:
```solidity
// Assuming _baobabToken and admin addresses are already defined
// For example, in a deployment script:
address baobabTokenAddress = 0x...; // Address of BAOBAB ERC20 token
address adminAddress = 0x...;       // Administrator wallet address

FeeCalculator feeCalculator = new FeeCalculator(baobabTokenAddress, adminAddress);
```

### FeeCalculator Examples
#### `calculateTradingFeeTaker`
Calculates the taker trading fee based on asset, user, and notional value.
**Input**:
```solidity
address asset = 0x...; // Address of the asset being traded (e.g., USDC)
address user = 0x...;  // Address of the user (taker)
uint256 notionalUsd = 100_000e6; // $100,000 USD notional value (6 decimals)
```
**Call**:
```solidity
uint256 takerFeeBps = feeCalculator.calculateTradingFeeTaker(asset, user, notionalUsd);
// takerFeeBps will be the fee in basis points (e.g., 8 for 0.08%)
```

#### `setAssetFeeConfig`
Allows an admin to set custom fee configurations for a specific asset.
**Input**:
```solidity
address asset = 0x...; // Address of the asset to configure
uint256 takerBps = 10;   // 0.10% taker fee
int256 makerBps = -5;   // 0.05% maker rebate (negative value)
```
**Call**:
```solidity
feeCalculator.setAssetFeeConfig(asset, takerBps, makerBps); // Requires FEE_MANAGER_ROLE
```

### FeeDistributor Examples
#### `distributeFees`
Distributes a total collected fee amount to various protocol recipients.
**Input**:
```solidity
uint256 amount = 1000e6; // Total fee amount to distribute, in settlement token decimals (e.g., $1000 USDC)
```
**Call**:
```solidity
feeDistributor.distributeFees(amount); // Requires `onlyAuthorizedDistributor` role
```

#### `claimMakerRebates`
Allows a user to claim their accumulated maker rebates.
**Input**:
```solidity
// None, `msg.sender` is implicitly the trader
```
**Call**:
```solidity
feeDistributor.claimMakerRebates(); // Called by the trader
```

### IncentiveManager Examples
#### `recordTrade`
Records a user's trade volume and calculates associated trading rewards.
**Input**:
```solidity
address user = 0x...;      // Trader's address
uint256 volumeTraded = 5000e18; // $5000 USD volume (18 decimals)
```
**Call**:
```solidity
incentiveManager.recordTrade(user, volumeTraded); // Requires `onlyPositionManager` role
```

#### `claimRewards`
Allows a user to claim their pending BAOBAB rewards.
**Input**:
```solidity
// None, `msg.sender` is implicitly the user
```
**Call**:
```solidity
incentiveManager.claimRewards(); // Called by the user
```

### RevenueManager Examples
#### `recordTradingFee`
Records a trading fee generated on a specific market.
**Input**:
```solidity
uint256 amount = 50e6;        // Fee amount (e.g., $50 USDC)
bytes32 marketId = keccak256("ETH-USD"); // Identifier for the market
```
**Call**:
```solidity
revenueManager.recordTradingFee(amount, marketId); // Requires `onlyAuthorized` role (e.g., FeeDistributor)
```

#### `getLifetimeRevenue`
Retrieves the cumulative revenue across all sources since inception.
**Input**:
```solidity
// None
```
**Call**:
```solidity
(
    uint256 tradingFees,
    uint256 liquidationFees,
    uint256 executionFees,
    uint256 vaultDepositFees,
    uint256 vaultWithdrawFees,
    uint256 vaultPerformanceFees,
    uint256 spreadRevenue,
    uint256 otherRevenue
) = revenueManager.getLifetimeRevenue();
```

## Technologies Used
| Category           | Technology        | Description                                     | Link                                                            |
| :----------------- | :---------------- | :---------------------------------------------- | :-------------------------------------------------------------- |
| **Blockchain**     | Solidity          | Smart contract programming language             | [Solidity](https://soliditylang.org/)                           |
| **Frameworks**     | OpenZeppelin      | Secure smart contract libraries for standard roles and tokens | [OpenZeppelin](https://openzeppelin.com/contracts/)             |
| **Development**    | Foundry / Hardhat | EVM development toolkit (assumed)               | [Foundry](https://getfoundry.sh/) / [Hardhat](https://hardhat.org/) |
| **Math Libraries** | BaobabMath        | Custom safe arithmetic and utility functions    | (Internal Library)                                              |

## Contributing
We welcome contributions to enhance the BAOBAB Protocol! If you're interested in improving our fee and incentive mechanisms, please follow these guidelines:

*   🌟 **Fork the Repository**: Start by forking this repository to your GitHub account.
*   🌿 **Create a New Branch**: Create a descriptive branch for your feature or bug fix (e.g., `feature/dynamic-maker-rebates`, `fix/gas-optimization`).
*   💻 **Implement Your Changes**: Write clean, well-tested code following existing patterns. Ensure all tests pass and add new tests for your changes.
*   📝 **Update Documentation**: If your changes impact functionality, update any relevant comments or documentation within the code.
*   🚀 **Submit a Pull Request**: Open a pull request to the `main` branch, describing your changes in detail.

## License
This project is licensed under the **BUSL-1.1 (Business Source License 1.1)**.

## Author Info
*   **LinkedIn**: [Your LinkedIn](https://www.linkedin.com/in/YOUR_USERNAME)
*   **Twitter**: [Your Twitter](https://twitter.com/YOUR_USERNAME)
*   **Website**: [Your Personal Website](https://www.yourwebsite.com)

---
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-lightgrey?logo=solidity)](https://soliditylang.org/)
[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)](https://mariadb.com/bsl11/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-Contracts-purple?logo=openzeppelin)](https://openzeppelin.com/contracts/)
[![Status: Production-Ready](https://img.shields.io/badge/Status-Production--Ready-success)](https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL)
[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)