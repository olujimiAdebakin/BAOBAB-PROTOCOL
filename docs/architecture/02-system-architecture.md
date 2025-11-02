# System Architecture

## High-Level Architecture


┌─────────────────┐ ┌──────────────────┐ ┌─────────────────┐
│ User Layer │ │ Protocol Layer │ │ External Layer │
│ │ │ │ │ │
│ • Web Frontend │◄──►│ • Core Router │◄──►│ • Multi-Oracle │
│ • Mobile App │ │ • Trading Engine │ │ • Pyth/Chainlink│
│ • API Clients │ │ • Event Engine │ │ • DEXes (Uniswap│
│ • Keeper Bots │ │ • Basket Engine │ │ • Data Providers │
└─────────────────┘ │ • Vault System │ └─────────────────┘
│ • Security Layer │
└──────────────────┘



## Core Contract Architecture

### Router Layer


CoreRouter (Main Entry)
├── TradingRouter (Perps, Spot, Margin)
├── BasketRouter (Create, Invest, Redeem)
├── EventRouter (Create, Trade, Settle)
└── VaultRouter (Deposit, Withdraw, Stake)



### Engine Layer


Trading Engine
├── PerpEngine (Perpetual futures)
├── SpotEngine (Spot trading)
├── CrossMarginEngine (Unified margin)
├── OrderManager (Order lifecycle)
└── LiquidationEngine (Risk management)

Event Engine
├── EventFactory (Market creation)
├── ScheduledEvent (Time-based events)
├── EmergencyEvent (Breaking news)
└── EventSettlement (Resolution)

Basket Engine
├── BasketFactory (Index creation)
├── BasketEngine (Operations)
├── BasketPricing (NAV calculations)
└── RebalancingEngine (Auto-adjustment)




### Infrastructure Layer


Vault System
├── LiquidityVault (LP deposits)
├── InsuranceVault (Risk coverage)
└── TreasuryVault (Protocol treasury)

Oracle System
├── OracleRegistry (Coordination)
├── OracleSecurity (Validation)
└── Adapters (Chainlink, Pyth, TWAP, Trusted)

Security Layer
├── AccessManager (Role-based access)
├── CircuitBreaker (Auto-pause)
├── EmergencyPauser (Manual pause)
└── RateLimiter (DoS protection)



## Data Flow

### Trading Flow


User → CoreRouter → TradingRouter

TradingRouter → CrossMarginEngine (collateral check)

CrossMarginEngine → PerpEngine/SpotEngine (position open)

PerpEngine → OracleRegistry (price validation)

Position opened → DataStore (state update)




### Oracle Flow


Multiple oracles fetch prices simultaneously

OracleRegistry collects all prices

OracleSecurity validates (freshness, deviation)

Validated price returned to requesting engine

Emergency fallback if validation fails



## Storage Architecture

### DataStore Structure
```solidity
// User data
mapping(address => UserAccount) accounts;
mapping(address => Position[]) positions;

// Market data  
mapping(address => MarketConfig) markets;
mapping(address => PriceData) prices;

// System state
ProtocolState globalState;
RiskParameters riskParams;


State Management
Hot Storage: Active positions, open orders (frequently accessed)

Warm Storage: User accounts, market configs (moderately accessed)

Cold Storage: Historical data, settlements (rarely accessed)

Upgradeability Strategy
Modular Upgrades
Individual engine upgrades without full protocol migration

Router-level versioning for backward compatibility

Data migration scripts for structural changes

Security Considerations
Time-locked upgrades for critical components

Multi-sig approval for production deployments

Emergency rollback procedures