# BAOBAB Protocol 🌳

![Solidity](https://img.shields.io/badge/Solidity-%23363636.svg?style=for-the-badge&logo=solidity&logoColor=white)
![Hardhat](https://img.shields.io/badge/Hardhat-222222?style=for-the-badge&logo=hardhat&logoColor=white)
![License](https://img.shields.io/badge/License-BUSL--1.1-blue.svg?style=for-the-badge)

A comprehensive and gas-optimized suite of Solidity libraries for building high-performance decentralized finance (DeFi) applications. This repository provides the foundational building blocks for creating perpetual DEXs, tokenized asset baskets, prediction markets, and more, with a unique focus on African market infrastructure.

## ✨ Features

-   **High-Precision Math Libraries**:
    -   `FixedPointMath`: Implements Q64.96 fixed-point arithmetic for unparalleled precision in financial calculations.
    -   `PercentageMath`: Basis-point accurate percentage and financial math for fees, interest rates, and risk parameters.
    -   `Statistics`: On-chain statistical analysis including mean, standard deviation, correlation, and Value at Risk (VaR).

-   **Gas-Optimized Utilities**:
    -   `ArrayUtils` & `SortUtils`: A rich set of array manipulation and sorting algorithms, optimized for order book and data management.
    -   `TimeUtils`: Advanced time-based logic, including funding rate schedules and specialized functions for African market trading hours (NSE, JSE).
    -   `AddressUtils`: Secure and gas-efficient address validation and interaction helpers.

-   **Modular Trading & Asset Structs**:
    -   `TradingStructs`: Comprehensive data structures for perpetuals, order books, liquidations, and advanced order types (TWAP, SCALE).
    -   `BasketStructs`: A complete framework for creating and managing tokenized asset baskets with multiple rebalancing strategies.
    -   `EventStructs`: Clean and efficient data structures for building scalable prediction markets.

## 🛠️ Technologies Used

| Technology   | Description                                                                  |
| ------------ | ---------------------------------------------------------------------------- |
| **Solidity** | Smart contract programming language for the Ethereum Virtual Machine (EVM).    |
| **Hardhat**  | Recommended development environment for compiling, deploying, and testing. |
| **Foundry**  | Alternative high-performance development toolkit for testing and deployment. |
| **Ethers.js**  | A complete and compact library for interacting with the Ethereum Blockchain. |

## 🚀 Getting Started

To integrate these libraries into your project, follow the steps below. This guide assumes you are using a Hardhat or Foundry development environment.

### Installation

1.  **Clone the Repository**:
    First, clone the BAOBAB Protocol repository to your local machine.
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    cd BAOBAB-PROTOCOL
    ```

2.  **Install Dependencies**:
    If you are using this as a standalone project, install the necessary dependencies.
    ```bash
    # Using npm
    npm install
    
    # Using forge
    forge install
    ```

3.  **Compile Contracts**:
    Compile the smart contracts to ensure everything is set up correctly.
    ```bash
    # Using Hardhat
    npx hardhat compile
    
    # Using Foundry
    forge build
    ```

## Usage

The BAOBAB Protocol is designed as a collection of libraries that can be imported directly into your smart contracts.

### Example: Using `PercentageMath`

Here’s how you can use the `PercentageMath` library to calculate a trading fee within your contract.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PercentageMath} from "./libraries/math/PercentageMath.sol";

contract MyTradingContract {
    uint16 public constant TRADING_FEE_BPS = 50; // 0.50% fee

    function calculateFee(uint256 tradeAmount) external pure returns (uint256) {
        // Calculates 0.50% of the tradeAmount
        return PercentageMath.calculateFee(tradeAmount, TRADING_FEE_BPS);
    }
}
```

### Example: Using Structs

Import and use the powerful data structures from `TradingStructs` to manage trading-related data in your application.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TradingStructs} from "./libraries/structs/TradingStructs.sol";
import {CommonStructs} from "./libraries/structs/CommonStructs.sol";

contract OrderManager {
    mapping(bytes32 => TradingStructs.TradeExecution) public tradeExecutions;

    function recordTrade(
        bytes32 orderId,
        bytes32 marketId,
        address trader,
        uint256 price,
        uint256 size
    ) external {
        TradingStructs.TradeExecution memory newTrade = TradingStructs.TradeExecution({
            orderId: orderId,
            positionId: bytes32(0),
            marketId: marketId,
            trader: trader,
            side: CommonStructs.Side.LONG,
            price: price,
            size: size,
            fees: 0, // Calculate fees separately
            pnl: 0,
            executionMode: TradingStructs.ExecutionMode.AUTO,
            timestamp: block.timestamp
        });

        bytes32 tradeId = keccak256(abi.encodePacked(orderId, block.timestamp));
        tradeExecutions[tradeId] = newTrade;
    }
}
```

## 🤝 Contributing

Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1.  **Fork the Project**
2.  **Create your Feature Branch** (`git checkout -b feature/AmazingFeature`)
3.  **Commit your Changes** (`git commit -m 'Add some AmazingFeature'`)
4.  **Push to the Branch** (`git push origin feature/AmazingFeature`)
5.  **Open a Pull Request**

Please ensure your code adheres to the existing style and that you add or update tests as appropriate.

## 📄 License

This project is licensed under the **Business Source License 1.1 (BUSL-1.1)**. This license allows for non-production use and testing, with commercial use requiring a separate license.

## ✍️ Author

**Olu Adebakin**

-   **LinkedIn**: [Your LinkedIn Profile](https://www.linkedin.com/in/your-username/)
-   **Twitter**: [@YourTwitterHandle](https://twitter.com/your-twitter-handle)
-   **Email**: your.email@example.com

---

[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)