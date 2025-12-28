# Baobab Protocol - Perpetual Futures Trading Engine

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL)
[![License](https://img.shields.io/badge/license-BUSL--1.1-blue)](https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL/blob/main/LICENSE)
[![Solidity](https://img.shields.io/badge/solidity-%5E0.8.24-black)](https://soliditylang.org/)

A production-grade decentralized perpetual exchange (Perp-DEX) engine suite built on Solidity, featuring institutional-grade risk management, automated deleveraging, and dynamic funding rates for EVM-compatible blockchains.

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Stacks / Technologies](#stacks--technologies)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [Author Info](#author-info)

---

## Overview

The Baobab Protocol is a comprehensive perpetual futures trading engine designed for decentralized exchanges. It provides a robust infrastructure for managing leveraged positions, calculating real-time profit and loss, implementing sophisticated risk management strategies, and ensuring market stability through dynamic funding rates and automated deleveraging mechanisms. It is a high-performance decentralized perpetual exchange (Perp-DEX) engine suite built on Solidity, emphasizing institutional-grade risk management and capital efficiency.

### What Makes Baobab Unique?

*   **Hyperliquid/Bybit-grade ADL System**: Sophisticated profit-based deleveraging protecting the insurance fund.
*   **Market-Specific Risk Tiers**: Configurable margin requirements and leverage limits per asset.
*   **On-Chain Portfolio Tracking**: Real-time aggregation of collateral, PnL, and margin ratios.
*   **Volume-Based Limits**: Anti-concentration mechanisms preventing market manipulation.
*   **Modular Security Framework**: Circuit breakers, emergency pauses, and rate limiting.

---

## Key Features

### 🎯 Core Trading Engine

*   **Complete Position Lifecycle Management**: Allows opening, increasing, decreasing, and closing perpetual positions with comprehensive state tracking.
*   **Real-Time PnL Calculation**: Provides instant unrealized and realized profit/loss computation for positions.
*   **Multi-Collateral Support**: Designed to handle ERC20 tokens as collateral, offering flexible margin requirements.
*   **Cross-Market Portfolio**: Offers a unified portfolio view, aggregating collateral, PnL, and margin ratios across all markets and positions for each trader.
*   **Modular Trading Engines**: Includes core logic for perpetual futures contract management (`PerpEngine`), advanced collateral management with shared margin (`CrossMarginEngine`), and integrated spot trading capabilities (`SpotEngine`).

### ⚡ Auto-Deleveraging (ADL) Engine

*   **Profit-Based Ranking**: Positions are scored by `(unrealizedPnL × leverage) / 100`, with higher scores being deleveraged first.
*   **Insurance Fund Protection**: Automatically closes profitable opposing positions when liquidations cannot be fully filled or the insurance fund is insufficient, safeguarding protocol solvency.
*   **Fair Deleverage**: Top-ranked traders are deleveraged first, realizing and keeping 100% of their profits, losing only future upside.
*   **Efficient Queue Management**: Features O(1) position addition/removal with efficient sorting algorithms for the ADL candidate queue.

### 💰 Dynamic Funding Rate System

*   **Periodic Funding Cycles**: Implements periodic funding payments (fixed at 8 hours) based on the Open Interest (OI) imbalance between long and short positions.
*   **Market-Specific Caps**: Configurable maximum funding rates per market (default 0.3% per 8-hour cycle) to prevent extreme fluctuations.
*   **Accumulated Funding Per Unit (AFPU)**: Utilizes a gas-efficient index-based funding calculation method.
*   **Pull-Based Settlement**: Users initiate funding payments/receipts upon position interaction, rather than through costly iterative loops.

### 🛡️ Advanced Risk Management

*   **Three Liquidity Tiers**: Markets are classified into HIGH (0.5% MMR), MEDIUM (0.75% MMR), and LOW (1% MMR) tiers, each with distinct margin requirements and maximum leverage.
*   **Dynamic Liquidation Prices**: Liquidation prices are dynamically calculated based on maintenance margin requirements and current position size.
*   **Circuit Breakers**: Features global and market-specific circuit breakers to halt trading during periods of extreme volatility.
*   **Emergency Pause**: A protocol-wide pause mechanism can be activated for critical situations, controlled by an `EmergencyPauser` contract.
*   **Rate Limiting**: Throughput controls are applied to sensitive operations to prevent abuse and ensure system stability.

### 📊 Volume & Concentration Controls

*   **Market Concentration Limits**: Prevents excessive capital concentration by a single trader within a single market (e.g., maximum 50% of portfolio volume).
*   **Position Size Caps**: New positions cannot exceed a certain percentage (e.g., 10%) of a trader's 30-day volume.
*   **New Trader Protections**: Stricter limits are enforced for new accounts with less than a certain lifetime trading volume (e.g., <$10k).
*   **Historical Volume Tracking**: Integrates with a `VolumeTracker` to monitor 30-day and lifetime trading volume per trader for robust risk assessment.

---

## Stacks / Technologies

| Technology               | Purpose                                      | Link                                                        |
| :----------------------- | :------------------------------------------- | :---------------------------------------------------------- |
| Solidity                 | Smart contract programming language          | [soliditylang.org](https://soliditylang.org/)               |
| Foundry                  | Development framework for testing and deployment | [book.getfoundry.sh](https://book.getfoundry.sh/)           |
| Ethereum Virtual Machine (EVM) | Runtime environment for smart contracts      | [ethereum.org](https://ethereum.org/en/developers/docs/evm/) |
| OpenZeppelin Contracts   | Secure, community-vetted smart contract libraries | [docs.openzeppelin.com/contracts](https://docs.openzeppelin.com/contracts/) |

---

## Installation

To get a local copy up and running, follow these steps.

1.  Clone the repository:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```
2.  Navigate to the project directory:
    ```bash
    cd BAOBAB-PROTOCOL
    ```
3.  Install dependencies (Foundry is required):
    ```bash
    forge install
    ```
4.  Compile the smart contracts:
    ```bash
    forge build
    ```
5.  Run tests to ensure everything is working correctly:
    ```bash
    forge test
    ```

### Environment Variables

Create a `.env` file in the root of your project and set the following variables:

```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-api-key
PRIVATE_KEY=0xabc123... (Deployer/Admin private key)
ETHERSCAN_API_KEY=your-etherscan-key
ADMIN_ADDRESS=0x... (Protocol administrator address)
KEEPER_ADDRESS=0x... (Authorized funding keeper address)
INSURANCE_VAULT_ADDRESS=0x... (Insurance fund address, specific for ADL)
```

---

## Usage

Interact with the smart contracts directly on an EVM-compatible blockchain. Below are example JSON requests and responses for key API endpoints.

### Base URL

The base URL will be the deployed contract address on the respective blockchain network.

### Endpoints

#### `POST /openPosition`

Opens a new perpetual position for a trader via the `PositionManager` contract.

**Request**:

```json
{
  "trader": "0x123...abc",
  "marketId": "0x... (bytes32)",
  "side": "0 (LONG) or 1 (SHORT)",
  "size": "1000000000000000000 (uint256)",
  "collateral": "100000000000000000 (uint256)",
  "entryPrice": "50000000000000000000000 (uint256)",
  "leverage": "10 (uint16)"
}
```

**Response**:

```json
{
  "positionId": "0x... (bytes32)",
  "status": "Success",
  "blockNumber": 19283746
}
```

**Errors**:

*   `400: PositionManager__InvalidSize`
*   `402: PositionManager__InsufficientInitialMargin`
*   `403: PositionManager__OnlyTradingEngine`

#### `POST /applyFundingRate`

Applies funding rates to all positions in a specified market via the `FundingEngine` contract. This function is typically called by an authorized keeper.

**Request**:

```json
{
  "marketId": "0x... (bytes32)"
}
```

**Response**:

```json
{
  "rateBps": "-15 (int256)",
  "lastFundingTime": 1715432100
}
```

**Errors**:

*   `400: FundingTooSoon` (Interval not elapsed)
*   `403: Only keeper`

#### `POST /executeADL`

Triggers the Auto-Deleveraging process in a specific market to cover liquidation shortfalls via the `AutoDeleverageEngine` contract.

**Request**:

```json
{
  "marketId": "0x... (bytes32)",
  "liquidatedPosition": "0x... (bytes32)",
  "side": "0 (LONG)",
  "sizeToClose": "500000000000000000",
  "executionPrice": "49500000000000000000000"
}
```

**Response**:

```json
{
  "success": true,
  "adlId": "0x... (bytes32)",
  "totalClosed": "500000000000000000"
}
```

**Errors**:

*   `403: ADL__OnlyLiquidationEngine`
*   `404: ADL__InsufficientCandidates`

#### `POST /updateADLQueue`

Adds or updates a position's entry in the ADL queue via the `AutoDeleverageEngine` contract.

**Request**:

```json
{
  "marketId": "bytes32",
  "positionId": "bytes32",
  "trader": "address",
  "side": "uint8",
  "unrealizedPnL": "int256",
  "leverage": "uint16"
}
```

**Response**:

```json
{
  "status": "void",
  "event": "ADLQueueUpdated"
}
```

**Errors**:

*   `403: ADL__onlyPositionManager`
*   `400: NEGATIVE_PNL`
*   `423: ADL__CircuitActive`

#### `POST /configureADL`

Configures the ADL parameters for a specific market via the `AutoDeleverageEngine` contract (admin-only).

**Request**:

```json
{
  "marketId": "bytes32",
  "insuranceFundThreshold": "uint16",
  "maxPositionsPerADL": "uint8",
  "gracePeriod": "uint256"
}
```

**Response**:

```json
{
  "status": "void",
  "event": "ADLConfigUpdated"
}
```

**Errors**:

*   `403: ADL__OnlyAdmin`
*   `400: ADL__InvalidConfig`

#### `POST /modifyPosition`

Modifies an existing position by adjusting its size and/or collateral via the `PositionManager` contract.

**Request**:

```json
{
  "positionId": "0x... (bytes32)",
  "sizeDelta": "500000000000000000 (int256)",
  "collateralDelta": "-10000000000000000 (int256)",
  "currentPrice": "51000000000000000000000"
}
```

**Response**:

```json
{
  "realizedPnL": "2500000000000000000",
  "newLiquidationPrice": "45000000000000000000000"
}
```

**Errors**:

*   `401: PositionManager__PositionNotFound`
*   `402: PositionManager__InsufficientCollateral`

#### `GET /getPosition`

Retrieves the detailed data for a specific position via the `PositionManager` contract.

**Request**:

```json
{
  "positionId": "0x... (bytes32)"
}
```

**Response**:

```json
{
  "position": {
    "trader": "0x...",
    "size": "1000000000000000000",
    "collateral": "100000000000000000",
    "entryPrice": "50000000000000000000000",
    "leverage": 10
  },
  "isLiquidatable": false,
  "inADLQueue": true,
  "accumulatedFunding": "1500000000000000"
}
```

**Errors**:

*   `404: PositionManager__PositionNotFound`

#### `GET /getADLQueue`

Retrieves the ADL queue for a given market and side via the `AutoDeleverageEngine` contract.

**Request**:

```json
{
  "marketId": "bytes32",
  "side": "uint8"
}
```

**Response**:

```json
[
  {
    "positionId": "bytes32",
    "trader": "address",
    "side": "uint8",
    "unrealizedPnL": "int256",
    "leverage": "uint16",
    "adlScore": "uint256",
    "lastUpdateTime": "uint256"
  }
]
```

---

## Contributing

We welcome contributions to the Baobab Protocol! Please follow these guidelines:

*   📥 Fork the repository to your GitHub account and create your feature branch.
*   🛠️ Ensure all logic adheres to the existing safety patterns, particularly those provided by `SecurityBase`.
*   🧪 Write comprehensive unit tests for all new engine logic and ensure all existing tests pass by running `forge test`.
*   📝 Document all external functions using NatSpec comments.
*   🚀 Submit a Pull Request with a detailed description of your modifications and their purpose.

---

## Author Info

*   **GitHub**: [olujimiAdebakin](https://github.com/olujimiAdebakin)
*   **Email**: omoladebu231@gmail.com
*   **Twitter**: [@olujimi_the_dev](https://twitter.com/olujimi_the_dev)

---

