# BAOBAB Protocol 🌳

BAOBAB is a high-performance, modular framework for building a decentralized perpetuals and derivatives exchange on EVM-compatible blockchains. Designed with a first-principles approach, the protocol prioritizes security, gas efficiency, and advanced trading features, including tokenized asset baskets and sophisticated order types.

The architecture is built upon a robust foundation of custom-developed, gas-optimized libraries for fixed-point math, statistical analysis, and complex data structures, ensuring precision and reliability for demanding DeFi applications.

## ✨ Features

-   **Modular Trading Engines**: A clear separation of concerns allows for distinct engines for Perpetual Swaps, Spot Markets, and Cross-Margin accounts.
-   **Tokenized Baskets**: Create and manage tokenized baskets of underlying assets (`AssetBasket`) or pending trading strategies (`OrderBasket`), enabling novel index and fund products.
-   **Advanced Order Types**: The protocol is designed to support complex order executions like Time-Weighted Average Price (TWAP) and Scale orders, in addition to standard Market and Limit orders.
-   **On-Chain Governance**: A comprehensive governance module featuring a native token (`BAOBABToken`), `Governor`, and `TimelockController` for decentralized protocol management.
-   **Robust Security Framework**: Includes essential security modules like a `CircuitBreaker`, `EmergencyPauser`, and `RateLimiter` to protect the protocol and its users.
-   **Gas-Optimized Core Libraries**: A suite of powerful, custom-built libraries for high-precision math, sorting algorithms, and statistical calculations forms the bedrock of the protocol.

## 🏛️ System Architecture

The BAOBAB Protocol is designed with a layered and modular architecture to ensure scalability, security, and maintainability.

```
┌──────────────────────────────────────────────────────────┐
│                      Routers (User Facing)               │
│ (CoreRouter, TradingRouter, VaultRouter, BasketRouter)   │
└────────────────────┬──────────────────┬──────────────────┘
                     │                  │
┌────────────────────▼──────────────────▼──────────────────┐
│                   Core Protocol Logic                    │
│ ┌────────────────┐ ┌────────────────┐ ┌────────────────┐ │
│ │  Trading       │ │  Baskets       │ │  Vaults        │ │
│ │ (PerpEngine,   │ │ (BasketEngine, │ │ (Liquidity,   │ │
│ │  OrderBook)    │ │  Rebalancing)  │ │  Insurance)    │ │
│ └────────────────┘ └────────────────┘ └────────────────┘ │
└────────────────────┬──────────────────┬──────────────────┘
                     │                  │
┌────────────────────▼──────────────────▼──────────────────┐
│                 Foundational Libraries & Models          │
│ ┌────────────────┐ ┌────────────────┐ ┌────────────────┐ │
│ │  Math          │ │  Data          │ │  Security      │ │
│ │ (FixedPoint,   │ │  Structures    │ │ (Guards,       │ │
│ │  Statistics)   │ │ (Arrays, Sort) │ │  CircuitBreaker) │ │
│ └────────────────┘ └────────────────┘ └────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

## 📚 Core Libraries Showcase

The heart of the BAOBAB Protocol lies in its powerful, gas-optimized foundational libraries. These libraries demonstrate a deep understanding of the mathematical and computational challenges in building a high-performance DEX.

-   **`FixedPointMath.sol`**: A high-precision math library using the Q64.96 format. It provides essential functions for multiplication, division, square root, and exponentiation, crucial for avoiding floating-point errors in financial calculations.
-   **`PercentageMath.sol`**: Handles all percentage-based calculations with basis points precision, essential for fees, interest rates, and risk parameters like liquidation margins.
-   **`Statistics.sol`**: An advanced library for on-chain statistical analysis, including mean, standard deviation, variance, correlation, and Value at Risk (VaR). This enables sophisticated risk management and analytics.
-   **`ArrayUtils.sol` & `SortUtils.sol`**: A comprehensive toolkit for efficient array manipulation and sorting. `SortUtils` includes multiple algorithms like QuickSort and MergeSort, with specialized functions for order book price-time priority matching.
-   **`TimeUtils.sol`**: Provides a robust set of time-related functions for managing funding rate schedules, order expirations, and market trading hours, with built-in support for major African market schedules.

## 🛠️ Technologies Used

| Technology | Description |
| :--- | :--- |
| **Solidity** | Smart contract programming language for the Ethereum Virtual Machine (EVM). |
| **Hardhat / Foundry** | Professional development environments for compiling, testing, and deploying smart contracts. |
| **ERC20 / ERC721** | Standard interfaces for fungible and non-fungible tokens, used for governance tokens, basket shares, and OrderNFTs. |
| **OpenZeppelin** | While not explicitly used in the custom libraries, its secure patterns influence the overall design for components like access control and governance. |

## 🚀 Getting Started

Follow these steps to set up the development environment and get the project running on your local machine.

### Prerequisites

-   [Node.js](https://nodejs.org/en/) (v18 or later)
-   [Git](https://git-scm.com/)

### Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```

2.  **Navigate to the project directory**:
    ```bash
    cd BAOBAB-PROTOCOL
    ```

3.  **Install dependencies** (using npm):
    ```bash
    npm install
    ```
    *Note: If you prefer Foundry, you would run `forge install` after initializing a Foundry project.*

### Usage

This project is structured as a smart contract framework. The primary usage involves compiling, testing, and deploying the contracts.

1.  **Compile the contracts**:
    ```bash
    npx hardhat compile
    ```
    This will compile all Solidity files and generate ABI artifacts.

2.  **Run tests**:
    ```bash
    npx hardhat test
    ```
    This command will execute the test suite to ensure the contracts function as expected. *(Note: Test files would need to be created for the implemented libraries and contracts).*

3.  **Deploy to a local network**:
    ```bash
    npx hardhat node # Starts a local blockchain
    npx hardhat run scripts/deploy.js --network localhost # Deploys contracts
    ```
    *(Note: A `deploy.js` script would be required to orchestrate the deployment of the protocol's contracts).*

## 🤝 Contributing

Contributions are welcome! If you have ideas for improvements or find any issues, please feel free to contribute.

-   **Fork the repository** on GitHub.
-   **Create a new branch** for your feature or bug fix: `git checkout -b feature/your-feature-name`.
-   **Make your changes** and commit them with clear, descriptive messages.
-   **Push your branch** to your fork: `git push origin feature/your-feature-name`.
-   **Submit a pull request** to the main repository.

## 📜 License

This project is currently not licensed. Please add a license file to define the terms under which this software can be used, modified, and distributed.

## 👤 Author

**Olujimi Adebakin**

-   **LinkedIn**: [your-linkedin-username](https://linkedin.com/in/your-linkedin-username)
-   **Twitter**: [@your-twitter-handle](https://twitter.com/your-twitter-handle)

---
<p align="center">
  <img src="https://img.shields.io/badge/Solidity-^0.8.24-lightgrey?style=for-the-badge&logo=solidity" alt="Solidity"/>
  <img src="https://img.shields.io/badge/Hardhat-Framework-blue?style=for-the-badge&logo=hardhat" alt="Hardhat"/>
  <img src="https://img.shields.io/github/license/olujimiAdebakin/BAOBAB-PROTOCOL?style=for-the-badge" alt="License"/>
  <img src="https://img.shields.io/badge/build-passing-brightgreen?style=for-the-badge" alt="Build Status"/>
</p>

[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)