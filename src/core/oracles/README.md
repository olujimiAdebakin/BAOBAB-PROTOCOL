# BAOBAB Oracle Infrastructure

## Overview

BAOBAB Oracle Infrastructure is a high-integrity price feed management system built in Solidity, designed to provide modular adapters and multi-layered security for perpetual decentralized exchanges. It integrates a resilient primary/fallback oracle logic with automated circuit breakers to ensure manipulation-resistant data for high-risk DeFi operations. The project provides a modular and extensible framework for integrating various decentralized oracle solutions within smart contracts, including adapters for popular oracle networks like Chainlink and Pyth, alongside custom implementations for computed, TWAP (Time-Weighted Average Price), and trusted oracle functionalities.

## Features

*   **Multi-Provider Support**: Provides unified `IPriceFeed` interfaces for seamless integration with external oracle networks.
    *   **Chainlink Adapter**: Integrates with Chainlink oracles for a wide range of reliable off-chain data feeds.
    *   **Pyth Adapter**: Supports Pyth network's high-frequency, low-latency market data feeds.
*   **Computed Oracles**: Enables the creation of complex price feeds, such as synthetic assets (e.g., A/B or A\*B) derived from two base price feeds (e.g., ETH/USD and BTC/USD to get ETH/BTC).
*   **TWAP Mechanism**: Implements Time-Weighted Average Price calculations for robust price feeds, smoothing out short-term price manipulation and enhancing manipulation resistance for sensitive actions like liquidations.
*   **Trusted Oracle**: Offers an adapter for integrating data from trusted, centralized sources, with prices manually set by an authorized admin.
*   **Primary/Fallback Oracle Strategy**: The centralized `OracleRegistry` manages resilient price retrieval using primary and fallback price feeds, combined with configurable heartbeat (staleness) checks to maximize uptime and security.
*   **Security Guards**: A mandatory central `OracleSecurity` layer enforces oracle safety guarantees, including circuit breaker checks, global pause functionality, staleness checks, and contextual confidence intervals based on the price's intended use (e.g., SPOT, PERP_TRADE, LIQUIDATION, FUNDING).
*   **Access Control**: Utilizes OpenZeppelin's `Ownable` and custom `AccessManager` to provide robust access control over critical functions like oracle deployment and configuration.
*   **Modular Design**: Features an easily extendable architecture to incorporate new oracle providers or custom data sources.

## Stacks / Technologies

