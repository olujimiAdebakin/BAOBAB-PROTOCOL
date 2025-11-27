# BAOBAB Protocol: Perpetual Decentralized Exchange (perp-dex) 🌐

## Overview
The BAOBAB Protocol is an ambitious, high-performance decentralized exchange (DEX) designed for perpetual futures, spot trading, and advanced event derivatives, with a strong focus on security, capital efficiency, and adaptability to global markets, including underserved African regions. Built on Solidity, this protocol features a robust access control system, a multi-layered security framework including circuit breakers and rate limiting, and sophisticated trading mechanisms like an Auto-Deleveraging (ADL) engine. While currently in a foundational development phase, the architecture is designed for a comprehensive suite of DeFi products.

## Features
- **Role-Based Access Control**: Hierarchical access management (Owner, Admin, Guardian, Keeper, Liquidator, etc.) for granular protocol operations and governance.
- **Advanced Security Modules**:
  - **Circuit Breaker**: Automatically halts trading during extreme price deviations, volume spikes, or liquidation cascades to prevent systemic risk.
  - **Emergency Pauser**: Granular pausing capabilities for individual modules or the entire protocol, with multi-sig and timelock integration.
  - **Rate Limiter**: Multi-layered protection against spam, DDoS, and economic attacks using token bucket, tiered limits, and gas consumption tracking.
  - **Reentrancy Guard**: Standardized protection against reentrancy vulnerabilities across all core contracts.
- **Perpetual Futures Trading**: Core infrastructure for managing leveraged positions, including dynamic margin requirements, liquidation, and funding rate mechanisms.
- **Auto-Deleveraging (ADL) Engine**: A sophisticated risk management mechanism that automatically deleverages profitable opposing positions to cover liquidation shortfalls, protecting the insurance fund.
- **Tokenized Baskets & Indices**: Framework for creating and managing tokenized asset baskets and order baskets, supporting various rebalancing strategies (manual, scheduled, threshold, dynamic).
- **Comprehensive Libraries**: Gas-optimized Solidity libraries for fixed-point math, percentage calculations, array utilities, sorting algorithms, and statistical analysis.
- **Modular & Extensible Architecture**: Designed with clearly separated concerns for markets, trading engines, oracles, fees, and vaults, allowing for future expansion.
- **Oracle Integration**: Unified interface for various price feeds (Chainlink, Pyth, TWAP, Trusted, Computed Oracles) to ensure robust and decentralized pricing.

## Getting Started
To set up the BAOBAB Protocol locally for development or testing, follow these steps.

### Installation
✨ Clone the repository:
```bash
git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
cd BAOBAB-PROTOCOL
```

⚙️ Install Hardhat (or Foundry) and project dependencies. For Hardhat:
```bash
npm install # or yarn install
```
Or if using Foundry:
```bash
forge install
```

🚀 Compile the smart contracts:
For Hardhat:
```bash
npx hardhat compile
```
For Foundry:
```bash
forge build
```

🧪 Run tests:
For Hardhat:
```bash
npx hardhat test
```
For Foundry:
```bash
forge test
```

### Environment Variables
The protocol relies on several addresses and parameters set at deployment or by the protocol administrator. These are typically passed as constructor arguments or set via administrative functions post-deployment.

*   `_admin`: `address` - Initial protocol administrator for core contracts (e.g., `AccessManager`, `EmergencyPauser`, `CircuitBreaker`, `PositionManager`).
*   `_multisig`: `address` - (For `EmergencyPauser`) An address designated for multi-signature governance actions.
*   `_accessManager`: `address` - (For `ProtocolOwner`) The deployed `AccessManager` contract address.
*   `_treasury`: `address` - (For `ProtocolOwner`) The protocol's designated treasury address.
*   `_insuranceVault`: `address` - (For `ProtocolOwner`, `AutoDeleverageEngine`) The protocol's insurance fund vault address.
*   `_feeRecipient`: `address` - (For `ProtocolOwner`) The address designated to receive protocol fees.
*   `_positionManager`: `address` - (For `FundingEngine`, `AutoDeleverageEngine`) The deployed `PositionManager` contract address.
*   `_oracleRegistry`: `address` - (For `PositionManager`) The deployed `OracleRegistry` contract address.
*   `_adlEngine`: `address` - (For `PositionManager`) The deployed `AutoDeleverageEngine` contract address.
*   `_fundingEngine`: `address` - (For `PositionManager`) The deployed `FundingEngine` contract address.
*   `_circuitBreaker`: `address` - (For `PositionManager`) The deployed `CircuitBreaker` contract address.
*   `_emergencyPauser`: `address` - (For `PositionManager`) The deployed `EmergencyPauser` contract address.

