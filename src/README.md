# BAOBAB Protocol Perpetual DEX 🚀

## Overview
The BAOBAB Protocol is a sophisticated decentralized perpetual exchange built on the Ethereum Virtual Machine (EVM), designed to facilitate secure and efficient trading of various assets with a strong emphasis on robust risk management. It incorporates a modular architecture with smart contracts for role-based access control, dynamic circuit breakers, emergency pausing capabilities, a unique auto-deleverage (ADL) engine, and a precise funding rate mechanism, ensuring operational stability and user asset protection in volatile market conditions.

## Features
*   🔐 **Role-Based Access Control**: Implements a hierarchical system to manage permissions across all protocol functions, ensuring secure operations and segregation of duties for roles like Owner, Admin, Guardian, Keeper, and Liquidator.
*   🛑 **Emergency Pausing System**: Provides granular and protocol-wide pausing mechanisms, allowing authorized entities to halt operations swiftly during critical situations, with multi-sig and timelock integration for enhanced security.
*   ⚡ **Dynamic Circuit Breakers**: Protects markets from extreme volatility and anomalous behavior by automatically triggering trading halts based on configurable thresholds for price deviation, volume spikes, and liquidation cascades.
*   🔄 **Auto-Deleverage (ADL) Engine**: A cutting-edge risk management system that strategically force-closes profitable opposing positions to cover liquidation shortfalls when the insurance fund is insufficient, thereby protecting protocol solvency.
*   📊 **Perpetual Position Management**: Offers comprehensive tools for managing the entire lifecycle of perpetual futures positions, including opening, modifying, and closing, with real-time updates on Unrealized PnL, margin ratios, and liquidation prices.
*   💰 **Automated Funding Rate Mechanism**: Calculates and applies periodic funding payments to align perpetual contract prices with underlying spot markets, dynamically adjusting based on Open Interest imbalances.
*   ⏱️ **On-chain Rate Limiting**: Safeguards the protocol against Denial-of-Service (DoS) attacks and spam by enforcing configurable rate limits on various user operations, including a whitelist for privileged accounts.
*   🩹 **Secure Token Rescue**: An emergency function accessible only by the protocol administrator, enabling the recovery of accidentally sent ERC-20 tokens or native ETH from contract addresses.
*   🧺 **Tokenized Baskets (Planned)**: Future expansion to support the creation and management of diversified tokenized asset and order baskets for advanced trading strategies and index products.
*   🏛️ **Decentralized Governance (Planned)**: Foundation for a community-driven governance model, including a native BAOBAB token and a proposal submission system to steer the protocol's evolution.

## Getting Started
To get the BAOBAB Protocol smart contracts running locally for development or testing, follow these instructions.

