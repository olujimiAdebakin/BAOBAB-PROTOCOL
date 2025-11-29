# BAOBAB Protocol Perpetual DEX Core Contracts 🔗

## Overview
This repository hosts the foundational Solidity smart contracts for the BAOBAB Protocol, a decentralized perpetual exchange (DEX). It provides robust on-chain infrastructure for managing perpetual futures positions, dynamic funding rates, a sophisticated auto-deleverage (ADL) mechanism, and a flexible oracle integration layer to ensure secure and efficient decentralized trading.

## Features
*   **Position Management**: Handles the full lifecycle of perpetual futures positions, including opening, modifying, and closing, with real-time collateral, PnL, and liquidation price tracking.
*   **Dynamic Funding Rates**: Implements a `FundingRateEngine` to calculate and apply periodic funding rates based on open interest (OI) skew, maintaining market balance and peg.
*   **Auto-Deleverage (ADL)**: Features a robust `AutoDeleverageEngine` designed to protect the insurance fund by automatically deleveraging the most profitable opposing positions in extreme market conditions, inspired by leading CEX risk models.
*   **Decentralized Oracles**: Integrates an `OracleRegistry` supporting multiple price feeds (e.g., Chainlink, Pyth) and custom adapters to ensure reliable and secure price data for all markets.
*   **Market Configuration**: Allows for granular configuration of market-specific risk parameters, including maintenance margins, initial margins, and maximum leverage, categorized by liquidity tiers.
*   **Event & Market Factories**: Provides factory contracts for creating and managing derivative events and perpetual markets, ensuring a modular and scalable architecture.

## Getting Started
### Installation
To set up the project locally, follow these steps:

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    cd BAOBAB-PROTOCOL
    ```

2.  **Install Dependencies**:
    This project uses Solidity, typically managed with a development environment like Hardhat or Foundry. Assuming `npm` or `forge` is installed:
    ```bash
    # For npm/Hardhat (if package.json exists)
    npm install

    # For Foundry (if foundry.toml exists)
    forge install
    ```
    If neither `package.json` nor `foundry.toml` are present, you might need to initialize a Hardhat/Foundry project and add the contracts.

3.  **Compile Smart Contracts**:
    Compile the Solidity contracts to generate their ABIs and bytecode.
    ```bash
    # Using Hardhat
    npx hardhat compile

    # Using Foundry
    forge build
    ```

### Environment Variables
This project requires certain environment variables, especially for deployment and interaction with blockchain networks. Please configure them in a `.env` file in the project root.

*   `ADMIN_ADDRESS`: The address designated as the protocol administrator. Example: `0xAdminAddressHere`
*   `ORACLE_REGISTRY_ADDRESS`: Address of the deployed Oracle Registry contract. Example: `0xOracleRegistryContractAddress`
*   `ADL_ENGINE_ADDRESS`: Address of the deployed AutoDeleverageEngine contract. Example: `0xADLEngineContractAddress`
*   `FUNDING_ENGINE_ADDRESS`: Address of the deployed FundingEngine contract. Example: `0xFundingEngineContractAddress`
*   `CIRCUIT_BREAKER_ADDRESS`: Address of the deployed CircuitBreaker contract. Example: `0xCircuitBreakerContractAddress`
*   `EMERGENCY_PAUSER_ADDRESS`: Address of the deployed EmergencyPauser contract. Example: `0xEmergencyPauserContractAddress`
*   `LIQUIDATION_ENGINE_ADDRESS`: Address of the deployed LiquidationEngine contract. Example: `0xLiquidationEngineContractAddress`
*   `INSURANCE_VAULT_ADDRESS`: Address of the protocol's insurance fund vault. Example: `0xInsuranceVaultContractAddress`
*   `RPC_URL_<NETWORK_NAME>`: RPC endpoint for a specific blockchain network (e.g., `RPC_URL_SEPOLIA`). Example: `https://sepolia.infura.io/v3/YOUR_API_KEY`
*   `PRIVATE_KEY`: Private key of the deployer/admin account. **Handle with extreme care, especially in production environments.** Example: `0x...your_private_key...`

