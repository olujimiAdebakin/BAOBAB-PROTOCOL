# System Architecture



## BAOBAB Protocol System Architecture

Overview

BAOBAB Protocol redefines decentralized trading by transforming orders into composable NFTs, creating the first platform where pending orders become productive assets. Built with a unified order book architecture and specialized African market focus, BAOBAB combines perpetual futures, spot trading, event derivatives, and tokenized baskets into a single, capital-efficient protocol.


Core Innovation: Order NFT Composability
The fundamental breakthrough lies in representing every limit order as an ERC-721 NFT, enabling unprecedented capital efficiency:

Order Lifecycle as Productive Asset:
Place Order → Mint Order NFT → [Stake for Rewards | Collateralize for Loans | Trade on Secondary] → Execution → Burn NFT


## High-Level Architecture

┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   User Layer    │    │  Protocol Layer  │    │ External Layer  │
│                 │    │                  │    │                 │
│ • Web Frontend  │◄──►│ • Core Router    │◄──►│ • Multi-Oracle  │
│ • Mobile App    │    │ • Trading Engine │    │ • Pyth/Chainlink│
│ • API Clients   │    │ • Event Engine   │    │ • DEX Routers   │
│ • Keeper Bots   │    │ • Basket Engine  │    │ • Data Providers│
│ • NFT Markets   │    │ • Vault System   │    │                 │
└─────────────────┘    │ • Security Layer │    └─────────────────┘
                       │ • Order NFT Sys  │
                       └──────────────────┘



## Core Contract Architecture

### Router Layer (User Entry Points)

CoreRouter (Main Entry Point)
├── TradingRouter (Perps, Spot, Cross-Margin)
│   ├── OrderManager (Order NFT Minting/Burning)
│   └── PositionManager (Position Tracking)
├── BasketRouter (Strategy & Asset Baskets)
│   ├── BasketFactory (Create Tokenized Funds)
│   └── BasketOperations (Invest/Redeem)
├── EventRouter (Prediction Markets)
│   ├── EventFactory (Market Creation)
│   └── EventSettlement (Outcome Resolution)
└── VaultRouter (Capital Management)
    ├── LiquidityVault (LP Operations)
    └── InsuranceVault (Risk Coverage)


### Engine Layer (Core Logic)

Trading Engine

Trading Engine
├── PerpEngine (Perpetual Futures)
│   ├── FundingRateCalculator
│   └── CrossMarginEngine (Unified Collateral)
├── SpotEngine (Spot Trading)
├── OrderManager (Order Lifecycle)
│   ├── OrderNFT (ERC-721 Implementation)
│   └── OrderCollateralization (50% LTV Loans)
├── LiquidationEngine (Risk Management)
└── DAOMarketMaker (Protocol-Owned Liquidity)
    ├── SpreadManager (0.3-0.5% Target)
    └── ProfitDistributor (Token Staker Rewards)


## Basket Engine (Strategy Tokenization)

Basket Engine
├── OrderBasketFactory (Trustless Strategy Funds)
│   ├── Bundle multiple orders into ERC-20 tokens
│   └── Non-custodial fund management
├── AssetBasketFactory (Traditional Index Funds)
│   ├── Underlying token holdings
│   └── Auto-rebalancing logic
├── BasketPricing (NAV Calculations)
└── RebalancingEngine (Strategy Maintenance)

## Event Engine (Prediction Markets)

Event Engine
├── ScheduledEvent (Time-based Markets)
│   ├── Elections, Economic Data, Sports
├── EmergencyEvent (Breaking News Events)
├── OutcomeVerifier (Multi-Oracle Settlement)
└── EventSettlement (Payout Distribution)


### Infrastructure Layer

Vault System
├── LiquidityVault (LP Deposits)
│   ├── Unified liquidity for all markets
│   └── ERC-4626 share tokens
├── InsuranceVault (Risk Coverage)
│   ├── $5M+ target for bad debt
│   └── Protocol backstop
├── TreasuryVault (Protocol Treasury)
│   ├── DAO market making profits
│   └── Fee distribution
└── VaultManager (Coordination)

## Oracle System

Oracle System
├── OracleRegistry (Coordination)
├── OracleSecurity (Validation)
│   ├── Price freshness checks
│   ├── Deviation thresholds
│   └── Emergency fallbacks
└── Adapters (Multi-Source Feeds)
    ├── ChainlinkAdapter (Primary)
    ├── PythAdapter (Low-Latency)
    ├── TWAPAdapter (Time-Weighted)
    └── TrustedOracle (African Assets)

## Security Layer

Security Layer
├── AccessManager (Role-Based Control)
│   ├── ProtocolOwner (Admin Functions)
│   └── RoleRegistry (Permission Definitions)
├── CircuitBreaker (Auto-Pause)
│   ├── 15%+ price move detection
│   └── Volatility protection
├── EmergencyPauser (Manual Intervention)
├── RateLimiter (DoS Protection)
└── ReentrancyGuard (Standard Protection)

## Data Flow

### Trading Flow with Order NFTs

1. User → TradingRouter → OrderManager
2. OrderManager → OrderNFT.mint() [Creates composable order]
3. OrderManager → CrossMarginEngine (collateral check)
4. CrossMarginEngine → PerpEngine/SpotEngine (position open)
5. Engine → OracleRegistry (price validation)
6. Position opened → DataStore (state update)
7. Order NFT remains active until execution/cancellation

## Order Collateralization Flow

1. User holds Order NFT → VaultRouter
2. VaultRouter → OrderCollateralization
3. OrderCollateralization validates:
   - Order value (50% LTV maximum)
   - Market liquidity
   - Risk parameters
4. Loan disbursed → User wallet
5. Order executes → Tokens held in escrow
6. User repays → Receives filled tokens

