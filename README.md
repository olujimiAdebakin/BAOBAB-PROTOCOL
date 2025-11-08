# BAOBAB Protocol 🌳

<div align="center">

![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.24-363636.svg)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)
![License](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)

**The First Composable Trading Primitive Protocol**

*Named after the resilient African Baobab tree—built to withstand volatility and serve diverse markets with unprecedented composability.*

[Documentation](docs/) • [Quick Start](#-quick-start) • [Architecture](#-architecture) • [Contributing](#-contributing)

---

</div>

## 🌍 Overview

BAOBAB Protocol is the **first decentralized exchange where orders become tradeable assets**. Unlike traditional DEXs where your order is just a database entry, BAOBAB mints every limit order as an NFT you can stake, collateralize, trade, or bundle into tokenized strategies—all while waiting for fills.

Built on a unified order book with specialized support for African and emerging market assets, BAOBAB combines DeFi composability with CEX-grade execution quality.

**The Innovation:** Your pending orders are no longer dead capital. They're productive assets earning yield, serving as collateral, or representing fund shares—before they even fill.

## 🎯 Key Features

### ⚡ Hybrid Execution Engine

**CLOB + AMM Model**: Best of both worlds with intelligent routing.

- **CLOB (Central Limit Order Book)**: Limit orders match peer-to-peer for best prices
- **AMM Vault**: Market orders execute instantly against protocol liquidity
- **Advanced Order Types**: 
  - **Market**: Instant execution at current price
  - **Limit**: Execute at specified price or better
  - **Scale**: Split large orders across multiple price levels (reduces slippage)
  - **TWAP**: Time-weighted execution over specified duration (minimizes market impact)
- **Smart Routing**: Protocol automatically routes to best execution venue
- **Unified Liquidity**: Single pool serves both CLOB and AMM trading

---

### 🎨 Orders as Composable NFTs ⭐ (Industry First)

Every limit order mints as an ERC-721 NFT, transforming dead capital into productive DeFi assets.

- **Tradeable**: Sell pending orders on OpenSea while waiting for fills
- **Stakeable**: Earn governance rewards on unfilled orders
- **Collateralizable**: Borrow up to 50% LTV without canceling
- **Bundleable**: Create tokenized strategy funds from multiple orders

**Example:** Place $100k buy order → Stake NFT (earn rewards) → Borrow $50k (use elsewhere) → Order fills → Repay loan → Keep tokens + staking profits

---

### ⚡ Gasless Execution Model

One approval, no more transaction signing. Keeper-powered execution with prepaid fees.

- User pays $2-3 execution fee upfront
- Keeper bots execute orders automatically (5-10 sec batches)
- User never signs again after initial approval
- Batch execution prevents front-running
- 96% gas savings vs sequential matching

---

### 🔄 Unified Liquidity Engine

One order book powers spot, perps, and all trading—no fragmented liquidity.

- Spot traders and perp traders share the same liquidity pool
- DAO market maker provides additional depth
- Better prices and tighter spreads than siloed venues
- Capital efficiency: LPs serve multiple markets simultaneously

---

### 🏛️ DAO-Controlled Market Making ⭐

Protocol-owned liquidity actively trades with governance oversight.

- Treasury places limit orders on both sides (buy/sell)
- Maintains target spreads (e.g., 0.3-0.5% bid-ask)
- Earns trading profits for token stakers
- Backstops liquidity during thin markets
- Fully transparent onchain performance

---

### 💰 Order Collateralization ⭐ (Industry First)

Borrow against pending orders without canceling them.

- Place order (e.g., Buy 100 ETH @ $1,950)
- Borrow up to 50% of order value ($97.5k)
- Order fills while collateralized → tokens in escrow
- Repay loan → receive filled tokens
- 5-12% APR interest (utilization-based)

---

### 🌳 Tokenized Strategy Baskets ⭐

**Order Baskets** (Our Innovation): Bundle multiple orders into non-custodial funds.

- Manager places 10-20 orders representing strategy
- Tokenize as ERC-20 (e.g., "BAOBAB-VOL" with 10k shares)
- Investors buy shares without trusting manager with funds
- Profits distribute automatically onchain
- Manager earns % fee, can't steal capital

**Asset Baskets** (Traditional): Hold underlying tokens directly with auto-rebalancing.

---

### 📊 Cross-Margin Perpetuals

Trade with up to 100x leverage using unified collateral.

- One collateral pool supports multiple positions
- Portfolio-level liquidation (safer than isolated)
- Profits from one position offset losses in another
- Funding rates balance long/short demand
- Insurance fund backstop for extreme events

---

### 🎯 Event Derivatives & Prediction Markets

Trade on real-world events with transparent settlement.

- **Political**: Elections, policy votes, appointments
- **Economic**: Central bank decisions, GDP, inflation
- **Sports**: AFCON, continental championships
- **African Focus**: Nigerian elections, CBN rates, regional events

---

### 🛡️ Enterprise-Grade Security

Multi-layered protection for protocol and users.

- Multi-signature admin controls (3-of-5)
- 72-hour timelock on critical operations
- Circuit breakers for extreme volatility
- Multi-oracle architecture (Chainlink + Pyth + TWAP)
- Comprehensive testing (unit, integration, fuzz, fork)

---

## 🏆 How BAOBAB Compares

| Feature | Uniswap | GMX | dYdX | Hyperliquid | **BAOBAB** |
|---------|---------|-----|------|-------------|------------|
| **Orders as NFTs** | ❌ | ❌ | ❌ | ❌ | ✅ **UNIQUE** |
| **Order Collateralization** | ❌ | ❌ | ❌ | ❌ | ✅ **UNIQUE** |
| **Strategy Tokenization** | ❌ | ❌ | ❌ | ❌ | ✅ **UNIQUE** |
| **DAO Market Making** | ❌ | ❌ | ❌ | ❌ | ✅ **UNIQUE** |
| **CLOB + AMM Hybrid** | AMM | AMM | CLOB | CLOB | ✅ **Both** |
| **Scale/TWAP Orders** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **Gasless Execution** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Spot + Perps** | Spot | Perps | Perps | Perps | Both |
| **African Assets** | ❌ | ❌ | ❌ | ❌ | ✅ **UNIQUE** |

---

## 🌍 African Market Focus

Purpose-built for African and emerging markets with specialized infrastructure.

### Supported Assets (Launch)

**Equities**: DANGCEM, MTNN, GTCO, ZENITHBANK (Nigerian stocks)  
**Forex**: NGN/USD, GHS/USD, KES/USD, ZAR/USD  
**Commodities**: Brent Crude, Gold, Cocoa, Coffee  

### Regional Events

- Nigerian presidential elections
- Central bank rate decisions (CBN, SARB)
- AFCON tournament outcomes
- Currency intervention predictions

### Infrastructure

- Regional RPC nodes (Lagos, Nairobi, Johannesburg)
- Local oracle partnerships for African asset pricing
- Mobile-first UI for African users
- Trading hours aligned with African market sessions

---

## 📜 Project Status

**Current Phase**: Core Implementation (75% Complete)

**Complete:**
- ✅ System architecture and design
- ✅ Core contract scaffolding
- ✅ Order NFT framework
- ✅ Execution fee model
- ✅ Testing infrastructure

**In Progress:**
- 🔄 Order book matching engine (90%)
- 🔄 Perpetuals engine (80%)
- 🔄 LP Vault and lending pool (75%)
- 🔄 Keeper bot implementation (10%)
- 🔄 Frontend interface (10%)

**Timeline:**
- **Q3 2026**: Testnet launch (Arbitrum Sepolia)
- **Q3 2026**: External audit + Mainnet launch
- **Q4 2026**: African asset integration
- **2027**: Multi-chain expansion + governance activation

---

## 🏗️ Architecture

```
protocol-contracts/
├── src/
│   ├── core/                                      # Core protocol logic
│   │   ├── trading/                               # Trading engines
│   │   │   ├── engines/
│   │   │   │   ├── AutoDeleverageEngine.sol        # ADL logic for solvency backstop
│   │   │   │   ├── CrossMarginEngine.sol         # Cross-margin perpetuals
│   │   │   │   ├── PerpEngine.sol                # Perpetual futures engine
│   │   │   │   ├── SpotEngine.sol                # Spot trading engine
│   │   │   │   └── OrderBook.sol                 # CLOB limit order matching
│   │   │   ├── FundingRateCalculator.sol         # Perp funding rate logic
│   │   │   ├── LiquidationEngine.sol             # Position liquidation
│   │   │   ├── OrderManager.sol                  # Order lifecycle management
│   │   │   └── PositionManager.sol               # Position tracking
│   │   ├── events/                               # Event derivatives system
│   │   │   ├── EmergencyEvent.sol                # Unscheduled event markets
│   │   │   ├── EventDerivative.sol               # Base event contract
│   │   │   ├── EventFactory.sol                  # Create new event markets
│   │   │   ├── EventSettlement.sol               # Settle event outcomes
│   │   │   ├── OutcomeVerifier.sol               # Verify event results
│   │   │   └── ScheduledEvent.sol                # Scheduled event markets
│   │   ├── markets/                              # Market factory and management
│   │   │   ├── MarketFactory.sol                 # Create new trading markets
│   │   │   ├── MarketRegistry.sol                # Track all markets
│   │   │   ├── PriceFeedAdapter.sol              # Connect price feeds
│   │   │   ├── RiskParameterManager.sol          # Market risk settings
│   │   │   └── TradingSchedule.sol               # Market hours/sessions
│   │   ├── oracles/                              # Multi-oracle price feed system
│   │   │   ├── adapters/
│   │   │   │   ├── ChainlinkAdapter.sol          # Chainlink integration
│   │   │   │   ├── ComputedOracle.sol            # Derived prices
│   │   │   │   ├── PythAdapter.sol               # Pyth Network integration
│   │   │   │   ├── TrustedOracle.sol             # Manual/trusted feeds
│   │   │   │   └── TWAPAdapter.sol               # Time-weighted average
│   │   │   ├── OracleRegistry.sol                # Oracle management
│   │   │   └── OracleSecurity.sol                # Price validation
│   │   └── data/                                 # Protocol data storage
│   │       ├── DataStore.sol                     # Core data storage
│   │       ├── DataStoreUtils.sol                # Storage helpers
│   │       ├── DataTypes.sol                     # Data type definitions
│   │       └── OrderStorage.sol                  # Order book data
│   ├── baskets/                                  # Tokenized basket engine
│   │   ├── BasketEngine.sol                      # Core basket logic
│   │   ├── BasketFactory.sol                     # Create basket products
│   │   ├── BasketPricing.sol                     # Basket valuation
│   │   ├── BasketTypes.sol                       # Basket data type definitions
│   │   └── RebalancingEngine.sol                 # Auto-rebalancing logic
│   ├── vaults/                                   # Capital management
│   │   ├── InsuranceVault.sol                    # Insurance fund
│   │   ├── LiquidityVault.sol                    # LP vault
│   │   ├── TreasuryVault.sol                     # Protocol treasury
│   │   └── VaultManager.sol                      # Vault coordination
│   ├── routers/                                  # User-facing interaction layer
│   │   ├── BasketRouter.sol                      # Basket operations
│   │   ├── CoreRouter.sol                        # Main entry point
│   │   ├── EventRouter.sol                       # Event trading
│   │   ├── TradingRouter.sol                     # Trading operations
│   │   └── VaultRouter.sol                       # Vault interactions
│   ├── readers/                                  # View functions and analytics
│   │   ├── BasketReader.sol                      # Basket data queries
│   │   ├── EventReader.sol                       # Event data queries
│   │   ├── OrderBookReader.sol                   # Order book queries
│   │   ├── PortfolioReader.sol                   # User portfolio data
│   │   ├── ProtocolReader.sol                    # Protocol stats
│   │   ├── RiskReader.sol                        # Risk metrics
│   │   └── TradingReader.sol                     # Trading data queries
│   ├── fees/                                     # Fee calculation and distribution
│   │   ├── FeeCalculator.sol                     # Calculate fees
│   │   ├── FeeDistributor.sol                    # Distribute fees
│   │   ├── IncentiveManager.sol                  # Manage incentives
│   │   └── RevenueManager.sol                    # Revenue tracking
│   ├── access/                                   # Role-based access control
│   │   ├── AccessManager.sol                     # Central access control
│   │   ├── ProtocolOwner.sol                     # Owner functions
│   │   └── RoleRegistry.sol                      # Role definitions
│   ├── security/                                 # Security systems
│   │   ├── CircuitBreaker.sol                    # Auto-pause on anomalies
│   │   ├── EmergencyPauser.sol                   # Emergency pause
│   │   ├── RateLimiter.sol                       # Rate limiting
│   │   ├── SecurityBase.sol                      # Base for common security features (e.g., ReentrancyGuard)
│   │   └── TokenRescue.sol                       # Mechanism to recover stuck funds
│   ├── tokens/                                   # Token implementations
│   │   ├── erc20/
│   │   │   ├── BasketShareToken.sol              # Basket share tokens
│   │   │   ├── VaultShareToken.sol               # Vault LP tokens (BLP)
│   │   │   └── BAOBABToken.sol                   # Governance + reward token
│   │   └── erc721/
│   │       ├── BasketNFT.sol                     # Basket NFTs
│   │       └── OrderNFT.sol                      # Order NFTs (composability)
│   ├── governance/                               # Governance module
│   │   ├── BAOBABGovernor.sol                    # Main voting contract
│   │   ├── TimelockController.sol                # 72h delay executor
│   │   ├── ProposalFactory.sol                   # Helper to create proposals
│   │   └── interfaces/                           # Governance interfaces
│   │       ├── IBAOBABGovernor.sol               # Governor interface
│   │       └── ITimelock.sol                     # Timelock interface
│   └── libraries/                                # Reusable utility libraries
│       ├── arrays/
│       │   ├── ArrayUtils.sol                    # Array manipulation
│       │   └── SortUtils.sol                     # Sorting algorithms
│       ├── interfaces/                           # External contract interfaces
│       │   └── IERC165.sol                       # Interface detection standard (ERC-165)
│       ├── math/
│       │   ├── FixedPointMath.sol                # Fixed-point arithmetic
│       │   ├── PercentageMath.sol                # Percentage calculations
│       │   └── Statistics.sol                    # Statistical functions
│       ├── structs/
│       │   ├── BasketStructs.sol                 # Basket data structures
│       │   ├── CommonStructs.sol                 # Shared structures
│       │   ├── EventStructs.sol                  # Event data structures
│       │   └── TradingStructs.sol                # Trading data structures
│       └── utils/
│           ├── AddressUtils.sol                  # Address utilities
│           ├── SafeTransfer.sol                  # Safe token transfers
│           └── TimeUtils.sol                     # Time utilities
├── test/                                         # Comprehensive test suite
│   ├── unit/                                     # Unit tests
│   │   ├── Access.t.sol
│   │   ├── Baskets.t.sol
│   │   ├── Events.t.sol
│   │   ├── Governance.t.sol
│   │   ├── Markets.t.sol
│   │   ├── OrderBook.t.sol
│   │   ├── Oracles.t.sol
│   │   ├── Trading.t.sol
│   │   └── Vaults.t.sol
│   ├── integration/                              # Integration tests
│   │   ├── BasketFlow.t.sol
│   │   ├── CrossMarginFlow.t.sol
│   │   ├── EventFlow.t.sol
│   │   ├── GovernanceFlow.t.sol
│   │   ├── LiquidationFlow.t.sol
│   │   ├── OrderBookFlow.t.sol
│   │   ├── TradingFlow.t.sol
│   │   └── VaultFlow.t.sol
│   ├── fuzz/                                     # Invariant/fuzz tests
│   │   ├── BasketInvariants.t.sol
│   │   ├── OrderBookInvariants.t.sol
│   │   ├── TradingInvariants.t.sol
│   │   └── VaultInvariants.t.sol
│   └── security/                                 # Security tests
│       ├── EdgeCases.t.sol
│       ├── LiquidationAttack.t.sol
│       ├── OracleAttack.t.sol
│       ├── OrderBookAttack.t.sol
│       └── RateLimitTest.t.sol
├── script/                                       # Deployment and operations
│   ├── deploy/                                   # Deployment scripts
│   │   ├── 01_Core.s.sol
│   │   ├── 02_Trading.s.sol
│   │   ├── 03_Markets.s.sol
│   │   ├── 04_Events.s.sol
│   │   ├── 05_Baskets.s.sol
│   │   ├── 06_Vaults.s.sol
│   │   ├── 07_Routers.s.sol
│   │   ├── 08_Governance.s.sol
│   │   └── 09_Initialize.s.sol
│   └── operations/                               # Operational scripts
│       ├── baskets/
│       │   ├── CreateBasket.s.sol
│       │   └── RebalanceBasket.s.sol
│       ├── events/
│       │   ├── CreateEvent.s.sol
│       │   └── SettleEvent.s.sol
│       ├── markets/
│       │   ├── AddMarket.s.sol
│       │   ├── UpdateRiskParams.s.sol
│       │   └── WhitelistOracle.s.sol
│       ├── governance/
│       │   ├── ProposeRewardMint.s.sol
│       │   ├── ProposeMarketMaking.s.sol
│       │   └── ExecuteProposal.s.sol
│       └── emergency/
│           └── EmergencyPause.s.sol
├── config/                                       # Configuration files
├── docs/                                         # Technical documentation
└── keeper-bots/                                  # Off-chain automation services
```

### Key Components

| Component | Purpose |
|-----------|---------|
| **OrderBook.sol** | CLOB matching engine for limit orders |
| **SpotEngine.sol** | AMM vault for instant market execution |
| **Order NFTs** | ERC-721 composable order representation |
| **Execution Fee Manager** | Gasless execution economics and keeper compensation |
| **Order Baskets** | Bundle orders into tokenized strategy funds |
| **LP Vault** | Multi-purpose liquidity for leverage, loans, market making |
| **DAO Market Maker** | Protocol-owned active liquidity provision |
| **Keeper Registry** | Authorization and rewards for automation bots |

---

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest)
- [Node.js](https://nodejs.org/) v18+
- Git with submodule support

### Installation

```bash
# Clone repository
git clone https://github.com/baobab-protocol/protocol-contracts.git
cd protocol-contracts

# Install dependencies
forge install
cd keeper-bots && pnpm install && cd ..

# Setup environment
cp .env.example .env
# Edit .env with your keys
```

### Basic Commands

```bash
# Compile contracts
forge build

# Run tests
forge test

# Deploy to testnet
forge script script/deploy/DeployAll.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast --verify

# Run keeper bot
cd keeper-bots && pnpm start
```

---

## 📚 Documentation

Comprehensive docs in `/docs`:

| Document | Description |
|----------|-------------|
| [Architecture Overview](docs/architecture/overview.md) | System design and component interaction |
| [Order NFT Composability](docs/architecture/nft-composability.md) | How orders become tradeable assets |
| [Gasless Execution](docs/architecture/gasless-execution.md) | Execution fees and keeper economics |
| [Trading Engine](docs/architecture/trading-engine.md) | Order book, perps, and margin system |
| [Keeper System](docs/architecture/keeper-system.md) | Bot architecture and profitability |
| [API Reference](docs/developer-guides/api-reference.md) | Contract interfaces |
| [Integration Guide](docs/developer-guides/integration-guide.md) | Build on BAOBAB |

---

## 🛠️ Technology Stack

| Technology | Purpose |
|------------|---------|
| **Solidity ^0.8.24** | Smart contract language |
| **Foundry** | Development and testing framework |
| **OpenZeppelin** | Security primitives |
| **Chainlink** | Primary oracle network |
| **Pyth Network** | Low-latency price feeds |
| **ERC-721** | Order NFT standard |
| **ERC-4626** | Vault token standard |
| **EIP-712** | Gasless signature standard |

---

## 🛡️ Security

**Audit Status:**
- ✅ Internal review complete
- ⏳ External audit scheduled Q3 2025 (Trail of Bits)
- ⏳ Bug bounty launching Q3 2025 ($500k pool)

**Security Features:**
- Multi-signature controls (3-of-5)
- 72-hour timelock on upgrades
- Circuit breakers on all trading
- Multi-oracle price validation
- Insurance fund ($5M+ target)

**Report Vulnerabilities:** security@baobabprotocol.xyz  
**Bug Bounty:** Up to $100k for critical findings (launching Q3 2025)

---

## ❓ FAQ

**Q: What makes BAOBAB different?**  
A: Orders become NFTs you can stake, collateralize, or bundle into funds. No other DEX offers this composability.

**Q: Why the 5-10 second delay?**  
A: Batch processing saves 96% on gas and prevents front-running. Tiny delay, massive benefits.

**Q: Is BAOBAB live?**  
A: Testnet Q2 2025, mainnet Q3 2025. Join [Discord](https://discord.gg/baobabprotocol) for updates.

**Q: Can I become a keeper?**  
A: Yes! Launching Q2 2025. Stake BAOBAB tokens, run our bot, earn ~$500-1000/day. Details in [Keeper Guide](docs/developer-guides/keeper-guide.md).

**Q: Why focus on Africa?**  
A: 1.4B people, $3T GDP, massively underserved by DeFi. We're building infrastructure Africa needs.

**Q: What's the difference between CLOB and AMM?**  
A: CLOB matches limit orders peer-to-peer. AMM executes market orders instantly against protocol liquidity. BAOBAB uses both for optimal execution.

---

## 🤝 Contributing

We welcome contributions! Areas we need help:

- 🧪 Test coverage expansion
- 📝 Documentation improvements
- 🐛 Bug fixes and optimizations
- 🌍 African market integration
- 🔐 Security reviews

**Process:**
1. Fork repository
2. Create feature branch
3. Write tests for new features
4. Submit pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## 📄 License

Business Source License 1.1 (BUSL-1.1). See [LICENSE](LICENSE) for details.

Commercial licensing inquiries: partnerships@baobabprotocol.xyz

---

## 🙏 Acknowledgments

- Inspired by the resilient African Baobab tree
- Built on the shoulders of the DeFi ecosystem
- Supported by the African developer community

**Core Contributor**: [Adebakin Olujimi](https://twitter.com/olujimi_the_dev)

---

<div align="center">

**BAOBAB Protocol - Building the Future of African DeFi** 🌳

*"Like the Baobab tree, we're built to withstand storms and provide shelter for generations."*

[Website](https://baobabprotocol.xyz) • [Twitter](https://twitter.com/baobabprotocol) • [Discord](https://discord.gg/baobabprotocol) • [Docs](https://docs.baobabprotocol.xyz)

</div>