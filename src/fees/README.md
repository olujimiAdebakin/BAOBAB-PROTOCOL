# BAOBAB Protocol Revenue & Incentive Engine

## Overview
A high-performance decentralized finance backend suite composed of Solidity smart contracts designed to manage fee calculations, revenue distribution, and trader incentive programs for a perpetual exchange. The system leverages automated tier-based discounting, rolling volume tracking via circular buffers, and multi-signature governed revenue allocation.

## Features
- **FeeCalculator**: Dynamic taker/maker fee engine with asset-specific configurations and volatility multipliers.
- **FeeDistributor**: Automated settlement token distribution across Treasury, LP Vaults, and Insurance Funds.
- **IncentiveManager**: Epoch-based reward system featuring referral bonuses and multi-tier trader multipliers.
- **RevenueManager**: Granular analytics engine providing daily snapshots of protocol volume and fee performance.
- **VolumeTracker**: Gas-optimized O(1) circular buffer for tracking 30-day rolling trading volumes.

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
   forge install openzeppelin/openzeppelin-contracts
   ```

3. **Compilation**
   ```bash
   forge build
   ```

### Environment Variables
Configure these variables in your `.env` file for deployment and testing:
```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
PRIVATE_KEY=0xabc123...
BAOBAB_TOKEN_ADDRESS=0x...
SETTLEMENT_TOKEN_ADDRESS=0x... # (e.g., USDC)
ADMIN_ADDRESS=0x...
MULTISIG_ADDRESS=0x...
```

## API Documentation
### Base URL
`Contract Address (Mainnet/Testnet Deployment)`

### Endpoints

#### GET /view/calculateTradingFeeTaker
Calculates the specific taker fee for a user based on their 30-day volume tier and asset volatility.
**Request**:
```json
{
  "asset": "address",
  "user": "address",
  "notionalUsd": "uint256"
}
```
**Response**:
```json
{
  "feeBps": "uint256"
}
```
**Errors**:
- 400: VolumeTrackerNotSet
- 400: InvalidAssetClass

#### POST /tx/distributeFees
Triggers the distribution of collected settlement tokens to protocol stakeholders.
**Request**:
```json
{}
```
**Response**:
```json
{
  "status": "Success",
  "distributionId": "uint256",
  "totalAmount": "uint256"
}
```
**Errors**:
- 403: UnauthorizedDistributor
- 400: InsufficientAmount
- 503: DistributionIsPaused

#### POST /tx/recordTrade
Records trading activity to update both lifetime and 30-day rolling volume metrics.
**Request**:
```json
{
  "user": "address",
  "marketId": "bytes32",
  "amount": "uint256"
}
```
**Response**:
```json
{
  "newLifetimeVolume": "uint256",
  "timestamp": "uint256"
}
```
**Errors**:
- 403: Unauthorized
- 400: ZeroAmount
- 400: InvalidMarketId

#### POST /tx/claimRewards
Allows traders to claim accumulated BAOBAB tokens from the current incentive epoch.
**Request**:
```json
{}
```
**Response**:
```json
{
  "claimedAmount": "uint256",
  "recipient": "address"
}
```
**Errors**:
- 400: NoRewardsToClaim
- 500: InsufficientRewardsPool

#### POST /tx/registerReferral
Links a new trader to a referrer to enable bonus incentives.
**Request**:
```json
{
  "referrer": "address"
}
```
**Response**:
```json
{
  "status": "Registered",
  "referee": "address",
  "referrer": "address"
}
```
**Errors**:
- 400: InvalidReferrer
- 400: AlreadyReferred
- 429: MaxReferralsExceeded

## Technologies Used
| Technology | Purpose |
|------------|---------|
| Solidity | Smart Contract Logic |
| Foundry | Development & Testing Framework |
| OpenZeppelin | Security Standards & Access Control |
| Hardhat | Deployment Scripting (Optional) |

## Contributing
- 🛠️ Fork the repository and create your feature branch.
- 🧪 Ensure all tests pass using `forge test`.
- 📝 Document all internal functions and state changes.
- 🚀 Submit a Pull Request for review by the core maintainers.

## Author Info
**Project Lead**
- GitHub: [olujimiAdebakin](https://github.com/olujimiAdebakin)
- Twitter/X: [@olujimi_the_dev]


![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/License-BUSL--1.1-blue)
![Solidity](https://img.shields.io/badge/Solidity-^0.8.24-lightgrey)

