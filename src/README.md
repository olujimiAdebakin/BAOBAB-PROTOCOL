# BAOBAB Protocol

A high-performance, institutional-grade decentralized exchange for perpetual contracts, spot trading, and advanced financial products, architected for security and efficiency on the Ethereum Virtual Machine.

## Overview

BAOBAB is a sophisticated DeFi protocol engineered with a modular design to support a comprehensive suite of trading features. The architecture is built entirely in Solidity and emphasizes security, gas optimization, and capital efficiency. It features a hybrid liquidity model, an advanced risk management engine, and innovative financial primitives like tokenized asset baskets, making it a robust platform for both retail and institutional traders.

### System Architecture

The protocol is designed with a clear separation of concerns, ensuring modularity and upgradeability. User interactions flow through routers, which delegate logic to specialized engines that manage core protocol functions like trading, positions, and liquidations.

```
+----------------+      +----------------+      +-------------------+
|   User / EOA   |----->|     Routers    |----->|  Trading Engines  |
+----------------+      | (Core, Trading)|      | (Perp, Spot, CLOB)|
                        +----------------+      +-------------------+
                                                      |
                                                      v
                               +-------------------------------------+
                               |          Core Managers              |
                               | (Position, Order, Risk, Liquidation)|
                               +-------------------------------------+
                                                      |
                 +----------------+-------------------+-------------------+
                 |                |                   |                   |
                 v                v                   v                   v
        +----------------+ +----------------+ +-----------------+ +-----------------+
        | Liquidity Vault| | Insurance Vault| | Treasury Vault  | |    Oracles      |
        +----------------+ +----------------+ +-----------------+ | (Chainlink, Pyth) |
                                                                 +-----------------+
```

## Features

-   **Perpetual Trading Engine**: Core module for managing leveraged long and short positions with advanced funding rate calculations.
-   **Advanced Order Types**: Native support for Market, Limit, Time-Weighted Average Price (TWAP), and Scale orders, represented as ERC-721 NFTs.
-   **Hybrid Liquidity Model**: Integrates a Central Limit Order Book (CLOB) with an AMM-style liquidity vault for deep liquidity and efficient price discovery.
-   **Cross-Margin System**: Allows traders to use their entire portfolio balance as collateral, improving capital efficiency and reducing liquidation risk.
-   **Auto-Deleveraging (ADL) Engine**: A robust, last-resort risk management mechanism that protects the insurance fund by deleveraging profitable traders during extreme market volatility.
-   **Tokenized Baskets**: Create and manage "ETFs" of on-chain assets (`AssetBasket`) or complex trading strategies (`OrderBasket`), tokenized as ERC-20 shares.
-   **Comprehensive Security Suite**: A multi-layered security approach including `CircuitBreaker`, `EmergencyPauser`, `RateLimiter`, and re-entrancy guards in all core contracts.
-   **Modular & Gas-Optimized Libraries**: A rich set of in-house libraries for fixed-point math, percentage calculations, statistical analysis, and gas-efficient array/sorting utilities.

## Technologies Used

| Technology         | Description                                                                  |
| ------------------ | ---------------------------------------------------------------------------- |
| **Solidity**       | Smart contract language for the core protocol logic.                         |
| **Ethereum**       | The target blockchain for deployment and execution.                          |
| **ERC-20**         | Token standard for governance, vault shares, and basket shares.              |
| **ERC-721**        | Token standard for representing unique orders (`OrderNFT`).                  |
| **Hardhat/Foundry**| Recommended development environment for compiling, testing, and deploying.   |
| **OpenZeppelin**   | Used as a reference for secure contract patterns like re-entrancy guards.    |
| **BUSL-1.1**       | Business Source License used for core modules to protect intellectual property.|

## Getting Started

Follow these instructions to set up the project locally for development and testing.

### Prerequisites

-   [Node.js](https://nodejs.org/en/) (v18 or later)
-   [Git](https://git-scm.com/)

### Installation

1.  **Clone the Repository**:
    Open your terminal and run the following command to clone the project:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```

2.  **Navigate to Project Directory**:
    ```bash
    cd BAOBAB-PROTOCOL
    ```

3.  **Install Dependencies**:
    This project uses `npm` to manage dependencies.
    ```bash
    npm install
    ```

4.  **Set Up Environment Variables**:
    Create a `.env` file in the root of the project by copying the example file:
    ```bash
    cp .env.example .env
    ```
    Open the `.env` file and fill in the required variables, such as your private key and RPC URLs for deployment.

### Usage

The project is structured to be used with a standard Ethereum development framework like Hardhat.

1.  **Compile the Smart Contracts**:
    Compile all the Solidity files to ensure there are no syntax errors and to generate artifacts.
    ```bash
    npx hardhat compile
    ```

2.  **Run Tests**:
    The protocol includes a comprehensive test suite to verify the functionality of each module.
    ```bash
    npx hardhat test
    ```

3.  **Deploy the Protocol**:
    Deploy the contracts to a local network or a testnet. Make sure your `.env` file is configured correctly for the target network.
    ```bash
    npx hardhat run scripts/deploy.js --network <your-network-name>
    ```
    *(Note: The `deploy.js` script is a placeholder and should be created based on deployment needs.)*

## Contributing

Contributions are welcome! If you'd like to contribute, please follow these guidelines:

-   📜 **Fork the Repository**: Create your own copy of the project to work on.
-   🌿 **Create a New Branch**: Make a new branch for your feature or bug fix (`git checkout -b feature/your-feature-name`).
-   ✍️ **Make Your Changes**: Implement your changes and ensure all code is well-documented.
-   ✅ **Run Tests**: Ensure that all existing and new tests pass successfully.
-   🚀 **Submit a Pull Request**: Push your changes to your fork and open a pull request with a clear description of your work.

## License

The core contracts of this project are licensed under the **Business Source License 1.1 (BUSL-1.1)**, while some libraries and interfaces may use the MIT License. Please check the SPDX license identifier at the top of each file for specific details.

## Author

**Olujimi Adebakin**

-   **LinkedIn**: [Connect on LinkedIn](https://www.linkedin.com/in/olujimi-adebakin-b3992323a/)
-   **Twitter**: [@your-twitter-username](https://twitter.com/your-twitter-username)

---

![Solidity](https://img.shields.io/badge/Solidity-%23363636.svg?style=for-the-badge&logo=solidity&logoColor=white)
![Ethereum](https://img.shields.io/badge/Ethereum-3C3C3D?style=for-the-badge&logo=ethereum&logoColor=white)
![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-blue.svg?style=for-the-badge)

[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)