
Oracle System Architecture
Overview
BAOBAB's multi-oracle system provides secure, reliable price feeds for diverse asset classes with specialized support for African markets. The system employs redundancy, validation, and fallback mechanisms to ensure price integrity.

Oracle Architecture
text
OracleRegistry (Coordinator)
    ├── ChainlinkAdapter (Decentralized Security)
    ├── PythAdapter (Low Latency & Cross-Chain)
    ├── TWAPAdapter (Manipulation Resistance)
    ├── TrustedOracle (African Assets & Emergency)
    └── ComputedOracle (Synthetic Prices & Indices)
        │
        └── OracleSecurity (Validation & Fallbacks)
Oracle Adapters
ChainlinkAdapter
Purpose: Battle-tested decentralized price feeds

solidity
function getPrice(bytes32 feedId) view returns (PriceData memory) {
    AggregatorV3Interface feed = AggregatorV3Interface(feedRegistry.getFeed(feedId));
    (, int256 price, , uint256 updatedAt, ) = feed.latestRoundData();
    
    return PriceData({
        price: uint256(price),
        timestamp: updatedAt,
        confidence: 0, // Chainlink doesn't provide confidence
        isValid: _isFresh(updatedAt)
    });
}
Best For:

Major crypto pairs (BTC/USD, ETH/USD)

High-liquidity forex pairs

When maximum decentralization is required

PythAdapter
Purpose: Low-latency cross-chain price feeds

solidity
function getPrice(bytes32 priceId) view returns (PriceData memory) {
    PythStructs.Price memory pythPrice = pyth.getPrice(priceId);
    
    return PriceData({
        price: _normalizePrice(pythPrice.price, pythPrice.expo),
        timestamp: pythPrice.publishTime,
        confidence: _normalizePrice(pythPrice.conf, pythPrice.expo),
        isValid: _isFresh(pythPrice.publishTime) && pythPrice.price > 0
    });
}
Best For:

Fast-moving markets and altcoins

Cross-chain consistency requirements

Stocks, commodities, and exotic pairs

TWAPAdapter
Purpose: Time-weighted average prices from DEXes

solidity
function getPrice(address token) view returns (PriceData memory) {
    (uint256 twapPrice, uint256 timestamp) = uniswapV3Oracle.consult(
        token,
        TWAP_INTERVAL
    );
    
    return PriceData({
        price: twapPrice,
        timestamp: timestamp,
        confidence: _calculateConfidence(token),
        isValid: _isLiquid(token) && _isFresh(timestamp)
    });
}
Best For:

New tokens without established feeds

Illiquid markets prone to manipulation

During high volatility periods

TrustedOracle
Purpose: Manual price inputs for African and exotic assets

solidity
function submitPrice(
    address asset, 
    uint256 price, 
    bytes memory signature
) external onlyApprovedSubmitter {
    require(_verifySignature(asset, price, signature), "Invalid signature");
    
    prices[asset] = PriceData({
        price: price,
        timestamp: block.timestamp,
        confidence: trustedConfidence[asset],
        isValid: true
    });
}
Best For:

Nigerian and African stocks

Assets without on-chain price feeds

Emergency manual overrides

Low-frequency update assets

ComputedOracle
Purpose: Calculated prices and synthetic indices

solidity
function getBasketNav(address basket) view returns (PriceData memory) {
    address[] memory components = basketEngine.getComponents(basket);
    uint256[] memory weights = basketEngine.getWeights(basket);
    
    uint256 totalValue;
    for (uint i = 0; i < components.length; i++) {
        PriceData memory compPrice = oracleRegistry.getPrice(components[i]);
        totalValue += (compPrice.price * weights[i]) / 1e18;
    }
    
    return PriceData({
        price: totalValue,
        timestamp: block.timestamp,
        confidence: _calculateBasketConfidence(components),
        isValid: true
    });
}
Best For:

Basket NAV calculations

Cross-rate computations (EUR/NGN via EUR/USD × USD/NGN)

Implied volatility calculations

Funding rate computations

Security Framework
Price Validation
solidity
function validatePrices(PriceData[] memory prices) 
    external view 
    returns (PriceData memory) 
{
    // 1. Filter stale prices
    prices = _filterStalePrices(prices, MAX_AGE);
    
    // 2. Filter by confidence
    prices = _filterLowConfidence(prices, MIN_CONFIDENCE);
    
    // 3. Remove outliers (median absolute deviation)
    prices = _filterOutliers(prices, MAX_DEVIATION);
    
    // 4. Return weighted average
    return _calculateWeightedAverage(prices);
}
Deviation Checks
solidity
function _checkDeviations(PriceData[] memory prices) internal pure {
    uint256 median = _calculateMedian(prices);
    
    for (uint i = 0; i < prices.length; i++) {
        uint256 deviation = _calculateDeviation(prices[i].price, median);
        if (deviation > MAX_ALLOWED_DEVIATION) {
            revert OracleDeviationTooHigh(deviation);
        }
    }
}
African Market Support
Nigerian Stock Configuration
json
{
  "DANGOTE": {
    "primary": "trusted",
    "fallbacks": [],
    "maxDeviation": 5.0,
    "maxAge": 86400,
    "updateFrequency": 86400,
    "trustedSigners": [
      "0x123...", "0x456...", "0x789..."
    ]
  }
}
African Currency Pairs
json
{
  "NGN/USD": {
    "primary": "pyth",
    "fallbacks": ["chainlink", "trusted"],
    "maxDeviation": 3.0,
    "maxAge": 3600
  }
}
Emergency Procedures
Circuit Breaker Triggers
10%+ price deviation between primary and secondary oracles

50%+ confidence interval expansion

Multiple oracle failure detection

Governance-initiated manual override

Fallback Strategies
text
Primary Oracle Failure:
1. Switch to secondary oracle immediately
2. Reduce position sizes and leverage
3. Notify users and operators
4. Manual intervention if automated fails

Multiple Oracle Failure:
1. Use most conservative price (lowest for longs, highest for shorts)
2. Suspend new position openings
3. Emergency liquidation protection
4. Security council resolution
Performance Optimization
Caching Strategy
Hot prices cached for 10 seconds

Warm prices cached for 60 seconds

Cold prices fetched on-demand

Cache invalidation on significant moves

Gas Optimization
solidity
// Batch price updates
function getPrices(address[] memory assets) 
    external view 
    returns (PriceData[] memory) 
{
    PriceData[] memory results = new PriceData[](assets.length);
    for (uint i = 0; i < assets.length; i++) {
        results[i] = getPrice(assets[i]);
    }
    return results;
}
Integration Example
javascript
// Get validated price for BTC
const priceData = await oracleRegistry.getPrice(BTC_ADDRESS);

// Check price validity
if (!priceData.isValid) {
    throw new Error("Price data is stale or invalid");
}

// Use in trading engine
const positionSize = await tradingEngine.calculateMaxPosition(
    userAddress,
    priceData.price
);
This completes the Architecture documentation. Continue to Integration Guides