## API Documentation

The BAOBAB Protocol is a suite of Solidity smart contracts deployed on the Ethereum Virtual Machine (EVM). Interaction occurs via transaction calls to contract addresses or reading public state variables. Below are examples of key external interfaces.

### Base Contract Interactions
Interactions with BAOBAB Protocol contracts are direct Solidity function calls. Each function defines its payload and expected response.

### Endpoints (Key Contract Functions)

#### `FUNCTION CALL` `AccessManager.grantRole(bytes32 role, address account)`
**Description**: Grants a specified role to a target account. Only an account with the `adminRole` for the given `role` can execute this.
**Request**:
```solidity
// Example: Granting ADMIN_ROLE to a new address
accessManager.grantRole(RoleRegistry.ADMIN_ROLE, 0xAbC...123);
```
**Parameters**:
- `role`: `bytes32` - The identifier of the role to grant (e.g., `RoleRegistry.ADMIN_ROLE`).
- `account`: `address` - The address of the account to which the role will be granted.
**Response**:
*   No direct return value. Emits a `RoleGranted` event on success.
**Errors**:
- `AccessManager__UnauthorizedRoleAdmin()`: If the caller does not hold the necessary administrative role for `role`.
- `AccessManager__AlreadyHasRole()`: If `account` already possesses the `role`.
- `AccessManager__InvalidAddress()`: If `account` is the zero address.

#### `FUNCTION CALL` `PositionManager.openPosition(address trader, bytes32 marketId, CommonStructs.Side side, uint256 size, uint256 collateral, uint256 entryPrice, uint16 leverage)`
**Description**: Opens a new perpetual trading position for a given trader on a specific market. Performs comprehensive risk checks including initial margin and max leverage.
**Request**:
```solidity
// Example: Opening a 10x LONG position on BTC-USD
positionManager.openPosition(
    0xDef...456, // trader address
    keccak256("BTC-USD"), // marketId
    CommonStructs.Side.LONG, // side
    1 ether, // size (1 BTC, assuming 1e18 decimals)
    0.005 ether, // collateral (e.g., 0.005 ETH)
    30000 ether, // entryPrice ($30,000)
    10 // leverage (10x)
);
```
**Parameters**:
- `trader`: `address` - The address of the user opening the position.
- `marketId`: `bytes32` - The unique identifier of the market.
- `side`: `CommonStructs.Side` - The direction of the position (`LONG` or `SHORT`).
- `size`: `uint256` - The notional size of the position in base asset units (e.g., BTC, ETH), scaled to 18 decimals.
- `collateral`: `uint256` - The collateral amount provided in quote asset units (e.g., USD, USDC), scaled to 18 decimals.
- `entryPrice`: `uint256` - The entry price of the position, scaled to 18 decimals.
- `leverage`: `uint16` - The leverage multiplier for the position (e.g., `10` for 10x).
**Response**:
- `positionId`: `bytes32` - The unique identifier for the newly created position. Emits a `PositionOpened` event.
**Errors**:
- `PositionManager__OnlyTradingEngine()`: If the caller is not the authorized `tradingEngine`.
- `PositionManager__CircuitBroken()`: If the market or global circuit breaker is active.
- `PositionManager__Paused()`: If the protocol or `PositionManager` module is paused.
- `PositionManager__InvalidSize()`: If `size` is zero or invalid.
- `PositionManager__InsufficientCollateral()`: If `collateral` is zero or insufficient to meet initial margin.
- `PositionManager__MarketNotConfigured()`: If `marketId` is not configured or inactive.
- `PositionManager__LeverageExceedsMax()`: If `leverage` exceeds the market's maximum allowed.
- `PositionManager__InsufficientInitialMargin()`: If `collateral` does not meet the initial margin requirement.