### Installation
*   🌐 **Clone the Repository**:
    Begin by cloning the project repository to your local machine.
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    cd BAOBAB-PROTOCOL/src
    ```
*   🛠️ **Install Foundry**:
    The project is developed using Foundry, a fast, portable, and modular toolkit for Ethereum application development. If you don't have Foundry installed, follow the official installation guide.
    ```bash
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
    ```
*   📦 **Install Dependencies**:
    The smart contracts utilize OpenZeppelin libraries. Install them using `forge install`.
    ```bash
    forge install OpenZeppelin/openzeppelin-contracts@v4.9.3 --no-commit
    ```
*   ⚙️ **Build Contracts**:
    Compile all smart contracts to ensure there are no compilation errors.
    ```bash
    forge build
    ```
*   🧪 **Run Tests (Optional but Recommended)**:
    Execute the test suite to verify the contracts' functionality and security.
    ```bash
    forge test
    ```

### Usage
Interacting with the BAOBAB Protocol involves deploying and calling functions on its various smart contracts. Below are examples demonstrating common interactions with core modules using `cast`, a command-line tool from Foundry.

#### Deployment and Initial Configuration
1.  **Deploy `AccessManager`**:
    Deploy the central `AccessManager` contract, providing the initial owner's address. This address will automatically be granted the `OWNER_ROLE`.
    ```bash
    # Replace <DEPLOYER_ADDRESS> with your Ethereum address
    forge create src/access/AccessManager.sol:AccessManager --constructor-args <DEPLOYER_ADDRESS> --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
    ```
    *Note down the deployed `AccessManager` address.*

2.  **Deploy Core Modules**:
    Deploy other critical contracts like `PositionManager`, `FundingEngine`, `CircuitBreaker`, `EmergencyPauser`, and `AutoDeleverageEngine`. Their constructors often require addresses of other core modules or an admin address.

    ```bash
    # Example: Deploy AutoDeleverageEngine (simplified constructor example)
    # Arguments: _admin, _liquidationEngine, _insuranceVault, _positionManager
    forge create src/core/trading/engines/AutoDeleverageEngine.sol:AutoDeleverageEngine \
      --constructor-args <ADMIN_ADDRESS> <LIQUIDATION_ENGINE_ADDRESS> <INSURANCE_VAULT_ADDRESS> <POSITION_MANAGER_ADDRESS> \
      --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
    ```
    *Replace `<..._ADDRESS>` placeholders with the actual deployed contract addresses.*

3.  **Link Contracts via Admin Functions**:
    After deployment, configure the inter-module addresses. For instance, set the `TradingEngine` and `LiquidationEngine` addresses in the `PositionManager` via admin-only functions.

    ```bash
    # Example: Set TradingEngine address in PositionManager
    cast send <POSITION_MANAGER_ADDRESS> "setTradingEngine(address)" <TRADING_ENGINE_ADDRESS> \
      --rpc-url <RPC_URL> --private-key <ADMIN_PRIVATE_KEY>
    ```
    Similarly, link other modules such as `FundingEngine`.

#### Access Control (AccessManager)
The `AccessManager` contract centralizes role assignments.
##### Granting a Role
**Request**:
```bash
cast send <ACCESS_MANAGER_ADDRESS> "grantRole(bytes32,address)" \
  $(cast keccak "KEEPER_ROLE()") <KEEPER_ACCOUNT_ADDRESS> \
  --rpc-url <RPC_URL> --private-key <OWNER_PRIVATE_KEY>
```
*   `ACCESS_MANAGER_ADDRESS`: Address of the deployed `AccessManager` contract.
*   `keccak("KEEPER_ROLE()")`: The `bytes32` representation of the `KEEPER_ROLE` from `RoleRegistry`.
*   `KEEPER_ACCOUNT_ADDRESS`: The address to grant the `KEEPER_ROLE` to.
*   `OWNER_PRIVATE_KEY`: Private key of an account holding the `OWNER_ROLE` (or the role's admin).
**Response**: Transaction hash on success.
**Errors**:
*   `AccessManager__UnauthorizedRoleAdmin`: Caller does not have permission to grant this role.
*   `AccessManager__AlreadyHasRole`: Account already possesses the role.
*   `AccessManager__InvalidAddress`: Provided account address is zero.

#### Position Management (PositionManager)
The `PositionManager` contract handles the core logic for perpetual positions.
##### Opening a New Position
*Note: This function is typically called by an authorized `TradingEngine` contract.*
**Request**:
```bash
cast send <POSITION_MANAGER_ADDRESS> "openPosition(address,bytes32,uint8,uint256,uint256,uint256,uint16)" \
  <TRADER_ADDRESS> <MARKET_ID_BYTES32> 0 <SIZE_18_DECIMALS> <COLLATERAL_18_DECIMALS> <ENTRY_PRICE_18_DECIMALS> <LEVERAGE_UINT16> \
  --rpc-url <RPC_URL> --private-key <TRADING_ENGINE_PRIVATE_KEY>
