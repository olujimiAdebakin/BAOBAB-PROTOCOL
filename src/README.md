# BAOBAB Protocol: Decentralized Perpetual Exchange 🌳

The BAOBAB Protocol is an ambitious and comprehensive decentralized perpetual exchange designed for robust, secure, and efficient derivatives trading. Engineered with a focus on African markets, it offers a sophisticated suite of features including role-based access control, advanced risk management with circuit breakers and auto-deleverage mechanisms, and highly precise fixed-point arithmetic for financial calculations. This protocol aims to provide a resilient and scalable infrastructure for on-chain perpetuals, spot trading, event derivatives, and tokenized baskets.

## Features

- **Robust Access Control**: Hierarchical role-based access control system (`AccessManager`) ensuring secure management of protocol operations.
- **Protocol Governance**: Mechanisms for protocol ownership, treasury management, and emergency controls (`ProtocolOwner`).
- **Advanced Risk Management**: Integrated `CircuitBreaker` for automatic trading halts during extreme market volatility and an `EmergencyPauser` for granular module control.
- **Multi-Layer Rate Limiting**: Production-grade `RateLimiter` protecting against spam, DoS, and economic attacks with tiered limits and gas consumption tracking.
- **Perpetual Position Management**: Core `PositionManager` handles opening, modifying, closing, and liquidating perpetual futures positions with dynamic margin and PnL tracking.
- **Automated Deleveraging (ADL)**: `AutoDeleverageEngine` automatically deleverages profitable opposing positions to protect the insurance fund during extreme market events.
- **Accurate Funding Rates**: `FundingEngine` calculates and applies periodic funding rates based on Open Interest imbalance.
- **High-Precision Mathematics**: `FixedPointMath` library utilizing Q64.96 format for accurate and gas-efficient financial calculations.
- **Percentage Calculations**: `PercentageMath` library for precise basis point operations in fees, interest, and risk parameters.
- **Statistical Analysis**: `Statistics` library for advanced risk management and analytics, including mean, standard deviation, and Value at Risk (VaR).
- **Gas-Optimized Utilities**: Libraries like `ArrayUtils`, `AddressUtils`, and `TimeUtils` provide efficient common operations.
- **Modular Architecture**: Clearly separated concerns across contracts like `BasketEngine`, `FeeCalculator`, `OracleRegistry`, and various routers.
- **Tokenized Assets**: Support for ERC-20 `BAOBABToken`, `BasketShareToken`, `VaultShareToken`, and ERC-721 `BasketNFT`, `OrderNFT` for flexible product offerings.

## Getting Started

### Installation

To get a local copy of the BAOBAB Protocol up and running, follow these steps.

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    cd BAOBAB-PROTOCOL
    ```

2.  **Install Foundry**:
    This project is built with Solidity and is best developed and tested using Foundry. If you don't have Foundry installed, run:
    ```bash
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
    ```

3.  **Install Dependencies**:
    Navigate to the project root and install the necessary Solidity dependencies, typically OpenZeppelin contracts.
    ```bash
    forge install
    ```

4.  **Build Contracts**:
    Compile the smart contracts using `forge build`:
    ```bash
    forge build
    ```

### Environment Variables

The project will likely require environment variables for deployment and interaction (e.g., RPC URLs, private keys). While specific `.env` examples are not provided in the source code, you would typically need to set up a `.env` file similar to this:

```ini
# Ethereum Virtual Machine (EVM) RPC URL
RPC_URL=https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID
PRIVATE_KEY=YOUR_DEPLOYER_PRIVATE_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY # For contract verification
```

## Usage

This project primarily consists of smart contracts designed to be deployed onto an EVM-compatible blockchain. Interaction involves calling public functions of these deployed contracts.

### Deployment (Conceptual)

Assuming you have your environment variables set and contracts compiled, you would typically deploy using `forge script` or a similar tool:

```bash
# Example deployment of AccessManager
forge script script/AccessManagerDeploy.s.sol:AccessManagerDeploy --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

### Interacting with Contracts