| Technology | Description | Link |
| :--------- | :------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------ |
| Solidity | Smart contract programming language for Ethereum. | [Solidity Docs](https://docs.soliditylang.org/en/latest/) |
| OpenZeppelin | Robust smart contract libraries providing secure and community-vetted components for Ethereum. | [OpenZeppelin Contracts](https://openzeppelin.com/contracts/) |
| Foundry | A blazing fast, portable, and modular toolkit for Ethereum application development, testing, and deployment. | [Foundry Docs](https://getfoundry.sh/) |
| Chainlink | A decentralized oracle network that provides reliable, tamper-proof real-world data to smart contracts. | [Chainlink Official Website](https://chain.link/) |
| Pyth Network | A specialized oracle network designed for low-latency, high-fidelity financial market data. | [Pyth Network Official Website](https://pyth.network/) |

## Installation

To get started with this project, follow these steps:

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```
2.  **Install dependencies**:
    ```bash
    forge install OpenZeppelin/openzeppelin-contracts
    ```
3.  **Build the project**:
    ```bash
    forge build
    ```
4.  **Run tests**:
    ```bash
    forge test
    ```

### Environment Variables

The project requires specific environment variables for deployment and interaction:

*   `RPC_URL`: The URL of the Ethereum/EVM node (e.g., `https://eth-mainnet.g.alchemy.com/v2/your-key`)
*   `PRIVATE_KEY`: The deployer account private key for contract instantiation
*   `ETHERSCAN_API_KEY`: Required for verifying contracts on Etherscan
*   `ORACLE_ADMIN_ADDRESS`: Address granted the `ORACLE_UPDATER_ROLE`

## Usage

The BAOBAB Oracle Infrastructure provides a robust system for managing and consuming price data within a decentralized application. Here's a high-level overview of how the core contracts are used:

*   **`ComputedOracleFactory`**: This factory contract is responsible for securely deploying and registering instances of `ComputedOracle.sol`. It allows governance to create complex price feeds for synthetic assets derived from two base price feeds.
    *   **`deployAndRegisterOracle(targetAssetAddress, feedA, feedB, operation, heartbeat)`**: Deploys a new `ComputedOracle` instance and immediately registers it with the `OracleRegistry` for a specified `targetAssetAddress`.
*   **`OracleRegistry`**: Acts as the centralized hub for managing, configuring, and retrieving market-specific prices. It implements a primary/fallback oracle strategy with heartbeat checks and links asset token addresses to market IDs.
    *   **`setMarketOracle(marketId, primaryOracle, fallbackOracle, heartbeat)`**: Configures the primary and fallback oracles for an existing market, setting the maximum allowable age for the primary feed.
    *   **`getPrice(asset)`**: Retrieves the current price, success status, confidence, and last updated timestamp for a market linked to a specific asset address.
*   **`OracleSecurity`**: This is the mandatory security layer through which all protocol components *must* consume price data. It enforces a sequence of checks including circuit breaker status, global pause, market activity, staleness, and contextual confidence.
    *   **`getValidatedPrice(asset, use)`**: Returns a fully validated, protocol-safe price for an asset, applying risk-based confidence requirements based on the `PriceUse` context (e.g., `SPOT`, `LIQUIDATION`).
*   **Adapters (`ChainlinkAdapter`, `PythAdapter`, `TWAPAdapter`, `TrustedOracle`)**: These contracts wrap external oracle solutions (Chainlink, Pyth) or provide custom data processing (TWAP, Trusted) to conform to the unified `IPriceFeed` interface, ensuring compatibility across the system.
    *   **`pushObservation()` (TWAPAdapter)**: Allows anyone to push new price observations, contributing to the time-weighted average price calculation.
    *   **`setPrice(newPrice)` (TrustedOracle)**: Enables the owner to manually update the price within a trusted oracle instance.

### API Documentation

The following endpoints are available for interaction with the deployed contracts:

#### EXTERNAL `deployAndRegisterOracle(address, address, address, uint8, uint256)`
**Request**:
_Payload Structure:_
```json
{
  "targetAssetAddress": "0x...",
  "feedA": "0x...",
  "feedB": "0x...",
  "operation": 0,
  "heartbeat": 3600
}
```
**Response**:
_Success Response:_
```json
{
  "computedOracleAddress": "0x..."
}
```
**Errors**:
- `0x98b8c54a`: `ComputedOracleFactory__ZeroAddressRegistry`
- `0x...`: `ComputedOracleFactory__InvalidInputAsset`

#### EXTERNAL `setMarketOracle(bytes32, address, address, uint256)`
**Request**:
_Payload Structure:_
```json
{
  "marketId": "0x...",
  "primaryOracle": "0x...",
  "fallbackOracle": "0x...",
  "heartbeat": 60
}
```
**Response**:
_Success Response:_
```json
{
  "status": "OracleConfigured"
}
```
**Errors**:
- `0x...`: `Oracle_Heartbeat_Too_Low`
- `0x...`: `OracleAlreadyConfigured`

#### EXTERNAL `getPrice(address)`
**Request**:
_Payload Structure:_
```json
{
  "asset": "0x..."
}
```
**Response**:
_Success Response:_
```json
{
  "price": 6500000000000,
  "success": true,
  "confidence": 5,
  "lastUpdated": 1715000000
}
```
**Errors**:
- `0x...`: `AssetNotLinked`

#### EXTERNAL `getValidatedPrice(address, uint8)`
**Request**:
_Payload Structure:_
```json
{
  "asset": "0x...",
  "use": 2
}
```
**Response**:
_Success Response:_
```json
{
  "validatedPrice": 6500000000000
}
```
**Errors**:
- `0x...`: `OracleSecurity__CircuitBroken`
- `0x...`: `OracleSecurity__StalePrice`
- `0x...`: `OracleSecurity__ConfidenceTooHigh`

#### EXTERNAL `pushObservation()`
**Request**:
_Payload Structure:_
```json
{}
```
**Response**:
_Success Response:_
```json
{
  "event": "TWAPObservationPushed"
}
```
**Errors**:
- `0x...`: `TWAP__NoObservations`

#### EXTERNAL `setPrice(int256)`
**Request**:
_Payload Structure:_
```json
{
  "newPrice": 100000000
}
```
**Response**:
_Success Response:_
```json
{
  "status": "PriceUpdated"
}
```
**Errors**:
- `0x...`: `OwnableUnauthorizedAccount`

## Contributing

We welcome contributions to this project! If you're interested in improving the Decentralized Oracle Adapters, please refer to the detailed guidelines in the `CONTRIBUTION.md` file.

Here's a summary of the contribution process:

*   🛠️ Fork the repository and create your feature branch.
*   🧪 Ensure all Forge tests pass before submitting a Pull Request.
*   📝 Document all new logic using NatSpec format.
*   🤝 Adhere to the Contributor Code of Conduct outlined in `CONTRIBUTION.md`.
*   Follow the conventional commits standard (e.g., `feat: Add new adapter for X`) for clear commit messages.
*   Open a Pull Request with a clear description of your changes and reference any related issues.

## License

This project is licensed under the BUSL-1.1 License.

## Author Info

*   **Developer Name**: olujimiAdebakin
*   **Email**: omoladebu231@gmail.com
*   **LinkedIn**: []
*   **Twitter**: [@olujimi_the_dev]

![Solidity](https://img.shields.io/badge/Solidity-%23363636.svg?style=for-the-badge&logo=solidity&logoColor=white)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4.svg?style=for-the-badge&logo=openzeppelin&logoColor=white)
![Foundry](https://img.shields.io/badge/Foundry-black.svg?style=for-the-badge&logo=foundry&logoColor=white)