#### `FUNCTION CALL` `AutoDeleverageEngine.executeADL(bytes32 marketId, bytes32 liquidatedPosition, CommonStructs.Side side, uint256 sizeToClose, uint256 executionPrice)`
**Description**: Triggers the Auto-Deleveraging (ADL) process to force-close profitable opposing positions when a liquidation cannot be fully covered by the insurance fund.
**Request**:
```solidity
// Example: ADL triggered for a failed LONG liquidation on BTC-USD
adlEngine.executeADL(
    keccak256("BTC-USD"), // marketId
    0xAAAA...BBBB, // liquidatedPositionId
    CommonStructs.Side.LONG, // side of liquidated position (ADL targets SHORTs)
    5 ether, // sizeToClose (e.g., 5 BTC notional)
    28000 ether // executionPrice ($28,000)
);
```
**Parameters**:
- `marketId`: `bytes32` - The identifier of the market where ADL is triggered.
- `liquidatedPosition`: `bytes32` - The unique ID of the position that failed to liquidate normally.
- `side`: `CommonStructs.Side` - The side of the `liquidatedPosition` (`LONG` or `SHORT`). ADL will target positions on the *opposite* side.
- `sizeToClose`: `uint256` - The total notional size that needs to be covered by ADL, scaled to 18 decimals.
- `executionPrice`: `uint256` - The price at which deleveraged positions will be closed, scaled to 18 decimals.
**Response**:
- `success`: `bool` - True if the ADL process successfully covered the `sizeToClose`, false otherwise. Emits `ADLTriggered` and `PositionDeleveraged` events.
**Errors**:
- `ADL__OnlyLiquidationEngine()`: If the caller is not the authorized `liquidationEngine`.
- `ADL__ADLNotEnabled()`: If ADL is disabled for the specified `marketId`.
- `ADL_ENGINE__Paused()`: If the ADL engine or protocol is paused.
- `ADL__CircuitActive()`: If the circuit breaker is active for the market.
- `ADL__InsufficientCandidates()`: If there are not enough profitable positions on the opposing side in the ADL queue to cover `sizeToClose`.

## Usage

### Smart Contract Deployment
To deploy the BAOBAB Protocol, you'll typically use a deployment script with Hardhat or Foundry. The order of deployment is crucial due to inter-contract dependencies. A recommended deployment flow:

1.  **Libraries**: Deploy `FixedPointMath`, `PercentageMath`, `Statistics`, `ArrayUtils`, `SortUtils`, `AddressUtils`, `ModuleIds`, `TimeUtils`, `SafeTransfer`. (These are `library` contracts or `abstract` contracts, so they might not need direct deployment but are linked).
2.  **Core Security**: Deploy `SecurityBase` (abstract), `RoleRegistry` (library), then `AccessManager`.
3.  **Owner & Pauser**: Deploy `EmergencyPauser` (with `_admin`, `_multisig`) and `CircuitBreaker` (with `_admin`). Then deploy `ProtocolOwner` (with `_accessManager`, `_treasury`, `_insuranceVault`, `_feeRecipient`).
4.  **Trading & Risk Infrastructure**: Deploy `PositionManager` (with addresses for `_admin`, `_oracleRegistry`, `_adlEngine`, `_fundingEngine`, `_circuitBreaker`, `_emergencyPauser`).
5.  **Engines**: Deploy `FundingRateEngine` (with `_positionManager`, `_accessManager`), `AutoDeleverageEngine` (with `_admin`, `_liquidationEngine`, `_insuranceVault`, `_positionManager`).
6.  **Set Dependencies**: Crucially, use administrative functions (e.g., `PositionManager.setTradingEngine`, `setLiquidationEngine`, `setFundingEngine`) to link the deployed contracts together.

### Example Interaction: Configuring a Market and Opening a Position

Let's assume `AccessManager` and `PositionManager` are deployed.

1.  **Set Market Risk Configuration**: As `BaobabAdmin`, define the risk parameters for a new market.
    ```solidity
    // In a Hardhat script or direct contract interaction:
    bytes32 btcUsdMarketId = keccak256("BTC-USD");
    positionManager.setMarketRiskConfig(
        btcUsdMarketId,
        PositionManager.LiquidityTier.HIGH, // e.g., BTC/ETH
        50,  // maintenanceMarginBps = 0.5%
        100, // initialMarginBps = 1%
        100  // maxLeverage = 100x
    );
    ```

2.  **Set Trading Engine**: As `BaobabAdmin`, authorize the `TradingEngine` (once implemented) to interact with `PositionManager`.
    ```solidity
    // Assuming tradingEngineAddress is the deployed TradingRouter/TradingEngine
    positionManager.setTradingEngine(tradingEngineAddress);
    ```

3.  **Open a Position**: A user (or `TradingEngine` on their behalf) can now open a position.
    ```solidity
    // This call would typically come from the TradingRouter or a wrapper contract
    // For demonstration, assume direct call (but in reality, TradingEngine would call this)
    address trader = 0xUserWalletAddress;
    uint256 size = 10 ether; // 10 units of BTC
    uint256 collateral = 0.5 ether; // 0.5 ETH collateral
    uint256 entryPrice = 60000 ether; // BTC @ $60,000
    uint16 leverage = 20; // 20x leverage

    positionManager.openPosition(
        trader,
        btcUsdMarketId,
        CommonStructs.Side.LONG,
        size,
        collateral,
        entryPrice,
        leverage
    );
    ```