After deployment, you can interact with the contracts using tools like `cast` (from Foundry), web3.js/ethers.js in a dApp, or through a block explorer.

#### Example: Granting a Role via AccessManager

To grant a role (e.g., `ADMIN_ROLE`) to an address via the `AccessManager` contract, you would call the `grantRole` function.

```bash
# First, get the role's keccak256 hash (e.g., from RoleRegistry)
ADMIN_ROLE_HASH="0x..." # Value for keccak256("ADMIN_ROLE")

# Call the grantRole function on the deployed AccessManager
cast send <ACCESS_MANAGER_ADDRESS> "grantRole(bytes32,address)" "$ADMIN_ROLE_HASH" <TARGET_ADDRESS> --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

#### Example: Opening a Position via PositionManager

To open a new perpetual position, you would interact with the `PositionManager` via your `TradingEngine` (which acts as a router).

```bash
# This is a conceptual example, actual interaction would be through the TradingRouter/TradingEngine
# assuming they are deployed and authorized.
cast send <TRADING_ENGINE_ADDRESS> "openPosition(address,bytes32,uint8,uint256,uint256,uint256,uint16)" \
"0x<TRADER_ADDRESS>" \
"0x<MARKET_ID>" \
"0" \
"1000000000000000000" \
"100000000000000000000" \
"50000000000000000000000" \
"10" \
--rpc-url $RPC_URL --private-key $PRIVATE_KEY
```
*Note: The `openPosition` function specifically mentions `onlyTradingEngine` modifier, meaning a direct call from an arbitrary `msg.sender` would revert. The example above is illustrative of the *parameters* passed to a trading mechanism.*

## Technologies Used

| Technology         | Description                                                          |
| :----------------- | :------------------------------------------------------------------- |
| **Solidity**       | Primary language for smart contract development.                     |
| **Foundry**        | Fast, customizable, and gas-efficient toolkit for testing & deployment. |
| **OpenZeppelin**   | Libraries for secure smart contract development.                     |
| **EVM Chains**     | Designed for deployment on any Ethereum Virtual Machine compatible blockchain. |

## Contributing

We welcome contributions to the BAOBAB Protocol! To contribute, please follow these guidelines:

✨ **Fork the Repository**: Start by forking the project to your GitHub account.

🌿 **Create a New Branch**:
```bash
git checkout -b feature/your-feature-name
```
Give your branch a descriptive name (e.g., `feature/add-rate-limiter-config` or `bugfix/resolve-adl-queue-bug`).

🛠️ **Make Your Changes**: Implement your features or bug fixes. Ensure your code adheres to the existing style and quality.

🧪 **Write & Run Tests**: All new features and bug fixes must be accompanied by comprehensive unit tests.
```bash
forge test
```
Make sure all existing tests pass as well.

📚 **Update Documentation**: If your changes introduce new functionality or alter existing behavior, please update the relevant documentation (comments in code, README, etc.).

⬆️ **Commit Your Changes**:
```bash
git commit -m "feat: Add new rate limiter configuration for TWAP orders"
```
Use clear and concise commit messages.

🚀 **Push to Your Fork**:
```bash
git push origin feature/your-feature-name
```

📤 **Open a Pull Request**: Submit a pull request from your fork to the main repository. Provide a detailed description of your changes and why they are valuable.

We appreciate your efforts to improve the BAOBAB Protocol!

## License

This project is distributed under the BUSL-1.1 License (Business Source License 1.1), as indicated by the SPDX license identifiers in the source files.

## Author Info

**Olujimi Adebakin**
- LinkedIn: [Your LinkedIn Profile](https://www.linkedin.com/in/olujimiadebakin) (Placeholder)
- Twitter: [@olujimiadebakin](https://twitter.com/olujimiadebakin) (Placeholder)

---
[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)
[![Built with Solidity](https://img.shields.io/badge/Built%20with-Solidity-5B4B2F.svg)](https://soliditylang.org/)
[![Foundry Powered](https://img.shields.io/badge/Powered%20by-Foundry-critical)](https://getfoundry.sh/)
[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)](https://spdx.org/licenses/BUSL-1.1.html)
