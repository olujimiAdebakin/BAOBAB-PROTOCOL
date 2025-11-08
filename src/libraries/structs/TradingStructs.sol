// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "./CommonStructs.sol";

/**
 * @title TradingStructs
 * @author BAOBAB Protocol
 * @notice Data structures specific to trading engines (Perps, Spot, Cross-Margin, CLOB)
 * @dev Contains structs for order matching, funding rates, liquidations, execution, and advanced orders
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                       TRADING STRUCTS
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
library TradingStructs {
    using CommonStructs for *;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       ENUMERATIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Execution venue selection for orders
     * @dev AUTO - Protocol smart routing (default, 90% of users)
     * @dev VAULT_ONLY - Must fill against vault (instant, higher fees)
     * @dev ORDERBOOK_ONLY - Must match peer-to-peer (best price, may wait)
     */
    enum ExecutionMode {
        AUTO,
        VAULT_ONLY,
        ORDERBOOK_ONLY
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    ORDER BOOK STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Single price level in order book
     * @param price Price level (18 decimals)
     * @param totalSize Total size of all orders at this price (18 decimals)
     * @param orderCount Number of orders at this level
     * @param orders Array of order IDs at this price
     */
    struct PriceLevel {
        uint256 price;
        uint256 totalSize;
        uint256 orderCount;
        bytes32[] orders;
    }

    /**
     * @notice Order book snapshot for a market
     * @param marketId Market identifier
     * @param bids Buy side price levels (highest to lowest)
     * @param asks Sell side price levels (lowest to highest)
     * @param bestBid Highest buy price (18 decimals)
     * @param bestAsk Lowest sell price (18 decimals)
     * @param spread Difference between best ask and bid (18 decimals)
     * @param midPrice Average of best bid and ask (18 decimals)
     * @param timestamp Snapshot time
     */
    struct OrderBook {
        bytes32 marketId;
        PriceLevel[] bids;
        PriceLevel[] asks;
        uint256 bestBid;
        uint256 bestAsk;
        uint256 spread;
        uint256 midPrice;
        uint256 timestamp;
    }

    /**
     * @notice Order matching result
     * @param orderId Order that was matched
     * @param matchedOrderId Counterparty order
     * @param price Execution price (18 decimals)
     * @param size Amount filled (18 decimals)
     * @param timestamp Match time
     * @param buyer Address of buyer
     * @param seller Address of seller
     */
    struct Match {
        bytes32 orderId;
        bytes32 matchedOrderId;
        uint256 price;
        uint256 size;
        uint256 timestamp;
        address buyer;
        address seller;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                  ADVANCED ORDER STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice SCALE order configuration (price-level splitting)
     * @param orderId Parent order identifier
     * @param startPrice Starting price level (18 decimals)
     * @param endPrice Ending price level (18 decimals)
     * @param totalLevels Number of price levels
     * @param priceStep Price increment between levels (18 decimals)
     * @param sizePerLevel Amount to place at each level (18 decimals)
     * @param currentLevel Progress tracker (0-indexed)
     * @param ascending True for buy ladder (up), false for sell ladder (down)
     * @param filledLevels Bitmap of completed levels
     */
    struct ScaleConfig {
        bytes32 orderId;
        uint256 startPrice;
        uint256 endPrice;
        uint8 totalLevels;
        uint256 priceStep;
        uint256 sizePerLevel;
        uint8 currentLevel;
        bool ascending;
        uint256 filledLevels;
    }

    /**
     * @notice TWAP order configuration (time-based execution)
     * @param orderId Parent order identifier
     * @param totalSize Total order size (18 decimals)
     * @param sliceSize Size per execution interval (18 decimals)
     * @param intervalSeconds Time between executions
     * @param startTime Execution window start
     * @param endTime Execution window end
     * @param lastExecution Last execution timestamp
     * @param executedSoFar Cumulative executed size (18 decimals)
     * @param remainingIntervals Intervals left to execute
     * @param isActive Whether TWAP is currently running
     */
    struct TWAPConfig {
        bytes32 orderId;
        uint256 totalSize;
        uint256 sliceSize;
        uint256 intervalSeconds;
        uint256 startTime;
        uint256 endTime;
        uint256 lastExecution;
        uint256 executedSoFar;
        uint256 remainingIntervals;
        bool isActive;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                   PERPETUALS STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Funding rate state for perpetual market
     * @param marketId Market identifier
     * @param fundingRate Current 8-hour funding rate (basis points, can be negative)
     * @param fundingRateVelocity Rate of change in funding rate
     * @param premiumIndex Premium/discount of perp vs spot
     * @param openInterestLong Total long open interest (18 decimals)
     * @param openInterestShort Total short open interest (18 decimals)
     * @param imbalance Long OI - Short OI (can be negative)
     * @param lastUpdateTime Last funding calculation time
     * @param nextFundingTime Next scheduled funding payment
     */
    struct FundingRateState {
        bytes32 marketId;
        int256 fundingRate;
        int256 fundingRateVelocity;
        int256 premiumIndex;
        uint256 openInterestLong;
        uint256 openInterestShort;
        int256 imbalance;
        uint256 lastUpdateTime;
        uint256 nextFundingTime;
    }

    /**
     * @notice Funding payment for a position
     * @param positionId Position receiving/paying funding
     * @param fundingRate Rate applied (negative = receive, positive = pay)
     * @param paymentAmount Amount paid/received (can be negative)
     * @param timestamp Payment time
     */
    struct FundingPayment {
        bytes32 positionId;
        int256 fundingRate;
        int256 paymentAmount;
        uint256 timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                   LIQUIDATION STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Liquidation event data
     * @param positionId Position being liquidated
     * @param trader Owner of liquidated position
     * @param liquidator Address executing liquidation
     * @param marketId Market of position
     * @param side LONG or SHORT
     * @param size Position size (18 decimals)
     * @param collateral Collateral seized (18 decimals)
     * @param markPrice Price at liquidation (18 decimals)
     * @param liquidationPrice Trigger price (18 decimals)
     * @param liquidationFee Fee charged (18 decimals)
     * @param insuranceFundContribution Amount to insurance fund (18 decimals)
     * @param timestamp Liquidation time
     */
    struct Liquidation {
        bytes32 positionId;
        address trader;
        address liquidator;
        bytes32 marketId;
        CommonStructs.Side side;
        uint256 size;
        uint256 collateral;
        uint256 markPrice;
        uint256 liquidationPrice;
        uint256 liquidationFee;
        uint256 insuranceFundContribution;
        uint256 timestamp;
    }

    /**
     * @notice Position health metrics for liquidation checking
     * @param positionId Position identifier
     * @param marginRatio Current margin / required margin (basis points)
     * @param maintenanceMarginRequired Minimum to avoid liquidation (18 decimals)
     * @param availableMargin Margin after unrealized PnL (18 decimals)
     * @param liquidationPrice Price triggering liquidation (18 decimals)
     * @param distanceToLiquidation Percentage away from liquidation (basis points)
     * @param isLiquidatable Whether position can be liquidated now
     */
    struct PositionHealth {
        bytes32 positionId;
        uint256 marginRatio;
        uint256 maintenanceMarginRequired;
        uint256 availableMargin;
        uint256 liquidationPrice;
        uint256 distanceToLiquidation;
        bool isLiquidatable;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                  EXECUTION STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Trade execution result
     * @param orderId Order that was executed
     * @param positionId Position opened/modified (if applicable)
     * @param marketId Market where trade occurred
     * @param trader Trader address
     * @param side LONG or SHORT
     * @param price Execution price (18 decimals)
     * @param size Amount traded (18 decimals)
     * @param fees Total fees charged (18 decimals)
     * @param pnl Realized profit/loss for closing trades (can be negative)
     * @param executionMode Where order was filled (AUTO/VAULT_ONLY/ORDERBOOK_ONLY)
     * @param timestamp Execution time
     */
    struct TradeExecution {
        bytes32 orderId;
        bytes32 positionId;
        bytes32 marketId;
        address trader;
        CommonStructs.Side side;
        uint256 price;
        uint256 size;
        uint256 fees;
        int256 pnl;
        ExecutionMode executionMode;
        uint256 timestamp;
    }

    /**
     * @notice Batch execution request from keeper
     * @param keeper Address executing batch
     * @param orderIds Orders to execute
     * @param maxGasPrice Maximum gas price willing to pay (wei)
     * @param deadline Execution must complete before this time
     * @param signature Keeper's signature proving authorization
     */
    struct BatchExecutionRequest {
        address keeper;
        bytes32[] orderIds;
        uint256 maxGasPrice;
        uint256 deadline;
        bytes signature;
    }

    /**
     * @notice Result of batch execution
     * @param batchId Unique batch identifier
     * @param keeper Executor address
     * @param successfulExecutions Orders successfully filled
     * @param failedExecutions Orders that failed
     * @param totalGasUsed Gas consumed by batch (wei)
     * @param totalFees Execution fees collected (18 decimals)
     * @param timestamp Batch execution time
     */
    struct BatchExecutionResult {
        bytes32 batchId;
        address keeper;
        bytes32[] successfulExecutions;
        bytes32[] failedExecutions;
        uint256 totalGasUsed;
        uint256 totalFees;
        uint256 timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                   CROSS-MARGIN STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Cross-margin account state
     * @param trader Account owner
     * @param totalCollateral Sum of all deposited collateral (18 decimals)
     * @param usedMargin Margin allocated to open positions (18 decimals)
     * @param availableMargin Free margin for new positions (18 decimals)
     * @param unrealizedPnL Net unrealized profit/loss across all positions (can be negative)
     * @param accountValue Total account value: collateral + unrealized PnL (18 decimals)
     * @param marginRatio Account margin ratio: accountValue / usedMargin (basis points)
     * @param leverage Effective portfolio leverage (basis points)
     * @param positionIds All open positions
     */
    struct CrossMarginAccount {
        address trader;
        uint256 totalCollateral;
        uint256 usedMargin;
        uint256 availableMargin;
        int256 unrealizedPnL;
        uint256 accountValue;
        uint256 marginRatio;
        uint256 leverage;
        bytes32[] positionIds;
    }

    /**
     * @notice Margin adjustment operation
     * @param accountId Account being adjusted
     * @param isDeposit True for deposit, false for withdrawal
     * @param amount Amount being added/removed (18 decimals)
     * @param newTotalCollateral Collateral after adjustment (18 decimals)
     * @param newMarginRatio Margin ratio after adjustment (basis points)
     * @param timestamp Adjustment time
     */
    struct MarginAdjustment {
        address accountId;
        bool isDeposit;
        uint256 amount;
        uint256 newTotalCollateral;
        uint256 newMarginRatio;
        uint256 timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      SPOT STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Spot trade against AMM vault
     * @param tradeId Unique trade identifier
     * @param trader User address
     * @param marketId Market identifier
     * @param side Buy or sell
     * @param amountIn Input token amount (18 decimals)
     * @param amountOut Output token amount (18 decimals)
     * @param price Effective execution price (18 decimals)
     * @param slippage Actual slippage vs expected (basis points)
     * @param fees Trading fees charged (18 decimals)
     * @param timestamp Trade time
     */
    struct SpotTrade {
        bytes32 tradeId;
        address trader;
        bytes32 marketId;
        CommonStructs.Side side;
        uint256 amountIn;
        uint256 amountOut;
        uint256 price;
        uint256 slippage;
        uint256 fees;
        uint256 timestamp;
    }

    /**
     * @notice AMM liquidity pool state
     * @param marketId Market identifier
     * @param reserveBase Base asset reserves (18 decimals)
     * @param reserveQuote Quote asset reserves (18 decimals)
     * @param totalLiquidity Total LP tokens outstanding (18 decimals)
     * @param price Current pool price: reserveQuote / reserveBase (18 decimals)
     * @param volume24h 24-hour trading volume (18 decimals)
     * @param fees24h 24-hour fee revenue (18 decimals)
     */
    struct AMMPool {
        bytes32 marketId;
        uint256 reserveBase;
        uint256 reserveQuote;
        uint256 totalLiquidity;
        uint256 price;
        uint256 volume24h;
        uint256 fees24h;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                 DAO MARKET MAKING STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice DAO market maker configuration for a market
     * @param marketId Market being managed
     * @param isActive Whether MM is currently operating
     * @param targetSpreadBps Desired bid-ask spread (basis points, e.g., 30 = 0.3%)
     * @param allocatedCapital Capital allocated for market making (18 decimals)
     * @param minOrderSize Minimum order size to place (18 decimals)
     * @param maxOrderSize Maximum order size to place (18 decimals)
     * @param refreshIntervalSeconds How often to update orders
     * @param profitTarget Profit threshold to realize gains (18 decimals)
     */
    struct DAOMarketMakerConfig {
        bytes32 marketId;
        bool isActive;
        uint16 targetSpreadBps;
        uint256 allocatedCapital;
        uint256 minOrderSize;
        uint256 maxOrderSize;
        uint256 refreshIntervalSeconds;
        uint256 profitTarget;
    }

    /**
     * @notice DAO market maker performance metrics
     * @param marketId Market identifier
     * @param totalTrades Number of filled orders
     * @param totalVolume Cumulative trading volume (18 decimals)
     * @param totalFees Fees earned from trades (18 decimals)
     * @param realizedPnL Profit/loss from closed positions (can be negative)
     * @param unrealizedPnL Current open position PnL (can be negative)
     * @param inventory Current asset holdings: positive = long, negative = short
     * @param uptime Percentage of time MM was active (basis points)
     * @param lastUpdateTime Last metrics update
     */
    struct DAOMarketMakerMetrics {
        bytes32 marketId;
        uint256 totalTrades;
        uint256 totalVolume;
        uint256 totalFees;
        int256 realizedPnL;
        int256 unrealizedPnL;
        int256 inventory;
        uint256 uptime;
        uint256 lastUpdateTime;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                  ORDER NFT METADATA
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Extended metadata for OrderNFT with advanced order support
     * @param orderId Order identifier (from OrderManager)
     * @param nftId NFT token ID
     * @param value Order notional value: size * price (18 decimals)
     * @param collateral Margin backing order (18 decimals)
     * @param borrowAmount If collateralized, amount borrowed (18 decimals)
     * @param stakeTimestamp When NFT was staked (0 if not staked)
     * @param fillTimestamp When order filled (0 if pending)
     * @param orderType MARKET, LIMIT, SCALE, or TWAP
     * @param executionMode AUTO, VAULT_ONLY, or ORDERBOOK_ONLY
     * @param isActive Whether order is still live
     * @param configHash Hash of ScaleConfig or TWAPConfig (if applicable)
     */
    struct OrderNFTMetadata {
        bytes32 orderId;
        uint256 nftId;
        uint256 value;
        uint256 collateral;
        uint256 borrowAmount;
        uint256 stakeTimestamp;
        uint256 fillTimestamp;
        CommonStructs.OrderType orderType;
        ExecutionMode executionMode;
        bool isActive;
        bytes32 configHash;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if position is healthy
     * @param health Position health struct
     * @return bool True if position has sufficient margin
     */
    function isPositionHealthy(PositionHealth memory health) internal pure returns (bool) {
        return !health.isLiquidatable && health.marginRatio > 10000; // >100%
    }

    /**
     * @notice Check if funding payment is due
     * @param state Funding rate state
     * @return bool True if funding should be calculated
     */
    function isFundingDue(FundingRateState memory state) internal view returns (bool) {
        return block.timestamp >= state.nextFundingTime;
    }

    /**
     * @notice Calculate effective leverage from margin ratio
     * @param marginRatio Current margin ratio (basis points)
     * @return uint256 Effective leverage (basis points, e.g., 50000 = 5x)
     */
    function calculateLeverage(uint256 marginRatio) internal pure returns (uint256) {
        if (marginRatio == 0) return 0;
        return (10000 * 10000) / marginRatio; // Invert to get leverage in bps
    }

    /**
     * @notice Check if TWAP execution is due
     * @param config TWAP configuration
     * @return bool True if next slice should execute
     */
    function isTWAPExecutionDue(TWAPConfig memory config) internal view returns (bool) {
        if (!config.isActive) return false;
        if (config.executedSoFar >= config.totalSize) return false;
        if (block.timestamp > config.endTime) return false;
        return block.timestamp >= config.lastExecution + config.intervalSeconds;
    }

    /**
     * @notice Check if SCALE order has more levels to fill
     * @param config SCALE configuration
     * @return bool True if more levels remain
     */
    function hasRemainingScaleLevels(ScaleConfig memory config) internal pure returns (bool) {
        return config.currentLevel < config.totalLevels;
    }

    /**
     * @notice Calculate next SCALE price level
     * @param config SCALE configuration
     * @return uint256 Next price to place order at (18 decimals)
     */
    function getNextScalePrice(ScaleConfig memory config) internal pure returns (uint256) {
        if (!hasRemainingScaleLevels(config)) return 0;

        if (config.ascending) {
            return config.startPrice + (config.priceStep * config.currentLevel);
        } else {
            return config.startPrice - (config.priceStep * config.currentLevel);
        }
    }
}
