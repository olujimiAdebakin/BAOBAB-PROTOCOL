# Maintenance Margin Rate (MMR)

## What is MMR?

**MMR is the safety cushion that keeps your position alive.** It's the minimum percentage of your position value you must maintain as collateral to avoid liquidation.

Think of it like this: If you take a 10x leveraged position, you're borrowing 9x from the protocol. MMR ensures there's always enough collateral to cover that debt, even when the market moves against you.

## The Simple Math

### Risk Buffer (What Protects You)
```
Risk Buffer = (1 / Leverage) - MMR
```

**Example:** 10x leverage with 0.5% MMR
- Initial margin: 10% (1/10)
- MMR: 0.5%
- Risk buffer: 10% - 0.5% = **9.5%**

This means the market can move 9.5% against you before liquidation.

### Liquidation Price

**LONG Position:**
```
Liquidation Price = Entry Price × (1 - Risk Buffer)
```

**SHORT Position:**
```
Liquidation Price = Entry Price × (1 + Risk Buffer)
```

## BAOBAB's MMR Tiers

We use different MMR rates based on market risk:

### Tier 1: Global Markets (0.5% MMR)
**Markets:** ETH-USD, BTC-USD, USDT-USD

**Why 0.5%?** These are highly liquid markets with tight spreads and predictable execution. Industry standard that matches Binance, Bybit, and other major platforms.

### Tier 2: African Markets (1.0% MMR)
**Markets:** DANGCEM-NG, MTNN-NG, NGN-USD, GHS-USD

**Why 1.0%?** Lower liquidity, wider spreads, and higher volatility. The extra 0.5% protects both you and the protocol from execution risks unique to emerging markets.

### Tier 3: Event Markets (1.5% MMR)
**Markets:** NIGERIA-ELECTION, CBN-RATE-DECISION

**Why 1.5%?** Binary outcomes create extreme volatility. These markets can gap significantly in seconds.

## Real-World Examples

### Example 1: Trading ETH (0.5% MMR)

**Your Position:**
- Collateral: $10,000
- Leverage: 10x
- Entry: $3,000 ETH
- Direction: LONG

**Calculations:**
- Position size: $100,000
- Risk buffer: 9.5%
- **Liquidation price: $2,715**

The market can drop 9.5% ($285) before liquidation.

### Example 2: Trading Dangote Cement (1.0% MMR)

**Your Position:**
- Collateral: $10,000
- Leverage: 10x
- Entry: ₦500 per share
- Direction: LONG

**Calculations:**
- Position size: $100,000
- Risk buffer: 9.0%
- **Liquidation price: ₦455**

The market can drop 9.0% (₦45) before liquidation. Notice you have 0.5% less buffer due to higher market risk.

## Impact Across Leverage Levels

### Standard Markets (0.5% MMR)

| Leverage | Your Capital | Borrowed | Risk Buffer | Liquidation Move |
|----------|--------------|----------|-------------|------------------|
| 2x       | 50%          | 50%      | 49.5%       | -49.5%           |
| 5x       | 20%          | 80%      | 19.5%       | -19.5%           |
| 10x      | 10%          | 90%      | 9.5%        | -9.5%            |
| 20x      | 5%           | 95%      | 4.5%        | -4.5%            |
| 50x      | 2%           | 98%      | 1.5%        | -1.5%            |

### Elevated Risk Markets (1.0% MMR)

| Leverage | Your Capital | Borrowed | Risk Buffer | Liquidation Move |
|----------|--------------|----------|-------------|------------------|
| 2x       | 50%          | 50%      | 49.0%       | -49.0%           |
| 5x       | 20%          | 80%      | 19.0%       | -19.0%           |
| 10x      | 10%          | 90%      | 9.0%        | -9.0%            |
| 20x      | 5%           | 95%      | 4.0%        | -4.0%            |
| 50x      | 2%           | 98%      | 1.0%        | -1.0%            |

**Key Insight:** At 50x leverage on African markets, you only have 1% room before liquidation. This is why understanding MMR matters.

## What Does MMR Actually Cover?

The MMR percentage pays for real costs when liquidating a position:

### 0.5% MMR Breakdown (Global Markets)
- **Slippage:** 0.2-0.3% (moving the market when liquidating)
- **Price movement:** 0.1-0.15% (market moves during execution)
- **Oracle differences:** 0.05% (mark price vs actual execution)
- **Execution costs:** 0.05-0.1% (gas, keeper fees)
- **Buffer:** ~0.0% (minimal safety margin)

### 1.0% MMR Breakdown (African Markets)
Everything above **PLUS:**
- **Additional volatility buffer:** 0.5%
- **Lower liquidity premium:** Coverage for wider spreads
- **Market-specific risks:** Off-hours volatility, currency fluctuations

## Why Dynamic MMR?

**Old Way (Static MMR):** One rate for all markets. Either too risky for emerging markets or too expensive for liquid markets.

**BAOBAB's Way (Dynamic MMR):** Match the MMR to actual market conditions.

This lets us:
- Compete with Binance/Bybit on BTC/ETH (0.5%)
- Responsibly pioneer African markets (1.0%)
- Protect users on volatile event derivatives (1.5%)

## How MMR Changes

### Governance Process
1. **Initial Setting:** Protocol team analyzes market data
2. **DAO Voting:** Community can propose changes
3. **Automatic Adjustments:** Based on measured volatility/liquidity
4. **Emergency Override:** Admin can adjust during extreme events

### Automatic Triggers (Example)
```javascript
// If 30-day volatility exceeds 100%, increase MMR
if (volatility30d > 100%) {
  increaseMMR(marketId, 0.25%);
}

// If average spread exceeds 0.1%, increase MMR  
if (averageSpread > 0.1%) {
  increaseMMR(marketId, 0.15%);
}
```

## Technical Implementation

### Decimal Notation
- 0.5% MMR = `0.005` in calculations
- 1.0% MMR = `0.010` in calculations
- In Solidity: `50` (basis points) or `5e15` (wei)

### Smart Contract Structure
```solidity
struct MarketConfig {
    bytes32 marketId;
    uint16 maintenanceMargin;  // 50 = 0.5%, 100 = 1.0%
    uint256 maxLeverage;
    bool isActive;
}

function calculateLiquidationPrice(
    bytes32 marketId,
    Side side,
    uint256 entryPrice,
    uint16 leverage
) external view returns (uint256) {
    // Get market-specific MMR
    uint256 MMR = getMMR(marketId);
    
    // Calculate risk buffer
    uint256 initialMargin = 1e18 / leverage;
    uint256 riskBuffer = initialMargin - MMR;
    
    // Return liquidation price based on direction
    if (side == LONG) {
        return entryPrice * (1e18 - riskBuffer) / 1e18;
    } else {
        return entryPrice * (1e18 + riskBuffer) / 1e18;
    }
}
```

## Bottom Line

**MMR isn't arbitrary—it's calculated insurance.** 

- **0.5% for BTC/ETH:** Match global standards, attract volume
- **1.0% for African markets:** Cover real execution risks
- **1.5% for events:** Protect against binary volatility

This tiered approach lets BAOBAB be both **competitively aggressive** on liquid markets and **responsibly conservative** on emerging ones.

The result? You get industry-standard rates where markets support it, and appropriate protection where they don't.