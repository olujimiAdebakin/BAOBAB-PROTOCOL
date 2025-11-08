# BAOBAB Protocol: Core Smart Contracts

A robust and modular smart contract library for building decentralized perpetuals exchanges, tokenized asset baskets, and on-chain prediction markets. This repository contains the core data structures that power the BAOBAB Protocol, designed for high-performance and gas-efficient DeFi applications, with a focus on serving African markets.

## ✨ Features

-   **Modular Data Structures**: Clean, separated structs for Trading, Baskets, Events, and common utilities, enabling easy integration and extension.
-   **Advanced Trading Engine**: Foundational structs for perpetuals, including funding rates, liquidations, and cross-margin accounts.
-   **Tokenized Baskets**: Sophisticated logic for creating and managing on-chain funds (Asset Baskets) and automated strategy vaults (Order Baskets).
-   **Multiple Rebalancing Strategies**: Support for Manual, Scheduled, Threshold, and Dynamic rebalancing to suit various fund management styles, from passive indices to active alpha-seeking strategies.
-   **Prediction Markets**: Gas-optimized structures for creating and resolving event-based prediction markets.
-   **Advanced Order Types**: Designed to support complex order types like Time-Weighted Average Price (TWAP) and SCALE orders.

## 🛠️ Technologies Used

| Technology | Description |
| :--- | :--- |
| [**Solidity**](https://soliditylang.org/) | The primary language for writing the smart contracts. |
| [**Foundry**](https://github.com/foundry-rs/foundry) | A blazing fast, portable, and modular toolkit for Ethereum application development. |
| [**BUSL-1.1**](https://spdx.org/licenses/BUSL-1.1.html) | Business Source License, ensuring the code remains open-source while protecting it commercially. |

## 🚀 Getting Started

Follow these instructions to get a copy of the project up and running on your local machine for development and testing purposes.

### Prerequisites

-   [Foundry / Forge](https://book.getfoundry.sh/getting-started/installation) installed.
-   [Git](https://git-scm.com/)

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```

2.  **Navigate to the project directory:**
    ```bash
    cd BAOBAB-PROTOCOL
    ```

3.  **Install dependencies:**
    This project may use libraries like Solmate or OpenZeppelin. Forge will install them automatically on compile.
    ```bash
    forge install
    ```

## Usage

The primary use of this repository is as a library of core data structures. However, you can compile and test the contracts to ensure their integrity.

### Compile Contracts

Compile the smart contracts using Forge to check for any compilation errors and to generate ABIs.

```bash
forge build
```

### Run Tests

Run the test suite to ensure all parts of the library function as expected. (Note: Test files are not provided in this context, but this is the standard command).

```bash
forge test
```

## Project Structure

The core logic is organized within the `src/libraries/structs` directory, providing a clear and modular architecture.

-   `CommonStructs.sol`: Contains shared data structures for markets, positions, and orders used across the entire protocol.
-   `TradingStructs.sol`: Defines structures specific to the trading engine, including the order book, advanced orders (TWAP/SCALE), liquidations, and perpetuals funding.
-   `BasketStructs.sol`: Holds all data structures related to creating, managing, and rebalancing tokenized Asset and Order Baskets.
-   `EventStructs.sol`: Provides lean, gas-optimized structs for on-chain prediction markets.
-   `RebalancingGuide.sol`: A descriptive file outlining the various rebalancing strategies supported by the basket engine.

## 🤝 Contributing

Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1.  **Fork the Project**
2.  **Create your Feature Branch** (`git checkout -b feature/AmazingFeature`)
3.  **Commit your Changes** (`git commit -m 'Add some AmazingFeature'`)
4.  **Push to the Branch** (`git push origin feature/AmazingFeature`)
5.  **Open a Pull Request**

## 📄 License

This project is licensed under the Business Source License 1.1 (BUSL-1.1). The code will eventually become fully open-source as specified in the license file for each contract.

---

### Connect with the Author

Let's connect! Feel free to reach out for collaborations or just a friendly chat.

-   **LinkedIn**: [Your LinkedIn Profile](https://www.linkedin.com/in/your-username)
-   **Twitter**: [@your-twitter-handle](https://twitter.com/your-twitter-handle)

<br>

![Solidity](https://img.shields.io/badge/Solidity-%23363636.svg?style=for-the-badge&logo=solidity&logoColor=white)
![Ethereum](https://img.shields.io/badge/Ethereum-3C3C3D?style=for-the-badge&logo=ethereum&logoColor=white)
![License](https://img.shields.io/badge/License-BUSL--1.1-blue?style=for-the-badge)

[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)