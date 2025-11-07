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
     */
    enum OrderType {
        MARKET,
        LIMIT,
        SCALE,
        TWAP
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
     * @dev PARTIAL - Partially filled
     * @dev FILLED - Fully executed
     * @dev CANCELLED - User cancelled before fill
     * @dev EXPIRED - Time limit reached without fill
     */
    enum OrderStatus {
        PENDING,
        PARTIAL,
        FILLED,
        CANCELLED,
        EXPIRED
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
     * @param size Amount of base asset in position
     * @param collateral Margin deposited to back position
     * @param entryPrice Average entry price for position
     * @param leverage Position leverage (1-100x)
     * @param lastFundingIndex Last funding rate index applied
     * @param unrealizedPnL Current profit/loss (updated periodically)
     * @param liquidationPrice Price at which position gets liquidated
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
     * @notice Cross-margin portfolio for a trader
     * @param trader Address of account owner
     * @param totalCollateral Sum of all collateral across positions
     * @param totalUnrealizedPnL Net unrealized profit/loss
     * @param marginRatio Current margin ratio (collateral / required margin)
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
     * @param size Amount to trade
     * @param price Limit price (0 for market orders)
     * @param leverage Leverage to apply (1-100x)
     * @param status Current order state
     * @param filledSize Amount executed so far
     * @param executionFee Fee paid for keeper execution
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
     * @notice Advanced order parameters for SCALE and TWAP
     * @param orderId Parent order identifier
     * @param totalLevels Number of sub-orders (for SCALE)
     * @param priceStep Price increment between levels (for SCALE)
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

    /**
     * @notice Aggregated price from multiple oracles
     * @param median Median price from all sources
     * @param mean Average price from all sources
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
     * @param loanAmount Amount borrowed in quote asset
     * @param collateralValue Order value at time of loan
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
     * @param tradingFee Fee charged for executing trade
     * @param executionFee Fee paid to keeper for gasless execution
     * @param liquidationFee Fee charged on liquidations
     * @param fundingFee Funding rate payment (can be negative)
     * @param protocolFee Protocol revenue share
     * @param totalFee Sum of all fees
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
     * @notice Protocol-wide fee configuration
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
     * @notice Check if order type is valid
     * @param orderType Order type to validate
     * @return bool True if valid order type
     */
    function isValidOrderType(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.MARKET || 
               orderType == OrderType.LIMIT || 
               orderType == OrderType.SCALE || 
               orderType == OrderType.TWAP;
    }

    /**
     * @notice Check if market is tradeable
     * @param status Market status to check
     * @return bool True if market accepts new orders
     */
    function isMarketTradeable(MarketStatus status) internal pure returns (bool) {
        return status == MarketStatus.ACTIVE;
    }

    /**
     * @notice Check if order is still active
     * @param status Order status to check
     * @return bool True if order can still be filled
     */
    function isOrderActive(OrderStatus status) internal pure returns (bool) {
        return status == OrderStatus.PENDING || status == OrderStatus.PARTIAL;
    }

    /**
     * @notice Check if position has expired collateralized loan
     * @param collateralizedOrder Collateralized order to check
     * @return bool True if loan is past due
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
        return (annualInterest * timeElapsed) / 365 days;
    }

    /**
     * @notice Validate fee distribution adds up to 100%
     * @param feeDistribution Fee distribution struct
     * @return bool True if distribution is valid
     */
    function isValidFeeDistribution(FeeDistribution memory feeDistribution) internal pure returns (bool) {
        uint256 total = uint256(feeDistribution.treasuryBps) + 
                       uint256(feeDistribution.lpBps) + 
                       uint256(feeDistribution.insuranceBps) + 
                       uint256(feeDistribution.stakersBps) + 
                       uint256(feeDistribution.burnBps);
        return total == 10000; // 100%
    }

    /**
     * @notice Calculate liquidation price for a position
     * @param position Position struct
     * @param maintenanceMarginBps Maintenance margin requirement
     * @return uint256 Price at which position gets liquidated
     */
    function calculateLiquidationPrice(
        Position memory position,
        uint16 maintenanceMarginBps
    ) internal pure returns (uint256) {
        if (position.size == 0) return 0;
        
        uint256 maintenanceMargin = (position.size * position.entryPrice * maintenanceMarginBps) / 10000;
        
        if (position.side == Side.LONG) {
            // Long liquidation: entryPrice - (collateral - maintenanceMargin) / size
            if (position.collateral <= maintenanceMargin) return 0;
            uint256 buffer = position.collateral - maintenanceMargin;
            return position.entryPrice - (buffer * 1e18 / position.size);
        } else {
            // Short liquidation: entryPrice + (collateral - maintenanceMargin) / size
            if (position.collateral <= maintenanceMargin) return type(uint256).max;
            uint256 buffer = position.collateral - maintenanceMargin;
            return position.entryPrice + (buffer * 1e18 / position.size);
        }
    }

    /**
     * @notice Calculate unrealized PnL for a position
     * @param position Position struct
     * @param currentPrice Current market price
     * @return int256 Unrealized profit/loss (can be negative)
     */
    function calculateUnrealizedPnL(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256) {
        if (position.size == 0) return 0;
        
        int256 priceDiff;
        if (position.side == Side.LONG) {
            priceDiff = int256(currentPrice) - int256(position.entryPrice);
        } else {
            priceDiff = int256(position.entryPrice) - int256(currentPrice);
        }
        
        return (priceDiff * int256(position.size)) / 1e18;
    }
}