```
*   `POSITION_MANAGER_ADDRESS`: Address of the deployed `PositionManager` contract.
*   `TRADER_ADDRESS`: Address of the user opening the position.
*   `MARKET_ID_BYTES32`: Unique identifier for the market (e.g., `keccak256("BTC-USD")`).
*   `0`: Represents `CommonStructs.Side.LONG` (use `1` for `SHORT`).
*   `SIZE_18_DECIMALS`: Desired position size (e.g., `1 ether` for 1 unit).
*   `COLLATERAL_18_DECIMALS`: Amount of collateral (e.g., `100 ether` for $100).
*   `ENTRY_PRICE_18_DECIMALS`: Price at which the position is opened (e.g., `30000 ether` for $30,000).
*   `LEVERAGE_UINT16`: Leverage multiplier (e.g., `10` for 10x).
*   `TRADING_ENGINE_PRIVATE_KEY`: Private key of the authorized `TradingEngine` (or a temporarily set admin for testing).
**Response**: Transaction hash and the `positionId` (bytes32) emitted in the `PositionOpened` event.
**Errors**:
*   `PositionManager__OnlyTradingEngine`: Caller is not the authorized `TradingEngine`.
*   `PositionManager__InvalidSize`: Provided size is zero.
*   `PositionManager__InsufficientCollateral`: Provided collateral is zero.
*   `PositionManager__MarketNotConfigured`: The specified `marketId` is not active or configured.
*   `PositionManager__LeverageExceedsMax`: Requested leverage exceeds market maximum.
*   `PositionManager__InsufficientInitialMargin`: Collateral does not meet initial margin requirements.
*   `PositionManager__CircuitBroken`: The circuit breaker is active for this market or globally.

#### Emergency Pause (EmergencyPauser)
The `EmergencyPauser` can pause parts of the protocol.
##### Pausing a Specific Module
**Request**:
```bash
cast send <EMERGENCY_PAUSER_ADDRESS> "pauseModule(bytes32,string,bool)" \
  $(cast keccak "POSITION_MANAGER()") "Unexpected market behavior" true \
  --rpc-url <RPC_URL> --private-key <ADMIN_PRIVATE_KEY>
```
*   `EMERGENCY_PAUSER_ADDRESS`: Address of the deployed `EmergencyPauser` contract.
*   `keccak("POSITION_MANAGER()")`: The `bytes32` ID for the `PositionManager` module.
*   `"Unexpected market behavior"`: A string explaining the reason for the pause.
*   `true`: Boolean indicating if the module can be unpaused later (false would require an upgrade).
*   `ADMIN_PRIVATE_KEY`: Private key of an account holding `ADMIN` or `GUARDIAN` authority.
**Response**: Transaction hash on success.
**Errors**:
*   `EmergencyPauser__InsufficientAuthority`: Caller does not have the required authority level.

## Contributing
We welcome and appreciate contributions to the BAOBAB Protocol! Please follow these guidelines to help us maintain code quality and a smooth development process.

*   🐛 **Bug Reports**: If you encounter any bugs, please open a detailed issue on our GitHub repository. Include steps to reproduce the bug, the expected behavior, and your environment setup.
*   💡 **Feature Suggestions**: Have an idea for a new feature or an enhancement? Open a feature request issue to discuss your ideas with the community.
*   📝 **Code Contributions**:
    1.  **Fork** the repository and clone it to your local machine.
    2.  Create a new, descriptive branch for your changes: `git checkout -b feat/your-feature` or `git checkout -b fix/issue-description`.
    3.  Make your modifications, ensuring all existing and new tests pass: `forge test`.
    4.  Commit your changes with a clear and concise message following [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specifications (e.g., `feat: implement new risk parameter`, `fix: correct funding rate calculation`).
    5.  Push your changes to your forked repository.
    6.  Open a **Pull Request** to the `main` branch of the original repository. Provide a detailed explanation of your changes and why they are necessary.

## License
The BAOBAB Protocol is licensed under the BUSL-1.1 License. Please refer to the individual contract files for specific license identifiers.

## Author Info
Connect with the visionary team behind the BAOBAB Protocol:

*   X (Twitter): [@BAOBAB_Protocol_PLACEHOLDER](https://twitter.com/BAOBAB_PROTOCOL_PLACEHOLDER)
*   LinkedIn: [BAOBAB Protocol_PLACEHOLDER](https://linkedin.com/company/BAOBAB_PROTOCOL_PLACEHOLDER)
*   Email: [contact@baobabprotocol.xyz_PLACEHOLDER](mailto:contact@baobabprotocol.xyz_PLACEHOLDER)

---

## Badges
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-lightgrey)](https://docs.soliditylang.org/en/latest/)
[![Foundry](https://img.shields.io/badge/Developed%20with-Foundry-red)](https://getfoundry.sh/)
[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)](https://spdx.org/licenses/BUSL-1.1.html)
[![Status: Under Development](https://img.shields.io/badge/Status-Under%20Development-orange)](https://shields.io)

[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)