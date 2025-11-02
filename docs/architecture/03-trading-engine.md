
Trading Engine Architecture
Overview
The BAOBAB Trading Engine enables sophisticated derivative and spot trading with unified cross-margin collateral management. Built for both retail and institutional traders with a focus on African market accessibility.

Core Components
PerpEngine
Purpose: Perpetual futures trading with funding rate mechanism

solidity
// Key functions
function openPosition(OpenPositionParams params) → Position
function closePosition(uint positionId, uint size) → PnL
function liquidatePosition(address user, uint positionId)
function updateFundingRate(address asset) → int256
Features:

Up to 100x leverage (configurable per asset)

Cross-margin collateral utilization

Isolated and cross-position liquidation

Dynamic funding rates based on market premium

SpotEngine
Purpose: Direct asset-to-asset trading

solidity
// Key functions  
function swapExactInput(SwapParams params) → uint amountOut
function createLimitOrder(LimitOrderParams params) → uint orderId
function executeLimitOrder(uint orderId)
Features:

AMM-based spot trading

Limit orders with post-only options

Multi-hop routing through DEX aggregators

Minimal slippage for African assets

CrossMarginEngine
Purpose: Unified collateral management across all positions

solidity
// Key functions
function depositCollateral(address asset, uint amount)
function withdrawCollateral(address asset, uint amount)
function getAccountValue(address user) → int256
function getMarginRatio(address user) → uint256
Features:

Single collateral pool for all trading activities

Multi-asset collateral (ETH, USDC, BTC, etc.)

Real-time margin ratio calculations

Portfolio-level risk management

Key Mechanisms
Margin System
text
Initial Margin = Position Size × Initial Margin Rate
Maintenance Margin = Position Size × Maintenance Margin Rate

Margin Ratio = (Account Value - Maintenance Margin) / Account Value

Liquidation when: Margin Ratio ≤ 0%
Funding Rate Calculation
solidity
// Every 8 hours
fundingRate = (markPrice - spotPrice) / spotPrice × fundingInterval

// Paid from longs to shorts if positive
// Paid from shorts to longs if negative
Liquidation Process
text
1. Margin check fails (margin ratio ≤ 0%)
2. LiquidationEngine identifies underwater positions
3. Liquidator can close up to 50% of position
4. Liquidation bonus (5-10%) paid to liquidator
5. Remaining position stays open if margin restored
Order Types
Market Orders
Immediate execution at best available price

Slippage protection with maximum tolerance

Gas optimization through batch execution

Limit Orders
Price-contingent execution

Post-only option to avoid paying spread

Good-till-cancelled or good-till-time

Stop Orders
Stop-loss and take-profit triggers

Oracle-based execution (not just on-chain trades)

Partial fills supported

Risk Management
Position Limits
solidity
// Per user, per market
maxPositionSize = min(
    absoluteLimit,           // Fixed cap
    openInterest × 0.1,      // 10% of total OI  
    accountValue × maxLeverage // Based on collateral
)
Circuit Breakers
10% price move in 5 minutes → reduced leverage

20% price move in 5 minutes → trading pause

Oracle deviation > 5% → use conservative price

African Asset Considerations
Higher margin requirements for illiquid assets

Extended liquidation timeframes during low liquidity

Trusted oracle fallbacks for local stocks

Integration Points
Oracle Dependencies
Primary: Pyth (low latency for crypto)

Secondary: Chainlink (decentralized security)

Fallback: TWAP (manipulation resistance)

Special: TrustedOracle (African assets)

Keeper Network
Automated liquidations

Funding rate updates

Limit order execution

System health monitoring


