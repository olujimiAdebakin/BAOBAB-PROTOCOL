# BAOBAB PROTOCOL

## Overview
A high-performance decentralized perpetual exchange (Perp-DEX) engine suite built on Solidity. The system features a robust Auto-Deleverage (ADL) mechanism and modular trading engines designed for institutional-grade risk management and capital efficiency.

## Features
- **AutoDeleverageEngine**: Sophisticated risk mitigation that ranks profitable positions by ADL score to protect the insurance fund.
- **PerpEngine**: Core logic for perpetual futures contract management and funding rate calculations.
- **CrossMarginEngine**: Advanced collateral management allowing shared margin across multiple trading positions.
- **OrderBook**: High-efficiency matching engine for decentralized limit and market order execution.
- **SpotEngine**: Integrated spot trading capabilities for underlying asset liquidity.

## Getting Started
### Installation
1. Clone the repository:
```bash
git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
```
2. Install dependencies (Foundry):
```bash
forge install
```
3. Compile the smart contracts:
```bash
forge build
```

### Environment Variables
Required variables for deployment and testing:
```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-api-key
PRIVATE_KEY=0xabc123...
ETHERSCAN_API_KEY=your-etherscan-key
ADMIN_ADDRESS=0x123...
INSURANCE_VAULT_ADDRESS=0x456...
```

## API Documentation
### Base URL
Smart Contract Deployment Address (Mainnet/Testnet)

### Endpoints
#### EXTERNAL executeADL
**Request**:
```json
{
  "marketId": "bytes32",
  "liquidatedPosition": "bytes32",
  "side": "uint8 (0 for Long, 1 for Short)",
  "sizeToClose": "uint256",
  "executionPrice": "uint256"
}
```

**Response**:
```json
{
  "success": "bool"
}
```

**Errors**:
- 403: ADL__OnlyLiquidationEngine
- 403: ADL_ENGINE__Paused
- 400: ADL__InsufficientCandidates
- 400: ADL__ADLNotEnabled

#### EXTERNAL updateADLQueue
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
- 403: ADL__onlyPositionManager
- 400: NEGATIVE_PNL
- 423: ADL__CircuitActive

#### EXTERNAL configureADL
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
- 403: ADL__OnlyAdmin
- 400: ADL__InvalidConfig

#### VIEW getADLQueue
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

## Technologies Used
| Technology | Purpose | Link |
|------------|---------|------|
| Solidity | Smart Contract Language | [soliditylang.org](https://soliditylang.org/) |
| Foundry | Development Framework | [book.getfoundry.sh](https://book.getfoundry.sh/) |
| OpenZeppelin | Security Standards | [openzeppelin.com](https://openzeppelin.com/) |

## Contributing
- 📥 Fork the repository and create your feature branch.
- 🛠️ Ensure all logic follows the existing safety patterns (SecurityBase).
- 🧪 Write comprehensive unit tests for all new engine logic.
- 📝 Document all external functions using NatSpec.
- 🚀 Submit a pull request with a detailed description of changes.

## Author Info
**[Your Name]**
- Twitter: [@your_handle]
- LinkedIn: [linkedin.com/in/your_username]
- Portfolio: [yourportfolio.com]

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-BUSL--1.1-blue)
![Solidity](https://img.shields.io/badge/solidity-%5E0.8.24-black)

