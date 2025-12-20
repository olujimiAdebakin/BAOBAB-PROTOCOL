# BAOBAB Protocol 🌳

## Overview
BAOBAB Protocol is a sophisticated decentralized finance (DeFi) revenue and incentive engine designed for high-performance perpetual exchanges. Built with Solidity 0.8.24, the system implements dynamic fee modeling, multi-tier reward distributions, and gas-optimized volume tracking using circular buffers.

## Features
- **FeeCalculator**: Dynamic pricing engine with volatility-adjusted multipliers and staking-based tier discounts.
- **FeeDistributor**: Production-grade settlement system that splits protocol revenue between Liquidity Providers, Insurance Funds, and Treasury.
- **IncentiveManager**: Epoch-based rewards system featuring a comprehensive referral program and Sybil-resistant trading incentives.
- **RevenueManager**: Detailed analytics engine providing daily snapshots, market-specific performance metrics, and automated allocation logic.
- **VolumeTracker**: High-efficiency circular buffer implementation for tracking 30-day rolling and lifetime trading volumes with O(1) complexity.

## Getting Started
### Installation
1. **Clone the Repository**
   ```bash
   git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
   cd BAOBAB-PROTOCOL
   ```

2. **Install Dependencies**
   ```bash
   # Using Foundry
   forge install OpenZeppelin/openzeppelin-contracts
   ```

3. **Compile the Contracts**
   ```bash
   forge build
   ```

### Environment Variables
Create a `.env` file in the root directory and populate the following variables:
```env
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-api-key
PRIVATE_KEY=0xabc123...your-private-key
BAOBAB_TOKEN_ADDRESS=0x123... (The protocol governance token)
SETTLEMENT_TOKEN_ADDRESS=0x456... (USDC/USDT address)
ADMIN_ADDRESS=0x789... (Multisig or EOA admin)
```

## API Documentation
### Base URL
`Mainnet/Arbitrum/Base Deployment Address`

### Endpoints

#### WRITE recordTrade
**Request**:
```json
{
  "user": "0xUserAddress",
  "marketId": "0xMarketBytes32",
  "amount": "1000000000000000000"
}
```

**Response**:
```json
{
  "event": "TradeRecorded",
  "newLifetimeVolume": "5000000000000000000",
  "timestamp": 1700000000
}
```

**Errors**:
- 403: Unauthorized (Caller is not an authorized recorder)
- 400: ZeroAmount (Trade size must be greater than zero)

#### READ calculateTradingFeeTaker
**Request**:
```json
{
  "asset": "0xAssetAddress",
  "user": "0xUserAddress",
  "notionalUsd": "1000000000000000000"
}
```

**Response**:
```json
{
  "feeBps": 8,
  "discountAppliedBps": 1500
}
```

**Errors**:
- 404: InvalidAssetClass (Asset not mapped to a fee class)

#### WRITE distributeFees
**Request**:
```json
{
  "caller": "0xAuthorizedDistributor"
}
```

**Response**:
```json
{
  "status": "Success",
  "distributionId": 142,
  "lpShare": "400000000",
  "treasuryShare": "300000000"
}
```

**Errors**:
- 403: DistributionIsPaused (Emergency circuit breaker active)
- 400: InsufficientAmount (Balance below minimum distribution threshold)

#### WRITE registerReferral
**Request**:
```json
{
  "referrer": "0xReferrerAddress"
}
```

**Response**:
```json
{
  "event": "ReferralRegistered",
  "referee": "0xUserAddress",
  "referrer": "0xReferrerAddress"
}
```

**Errors**:
- 400: AlreadyReferred (User already has an assigned referrer)
- 403: InvalidReferrer (Referrer cannot be the user themselves)

## Technologies Used

| Technology | Purpose | Link |
| --- | --- | --- |
| Solidity 0.8.24 | Smart Contract Logic | [soliditylang.org](https://soliditylang.org/) |
| OpenZeppelin | Security & Access Control | [openzeppelin.com](https://openzeppelin.com/) |
| Foundry | Development Framework | [book.getfoundry.sh](https://book.getfoundry.sh/) |
| BUSL-1.1 | License Framework | [spdx.org](https://spdx.org/licenses/BUSL-1.1.html) |

## Contributing
- 🤝 Fork the repository and create your feature branch.
- 📝 Ensure all code follows the protocol's NatSpec documentation standards.
- 🧪 Run full test suites (`forge test`) before submitting a PR.
- 🛡️ Maintain security best practices regarding reentrancy and access control.

## License
This project is licensed under the **BUSL-1.1** (Business Source License 1.1). See the source file headers for more details.

## Author Info
**Adebakn Olujimi**
- Twitter: @olujimi_the_dev


---
![Solidity](https://img.shields.io/badge/Solidity-%23363636.svg?style=for-the-badge&logo=solidity&logoColor=white)
![Build Status](https://img.shields.io/badge/Foundry-Passing-brightgreen?style=for-the-badge)
![DeFi](https://img.shields.io/badge/DeFi-Protocol-blue?style=for-the-badge)
