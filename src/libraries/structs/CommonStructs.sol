// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title CommonStructs
 * @author BAOBAB Protocol
 * @notice Shared data structures used across multiple protocol modules
 * @dev Contains core types for markets, positions, orders, and protocol state
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                        COMMON STRUCTS
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
library CommonStructs {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       ENUMERATIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Order execution types
     * @dev MARKET - Instant execution at best available price
     * @dev LIMIT - Execute only at specified price or better
     * @dev SCALE - Split order across multiple price levels
     * @dev TWAP - Time-weighted average price execution
     * @dev STOP - Converts to market order when trigger price is hit
     * @dev STOP_LIMIT - Converts to limit order when trigger price is hit
     * @dev TAKE_PROFIT - Closes position at profit target
     * @dev LIQUIDATION - System-generated for position liquidations
     */
    enum OrderType {
        MARKET,
        LIMIT,
        SCALE,
        TWAP,
        STOP,
        STOP_LIMIT,
        TAKE_PROFIT,
        LIQUIDATION
    }

    /**
     * @notice Trade direction
     * @dev LONG - Buy/bullish position
     * @dev SHORT - Sell/bearish position
     */
    enum Side {
        LONG,
        SHORT
    }

    /**
     * @notice Order lifecycle states
     * @dev PENDING - Order placed, awaiting execution
     * @dev PARTIALLY_FILLED - Partially filled, remaining size available
     * @dev FILLED - Fully executed, no further actions possible
     * @dev CANCELLED - User cancelled before full execution
     * @dev EXPIRED - Time limit reached without fill
     * @dev REJECTED - Failed validation checks during placement
     */
    enum OrderStatus {
        PENDING,
        PARTIALLY_FILLED,
        FILLED,
        CANCELLED,
        EXPIRED,
        REJECTED
    }

    /**
     * @notice Market operational states
     * @dev ACTIVE - Normal trading operations
     * @dev PAUSED - Trading temporarily halted
     * @dev CLOSED - Market permanently closed
     * @dev SETTLING - Final settlement in progress
     */
    enum MarketStatus {
        ACTIVE,
        PAUSED,
        CLOSED,
        SETTLING
    }

    /**
     * @notice Asset categories supported by protocol
     * @dev CRYPTO - Cryptocurrency pairs (BTC/USD, ETH/USD)
     * @dev STOCK - Equity markets (DANGCEM, MTNN)
     * @dev FOREX - Foreign exchange (NGN/USD, GHS/USD)
     * @dev COMMODITY - Physical commodities (Gold, Brent Crude)
     */
    enum AssetClass {
        CRYPTO,
        STOCK,
        FOREX,
        COMMODITY
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      MARKET STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Core market configuration and metadata
     * @param marketId Unique identifier for the market
     * @param baseAsset Asset being traded (e.g., "BTC", "DANGCEM")
     * @param quoteAsset Settlement currency (e.g., "USD", "USDC")
     * @param assetClass Category of asset (CRYPTO, STOCK, etc.)
     * @param status Current operational state
     * @param createdAt Timestamp of market creation
     * @param oracleAdapter Address providing price feeds
     */
    struct Market {
        bytes32 marketId;
        string baseAsset;
        string quoteAsset;
        AssetClass assetClass;
        MarketStatus status;
        uint256 createdAt;
        address oracleAdapter;
    }

    /**
     * @notice Risk parameters controlling market behavior
     * @param maxLeverage Maximum allowed leverage (e.g., 100 = 100x)
     * @param maintenanceMarginBps Minimum margin to avoid liquidation (basis points)
     * @param liquidationFeeBps Fee charged on liquidations (basis points)
     * @param maxOpenInterest Maximum total open interest allowed
     * @param maxPositionSize Largest single position permitted
     * @param tradingFeeBps Fee charged per trade (basis points)
     * @param fundingRateCoefficient Sensitivity of funding rate to imbalance
     */
    struct RiskParameters {
        uint16 maxLeverage;
        uint16 maintenanceMarginBps;
        uint16 liquidationFeeBps;
        uint256 maxOpenInterest;
        uint256 maxPositionSize;
        uint16 tradingFeeBps;
        uint256 fundingRateCoefficient;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      POSITION STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice User's open trading position
     * @param positionId Unique identifier for position
     * @param marketId Market where position exists
     * @param trader Address of position owner
     * @param side LONG or SHORT
     * @param size Amount of base asset in position (18 decimals)
     * @param collateral Margin deposited to back position (18 decimals)
     * @param entryPrice Average entry price for position (18 decimals)
     * @param leverage Position leverage (1-100x)
     * @param lastFundingIndex Last funding rate index applied
     * @param unrealizedPnL Current profit/loss (updated periodically)
     * @param liquidationPrice Price at which position gets liquidated (18 decimals)
     * @param openedAt Timestamp when position was opened
     */
    struct Position {
        bytes32 positionId;
        bytes32 marketId;
        address trader;
        Side side;
        uint256 size;
        uint256 collateral;
        uint256 entryPrice;
        uint16 leverage;
        int256 lastFundingIndex;
        int256 unrealizedPnL;
        uint256 liquidationPrice;
        uint256 openedAt;
    }

    /**
     * @notice Extended position data with runtime state tracking
     * @param position Core position data from CommonStructs
     * @param lastUpdateTime Last time position was updated
     * @param accumulatedFunding Cumulative funding payments
     * @param isLiquidatable Whether position can be liquidated now
     * @param inADLQueue Whether position is in auto-deleverage queue
     */
    struct PositionData {
        Position position;
        uint256 lastUpdateTime;
        int256 accumulatedFunding;
        bool isLiquidatable;
        bool inADLQueue;
    }

    /**
     * @notice Cross-margin portfolio for a trader
     * @param trader Address of account owner
     * @param totalCollateral Sum of all collateral across positions (18 decimals)
     * @param totalUnrealizedPnL Net unrealized profit/loss
     * @param marginRatio Current margin ratio (collateral / required margin) in basis points
     * @param positionCount Number of open positions
     * @param lastUpdateTime Last time portfolio was recalculated
     */
    struct Portfolio {
        address trader;
        uint256 totalCollateral;
        int256 totalUnrealizedPnL;
        uint256 marginRatio;
        uint256 positionCount;
        uint256 lastUpdateTime;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       ORDER STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Standard order placed by user
     * @param orderId Unique identifier for order
     * @param nftId Token ID if order minted as NFT (0 if not minted)
     * @param trader Address placing the order
     * @param marketId Market for execution
     * @param orderType MARKET, LIMIT, SCALE, or TWAP
     * @param side LONG or SHORT
     * @param size Amount to trade (18 decimals)
     * @param price Limit price (0 for market orders, 18 decimals)
     * @param leverage Leverage to apply (1-100x)
     * @param status Current order state
     * @param filledSize Amount executed so far (18 decimals)
     * @param executionFee Fee paid for keeper execution (18 decimals)
     * @param createdAt Order placement timestamp
     * @param expiresAt Expiration timestamp (0 = no expiry)
     */
    struct Order {
        bytes32 orderId;
        uint256 nftId;
        address trader;
        bytes32 marketId;
        OrderType orderType;
        Side side;
        uint256 size;
        uint256 price;
        uint16 leverage;
        OrderStatus status;
        uint256 filledSize;
        uint256 executionFee;
        uint256 createdAt;
        uint256 expiresAt;
    }

    /**
     * @notice Comprehensive order data structure for OrderStorage
     * @dev Enhanced version with advanced order type support
     * @param orderId Unique identifier for the order
     * @param trader Address of the order placer
     * @param marketId Market identifier for the trading pair
     * @param side Position direction (LONG or SHORT)
     * @param orderType Type of order determining execution logic
     * @param size Total order size in base asset units (18 decimals)
     * @param triggerPrice Trigger price for stop/take-profit orders (18 decimals)
     * @param limitPrice Limit price for limit/stop-limit orders (18 decimals)
     * @param collateral Collateral amount for reduce-only orders (18 decimals)
     * @param leverage Leverage multiplier for position (1-1000)
     * @param timestamp Order creation timestamp
     * @param expiry Order expiry timestamp (0 = no expiry)
     * @param status Current order status in lifecycle
     * @param filledSize Cumulative filled amount so far (18 decimals)
     * @param reduceOnly Reduce-only flag for position management
     */
    struct OrderStorageOrder {
        bytes32 orderId;
        address trader;
        bytes32 marketId;
        Side side;
        OrderType orderType;
        uint256 size;
        uint256 triggerPrice;
        uint256 limitPrice;
        uint256 collateral;
        uint16 leverage;
        uint256 timestamp;
        uint256 expiry;
        OrderStatus status;
        uint256 filledSize;
        bool reduceOnly;
    }

    /**
     * @notice TWAP (Time-Weighted Average Price) order configuration
     * @param totalSize Total order size to execute (18 decimals)
     * @param executedSize Size executed so far (18 decimals)
     * @param remainingSize Size left to execute (18 decimals)
     * @param chunkSize Size per execution interval (18 decimals)
     * @param intervalSeconds Time between executions in seconds
     * @param startTime When TWAP started
     * @param endTime When TWAP should complete
     * @param lastExecutionTime Last chunk execution timestamp
     * @param executionCount How many chunks executed
     * @param totalIntervals Total number of intervals
     * @param childOrderIds Child limit orders spawned
     * @param isActive Whether TWAP is currently running
     */
    struct TWAPConfig {
        uint256 totalSize;
        uint256 executedSize;
        uint256 remainingSize;
        uint256 chunkSize;
        uint256 intervalSeconds;
        uint256 startTime;
        uint256 endTime;
        uint256 lastExecutionTime;
        uint256 executionCount;
        uint256 totalIntervals;
        bytes32[] childOrderIds;
        bool isActive;
    }

    /**
     * @notice Scale order configuration for multi-level execution
     * @param totalSize Total order size (18 decimals)
     * @param startPrice Starting price level (18 decimals)
     * @param endPrice Ending price level (18 decimals)
     * @param priceStep Price increment between levels (18 decimals)
     * @param numberOfLevels How many price levels
     * @param sizePerLevel Size at each level (18 decimals)
     * @param childOrderIds Child limit orders at each level
     * @param isActive Whether scale order is active
     */
    struct ScaleConfig {
        uint256 totalSize;
        uint256 startPrice;
        uint256 endPrice;
        uint256 priceStep;
        uint256 numberOfLevels;
        uint256 sizePerLevel;
        bytes32[] childOrderIds;
        bool isActive;
    }

    /**
     * @notice Advanced order parameters for SCALE and TWAP strategies
     * @param orderId Parent order identifier
     * @param totalLevels Number of sub-orders (for SCALE)
     * @param priceStep Price increment between levels (for SCALE, 18 decimals)
     * @param duration Execution window in seconds (for TWAP)
     * @param intervalSeconds Time between executions (for TWAP)
     * @param executedIntervals Intervals completed so far
     * @param lastExecutionTime Timestamp of last execution
     */
    struct AdvancedOrderParams {
        bytes32 orderId;
        uint8 totalLevels;
        uint256 priceStep;
        uint256 duration;
        uint256 intervalSeconds;
        uint256 executedIntervals;
        uint256 lastExecutionTime;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      PRICE STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Oracle price data with metadata
     * @param price Asset price with 8 decimals (e.g., 50000.00000000 for $50k BTC)
     * @param timestamp When price was reported
     * @param confidence Price confidence interval (0-100%)
     * @param source Oracle provider address
     */
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint8 confidence;
        address source;
    }

    /// @notice Price level for order book (future enhancement)
    struct PriceLevel {
        uint256 price;
        bytes32[] orderIds; // Orders at this price level
        uint256 nextPrice; // Linked list pointer
        uint256 prevPrice; // Linked list pointer
    }

    /**
     * @notice Aggregated price from multiple oracles
     * @param median Median price from all sources (8 decimals)
     * @param mean Average price from all sources (8 decimals)
     * @param timestamp Latest update time
     * @param sourceCount Number of oracles contributing
     * @param isValid Whether price passes validation checks
     */
    struct AggregatedPrice {
        uint256 median;
        uint256 mean;
        uint256 timestamp;
        uint8 sourceCount;
        bool isValid;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    COLLATERAL STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Collateralized order (order used as collateral for loan)
     * @param orderId Order being collateralized
     * @param nftId NFT token ID of the order
     * @param borrower Address borrowing against order
     * @param loanAmount Amount borrowed in quote asset (18 decimals)
     * @param collateralValue Order value at time of loan (18 decimals)
     * @param ltv Loan-to-value ratio (basis points, max 5000 = 50%)
     * @param interestRate Annual interest rate (basis points)
     * @param borrowedAt Loan origination timestamp
     * @param dueAt Loan maturity timestamp
     * @param isActive Whether loan is currently outstanding
     */
    struct CollateralizedOrder {
        bytes32 orderId;
        uint256 nftId;
        address borrower;
        uint256 loanAmount;
        uint256 collateralValue;
        uint16 ltv;
        uint16 interestRate;
        uint256 borrowedAt;
        uint256 dueAt;
        bool isActive;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                        FEE STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Fee breakdown for a transaction
     * @param tradingFee Fee charged for executing trade (18 decimals)
     * @param executionFee Fee paid to keeper for gasless execution (18 decimals)
     * @param liquidationFee Fee charged on liquidations (18 decimals)
     * @param fundingFee Funding rate payment (can be negative, 18 decimals)
     * @param protocolFee Protocol revenue share (18 decimals)
     * @param totalFee Sum of all fees (18 decimals)
     */
    struct FeeBreakdown {
        uint256 tradingFee;
        uint256 executionFee;
        uint256 liquidationFee;
        int256 fundingFee;
        uint256 protocolFee;
        uint256 totalFee;
    }

    /**
     * @notice Protocol-wide fee distribution configuration
     * @param treasuryBps Protocol revenue share (basis points)
     * @param lpBps Liquidity provider fee share (basis points)
     * @param insuranceBps Insurance fund fee share (basis points)
     * @param stakersBps NFT stakers reward share (basis points)
     * @param burnBps Token burn allocation (basis points)
     */
    struct FeeDistribution {
        uint16 treasuryBps;
        uint16 lpBps;
        uint16 insuranceBps;
        uint16 stakersBps;
        uint16 burnBps;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if order type is valid for basic trading
     * @param orderType Order type to validate
     * @return bool True if valid order type
     */
    function isValidOrderType(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.MARKET || orderType == OrderType.LIMIT || orderType == OrderType.SCALE
            || orderType == OrderType.TWAP;
    }

    /**
     * @notice Check if market is currently tradeable
     * @param status Market status to check
     * @return bool True if market accepts new orders
     */
    function isMarketTradeable(MarketStatus status) internal pure returns (bool) {
        return status == MarketStatus.ACTIVE;
    }

    /**
     * @notice Check if order is still active and can be filled
     * @param status Order status to check
     * @return bool True if order can still be filled
     */
    function isOrderActive(OrderStatus status) internal pure returns (bool) {
        return status == OrderStatus.PENDING || status == OrderStatus.PARTIALLY_FILLED;
    }

    /**
     * @notice Check if collateralized loan is overdue
     * @param collateralizedOrder Collateralized order to check
     * @return bool True if loan is past due date
     */
    function isLoanOverdue(CollateralizedOrder memory collateralizedOrder) internal view returns (bool) {
        return collateralizedOrder.isActive && block.timestamp > collateralizedOrder.dueAt;
    }

    /**
     * @notice Calculate total interest owed on collateralized order
     * @param collateralizedOrder Collateralized order details
     * @return uint256 Interest amount owed (18 decimals)
     */
    function calculateInterestOwed(CollateralizedOrder memory collateralizedOrder) internal view returns (uint256) {
        if (!collateralizedOrder.isActive) return 0;

        uint256 timeElapsed = block.timestamp - collateralizedOrder.borrowedAt;
        uint256 annualInterest = (collateralizedOrder.loanAmount * collateralizedOrder.interestRate) / 10000;

        // Calculate pro-rated interest (365 days = 31536000 seconds)
        return (annualInterest * timeElapsed) / 31536000;
    }

    /**
     * @notice Validate fee distribution adds up to 100%
     * @param feeDistribution Fee distribution struct
     * @return bool True if distribution is valid (sums to 10000 basis points)
     */
    function isValidFeeDistribution(FeeDistribution memory feeDistribution) internal pure returns (bool) {
        uint256 total = uint256(feeDistribution.treasuryBps) + uint256(feeDistribution.lpBps)
            + uint256(feeDistribution.insuranceBps) + uint256(feeDistribution.stakersBps) + uint256(feeDistribution.burnBps);
        return total == 10000;
    }

    /**
     * @notice Calculate liquidation price for a position
     * @param position Position struct
     * @param maintenanceMarginBps Maintenance margin requirement in basis points
     * @return uint256 Price at which position gets liquidated (18 decimals)
     */
    function calculateLiquidationPrice(Position memory position, uint16 maintenanceMarginBps)
        internal
        pure
        returns (uint256)
    {
        if (position.size == 0) return 0;

        uint256 notional = (position.size * position.entryPrice) / 1e18;
        uint256 maintenanceMargin = (notional * maintenanceMarginBps) / 10000;

        if (position.collateral <= maintenanceMargin) {
            return position.side == Side.LONG ? 0 : type(uint256).max;
        }

        uint256 buffer = position.collateral - maintenanceMargin;
        uint256 priceMove = (buffer * 1e18) / position.size;

        if (position.side == Side.LONG) {
            return position.entryPrice > priceMove ? position.entryPrice - priceMove : 1;
        } else {
            return position.entryPrice + priceMove;
        }
    }

    /**
     * @notice Calculate unrealized PnL for a position
     * @param position Position struct
     * @param currentPrice Current market price (18 decimals)
     * @return int256 Unrealized profit/loss (can be negative, 18 decimals)
     */
    function calculateUnrealizedPnL(Position memory position, uint256 currentPrice) internal pure returns (int256) {
        if (position.size == 0) return 0;

        int256 priceDiff = position.side == Side.LONG
            ? int256(currentPrice) - int256(position.entryPrice)
            : int256(position.entryPrice) - int256(currentPrice);

        return (priceDiff * int256(position.size)) / 1e18;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                  ORDER STORAGE VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate OrderStorage order parameters
     * @param orderType Type of order to validate
     * @param size Order size to validate (must be > 0)
     * @param triggerPrice Trigger price for stop/take-profit orders
     * @param limitPrice Limit price for limit orders
     * @return bool True if order parameters are valid
     */
    function isValidOrderStorageParams(OrderType orderType, uint256 size, uint256 triggerPrice, uint256 limitPrice)
        internal
        pure
        returns (bool)
    {
        if (size == 0) return false;

        if (orderType == OrderType.LIMIT && limitPrice == 0) return false;

        if ((orderType == OrderType.STOP || orderType == OrderType.TAKE_PROFIT) && triggerPrice == 0) {
            return false;
        }

        return true;
    }

    /**
     * @notice Check if order can be filled with specified amount
     * @param order Order to check
     * @param fillSize Amount to fill
     * @return bool True if order can be filled with given amount
     */
    function canFillOrder(OrderStorageOrder memory order, uint256 fillSize) internal pure returns (bool) {
        return order.status == OrderStatus.PENDING && fillSize > 0 && fillSize <= order.size;
    }

    /**
     * @notice Check if order can be cancelled
     * @param order Order to check
     * @return bool True if order can be cancelled
     */
    function canCancelOrder(OrderStorageOrder memory order) internal pure returns (bool) {
        return order.status == OrderStatus.PENDING || order.status == OrderStatus.PARTIALLY_FILLED;
    }

    /**
     * @notice Check if order is expired based on current time
     * @param order Order to check
     * @return bool True if order is expired
     */
    function isOrderExpired(OrderStorageOrder memory order) internal view returns (bool) {
        return order.expiry > 0 && block.timestamp >= order.expiry;
    }

    /**
     * @notice Calculate remaining order size available for execution
     * @param order Order to calculate
     * @return uint256 Remaining size available for execution (18 decimals)
     */
    function getRemainingSize(OrderStorageOrder memory order) internal pure returns (uint256) {
        return order.size - order.filledSize;
    }
}
