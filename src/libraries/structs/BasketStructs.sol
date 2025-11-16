// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "./CommonStructs.sol";

/**
 * @title BasketStructs
 * @author BAOBAB Protocol
 * @notice Data structures for tokenized basket products (Asset Baskets & Order Baskets)
 * @dev Contains structs for basket creation, rebalancing, and performance tracking
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                       BASKET STRUCTS
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
library BasketStructs {
    using CommonStructs for *;
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       ENUMERATIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Type of basket product
     * @dev ASSET_BASKET - Holds actual tokens (e.g.ETF, Commodity, African Tech Index)
     * @dev ORDER_BASKET - Bundles pending OrderNFTs (e.g., Volatility Strategy Fund)
     */
    enum BasketType {
        ASSET_BASKET,
        ORDER_BASKET
    }

    /**
     * @notice Rebalancing methodology
     * @dev MANUAL - Manager manually rebalances
     * @dev SCHEDULED - Automatic rebalance at fixed intervals
     * @dev THRESHOLD - Rebalance when drift exceeds threshold
     * @dev DYNAMIC - Algorithm-driven rebalancing
     */
    enum RebalancingStrategy {
        MANUAL,
        SCHEDULED,
        THRESHOLD,
        DYNAMIC
    }

    /**
     * @notice Basket operational status
     * @dev ACTIVE - Accepting subscriptions/redemptions
     * @dev PAUSED - Temporarily halted
     * @dev CLOSED - No longer accepting new investors
     * @dev LIQUIDATING - Winding down positions
     */
    enum BasketStatus {
        ACTIVE,
        PAUSED,
        CLOSED,
        LIQUIDATING
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    CORE BASKET STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Base basket configuration and metadata
     * @param basketId Unique identifier (keccak256 hash)
     * @param basketType ASSET_BASKET or ORDER_BASKET
     * @param name Human-readable name (e.g., "African Tech Index")
     * @param symbol Token symbol (e.g., "ATI")
     * @param description Strategy explanation for investors
     * @param manager Address managing basket composition
     * @param shareToken ERC-20 token representing shares
     * @param status Current operational state
     * @param createdAt Creation timestamp
     * @param managementFeeBps Annual management fee (basis points, e.g., 200 = 2%)
     * @param performanceFeeBps Performance fee on profits (basis points, e.g., 2000 = 20%)
     * @param minInvestment Minimum subscription amount (18 decimals)
     * @param maxInvestment Maximum subscription amount (0 = unlimited)
     */
    struct Basket {
        bytes32 basketId;
        BasketType basketType;
        string name;
        string symbol;
        string description;
        address manager;
        address shareToken;
        BasketStatus status;
        uint256 createdAt;
        uint16 managementFeeBps;
        uint16 performanceFeeBps;
        uint256 minInvestment;
        uint256 maxInvestment;
    }

    /**
     * @notice Component within basket (asset or OrderNFT)
     * @param asset Address of asset token or OrderNFT contract
     * @param tokenId Token ID (for NFTs) or 0 (for fungible assets)
     * @param targetWeightBps Desired allocation (basis points, sum = 10000)
     * @param currentWeightBps Actual current allocation (updated periodically)
     * @param amount Quantity held (18 decimals for tokens, 1 for NFTs)
     * @param entryValue Value when added to basket (18 decimals)
     * @param currentValue Latest valuation (18 decimals)
     * @param lastRebalance Last time this component was rebalanced
     * @param isFilled Whether order has executed (only for OrderNFT baskets)
     */
    struct BasketComponent {
        address asset;
        uint256 tokenId;
        uint16 targetWeightBps;
        uint16 currentWeightBps;
        uint256 amount;
        uint256 entryValue;
        uint256 currentValue;
        uint256 lastRebalance;
        bool isFilled;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                   ASSET BASKET STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Asset basket holding actual tokens
     * @param basketId Basket identifier
     * @param components Array of held assets and weights
     * @param totalValue Total basket value in quote asset (18 decimals)
     * @param totalShares Outstanding share tokens (18 decimals)
     * @param navPerShare Net asset value per share (18 decimals)
     * @param lastValuation Last NAV calculation time
     * @param rebalanceStrategy How basket rebalances
     * @param rebalanceThresholdBps Max allowed weight drift before rebalance (e.g., 500 = 5%)
     * @param nextRebalance Next scheduled rebalance (0 if not scheduled)
     */
    struct AssetBasket {
        bytes32 basketId;
        BasketComponent[] components;
        uint256 totalValue;
        uint256 totalShares;
        uint256 navPerShare;
        uint256 lastValuation;
        RebalancingStrategy rebalanceStrategy;
        uint16 rebalanceThresholdBps;
        uint256 nextRebalance;
    }

    /**
     * @notice Specific asset index (e.g., African Tech, Renewable Energy)
     * @param basketId Basket identifier
     * @param indexName Name of index (e.g., "Pan-African Equity Index")
     * @param inceptionValue Starting index value (typically 100 or 1000)
     * @param currentValue Current index value
     * @param priceReturn Return excluding dividends (basis points)
     * @param totalReturn Return including dividends (basis points)
     * @param constituents Array of components
     * @param lastUpdate Last index calculation
     */
    struct AssetIndex {
        bytes32 basketId;
        string indexName;
        uint256 inceptionValue;
        uint256 currentValue;
        int256 priceReturn;
        int256 totalReturn;
        BasketComponent[] constituents;
        uint256 lastUpdate;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                   ORDER BASKET STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Order basket bundling pending OrderNFTs
     * @param basketId Basket identifier
     * @param orderIds Array of OrderNFT token IDs in basket
     * @param strategy Trading strategy description
     * @param totalCapital Capital allocated to strategy (18 decimals)
     * @param deployedCapital Capital currently in pending orders (18 decimals)
     * @param availableCapital Unallocated capital (18 decimals)
     * @param totalShares Outstanding basket shares (18 decimals)
     * @param navPerShare Current NAV per share (18 decimals)
     * @param realizedPnL Profit/loss from filled orders (18 decimals, can be negative)
     * @param unrealizedValue Estimated value of pending orders (18 decimals)
     */
    struct OrderBasket {
        bytes32 basketId;
        uint256[] orderIds;
        string strategy;
        uint256 totalCapital;
        uint256 deployedCapital;
        uint256 availableCapital;
        uint256 totalShares;
        uint256 navPerShare;
        int256 realizedPnL;
        uint256 unrealizedValue;
    }

    /**
     * @notice Order basket component (individual OrderNFT within basket)
     * @param orderId Order identifier (from OrderManager)
     * @param nftId NFT token ID
     * @param marketId Market for order
     * @param orderType MARKET, LIMIT, SCALE, TWAP
     * @param side LONG or SHORT
     * @param size Order size (18 decimals)
     * @param allocatedCapital Capital allocated to this order (18 decimals)
     * @param entryValue Value when added to basket (18 decimals)
     * @param currentValue Latest estimated value (18 decimals)
     * @param status Current order status
     * @param addedAt When order was added to basket
     */
    struct OrderBasketComponent {
        bytes32 orderId;
        uint256 nftId;
        bytes32 marketId;
        CommonStructs.OrderType orderType;
        CommonStructs.Side side;
        uint256 size;
        uint256 allocatedCapital;
        uint256 entryValue;
        uint256 currentValue;
        CommonStructs.OrderStatus status;
        uint256 addedAt;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                  REBALANCING STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Rebalancing configuration
     * @param maxDeviationBps Max weight drift before rebalance (e.g., 500 = 5%)
     * @param minIntervalSeconds Minimum time between rebalances
     * @param maxIntervalSeconds Force rebalance after this time
     * @param gasLimit Max gas per rebalance operation
     * @param autoExecute Whether keepers auto-rebalance
     * @param maxSlippageBps Maximum slippage tolerance (e.g., 100 = 1%)
     */
    struct RebalanceConfig {
        uint16 maxDeviationBps;
        uint256 minIntervalSeconds;
        uint256 maxIntervalSeconds;
        uint256 gasLimit;
        bool autoExecute;
        uint16 maxSlippageBps;
    }

    /**
     * @notice Rebalancing operation record
     * @param basketId Basket being rebalanced
     * @param rebalanceId Unique rebalance identifier
     * @param executor Address triggering rebalance
     * @param timestamp Rebalance execution time
     * @param oldValue Basket value before rebalance (18 decimals)
     * @param newValue Basket value after rebalance (18 decimals)
     * @param removedComponents Components removed (asset addresses or NFT IDs)
     * @param addedComponents Components added (asset addresses or NFT IDs)
     * @param realizedPnL Profit/loss from trades (18 decimals, can be negative)
     * @param totalGasCost Gas cost of rebalance (18 decimals)
     */
    struct RebalanceLog {
        bytes32 basketId;
        bytes32 rebalanceId;
        address executor;
        uint256 timestamp;
        uint256 oldValue;
        uint256 newValue;
        uint256[] removedComponents;
        uint256[] addedComponents;
        int256 realizedPnL;
        uint256 totalGasCost;
    }

    /**
     * @notice Parameters for scheduled rebalancing
     * @param intervalSeconds Time between rebalances
     * @param maxSlippageBps Maximum slippage tolerance
     * @param minTradeSize Minimum size per trade (18 decimals)
     * @param gasLimitPerComponent Max gas per component adjustment
     * @param lastRebalance Last rebalance timestamp
     * @param nextRebalance Next scheduled rebalance
     */
    struct RebalanceSchedule {
        uint256 intervalSeconds;
        uint16 maxSlippageBps;
        uint256 minTradeSize;
        uint256 gasLimitPerComponent;
        uint256 lastRebalance;
        uint256 nextRebalance;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                              SUBSCRIPTION/REDEMPTION STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Investor subscription (buying basket shares)
     * @param subscriptionId Unique subscription identifier
     * @param basketId Basket being subscribed to
     * @param investor Investor address
     * @param investmentAmount Amount invested in quote asset (18 decimals)
     * @param sharesReceived Basket shares minted (18 decimals)
     * @param navAtSubscription NAV per share at subscription (18 decimals)
     * @param feesCharged Fees deducted - management + entry fees (18 decimals)
     * @param timestamp Subscription time
     */
    struct Subscription {
        bytes32 subscriptionId;
        bytes32 basketId;
        address investor;
        uint256 investmentAmount;
        uint256 sharesReceived;
        uint256 navAtSubscription;
        uint256 feesCharged;
        uint256 timestamp;
    }

    /**
     * @notice Investor redemption (selling basket shares)
     * @param redemptionId Unique redemption identifier
     * @param basketId Basket being redeemed
     * @param investor Investor address
     * @param sharesRedeemed Number of shares burned (18 decimals)
     * @param assetReceived Amount received in quote asset (18 decimals)
     * @param navAtRedemption NAV per share at redemption (18 decimals)
     * @param feesCharged Exit fees + performance fees (18 decimals)
     * @param timestamp Redemption time
     */
    struct Redemption {
        bytes32 redemptionId;
        bytes32 basketId;
        address investor;
        uint256 sharesRedeemed;
        uint256 assetReceived;
        uint256 navAtRedemption;
        uint256 feesCharged;
        uint256 timestamp;
    }

    /**
     * @notice Investor position in basket
     * @param investor Address of investor
     * @param basketId Basket identifier
     * @param shares Number of shares held (18 decimals)
     * @param depositTime Initial investment time
     * @param totalDeposited Cumulative deposits (18 decimals)
     * @param totalWithdrawn Cumulative withdrawals (18 decimals)
     * @param pendingRewards BAOBAB rewards from strategy fees (18 decimals)
     * @param lastClaimTime Last reward claim timestamp
     */
    struct InvestorPosition {
        address investor;
        bytes32 basketId;
        uint256 shares;
        uint256 depositTime;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 pendingRewards;
        uint256 lastClaimTime;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                 PERFORMANCE STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Basket performance metrics
     * @param basketId Basket identifier
     * @param inceptionDate Basket creation date
     * @param inceptionNAV Starting NAV per share (18 decimals)
     * @param currentNAV Current NAV per share (18 decimals)
     * @param dayReturn 24-hour return (basis points, e.g., 150 = 1.5%)
     * @param weekReturn 7-day return (basis points)
     * @param monthReturn 30-day return (basis points)
     * @param yearReturn 365-day return (basis points)
     * @param lifetimeReturn Total return since inception (basis points)
     * @param sharpeRatio Risk-adjusted return metric (4 decimals, e.g., 15000 = 1.5)
     * @param maxDrawdown Largest peak-to-trough decline (basis points)
     * @param volatility Annualized volatility (basis points)
     * @param totalVolume Cumulative trading volume (18 decimals)
     * @param lastUpdate Last metrics calculation
     */
    struct BasketPerformance {
        bytes32 basketId;
        uint256 inceptionDate;
        uint256 inceptionNAV;
        uint256 currentNAV;
        int256 dayReturn;
        int256 weekReturn;
        int256 monthReturn;
        int256 yearReturn;
        int256 lifetimeReturn;
        int256 sharpeRatio;
        int256 maxDrawdown;
        uint256 volatility;
        uint256 totalVolume;
        uint256 lastUpdate;
    }

    /**
     * @notice Manager fee collection record
     * @param basketId Basket identifier
     * @param manager Manager address
     * @param periodStart Fee period start
     * @param periodEnd Fee period end
     * @param managementFee Management fee collected (18 decimals)
     * @param performanceFee Performance fee collected (18 decimals)
     * @param totalFees Total fees in period (18 decimals)
     * @param timestamp Collection time
     */
    struct ManagerFeeCollection {
        bytes32 basketId;
        address manager;
        uint256 periodStart;
        uint256 periodEnd;
        uint256 managementFee;
        uint256 performanceFee;
        uint256 totalFees;
        uint256 timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                  STRATEGY FILTER STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Filter for OrderNFT selection in Order Baskets
     * @param allowedMarkets Markets to include (empty = all markets)
     * @param allowedOrderTypes Order types to include (empty = all types)
     * @param minNotional Minimum order value (18 decimals)
     * @param maxNotional Maximum order value (0 = unlimited)
     * @param minTimeToExpiry Minimum seconds until expiration
     * @param maxTimeToExpiry Maximum seconds until expiration (0 = unlimited)
     * @param requireActiveStatus Only include PENDING/PARTIAL orders
     * @param allowedSides Allowed trade directions (empty = both)
     */
    struct NFTFilter {
        bytes32[] allowedMarkets;
        CommonStructs.OrderType[] allowedOrderTypes;
        uint256 minNotional;
        uint256 maxNotional;
        uint256 minTimeToExpiry;
        uint256 maxTimeToExpiry;
        bool requireActiveStatus;
        CommonStructs.Side[] allowedSides;
    }

    /**
     * @notice Fee structure for basket operations
     * @param managementFeeBps Annual management fee (basis points, e.g., 200 = 2%)
     * @param performanceFeeBps Performance fee on profits (basis points, e.g., 2000 = 20%)
     * @param entryFeeBps Fee on subscriptions (basis points, e.g., 50 = 0.5%)
     * @param exitFeeBps Fee on redemptions (basis points, e.g., 100 = 1%)
     * @param feeRecipient Address receiving fees (treasury or manager)
     * @param lastFeeCollection Last fee collection timestamp
     */
    struct FeeStructure {
        uint16 managementFeeBps;
        uint16 performanceFeeBps;
        uint16 entryFeeBps;
        uint16 exitFeeBps;
        address feeRecipient;
        uint256 lastFeeCollection;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    VALIDATION HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if basket is accepting investments
     * @param status Basket status
     * @return bool True if basket is active
     */
    function isBasketActive(BasketStatus status) internal pure returns (bool) {
        return status == BasketStatus.ACTIVE;
    }

    /**
     * @notice Validate component weights sum to 100%
     * @param components Array of basket components
     * @return bool True if weights sum to 10000 (100%)
     */
    function validateWeights(BasketComponent[] memory components) internal pure returns (bool) {
        uint256 totalWeight;
        for (uint256 i = 0; i < components.length; i++) {
            totalWeight += components[i].targetWeightBps;
        }
        return totalWeight == 10000;
    }

    /**
     * @notice Check if rebalance is due based on time
     * @param schedule Rebalance schedule
     * @return bool True if rebalance should execute
     */
    function isRebalanceDue(RebalanceSchedule memory schedule) internal view returns (bool) {
        return block.timestamp >= schedule.nextRebalance;
    }

    /**
     * @notice Calculate weight drift from target
     * @param component Basket component
     * @return uint256 Absolute difference between current and target weight (bps)
     */
    function calculateDrift(BasketComponent memory component) internal pure returns (uint256) {
        if (component.currentWeightBps > component.targetWeightBps) {
            return component.currentWeightBps - component.targetWeightBps;
        }
        return component.targetWeightBps - component.currentWeightBps;
    }

    /**
     * @notice Check if any component exceeds drift threshold
     * @param components Array of basket components
     * @param maxDeviationBps Maximum allowed drift
     * @return bool True if rebalance needed
     */
    function needsRebalance(BasketComponent[] memory components, uint16 maxDeviationBps) internal pure returns (bool) {
        for (uint256 i = 0; i < components.length; i++) {
            if (calculateDrift(components[i]) > maxDeviationBps) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Calculate NAV per share
     * @param totalValue Total basket value (18 decimals)
     * @param totalShares Outstanding shares (18 decimals)
     * @return uint256 NAV per share (18 decimals)
     */
    function calculateNAV(uint256 totalValue, uint256 totalShares) internal pure returns (uint256) {
        if (totalShares == 0) return 0;
        return (totalValue * 1e18) / totalShares;
    }
}
