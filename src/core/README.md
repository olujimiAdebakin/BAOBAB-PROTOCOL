# Baobab Protocol 🌴

## Overview
Baobab Protocol is a modular decentralized perpetual exchange (DEX) engine written in Solidity. It utilizes a high-performance position management system, automated deleveraging (ADL) mechanisms, and multi-source oracle integration to provide institutional-grade trading infrastructure on-chain.

## Features
*   **Order Management**: Stores and manages all limit/stop orders for the protocol, with direct integration with `PositionManager`, ensuring gas-optimized order handling.
*   **Position Management**: Core contract for managing perpetual positions, including real-time PnL calculation, margin requirements, and liquidation mechanics. It features dynamic risk parameters based on liquidity tiers.
*   **Auto-Deleverage (ADL) Engine**: An advanced risk socialization mechanism that automatically closes profitable opposing positions when liquidations cannot be fully covered, protecting the protocol's insurance fund during extreme market volatility.
*   **Dynamic Funding Rate Engine**: Calculates and applies periodic funding rates to open positions based on Open Interest (OI) imbalance, promoting price stability and convergence with spot markets.
*   **Market Registry**: A central registry for all trading markets within the protocol, handling market metadata (base/quote assets, asset class), risk parameters (leverage, margin requirements, fees), and operational status.
*   **Oracle Integration**: Centralized registry for mapping assets to primary and fallback price feeds, supporting various adapters such as Pyth, Chainlink, and TWAP for robust and secure price discovery.
*   **Robust Error Handling & Security**: Implements custom error types for clear feedback and includes comprehensive security features through `onlyAdmin`, `onlyKeeper`, `whenNotEmergencyPaused`, and `whenCircuitActivated` modifiers to control access and prevent unauthorized operations or trades during critical events.

## Getting Started
### Installation
1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```
2.  **Install Dependencies**: (Requires [Foundry](https://book.getfoundry.sh/) to be installed)
    ```bash
    forge install
    ```
3.  **Build the Project**:
    ```bash
    forge build
    ```
4.  **Run Tests (Optional)**:
    ```bash
    forge test
    ```

### Environment Variables
Create a `.env` file in the root directory and include the following variables:
```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-api-key
PRIVATE_KEY=0xabc123...your_private_key
ETHERSCAN_API_KEY=your_etherscan_key
BAOBAB_ADMIN_ADDRESS=0x...admin_address
KEEPER_ADDRESS=0x... (Authorized funding keeper address)
```

## API Documentation
### Base URL
`blockchain://protocol-core/v1` (replace `blockchain://protocol-core/v1` with the deployed contract addresses on your target network)

### Endpoints

#### POST /MarketRegistry/registerMarket
Register a new market in the protocol with specified metadata and risk parameters.

**Request**:
```json
{
  "baseAsset": "string",
  "quoteAsset": "string",
  "assetClass": "uint8 (0: CRYPTO, 1: STOCK, 2: FOREX, 3: COMMODITY)",
  "oracleAdapter": "address",
  "maxLeverage": "uint16",
  "maintenanceMarginBps": "uint16",
  "liquidationFeeBps": "uint16",
  "maxOpenInterest": "uint256",
  "tradingFeeBps": "uint16"
}
```

**Response**:
```json
{
  "marketId": "bytes32"
}
```

**Errors**:
-   `403`: `MarketRegistry__Unauthorized`
-   `400`: `MarketRegistry__InvalidLeverage`
-   `409`: `MarketRegistry__MarketAlreadyExists`

#### POST /PositionManager/openPosition
Open a new perpetual position for a trader in a specified market.

**Request**:
```json
{
  "trader": "address",
  "marketId": "bytes32",
  "side": "uint8 (0: LONG, 1: SHORT)",
  "size": "uint256 (18 decimals)",
  "collateral": "uint256 (18 decimals)",
  "entryPrice": "uint256 (18 decimals)",
  "leverage": "uint16"
}
```

**Response**:
```json
{
  "positionId": "bytes32"
}
```

**Errors**:
-   `403`: `PositionManager__OnlyTradingEngine`
-   `400`: `PositionManager__LeverageExceedsMax`
-   `402`: `PositionManager__InsufficientInitialMargin`

#### POST /PositionManager/increasePosition
Increase the size and/or collateral of an existing position.

**Request**:
```json
{
  "positionId": "bytes32",
  "additionalSize": "uint256 (18 decimals)",
  "additionalCollateral": "uint256 (18 decimals)"
}
```

**Response**:
(No explicit return value for this function, but emits `PositionIncreased` event)

**Errors**:
-   `400`: `PositionManager__InvalidSize`
-   `402`: `PositionManager__InsufficientCollateral`
-   `403`: `PositionManager__OnlyTradingEngine`
-   `404`: `PositionManager__InvalidPosition`

#### POST /PositionManager/decreasePosition
Decrease the size and/or withdraw collateral from an existing position.

**Request**:
```json
{
  "positionId": "bytes32",
  "reduceSize": "uint256 (18 decimals)",
  "withdrawCollateral": "uint256 (18 decimals)"
}
```

