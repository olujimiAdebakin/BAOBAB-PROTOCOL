// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";

/**
 * @title OrderStorage
 * @notice Stores and manages all limit/stop orders for BAOBAB
 * @dev Direct integration with PositionManager. No DataStore. Gas-optimized.
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                      ORDER STORAGE ENGINE
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
contract OrderStorage {
    using CommonStructs for CommonStructs.OrderStorageOrder;
    using AddressUtils for *;
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS & ENUMS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    //     /// @notice Order types supported by the protocol
    //     enum OrderType {
    //         LIMIT,
    //         STOP,
    //         STOP_LIMIT,
    //         TAKE_PROFIT,
    //         LIQUIDATION // Internal system orders
    //     }

    //     /// @notice Order status lifecycle
    //     enum OrderStatus {
    //         PENDING,
    //         FILLED,
    //         PARTIALLY_FILLED,
    //         CANCELLED,
    //         EXPIRED,
    //         REJECTED
    //     }

    //     /// @notice Full order data structure
    //     struct Order {
    //         bytes32 orderId;
    //         address trader;
    //         bytes32 marketId;
    //         CommonStructs.Side side;
    //         OrderType orderType;
    //         uint256 size;           // 18 decimals - total order size
    //         uint256 triggerPrice;   // 18 decimals (for stop/take profit orders)
    //         uint256 limitPrice;     // 18 decimals (for limit orders)
    //         uint256 collateral;     // 18 decimals (for reduce-only orders)
    //         uint16 leverage;        // 1-1000x leverage
    //         uint256 timestamp;      // Order creation time
    //         uint256 expiry;         // 0 = no expiry, otherwise timestamp
    //         OrderStatus status;
    //         uint256 filledSize;     // How much has been filled so far
    //         bool reduceOnly;        // True if order can only reduce position
    //     }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error OrderStorage__Unauthorized();
    error OrderStorage__OrderNotFound();
    error OrderStorage__OrderAlreadyFilled();
    error OrderStorage__InvalidSize();
    error OrderStorage__InvalidPrice();
    error OrderStorage__Expired();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event OrderPlaced(
        bytes32 indexed orderId,
        address indexed trader,
        bytes32 indexed marketId,
        CommonStructs.Side side,
        CommonStructs.OrderType orderType,
        uint256 size,
        uint256 triggerPrice,
        uint256 limitPrice,
        uint16 leverage,
        bool reduceOnly
    );

    event OrderFilled(
        bytes32 indexed orderId, address indexed trader, bytes32 indexed marketId, uint256 fillPrice, uint256 fillSize
    );

    event OrderCancelled(
        bytes32 indexed orderId, address indexed trader, bytes32 indexed marketId, uint256 remainingSize, string reason
    );

    event OrderExpired(bytes32 indexed orderId);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice All orders by orderId
    mapping(bytes32 => CommonStructs.OrderStorageOrder) public orders;

    /// @notice User orders (trader => orderIds[])
    mapping(address => bytes32[]) public userOrders;

    /// @notice Market orders (marketId => orderIds[])
    mapping(bytes32 => bytes32[]) public marketOrders;

    /// @notice Pending orders by type and side (for matching)
    mapping(bytes32 => mapping(CommonStructs.Side => bytes32[])) public pendingOrders;

    /// @notice Order index in pending queue for efficient removal
    mapping(bytes32 => uint256) public orderIndexInPending;

    /// @notice Order ID counter
    uint256 private _orderIdCounter;

    /// @notice PositionManager reference - immutable for security
    address public immutable positionManager;

    // Order book structures (future enhancement)
    mapping(bytes32 => mapping(uint256 => CommonStructs.PriceLevel)) public bidLevels; // Bids sorted descending
    mapping(bytes32 => mapping(uint256 => CommonStructs.PriceLevel)) public askLevels; // Asks sorted ascending
    mapping(bytes32 => uint256) public bestBid; // Best bid price per market
    mapping(bytes32 => uint256) public bestAsk; // Best ask price per market

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize OrderStorage with PositionManager dependency
     * @param _positionManager Address of PositionManager contract
     */
    constructor(address _positionManager) {
        _positionManager.validateNotZero();
        if (_positionManager == address(0)) revert OrderStorage__Unauthorized();
        positionManager = _positionManager;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Restrict access to only PositionManager
     */
    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert OrderStorage__Unauthorized();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    ORDER LIFECYCLE - EXTERNAL
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Place a new order
     * @dev Only callable by PositionManager after validation
     * @param trader Address of the order placer
     * @param marketId Market identifier
     * @param side LONG or SHORT position direction
     * @param orderType Type of order (LIMIT, STOP, etc.)
     * @param size Order size in base asset units (18 decimals)
     * @param triggerPrice Trigger price for stop/take-profit orders
     * @param limitPrice Limit price for limit orders
     * @param collateral Collateral amount for reduce-only orders
     * @param leverage Leverage multiplier (1-1000)
     * @param expiry Order expiry timestamp (0 = no expiry)
     * @param reduceOnly Whether order can only reduce position
     * @return orderId Unique identifier for the created order
     */
    function placeOrder(
        address trader,
        bytes32 marketId,
        CommonStructs.Side side,
        CommonStructs.OrderType orderType,
        uint256 size,
        uint256 triggerPrice,
        uint256 limitPrice,
        uint256 collateral,
        uint16 leverage,
        uint256 expiry,
        bool reduceOnly
    ) external onlyPositionManager returns (bytes32 orderId) {
        // Validate input parameters
        if (size == 0) revert OrderStorage__InvalidSize();
        trader.validateNotZero();
        //   if (orderType == OrderType.LIMIT && limitPrice == 0) revert OrderStorage__InvalidPrice();
        //   if ((orderType == OrderType.STOP || orderType == OrderType.TAKE_PROFIT) && triggerPrice == 0) {
        //       revert OrderStorage__InvalidPrice();
        //   }

        if (!CommonStructs.isValidOrderStorageParams(orderType, size, triggerPrice, limitPrice)) {
            revert OrderStorage__InvalidSize();
        }

        // Generate unique order ID
        orderId = keccak256(abi.encodePacked(trader, marketId, _orderIdCounter++, block.timestamp, block.prevrandao));

        // Create order structure
        CommonStructs.OrderStorageOrder memory order = CommonStructs.OrderStorageOrder({
            orderId: orderId,
            trader: trader,
            marketId: marketId,
            side: side,
            orderType: orderType,
            size: size,
            triggerPrice: triggerPrice,
            limitPrice: limitPrice,
            collateral: collateral,
            leverage: leverage,
            timestamp: block.timestamp,
            expiry: expiry,
            status: CommonStructs.OrderStatus.PENDING,
            filledSize: 0,
            reduceOnly: reduceOnly
        });

        // Store order in mappings
        orders[orderId] = order;
        userOrders[trader].push(orderId);
        marketOrders[marketId].push(orderId);
        _addToPending(orderId, marketId, side);

        emit OrderPlaced(
            orderId, trader, marketId, side, orderType, size, triggerPrice, limitPrice, leverage, reduceOnly
        );
    }

    /**
     * @notice Fill an order (partial or full)
     * @dev Only PositionManager can fill orders after execution
     * @param orderId Order identifier to fill
     * @param fillSize Amount to fill (must be <= remaining size)
     * @param fillPrice Actual execution price
     */
    function fillOrder(bytes32 orderId, uint256 fillSize, uint256 fillPrice) external onlyPositionManager {
        CommonStructs.OrderStorageOrder storage order = orders[orderId];

        // Validate order state
        if (order.orderId == bytes32(0)) revert OrderStorage__OrderNotFound();
        if (order.status != CommonStructs.OrderStatus.PENDING) revert OrderStorage__OrderAlreadyFilled();
        if (fillSize == 0 || fillSize > order.size) revert OrderStorage__InvalidSize();

        // Update filled amount
        order.filledSize += fillSize;

        if (fillSize == order.size) {
            // Full fill - mark as filled and remove from pending
            order.status = CommonStructs.OrderStatus.FILLED;
            _removeFromPending(orderId, order.marketId, order.side);
        } else {
            // Partial fill - update remaining size
            order.status = CommonStructs.OrderStatus.PARTIALLY_FILLED;
            order.size -= fillSize;
        }

        emit OrderFilled(orderId, order.trader, order.marketId, fillPrice, fillSize);
    }

    /**
     * @notice Cancel a single order
     * @param orderId Order identifier to cancel
     * @param reason Reason for cancellation
     */
    function cancelOrder(bytes32 orderId, string calldata reason) external onlyPositionManager {
        _cancelOrder(orderId, reason);
    }

    /**
     * @notice Cancel multiple orders in batch
     * @param orderIds Array of order identifiers to cancel
     * @param reason Reason for cancellation
     */
    function cancelOrderBatch(bytes32[] calldata orderIds, string calldata reason) external onlyPositionManager {
        for (uint256 i = 0; i < orderIds.length; i++) {
            _cancelOrder(orderIds[i], reason);
        }
    }

    /**
     * @notice Cancel all user orders in a specific market
     * @param trader Address of the trader
     * @param marketId Market identifier
     * @param reason Reason for cancellation
     * @return cancelledCount Number of orders cancelled
     */
    function cancelAllUserOrdersInMarket(address trader, bytes32 marketId, string calldata reason)
        external
        onlyPositionManager
        returns (uint256 cancelledCount)
    {
        bytes32[] memory userOrderIds = userOrders[trader];

        for (uint256 i = 0; i < userOrderIds.length; i++) {
            CommonStructs.OrderStorageOrder storage order = orders[userOrderIds[i]];

            // Only cancel active orders in this market
            if (
                order.marketId == marketId
                    && (
                        order.status == CommonStructs.OrderStatus.PENDING
                            || order.status == CommonStructs.OrderStatus.PARTIALLY_FILLED
                    )
            ) {
                _cancelOrder(userOrderIds[i], reason);
                cancelledCount++;
            }
        }
    }

    /**
     * @notice Cancel all user orders across all markets
     * @param trader Address of the trader
     * @param reason Reason for cancellation
     * @return cancelledCount Number of orders cancelled
     */
    function cancelAllUserOrders(address trader, string calldata reason)
        external
        onlyPositionManager
        returns (uint256 cancelledCount)
    {
        bytes32[] memory userOrderIds = userOrders[trader];

        for (uint256 i = 0; i < userOrderIds.length; i++) {
            CommonStructs.OrderStorageOrder storage order = orders[userOrderIds[i]];

            // Only cancel active orders
            if (
                order.status == CommonStructs.OrderStatus.PENDING
                    || order.status == CommonStructs.OrderStatus.PARTIALLY_FILLED
            ) {
                _cancelOrder(userOrderIds[i], reason);
                cancelledCount++;
            }
        }
    }

    /**
     * @notice Expire a single order
     * @param orderId Order identifier to expire
     */
    function expireOrder(bytes32 orderId) external onlyPositionManager {
        _expireOrder(orderId);
    }

    /**
     * @notice Expire multiple orders in batch
     * @param orderIds Array of order identifiers to expire
     */
    function expireOrderBatch(bytes32[] calldata orderIds) external onlyPositionManager {
        for (uint256 i = 0; i < orderIds.length; i++) {
            _expireOrder(orderIds[i]);
        }
    }

    /**
     * @notice Clean up expired orders for a market
     * @param marketId Market identifier to clean up
     * @return expiredCount Number of orders expired
     */
    function cleanupExpiredOrders(bytes32 marketId) external onlyPositionManager returns (uint256 expiredCount) {
        bytes32[] memory marketOrderIds = marketOrders[marketId];

        for (uint256 i = 0; i < marketOrderIds.length; i++) {
            CommonStructs.OrderStorageOrder storage order = orders[marketOrderIds[i]];

            // Check if expired and still active
            if (
                order.expiry > 0 && block.timestamp >= order.expiry
                    && (
                        order.status == CommonStructs.OrderStatus.PENDING
                            || order.status == CommonStructs.OrderStatus.PARTIALLY_FILLED
                    )
            ) {
                order.status = CommonStructs.OrderStatus.EXPIRED;
                _removeFromPending(marketOrderIds[i], marketId, order.side);
                emit OrderExpired(marketOrderIds[i]);
                expiredCount++;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    ORDER LIFECYCLE - INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal function to cancel an order
     * @param orderId Order identifier to cancel
     * @param reason Reason for cancellation
     */
    function _cancelOrder(bytes32 orderId, string memory reason) internal {
        CommonStructs.OrderStorageOrder storage order = orders[orderId];

        // Validation checks
        if (order.orderId == bytes32(0)) revert OrderStorage__OrderNotFound();
        if (
            order.status != CommonStructs.OrderStatus.PENDING
                && order.status != CommonStructs.OrderStatus.PARTIALLY_FILLED
        ) {
            revert OrderStorage__OrderAlreadyFilled();
        }

        // Update status
        order.status = CommonStructs.OrderStatus.CANCELLED;

        // Remove from pending queue
        _removeFromPending(orderId, order.marketId, order.side);

        // Emit event
        emit OrderCancelled(orderId, order.trader, order.marketId, order.size - order.filledSize, reason);
    }

    /**
     * @notice Internal function to expire an order
     * @param orderId Order identifier to expire
     */
    function _expireOrder(bytes32 orderId) internal {
        CommonStructs.OrderStorageOrder storage order = orders[orderId];

        if (order.orderId == bytes32(0)) revert OrderStorage__OrderNotFound();
        if (order.expiry == 0 || block.timestamp < order.expiry) {
            revert OrderStorage__Expired();
        }

        order.status = CommonStructs.OrderStatus.EXPIRED;
        _removeFromPending(orderId, order.marketId, order.side);
        emit OrderExpired(orderId);
    }

    /**
     * @notice Add order to pending queue with index tracking
     * @param orderId Order identifier to add
     * @param marketId Market identifier
     * @param side Order side (LONG/SHORT)
     */
    function _addToPending(bytes32 orderId, bytes32 marketId, CommonStructs.Side side) internal {
        bytes32[] storage queue = pendingOrders[marketId][side];
        orderIndexInPending[orderId] = queue.length;
        queue.push(orderId);
    }

    /**
     * @notice Remove order from pending queue efficiently
     * @param orderId Order identifier to remove
     * @param marketId Market identifier
     * @param side Order side (LONG/SHORT)
     */
    function _removeFromPending(bytes32 orderId, bytes32 marketId, CommonStructs.Side side) internal {
        bytes32[] storage queue = pendingOrders[marketId][side];
        uint256 index = orderIndexInPending[orderId];
        uint256 lastIndex = queue.length - 1;

        // Swap and pop for O(1) removal
        if (index != lastIndex) {
            bytes32 lastOrderId = queue[lastIndex];
            queue[index] = lastOrderId;
            orderIndexInPending[lastOrderId] = index;
        }

        queue.pop();
        delete orderIndexInPending[orderId];
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get full order data by ID
     * @param orderId Order identifier
     * @return Order structure with all order data
     */
    function getOrder(bytes32 orderId) external view returns (CommonStructs.OrderStorageOrder memory) {
        return orders[orderId];
    }

    /**
     * @notice Get all order IDs for a trader
     * @param trader Address of the trader
     * @return Array of order IDs owned by the trader
     */
    function getUserOrders(address trader) external view returns (bytes32[] memory) {
        return userOrders[trader];
    }

    /**
     * @notice Get all order IDs for a market
     * @param marketId Market identifier
     * @return Array of order IDs in the market
     */
    function getMarketOrders(bytes32 marketId) external view returns (bytes32[] memory) {
        return marketOrders[marketId];
    }

    /**
     * @notice Get pending orders for a market and side (filtered for expiry)
     * @param marketId Market identifier
     * @param side Order side (LONG/SHORT)
     * @return validOrders Array of valid pending order IDs
     */
    function getPendingOrders(bytes32 marketId, CommonStructs.Side side)
        external
        view
        returns (bytes32[] memory validOrders)
    {
        bytes32[] memory allOrders = pendingOrders[marketId][side];
        uint256 validCount = 0;

        // Count valid (non-expired) orders
        for (uint256 i = 0; i < allOrders.length; i++) {
            CommonStructs.OrderStorageOrder memory order = orders[allOrders[i]];
            if (order.expiry == 0 || block.timestamp < order.expiry) {
                validCount++;
            }
        }

        // Create array with only valid orders
        validOrders = new bytes32[](validCount);
        uint256 j = 0;
        for (uint256 i = 0; i < allOrders.length; i++) {
            CommonStructs.OrderStorageOrder memory order = orders[allOrders[i]];
            if (order.expiry == 0 || block.timestamp < order.expiry) {
                validOrders[j++] = allOrders[i];
            }
        }
    }

    /**
     * @notice Get total number of orders created
     * @return Total order count
     */
    function getOrderCount() external view returns (uint256) {
        return _orderIdCounter;
    }
}
