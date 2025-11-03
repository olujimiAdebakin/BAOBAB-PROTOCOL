# BAOBAB Protocol 🌳

<div align="center">

![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.24-363636.svg)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)
![License](https://img.shields.io/badge/License-BUSL--1.1-blue.svg)

**The Resilient DeFi Protocol for African and Global Markets**

*Named after the resilient African Baobab tree, our protocol is built for stability, longevity, and serving diverse financial markets with a focus on African assets.*

[Documentation](#-documentation) • [Quick Start](#-getting-started) • [Architecture](#️-architecture-overview) • [Contributing](#-contributing)

---

</div>

## 📋 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Project Status](#-project-status)
- [Architecture Overview](#️-architecture-overview)
- [African Market Focus](#-african-market-focus)
- [Getting Started](#-getting-started)
- [Documentation](#-documentation)
- [Technology Stack](#️-technology-stack)
- [Security](#️-security)
- [Contributing](#-contributing)
- [License](#-license)

## 🌍 Overview

BAOBAB Protocol is a comprehensive decentralized trading platform that combines perpetual futures, event derivatives, and tokenized asset baskets. Our mission is to provide enterprise-grade DeFi infrastructure with specialized support for African and emerging market assets.

### Why BAOBAB?

Like the iconic Baobab tree that can survive for millennia, BAOBAB Protocol is designed to withstand market volatility and provide reliable financial infrastructure for generations. We bridge the gap between traditional African financial markets and decentralized finance.

## ✨ Key Features

### 🎯 Advanced Trading Engine

- **Cross-Margin Perpetuals**: Trade with up to 100x leverage using unified collateral across multiple positions
- **Spot Trading**: Direct asset exchange with advanced order types and deep liquidity
- **Professional Risk Management**: Portfolio-level margin calculations and automated liquidation systems
- **Multi-Asset Support**: Trade crypto, stocks, forex, and commodities from a single platform
- **Modular Architecture**: Extensible trading engines supporting perpetuals, spot, and custom trading strategies

### 📊 Event Derivatives

- **Prediction Markets**: Trade on real-world events with decentralized outcome resolution
- **African Focus**: Nigerian elections, AFCON tournaments, central bank decisions, and economic announcements
- **Flexible Market Types**: Both scheduled events and emergency/breaking news markets
- **Transparent Settlement**: Verifiable, on-chain outcome resolution with multi-oracle verification

### 🌳 Tokenized Asset Baskets

- **African Market Indices**: Pan-African and country-specific market exposure
- **Thematic Portfolios**: Web3 gaming, renewable energy, layer-2 ecosystems, and more
- **Auto-Rebalancing**: Algorithmic portfolio management with customizable strategies
- **Institutional-Grade Strategies**: Market neutral, volatility harvesting, and carry trades
- **ERC-20 Share Tokens**: Liquid, composable basket tokens for maximum flexibility

### 🛡️ Enterprise-Grade Security

- **Multi-Oracle Architecture**: Chainlink, Pyth Network, TWAP, and trusted oracle integration
- **Circuit Breakers**: Automated trading halts during extreme volatility or anomalous conditions
- **Rate Limiting**: Protection against DoS attacks and market manipulation
- **Comprehensive Testing**: Unit, integration, fuzz, and fork testing for all critical paths
- **Time-Locked Upgrades**: Multi-sig governance with mandatory delay periods

## 📜 Project Status

**Current Phase**: Architectural Blueprint & Implementation Foundation

This repository contains a complete architectural blueprint with structured core contracts and well-defined business logic. While the foundation is solid and production-ready in design, full implementation of all modules is ongoing. This provides an excellent starting point for building a production-grade decentralized exchange.

**What's Ready:**
- ✅ Complete system architecture and design patterns
- ✅ Core contract structure and interfaces
- ✅ Security module framework
- ✅ Testing infrastructure setup

**In Progress:**
- 🔄 Full implementation of trading engines
- 🔄 Event derivatives settlement mechanisms
- 🔄 Comprehensive test coverage
- 🔄 Oracle integration and testing

## 🏗️ Architecture Overview

BAOBAB Protocol follows a modular, upgradeable architecture designed for security, scalability, and maintainability.

```
protocol-contracts/
├── src/
│   ├── core/              # Core protocol logic
│   │   ├── trading/       # Perpetuals, spot, and margin trading
│   │   ├── events/        # Event derivatives system
│   │   ├── markets/       # Market factory and management
│   │   ├── oracles/       # Multi-oracle price feed system
│   │   └── data/          # Protocol data storage and state
│   ├── baskets/           # Tokenized basket engine
│   ├── vaults/            # Liquidity, insurance, and treasury vaults
│   ├── routers/           # User-facing interaction layer
│   ├── readers/           # View functions and analytics
│   ├── fees/              # Fee calculation and distribution
│   ├── access/            # Role-based access control
│   ├── security/          # Circuit breakers, pausers, rate limiters
│   ├── tokens/            # ERC-20/ERC-721 implementations
│   └── libraries/         # Reusable utility libraries
├── test/                  # Comprehensive test suite
├── script/                # Deployment and operational scripts
├── config/                # Network and protocol configuration
├── docs/                  # Technical documentation
└── keeper-bots/           # Off-chain automation services
```

### Key Architectural Components

| Component | Purpose |
|-----------|---------|
| **Trading Engines** | Handle perpetual futures, spot trading, and cross-margin calculations |
| **Market Factory** | Dynamic creation of new trading markets with configurable parameters |
| **Oracle Registry** | Unified interface for multiple price feed providers with fallback mechanisms |
| **Vault System** | Segregated fund management for liquidity, insurance, and treasury |
| **Router Layer** | Simplified user interface abstracting complex multi-contract interactions |
| **Security Modules** | Circuit breakers, emergency pause, and rate limiting for protocol safety |

## 🌍 African Market Focus

BAOBAB Protocol is purpose-built to serve African markets with specialized features:

### Supported Local Assets

**Nigerian Equities**
- Dangote Cement (DANGCEM)
- MTN Nigeria (MTNN)
- Guaranty Trust Bank (GTCO)
- Zenith Bank (ZENITHBANK)

**Currency Pairs**
- NGN/USD, GHS/USD, KES/USD
- Intra-African pairs: NGN/GHS, NGN/KES

**Commodities**
- Brent Crude Oil
- Gold and precious metals
- Agricultural products (cocoa, coffee)

### Regional Events Coverage

**Political Events**
- National elections and referendums
- Policy announcements and reforms
- Regulatory decisions

**Economic Indicators**
- Central bank interest rate decisions
- Inflation and GDP reports
- Currency interventions

**Sports & Culture**
- Africa Cup of Nations (AFCON)
- Continental club competitions
- Major cultural events

### Localized Features

- ✅ Trusted oracles for African asset pricing
- ✅ Trading hours aligned with African market sessions
- ✅ Support for local currency settlement paths
- ✅ Reduced latency for African users via regional infrastructure

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest version)
- [Git](https://git-scm.com/) with submodule support
- [Node.js](https://nodejs.org/) v16+ (for scripts and tooling)

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/your-username/baobab-protocol.git
cd baobab-protocol
```

2. **Initialize submodules**
```bash
git submodule update --init --recursive
```

3. **Install dependencies**
```bash
forge install
```

4. **Configure environment variables**

Create a `.env` file in the root directory:

```env
# Wallet Configuration
DEPLOYER_PRIVATE_KEY=your_deployer_private_key
GUARDIAN_PRIVATE_KEY=your_guardian_private_key

# RPC Endpoints
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
BASE_RPC_URL=https://mainnet.base.org
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_INFURA_KEY

# Block Explorers
ARBISCAN_API_KEY=your_arbiscan_api_key
BASESCAN_API_KEY=your_basescan_api_key
ETHERSCAN_API_KEY=your_etherscan_api_key

# Oracle Configuration
CHAINLINK_NODE_URL=your_chainlink_node_url
PYTH_ENDPOINT=https://xc-mainnet.pyth.network
```

### Basic Usage

**Compile contracts**
```bash
forge build
```

**Run tests**
```bash
forge test
```

**Run tests with gas reporting**
```bash
forge test --gas-report
```

**Run specific test file**
```bash
forge test --match-path test/core/trading/PerpEngine.t.sol
```

**Deploy to testnet**
```bash
forge script script/deploy/01_Core.s.sol \
  --rpc-url $ARBITRUM_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --verify
```

## 📚 Documentation

Comprehensive documentation is available in the `/docs` directory:

| Document | Description |
|----------|-------------|
| [Architecture Overview](docs/ARCHITECTURE.md) | High-level system design and component interaction |
| [Trading Engine](docs/TRADING_ENGINE.md) | Perpetuals, spot trading, and margin system |
| [Event Derivatives](docs/EVENT_DERIVATIVES.md) | Prediction market mechanics and settlement |
| [Basket Engine](docs/BASKET_ENGINE.md) | Tokenized indices and portfolio management |
| [Oracle System](docs/ORACLES.md) | Multi-oracle architecture and price feed security |
| [Security Model](docs/SECURITY.md) | Threat model and security considerations |
| [API Reference](docs/API_REFERENCE.md) | Complete contract interface documentation |
| [Quick Start Guide](docs/QUICK_START.md) | Get started in 5 minutes |

## 🛠️ Technology Stack

| Technology | Purpose |
|------------|---------|
| [**Solidity ^0.8.24**](https://soliditylang.org/) | Smart contract programming language |
| [**Foundry**](https://book.getfoundry.sh/) | Development framework and testing toolkit |
| [**OpenZeppelin Contracts**](https://www.openzeppelin.com/contracts) | Battle-tested security primitives |
| [**Chainlink**](https://chain.link/) | Decentralized oracle network for price feeds |
| [**Pyth Network**](https://pyth.network/) | Low-latency, high-frequency price data |

### Protocol Metrics

| Metric | Value |
|--------|-------|
| Maximum Leverage | 100x |
| Supported Assets | 50+ |
| Oracle Providers | 4+ |
| Cross-Margin Support | ✅ |
| Gas Optimized | ✅ |
| Battle Tested | 🔄 In Progress |

## 🛡️ Security

Security is our highest priority. BAOBAB Protocol implements multiple layers of protection:

### Security Features

- ✅ **Multi-signature Admin Controls**: All critical operations require multiple signatures
- ✅ **Time-locked Upgrades**: Mandatory delay period for all contract upgrades
- ✅ **Emergency Pause System**: Instant protocol-wide or module-specific shutdown capability
- ✅ **Circuit Breakers**: Automatic trading halts during anomalous market conditions
- ✅ **Rate Limiting**: Protection against DoS and spam attacks
- ✅ **Comprehensive Testing**: Unit, integration, fuzz, and fork tests

### Audit Status

- 🔄 **Internal Security Review**: Ongoing
- ⏳ **External Audit**: Scheduled (Q2 2025)
- ⏳ **Bug Bounty Program**: Coming Soon

### Reporting Vulnerabilities

If you discover a security vulnerability, please email **security@baobabprotocol.xyz** instead of opening a public issue. We take all security reports seriously and will respond promptly.

## 🤝 Contributing

We welcome contributions from the community! Here's how you can help:

### Contribution Process

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Commit your changes** (`git commit -m 'Add amazing feature'`)
4. **Push to your branch** (`git push origin feature/amazing-feature`)
5. **Open a Pull Request**

### Development Guidelines

- Write clear, self-documenting code
- Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Add tests for all new functionality
- Update documentation for any API changes
- Ensure all tests pass before submitting PR

### Areas We Need Help

- 🧪 Test coverage expansion
- 📝 Documentation improvements
- 🐛 Bug fixes and optimizations
- 🌍 African market data and oracle integration
- 🔐 Security reviews and auditing

## 👥 Team

BAOBAB Protocol is built by a distributed team of DeFi experts, quantitative researchers, and African market specialists with extensive experience in:

- Traditional finance and institutional market making
- Blockchain infrastructure and smart contract development
- African financial markets and regulatory frameworks
- Quantitative risk management and algorithmic trading

**Core Contributor**: [Adebakin Olujimi](https://twitter.com/olujimi_the_dev)

## 📄 License

This project is licensed under the **Business Source License 1.1 (BUSL-1.1)**.

See the [LICENSE](LICENSE) file for details. Additional usage grants may be available - contact us for commercial licensing inquiries.

## 🙏 Acknowledgments

- Inspired by the resilience and longevity of the African Baobab tree
- Built on the shoulders of the global DeFi ecosystem
- Supported by the vibrant African developer community
- Special thanks to our security researchers and auditors

---

<div align="center">

**BAOBAB Protocol - Building the Future of African DeFi, One Block at a Time** 🌳

*"Like the Baobab tree, we're built to withstand storms and provide shelter for generations."*

**[Website](https://baobabprotocol.xyz)** • **[Twitter](https://twitter.com/baobabprotocol)** • **[Discord](https://discord.gg/baobabprotocol)** • **[Documentation](https://docs.baobabprotocol.xyz)**

</div>