## Usage
Interacting with the BAOBAB Protocol's smart contracts typically involves deployment to an EVM-compatible blockchain and then sending transactions to call their public functions.

### Deployment
To deploy the contracts to a local development network or a testnet:

1.  **Ensure Environment Variables are Set**: Refer to the "Environment Variables" section above.
2.  **Run Deployment Scripts**:
    ```bash
    # Example for Hardhat (assuming a deploy script is in 'scripts/')
    npx hardhat run scripts/deploy.js --network sepolia

    # Example for Foundry
    forge script script/DeployContracts.s.sol --rpc-url $RPC_URL_SEPOLIA --private-key $PRIVATE_KEY --broadcast --verify
    ```
    *Note: Replace `sepolia` with your target network and ensure your `hardhat.config.js` or `foundry.toml` is configured for it.*

### Interacting with Contracts
Once deployed, you can interact with the contracts using tools like Hardhat's console, Foundry's `cast` or `forge script`, or directly through web3 libraries in your dApp.

#### Example: Setting Market Risk Configuration
As an administrator, you might set up a new market's risk parameters:

```solidity
// Example pseudo-code for calling setMarketRiskConfig
// In a Hardhat test or script:
const positionManager = await ethers.getContractAt("PositionManager", "0xPositionManagerAddress");

const marketId = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("BTC-USD-PERP"));
const liquidityTier = 0; // Assuming HIGH = 0
const maintenanceMarginBps = 50; // 0.5%
const initialMarginBps = 100; // 1%
const maxLeverage = 100; // 100x

await positionManager.setMarketRiskConfig(
    marketId,
    liquidityTier,
    maintenanceMarginBps,
    initialMarginBps,
    maxLeverage
);

console.log(`Market ${marketId} configured.`);
```

#### Example: Opening a Position
A trading engine would call `openPosition` on the `PositionManager`:

```solidity
// Example pseudo-code for calling openPosition
// In a Hardhat test or script:
const positionManager = await ethers.getContractAt("PositionManager", "0xPositionManagerAddress");
const traderAddress = "0xTraderWalletAddress";
const marketId = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ETH-USD-PERP"));
const side = 0; // CommonStructs.Side.LONG
const size = ethers.utils.parseUnits("1", 18); // 1 ETH equivalent
const collateral = ethers.utils.parseUnits("1000", 18); // $1000 collateral
const entryPrice = ethers.utils.parseUnits("3000", 18); // $3000
const leverage = 10; // 10x leverage

await positionManager.connect(tradingEngineSigner).openPosition(
    traderAddress,
    marketId,
    side,
    size,
    collateral,
    entryPrice,
    leverage
);

console.log(`Position opened for ${traderAddress} on market ${marketId}.`);
```

## Technologies Used
| Technology         | Purpose                                     |
| :----------------- | :------------------------------------------ |
| **Solidity**       | Smart contract development language         |
| **OpenZeppelin**   | Secure, community-vetted smart contract libraries |
| **Hardhat / Foundry**| Development environments for compiling, testing, and deploying contracts |

## Contributing
We welcome contributions to the BAOBAB Protocol! To get started:

1.  **Fork the repository** 🍴.
2.  **Create a new branch** for your feature or bug fix: `git checkout -b feature/your-feature-name` or `bugfix/issue-description`.
3.  **Make your changes** and write clear, concise commit messages.
4.  **Write comprehensive tests** for your changes to ensure functionality and prevent regressions.
5.  **Ensure all tests pass** locally.
6.  **Submit a Pull Request** (PR) to the `main` branch. Provide a detailed description of your changes and why they are necessary.

## License
This project is primarily licensed under the **BUSL-1.1** and **MIT** licenses, as indicated by the `SPDX-License-Identifier` in the source code files.

## Author Info
**Adebakin Olujimi**
*   Twitter: [@olujimi_the_dev]

---
[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)