**Response**:
(No explicit return value for this function, but emits `PositionDecreased` and `PnLRealized` events)

**Errors**:
-   `400`: `PositionManager__InvalidReduction`
-   `402`: `PositionManager__InsufficientCollateral`
-   `403`: `PositionManager__OnlyTradingEngine`
-   `404`: `PositionManager__InvalidPosition`
-   `406`: `PositionManager__ReductionExceedsPosition`

#### POST /PositionManager/closePosition
Close an existing position entirely.

**Request**:
```json
{
  "positionId": "bytes32",
  "closePrice": "uint256 (18 decimals)"
}
```

**Response**:
```json
{
  "realizedPnL": "int256 (18 decimals)"
}
```

**Errors**:
-   `404`: `PositionManager__PositionNotFound`
-   `500`: `PositionManager__CircuitBroken`

#### POST /FundingEngine/applyFundingRate
Calculates and applies the funding rate to all positions in a given market.

**Request**:
```json
{
  "marketId": "bytes32"
}
```

**Response**:
```json
{
  "rateBps": "int256 (basis points)",
  "lastFundingTime": "uint256 (timestamp)"
}
```

**Errors**:
-   `403`: `Only keeper`
-   `429`: `FundingTooSoon` (Interval not elapsed)

#### POST /AutoDeleverageEngine/executeADL
Executes the Auto-Deleveraging (ADL) process for a failed liquidation to cover shortfalls.

**Request**:
```json
{
  "marketId": "bytes32",
  "liquidatedPosition": "bytes32",
  "side": "uint8 (0: LONG, 1: SHORT)",
  "sizeToClose": "uint256 (18 decimals)",
  "executionPrice": "uint256 (18 decimals)"
}
```

**Response**:
```json
{
  "success": "bool"
}
```

**Errors**:
-   `403`: `ADL__OnlyLiquidationEngine`
-   `400`: `ADL__InsufficientCandidates`

#### POST /OracleRegistry/setOracle
Sets the primary and fallback oracle for a given asset.

**Request**:
```json
{
  "asset": "address",
  "primary": "address",
  "fallback": "address"
}
```

**Response**:
```json
{
  "status": "success"
}
```

**Errors**:
-   `403`: `AccessControl: account 0x... is missing role 0x...` (requires `ORACLE_MANAGER` role)

#### GET /PositionManager/getPosition
Retrieve full data for a specific position by its ID.

**Request**:
```json
{
  "positionId": "bytes32"
}
```

**Response**:
```json
{
  "position": {
    "trader": "address",
    "marketId": "bytes32",
    "side": "uint8",
    "size": "uint256",
    "collateral": "uint256",
    "entryPrice": "uint256",
    "leverage": "uint16",
    "lastFundingIndex": "int256",
    "unrealizedPnL": "int256",
    "liquidationPrice": "uint256",
    "openedAt": "uint256"
  },
  "lastUpdateTime": "uint256",
  "accumulatedFunding": "int256",
  "isLiquidatable": "bool",
  "inADLQueue": "bool"
}
```

**Errors**:
-   `404`: `PositionManager__PositionNotFound`

## Technologies Used
| Technology | Purpose | Link |
| :--- | :--- | :--- |
| [Solidity](https://soliditylang.org/) | Smart Contract Logic | [soliditylang.org](https://soliditylang.org/) |
| [Foundry](https://book.getfoundry.sh/) | Development & Testing Framework | [book.getfoundry.sh](https://book.getfoundry.sh/) |
| [OpenZeppelin Contracts](https://openzeppelin.com/contracts/) | Security Standard Implementations (e.g., AccessControl, IERC20) | [openzeppelin.com](https://openzeppelin.com/contracts/) |
| [EVM](https://ethereum.org/) | Ethereum Virtual Machine Execution Environment | [ethereum.org](https://ethereum.org/) |
| [Chainlink](https://chain.link/) | Decentralized Price Oracles | [chain.link](https://chain.link/) |
| [Pyth Network](https://pyth.network/) | Low-latency Market Data | [pyth.network](https://pyth.network/) |

## Contributing
-   **Fork the Project**: Create your own feature branch from `main`.
-   **Adhere to Style**: Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/v0.8.24/style-guide.html).
-   **Test Coverage**: Ensure all new logic has corresponding unit tests in the `test/` directory.
-   **Submit PR**: Provide a clear description of changes and related issues for review.

## Author Info
Developed by the Baobab Protocol Engineering Team.
-   **Github**: [olujimiAdebakin](https://github.com/olujimiAdebakin)
-   **Twitter**: [@jimi_baobab](https://twitter.com/placeholder)
-   **LinkedIn**: [Olujimi Adebakin](https://linkedin.com/in/placeholder)

![Solidity](https://img.shields.io/badge/Solidity-%23363636.svg?style=for-the-badge&logo=solidity&logoColor=white)
![Foundry](https://img.shields.io/badge/Foundry-%232D3748.svg?style=for-the-badge&logo=foundry&logoColor=white)
![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge)


