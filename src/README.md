# BAOBAB Protocol: A High-Performance Perpetual DEX 📈

BAOBAB is a sophisticated, high-performance decentralized perpetuals exchange built with Solidity. It features a robust, modular architecture designed for security, efficiency, and scalability, incorporating advanced mechanisms like an Auto-Deleveraging (ADL) engine, tokenized asset baskets, and comprehensive risk management systems.

## ✨ Features

-   **Advanced Trading Engine**: Supports both perpetual and spot markets with a hybrid order book and vault-based execution model.
-   **Granular Access Control**: A hierarchical, role-based access system (`AccessManager`, `RoleRegistry`) secures all protocol functions.
-   **Comprehensive Security Suite**: Includes a `CircuitBreaker` for market volatility, an `EmergencyPauser` for system-wide halts, and a `RateLimiter` to prevent spam and DoS attacks.
-   **Auto-Deleveraging (ADL)**: A sophisticated ADL engine protects the insurance fund during extreme market conditions by deleveraging profitable traders, a mechanism used by top-tier centralized exchanges.
-   **Tokenized Baskets**: A flexible system (`BasketEngine`, `BasketFactory`) for creating and managing tokenized asset baskets and strategy funds, similar to on-chain ETFs.
-   **Robust Position Management**: Manages complex perpetual positions, cross-margin, PnL calculations, and liquidations with high precision.
-   **Custom Math Libraries**: Gas-optimized libraries for `FixedPointMath`, `PercentageMath`, and `Statistics` ensure high-precision calculations essential for financial applications.

## 🛠️ Technologies Used

| Technology       | Description                                                                 |
| ---------------- | --------------------------------------------------------------------------- |
| **Solidity**     | The core language for smart contract development on the Ethereum blockchain. |
| **Hardhat**      | A professional development environment for building, testing, and deploying smart contracts. |
| **OpenZeppelin** | Utilized for standard, secure, and community-vetted smart contract interfaces like IERC20. |
| **Chainlink/Pyth** | Oracle adapters designed to integrate reliable, real-world price feeds for market valuation and settlement. |

## 🚀 Getting Started

To get a local copy up and running, follow these simple steps.

### Prerequisites

You will need `Node.js`, `npm`, and `Git` installed on your machine.

### Installation

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```

2.  **Navigate to the Project Directory**:
    ```bash
    cd BAOBAB-PROTOCOL
    ```

3.  **Install Dependencies**:
    ```bash
    npm install
    ```

4.  **Set Up Environment Variables**:
    Create a `.env` file in the root of the project and add the necessary environment variables.
    ```env
    PRIVATE_KEY="YOUR_ETHEREUM_PRIVATE_KEY"
    INFURA_API_KEY="YOUR_INFURA_API_KEY"
    ETHERSCAN_API_KEY="YOUR_ETHERSCAN_API_KEY"
    ```

### Usage

The protocol is designed to be deployed and tested in a development environment like Hardhat.

-   **Compile the Contracts**:
    Compile the smart contracts to check for errors and generate artifacts.
    ```bash
    npx hardhat compile
    ```

-   **Run Tests**:
    Execute the test suite to ensure all components are functioning correctly.
    ```bash
    npx hardhat test
    ```

-   **Deploy to a Local Network**:
    Run a local Hardhat node to simulate a blockchain environment.
    ```bash
    npx hardhat node
    ```
    In a separate terminal, deploy the contracts to the local node.
    ```bash
    npx hardhat run scripts/deploy.js --network localhost
    ```

## 🏛️ Architectural Overview

The BAOBAB Protocol is structured into several core modules, each responsible for a specific domain of functionality:

-   📁 **`access`**: Manages permissions and ownership. The `AccessManager` contract is the central point for a sophisticated role-based access control system defined in `RoleRegistry`.
-   📁 **`core`**: Contains the primary logic for trading operations.
    -   **`trading/engines`**: Includes the `AutoDeleverageEngine`, `PerpEngine`, and `SpotEngine` which handle the core mechanics of different trading products.
    -   **`markets`**: Manages market creation, registration, and risk parameters.
    -   **`oracles`**: Provides adapters for various price feed providers like Chainlink and Pyth.
-   📁 **`security`**: A suite of contracts designed to protect the protocol. `CircuitBreaker` halts trading during extreme volatility, `EmergencyPauser` allows for manual intervention, and `RateLimiter` prevents abuse.
-   📁 **`baskets`**: Implements the logic for creating and managing tokenized asset baskets, including rebalancing and pricing.
-   📁 **`vaults`**: Manages the protocol's funds, including the `LiquidityVault`, `InsuranceVault`, and `TreasuryVault`.
-   📁 **`libraries`**: A collection of highly optimized utility libraries for math, array manipulation, and time-based calculations, forming the foundation of the protocol's efficiency and precision.

## 🤝 Contributing

Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1.  **Fork the Project**
2.  **Create your Feature Branch** (`git checkout -b feature/AmazingFeature`)
3.  **Commit your Changes** (`git commit -m 'Add some AmazingFeature'`)
4.  **Push to the Branch** (`git push origin feature/AmazingFeature`)
5.  **Open a Pull Request**

## 📄 License

This project is licensed under the **Business Source License 1.1 (BUSL-1.1)**. See the `SPDX-License-Identifier` in the source files for more information.

## ✍️ Author

**Olujimi Adebakin**

-   **LinkedIn**: [Your LinkedIn Profile](https://www.linkedin.com/in/your-username/)
-   **Twitter**: [@YourTwitterHandle](https://twitter.com/your-username)

---

<p align="center">
  <img src="https://img.shields.io/badge/Solidity-^0.8.24-blue?style=for-the-badge&logo=solidity" alt="Solidity Badge">
  <img src="https://img.shields.io/badge/Hardhat-Framework-yellow?style=for-the-badge&logo=hardhat" alt="Hardhat Badge">
  <img src="https://img.shields.io/badge/License-BUSL--1.1-green?style=for-the-badge" alt="License Badge">
</p>

[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)