## Gasless Execution Flow

1. User places order + pays $2-3 execution fee
2. Order enters batch queue (5-10 second window)
3. Keeper bot monitors queue:
   - Checks order validity
   - Validates prices
   - Executes batch via OrderManager
4. OrderManager:
   - Processes fills
   - Updates positions
   - Burns executed Order NFTs
   - Compensates keeper from fee pool

## Basket Creation Flow

   1. Manager → BasketRouter → OrderBasketFactory
2. Manager places 10-20 strategy orders
3. OrderBasketFactory:
   - Bundles orders into strategy
   - Mints ERC-20 basket tokens
   - Sets manager fee structure
4. Investors buy basket tokens
5. Keepers execute underlying orders automatically
6. Profits distributed to token holders
### Oracle Flow


Multiple oracles fetch prices simultaneously

OracleRegistry collects all prices

OracleSecurity validates (freshness, deviation)

Validated price returned to requesting engine

Emergency fallback if validation fails



## Storage Architecture

### DataStore Structure
```solidity
// Core Protocol Data
mapping(address => UserAccount) accounts;
mapping(address => Position[]) positions;
mapping(uint256 => OrderNFT) orderNFTs;  // Order composability

// Market Configuration  
mapping(address => MarketConfig) markets;
mapping(address => PriceData) prices;

// Basket Management
mapping(address => BasketStrategy) baskets;
mapping(address => BasketPosition[]) basketHoldings;

// System State
ProtocolState globalState;
RiskParameters riskParams;
DAOMarketMakerState mmState;


State Management

Hot Storage: Active positions, open orders, recent prices (frequently accessed)

Warm Storage: User accounts, market configs, basket compositions (moderately accessed)

Cold Storage: Historical data, settled events, old orders (rarely accessed)

## Oracle Integration Architecture

## Multi-Source Price Validation

Price Request Flow:
1. Trading Engine → OracleRegistry
2. OracleRegistry queries all adapters simultaneously
3. Adapters return prices with confidence intervals
4. OracleSecurity validates:
   - Timestamp freshness (< 2 minutes)
   - Price deviation (< 1% between sources)
   - Volume-weighted confidence
5. Validated price returned to engine
6. Emergency fallback if validation fails


African Asset Pricing

African Market Data Flow:
1. TrustedOracle for local assets (Nigerian stocks, forex)
2. Local data provider partnerships
3. Multi-hour trading session alignment
4. Regional RPC node integration (Lagos, Nairobi, Johannesburg)



Upgradeability Strategy

Modular Upgrade Architecture

Upgrade Path:
CoreRouter (Immutable) → Versioned Engines → DataStore (Persistent)
    │
    ├── Trading Engine v1 → v2 (Order NFT enhancements)
    ├── Basket Engine v1 → v2 (New basket types)  
    ├── Event Engine v1 → v2 (Additional event types)
    └── Vault System v1 → v2 (New vault strategies)

Security-First Upgrade Process

Time-locked upgrades: 72-hour delay for critical components

Multi-sig approval: 3-of-5 required for production deployments

Emergency rollback: Quick revert procedures for critical issues

Data migration: Script-based state transitions for structural changes


## Keeper Network Architecture

## Decentralized Execution

Keeper Ecosystem:
Keeper Registry → Authorized Bots → Batch Execution → Fee Distribution
    │
    ├── Order Execution Keepers (5-10 second batches)
    ├── Liquidation Keepers (Risk management)
    ├── Basket Rebalancing Keepers (Strategy maintenance)
    └── Event Settlement Keepers (Market resolution)

## Keeper Economics

Staking requirement: BAOBAB tokens for bot authorization

Execution rewards: $500-1000/day potential earnings

Fee structure: Base reimbursement + performance incentives

Slashing conditions: Malicious behavior penalties

African Market Integration

Regional Infrastructure

African-First Architecture:
Local RPC Nodes → Regional Oracles → Market Hours → Mobile Optimization
    │               │               │              │
 Lagos          Nigerian      9AM-4PM WAT    Low-bandwidth
 Nairobi        Kenyan assets  EAT alignment  Mobile-first UI
 Johannesburg   South African  SAST alignment Offline capabilities

 Supported Asset Classes

Equities: Top Nigerian and African public companies

Forex: Major African currency pairs with local settlement

Commodities: African-produced resources (cocoa, gold, oil)

Events: Regional political, economic, and sports markets

Security Architecture

Multi-Layered Protection

Security Stack:
Application Layer → Protocol Layer → Infrastructure Layer → External Layer
    │                  │                  │                  │
Input validation    Access control    Oracle security   Bug bounty
Rate limiting       Circuit breakers  Timelocks         External audits
Reentrancy guards   Emergency pause   Multi-sig         Insurance fund

Risk Management Framework

Pre-trade: Collateral checks, position limits, market hours

Execution: Price validation, slippage protection, MEV resistance

Post-trade: Liquidation buffers, insurance backstop, profit/loss tracking

Composability Architecture

Order NFT Integration Points

Order NFT as DeFi Primitive:
BAOBAB Protocol → External Ecosystems
    │
    ├── NFT Markets (OpenSea, Blur) - Secondary order trading
    ├── Lending Protocols (Aave, Compound) - Order NFT collateral
    ├── Yield Platforms (Yearn, Convex) - Order staking strategies
    └── Fund Management - Basket token integration


    Standard Interface Support

ERC-721: Order NFTs with metadata (order details, status, value)

ERC-20: Basket tokens representing strategy exposure

ERC-4626: Vault shares for liquidity providers

EIP-712: Gasless order signing and execution

This architecture enables BAOBAB Protocol to deliver its core innovation: transforming orders from temporary database entries into permanent, composable DeFi assets while maintaining enterprise-grade security and African market specialization.