This detailed architecture facilitates a robust and secure DeFi trading environment, allowing for complex financial instruments while prioritizing user safety and protocol stability.

## Features List
*   **Decentralized Access Control**: Granular, hierarchical role management to secure critical protocol functions and ensure operational integrity.
*   **Comprehensive Security Layers**: Integration of `CircuitBreaker`, `EmergencyPauser`, and `RateLimiter` to safeguard against market volatility, external attacks, and governance exploits.
*   **Perpetual Futures Engine**: Core logic for managing leveraged positions, margin, PnL calculation, and dynamic liquidation processes.
*   **Automated Risk Management (ADL)**: Proactive Auto-Deleveraging system to socialize liquidation losses among profitable traders, protecting the insurance fund.
*   **Modular Architecture**: Clearly defined contract roles and interfaces enable independent development, upgrades, and audits of protocol components.
*   **High-Precision Math Libraries**: Custom `FixedPointMath` and `PercentageMath` for accurate and gas-efficient financial calculations.
*   **Data Structure Optimization**: Extensive use of `structs` and internal `mappings` with gas-efficient array utilities (`ArrayUtils`, `SortUtils`) for efficient state management.
*   **Dynamic Market Configuration**: Flexible parameters for setting market-specific risk tiers, leverage limits, and margin requirements.
*   **Extensible Oracle Framework**: Support for various oracle adapters to provide reliable and decentralized price feeds for all markets.
*   **Governance Integration**: Designed to be upgradable and configurable via a future DAO, ensuring community-driven evolution.

## Technologies Used
| Technology         | Category           | Description                                                                     | Link                                                                      |
| :----------------- | :----------------- | :------------------------------------------------------------------------------ | :------------------------------------------------------------------------ |
| **Solidity**       | Smart Contract     | Primary language for developing secure and robust decentralized applications.   | [soliditylang.org](https://soliditylang.org/)                             |
| **Hardhat / Foundry** | Development Tools  | Development environment for compiling, testing, and deploying Solidity contracts. | [hardhat.org](https://hardhat.org/) / [getfoundry.sh](https://getfoundry.sh/) |
| **OpenZeppelin Contracts** | Libraries        | Standard, tested smart contracts for security and common patterns (e.g., ERC20, IERC165). | [openzeppelin.com/contracts](https://docs.openzeppelin.com/contracts/4.x/) |
| **BUSL-1.1 License** | Licensing          | Business Source License for controlled initial use, then open-source.           | [spdx.org/licenses/BUSL-1.1.html](https://spdx.org/licenses/BUSL-1.1.html) |
| **Ethereum Virtual Machine (EVM)** | Runtime Environment | The runtime environment for smart contracts in the Ethereum ecosystem.          | [ethereum.org/en/developers/docs/evm](https://ethereum.org/en/developers/docs/evm/) |
| **IPFS**           | Storage            | Decentralized storage for off-chain metadata (e.g., event descriptions).        | [ipfs.io](https://ipfs.io/)                                               |
| **Chainlink / Pyth** | Oracles            | Decentralized oracle networks for reliable price data feeds.                    | [chain.link](https://chain.link/) / [pyth.network](https://pyth.network/) |

## Contributing
We welcome contributions to the BAOBAB Protocol! To get started:

*   ✨ **Fork the repository** and clone it to your local machine.
*   🌟 **Create a new branch** for your feature or bug fix: `git checkout -b feature/your-feature-name`.
*   🛠️ **Set up your development environment** (Hardhat or Foundry, as described in "Installation").
*   📝 **Write clear, concise, and well-documented code**. Adhere to existing coding styles and best practices.
*   🧪 **Write unit and integration tests** for any new features or bug fixes. Ensure all tests pass.
*   ✅ **Ensure test coverage** remains high.
*   ⬆️ **Push your changes** to your fork.
*   🤝 **Open a Pull Request** to the `main` branch, providing a detailed description of your changes and why they are necessary.

Please ensure your work aligns with the project's vision for a secure, efficient, and scalable DeFi protocol.

## License
This project is primarily licensed under the **Business Source License 1.1 (BUSL-1.1)**. Some components may inherit or incorporate code under the MIT License, as indicated by their respective SPDX license identifiers. For full details, please refer to the license headers in the source code files.

## Author Info

**Olujimi Adebakin**
*   LinkedIn: [linkedin.com/in/olujimiadebakin](https://linkedin.com/in/olujimiadebakin)
*   Twitter: [@olujimiadebakin](https://twitter.com/olujimiadebakin)

---
[![Readme was generated by Dokugen](https://img.shields.io/badge/Readme%20was%20generated%20by-Dokugen-brightgreen)](https://www.npmjs.com/package/dokugen)