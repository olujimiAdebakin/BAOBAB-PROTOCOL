// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../../security/SecurityBase.sol";
import {IPositionManager} from "../../../interfaces/IPositionManager.sol";
import {AddressUtils} from "../../../libraries/utils/AddressUtils.sol";
import {LiquidationEngine} from "../LiquidationEngine.sol";
import {AddressUtils} from "../../../libraries/utils/AddressUtils.sol";
import {ICircuitBreaker} from "../../../interfaces/ICircuitBreaker.sol";
import {IEmergencyPauser} from "../../../interfaces/IEmergencyPauser.sol";

/**
 * @title AutoDeleverageEngine
 * @author BAOBAB Protocol
 * @notice Automatically closes profitable opposing positions when liquidations can't fill
 * @dev Protects insurance fund by socializing losses among profitable traders
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                  AUTO-DELEVERAGE ENGINE
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *
 * ADL MECHANISM (Auto-Deleverage):
 * 1. Liquidation triggered but cannot fill (no counterparty in orderbook/vault)
 * 2. Insurance Fund balance < required cover → shortfall detected
 * 3. System ranks profitable positions on the OPPOSITE side by ADL Score:
 *    → ADL Score = (unrealizedPnL × leverage) / 100   (higher = deleveraged first)
 * 4. Force-closes top-ranked positions until shortfall fully covered
 * 5. Deleveraged traders realize & KEEP 100% of their profits (only future upside lost)
 *
 * NIGERIA FLASH-CRASH EXAMPLE:
 * - Jimi opens 10x LONG BTC-PERP @ $60k
 * - Price dumps to $30k → Jimi liquidated, needs $100k to close
 * - Insurance Fund only has $20k → $80k shortfall
 * - ADL scans all SHORT winners:
 *   • Pelumi: +$50k profit @ 20x leverage → score = ($50k × 20) / 100 = 10,000
 *   • Ada:    +$30k profit @ 15x leverage → score = ($30k × 15) / 100 =  4,500
 *   • Chike:  +$10k profit @ 25x leverage → score = ($10k × 25) / 100 =  2,500
 * - Protocol force-closes Pelumi fully + Ada partially
 * - Jimi’s position closed at fair price
 * - Pelumi keeps his full $50k profit, Ada keeps $30k
 * - Insurance Fund loses only $20k → SAVED 🇳🇬
 *
 * ON-CHAIN SCORE CALCULATION (Pelumi):
 *   unrealizedPnL = 50_000 * 1e18          // $50k in 18 decimals
 *   leverage      = 20                     // uint16
 *   adlScore      = (50_000e18 × 20) / 100
 *                 = 1_000_000e18 / 100
 *                 = 10_000e18              // stored on-chain
 *
 * Frontend displays: "ADL Rank #1 · Score 10,000 · HIGH RISK"
 *
 * Hyperliquid/Bybit-grade protection. Built for African volatility. 🚀
 */
contract AutoDeleverageEngine is SecurityBase {
    IPositionManager public positionManager;
    LiquidationEngine public liquidationEngine;
    ICircuitBreaker public circuitBreaker;
    IEmergencyPauser public emergencyPauser;

    using AddressUtils for *;
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Position ranking for ADL queue
     * @param positionId Position identifier
     * @param trader Trader address
     * @param side LONG or SHORT
     * @param unrealizedPnL Current profit (always positive for ADL candidates)
     * @param leverage Position leverage
     * @param adlScore Ranking score (higher = first to be deleveraged)
     * @param lastUpdateTime Last queue update
     */
    struct ADLCandidate {
        bytes32 positionId;
        address trader;
        CommonStructs.Side side;
        uint256 unrealizedPnL;
        uint16 leverage;
        uint256 adlScore;
        uint256 lastUpdateTime;
    }

    /**
     * @notice ADL execution record
     * @param adlId Unique ADL event identifier
     * @param marketId Market where ADL occurred
     * @param liquidatedPosition Position that triggered ADL
     * @param deleveragedPositions Positions that were force-closed
     * @param totalSizeClosed Total size closed (18 decimals)
     * @param executionPrice Price at which ADL executed (18 decimals)
     * @param timestamp ADL execution time
     */
    struct ADLExecution {
        bytes32 adlId;
        bytes32 marketId;
        bytes32 liquidatedPosition;
        bytes32[] deleveragedPositions;
        uint256 totalSizeClosed;
        uint256 executionPrice;
        uint256 timestamp;
    }

    /**
     * @notice ADL configuration per market
     * @param isEnabled Whether ADL is active for this market
     * @param insuranceFundThreshold Insurance fund % before ADL triggers (bps)
     * @param maxPositionsPerADL Maximum positions to deleverage in one event
     * @param gracePeriod Time to attempt normal liquidation before ADL (seconds)
     */
    struct ADLConfig {
        bool isEnabled;
        uint16 insuranceFundThreshold;
        uint8 maxPositionsPerADL;
        uint256 gracePeriod;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Per-market ADL configuration storage
     * @dev Maps market identifier to its specific ADL parameters
     * @dev Different markets can have different ADL thresholds and behaviors
     * @dev Example: ETH market might have 80% insurance fund threshold, BTC 75%
     * @dev Key: bytes32 marketId (e.g., keccak256("ETH-USD"))
     * @dev Value: ADLConfig struct containing thresholds, limits, and flags
     */
    mapping(bytes32 => ADLConfig) public adlConfigs;

    /**
     * @notice ADL candidate queue organized by market and side
     * @dev Two-dimensional mapping: market → side → array of ADL candidates
     * @dev Candidates are sorted by profitability (most profitable first)
     * @dev LONG side queue: Profitable long positions that can be force-closed to cover short liquidation deficits
     * @dev SHORT side queue: Profitable short positions that can be force-closed to cover long liquidation deficits
     * @dev When ADL triggers, system dequeues from the opposite side of the liquidated position
     */
    mapping(bytes32 => mapping(CommonStructs.Side => ADLCandidate[])) public adlQueues;

    /**
     * @notice Reverse mapping from position ID to its index in the ADL queue
     * @dev Enables O(1) lookup and removal from ADL queues
     * @dev Without this, removing a position would require O(n) queue scanning
     * @dev Key: bytes32 positionId (unique position identifier)
     * @dev Value: uint256 index in the adlQueues[market][side] array
     * @dev Special value: type(uint256).max indicates position is not in queue
     */
    mapping(bytes32 => uint256) public queueIndices;

    /**
     * @notice Historical record of ADL executions for auditing and analysis
     * @dev Stores complete execution details for each ADL event
     * @dev Key: bytes32 adlId (unique ADL event identifier)
     * @dev Value: ADLExecution struct containing:
     *   - marketId, triggerPositionId, totalSizeClosed
     *   - timestamp, executedPrice, insuranceShortfall
     *   - array of deleveraged positions with their PnL
     * @dev Used for post-mortem analysis, risk reporting, and user compensation
     */
    mapping(bytes32 => ADLExecution) public adlExecutions;

    /**
     * @notice Counter of total ADL events per market for risk monitoring
     * @dev Tracks how frequently ADL activates in each market
     * @dev Key: bytes32 marketId
     * @dev Value: uint256 count of ADL events (incremented on each ADL trigger)
     * @dev High counts may indicate market instability or need for parameter adjustment
     * @dev Used in risk dashboards and governance reporting
     */
    mapping(bytes32 => uint256) public totalADLEvents;

    /**
     * @notice Authorized liquidation engine contract address
     * @dev Only this contract can trigger ADL operations
     * @dev LiquidationEngine determines when insurance fund is depleted and ADL is needed
     * @dev Separation of concerns: LiquidationEngine handles normal liquidations, ADL handles extreme cases
     * @dev Set during initialization and immutable thereafter for security
     */
    address public liquidationEngine;

    /**
     * @notice Insurance vault contract address
     * @dev Protocol's insurance fund that covers liquidation shortfalls
     * @dev ADL only triggers when insurance vault cannot fully cover a liquidation loss
     * @dev Source of funds for partial compensation to deleveraged traders
     * @dev May pay bonuses to traders whose positions are force-closed via ADL
     */
    address public insuranceVault;

    /**
     * @notice Protocol administrator address with configuration privileges
     * @dev Can update ADL parameters, enable/disable ADL per market
     * @dev Typically a multi-sig or governance contract in production
     * @dev Critical security role - controls emergency risk management parameters
     * @dev In final implementation, this would use OpenZeppelin AccessControl
     */
    address public BaobabAdmin;
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when Automatic Deleveraging (ADL) is triggered for a market
     * @dev ADL occurs when insurance fund is depleted and profitable positions are force-closed to cover losses
     * @param adlId Unique identifier for the ADL event
     * @param marketId Market where ADL was triggered
     * @param liquidatedPosition Position that triggered the ADL (the one being covered)
     * @param totalSizeClosed Total position size closed across all deleveraged positions
     */
    event ADLTriggered(
        bytes32 indexed adlId, bytes32 indexed marketId, bytes32 liquidatedPosition, uint256 totalSizeClosed
    );

    /**
     * @notice Emitted when a position is automatically deleveraged (force-closed)
     * @dev This happens to profitable positions when insurance fund cannot cover liquidation losses
     * @param positionId Unique identifier of the position being deleveraged
     * @param trader Address of the position owner
     * @param realizedPnL Profit/Loss realized from the forced closure (can be positive or negative)
     * @param timestamp Block timestamp when deleveraging occurred
     */
    event PositionDeleveraged(
        bytes32 indexed positionId, address indexed trader, uint256 realizedPnL, uint256 timestamp
    );

    struct ForceCloseParams {
        bytes32 positionId;
        address trader;
        uint256 size;
        uint256 price;
    }

    /**
     * @notice Emitted when ADL queue is updated for a market side
     * @dev Tracks the queue of positions eligible for ADL (sorted by profitability)
     * @param marketId Market identifier
     * @param side LONG or SHORT side of the market
     * @param queueLength Current number of positions in the ADL queue
     */
    event ADLQueueUpdated(bytes32 indexed marketId, CommonStructs.Side side, uint256 queueLength);

    /**
     * @notice Emitted when internal ADL force-close occurs
     * @dev Internal event for debugging and monitoring ADL execution
     * @param positionId Unique identifier of the position being force-closed
     * @param trader Address of the position owner
     * @param size Size of the position being closed
     * @param price Execution price used for the force-close
     */
    event InternalADLForceClose(bytes32 indexed positionId, address indexed trader, uint256 size, uint256 price);

    /**
     * @notice Emitted when ADL configuration is updated for a market
     * @dev Includes changes to ADL thresholds, queue parameters, or activation conditions
     * @param marketId Market identifier
     */
    event ADLConfigUpdated(bytes32 indexed marketId);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Reverts when caller is not the authorized LiquidationEngine
     * @dev ADL operations should only be triggered by the liquidation system
     * @dev This prevents unauthorized actors from triggering deleveraging
     */
    error ADL__OnlyLiquidationEngine();

    /**
     * @notice Reverts when caller is not the PositionManager
     * @dev ADL queue updates must come from position lifecycle events
     * @dev Ensures only valid position changes affect ADL candidacy
     */
    error ADL__onlyPositionManager();
    /**
     * @notice Reverts when caller is not protocol admin
     * @dev Configuration changes and emergency operations require admin privileges
     * @dev Protects critical ADL parameters from unauthorized modification
     */
    error ADL__OnlyAdmin();

    /**
     * @notice Reverts when Automatic Deleveraging is not enabled for the market
     * @dev ADL must be explicitly enabled per-market via governance
     * @dev Some markets may operate without ADL for specific risk profiles
     */
    error ADL__ADLNotEnabled();

    /**
     * @notice Reverts when ADL engine or protocol is paused
     * @dev Pausing ADL halts all automatic deleveraging operations
     * @dev Used in emergencies to prevent further risk during crises
     */
    error ADL_ENGINE__Paused();

    /**
     * @notice Reverts when circuit breaker is active for the market
     * @dev ADL should not operate during circuit breaker halts
     * @dev Prevents further risk actions when markets are already frozen
     */
    error ADL__CircuitActive();

    /**
     * @notice Reverts when insufficient profitable positions available for ADL
     * @dev ADL requires enough profitable positions to cover liquidation shortfall
     * @dev If no profitable positions exist, protocol may need to use insurance fund
     */
    error ADL__InsufficientCandidates();

    /**
     * @notice Reverts when ADL configuration parameters are invalid
     * @dev Ensures ADL thresholds, limits, and ratios are within safe bounds
     * @dev Prevents dangerous configurations that could harm protocol solvency
     */
    error ADL__InvalidConfig();

    /**
     * @notice Reverts when general input parameters are invalid
     * @dev Catch-all for malformed inputs, zero values, or out-of-bounds parameters
     * @dev Provides safety against incorrect function calls
     */
    error InvalidInput();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor(
        address _admin,
        address _liquidationEngine,
        address _insuranceVault,
        address _positionManager,
        address _liquidationEngine
    ) {
        // Zero-address guard — prevents deployment with invalid core contracts
        if (
            _admin == address(0) || _liquidationEngine == address(0) || _insuranceVault == address(0)
                || _positionManager == address(0)
        ) {
            revert ADL__InvalidConfig();
        }

        _admin.validateNotZero();
        _liquidationEngine.validateContract();
        _insuranceVault.validateContract();
        _positionManager.validateContract();

        positionManager = IPositionManager(_positionManager);
        if (_positionManager == address(0)) revert ADL__InvalidConfig();

        BaobabAdmin = _admin;
        insuranceVault = _insuranceVault;
        liquidationEngine = _liquidationEngine;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyLiquidationEngine() {
        msg.sender.isZero();
        if (msg.sender != liquidationEngine) revert ADL__OnlyLiquidationEngine();
        _;
    }

    modifier onlyPositionManager() {
        msg.sender.isZero();
        if (msg.sender != positionManager) revert ADL__onlyPositionManager();
        _;
    }

    /**
     * @notice Checks if the Pauser contract has paused operations.
     */
    modifier whenNotEmergencyPaused() {
        if (emergencyPauser.protocolPaused() || emergencyPauser.isModulePaused(ModuleIds.ADL_ENGINE)) {
            revert ADL_ENGINE__Paused();
        }
        _;
    }

    modifier whenCircuitNotActive(bytes32 marketId) {
        if (circuitBreaker.globalHalt() || circuitBreaker.isCircuitTripped(marketId)) {
            revert ADL__CircuitActive();
        }
        _;
    }

    modifier onlyAdmin() {
        msg.sender.validateNotZero();
        if (msg.sender != BaobabAdmin) revert ADL__OnlyAdmin();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      ADL EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute auto-deleveraging for a failed liquidation
     * @param marketId Market identifier
     * @param liquidatedPosition Position being liquidated
     * @param side Side of liquidated position (opposite side will be deleveraged)
     * @param sizeToClose Size that needs to be closed (18 decimals)
     * @param executionPrice Current market price (18 decimals)
     * @return success True if ADL completed successfully
     * @dev Only callable by LiquidationEngine when normal liquidation fails
     */

    /**
     * @notice Executes the Auto-Deleveraging (ADL) process when a standard liquidation fails.
     * @dev This function is called exclusively by the LiquidationEngine to reduce risk
     *      by force-closing positions on the opposing side of the market until the
     *      liquidated size is covered. It iterates through the ADL queue, force-closes
     *      positions, updates records, and emits events for each deleveraged position.
     *
     * @param marketId The identifier of the market where the ADL is performed.
     * @param liquidatedPosition The position ID that triggered the ADL event.
     * @param side The side (LONG or SHORT) of the liquidated position. The function
     *             deleverages positions on the opposite side.
     * @param sizeToClose The total position size to be closed, in 18-decimal precision.
     * @param executionPrice The current execution price used to close positions, in 18-decimals.
     *
     * @return success A boolean indicating whether the ADL fully covered the required size.
     */
    function executeADL(
        bytes32 marketId,
        bytes32 liquidatedPosition,
        CommonStructs.Side side,
        uint256 sizeToClose,
        uint256 executionPrice
    ) external onlyLiquidationEngine whenNotEmergencyPaused nonReentrant returns (bool success) {
        ADLConfig memory config = adlConfigs[marketId];

        if (!config.isEnabled) revert ADL__ADLNotEnabled();

        // Determine opposing side to deleverage
        CommonStructs.Side opposingSide =
            side == CommonStructs.Side.LONG ? CommonStructs.Side.SHORT : CommonStructs.Side.LONG;

        ADLCandidate[] storage queue = adlQueues[marketId][opposingSide];

        if (queue.length == 0) revert ADL__InsufficientCandidates();

        // Generate ADL ID
        bytes32 adlId = keccak256(abi.encodePacked(marketId, liquidatedPosition, block.timestamp));

        bytes32[] memory deleveragedPositions = new bytes32[](config.maxPositionsPerADL);
        uint256 totalClosed = 0;
        uint256 deleveragedCount = 0;

        // Deleverage positions from top of queue until size covered
        for (uint256 i = 0; i < queue.length && totalClosed < sizeToClose; i++) {
            if (deleveragedCount >= config.maxPositionsPerADL) break;

            ADLCandidate memory candidate = queue[i];

            // Calculate size to close from this position
            uint256 positionSize = _getPositionSize(candidate.positionId);
            uint256 closeSize = sizeToClose - totalClosed;

            if (closeSize > positionSize) {
                closeSize = positionSize;
            }

            // Force-close position
            ForceCloseParams memory params = ForceCloseParams({
                positionId: candidate.positionId,
                trader: candidate.trader,
                size: closeSize,
                price: executionPrice
            });
            _forceClosePosition(params);

            deleveragedPositions[deleveragedCount] = candidate.positionId;
            totalClosed += closeSize;
            deleveragedCount++;

            emit PositionDeleveraged(candidate.positionId, candidate.trader, candidate.unrealizedPnL, block.timestamp);
        }

        // Remove deleveraged positions from queue
        _removeFromQueue(marketId, opposingSide, deleveragedCount);

        // Record ADL execution
        adlExecutions[adlId] = ADLExecution({
            adlId: adlId,
            marketId: marketId,
            liquidatedPosition: liquidatedPosition,
            deleveragedPositions: deleveragedPositions,
            totalSizeClosed: totalClosed,
            executionPrice: executionPrice,
            timestamp: block.timestamp
        });

        totalADLEvents[marketId]++;

        emit ADLTriggered(adlId, marketId, liquidatedPosition, totalClosed);

        return totalClosed >= sizeToClose;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      QUEUE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add or update position in ADL queue
     * @param marketId Market identifier
     * @param positionId Position identifier
     * @param trader Trader address
     * @param side Position side
     * @param unrealizedPnL Current profit (18 decimals)
     * @param leverage Position leverage
     * @dev Called by PositionManager on every position update
     */
    function updateADLQueue(
        bytes32 marketId,
        bytes32 positionId,
        address trader,
        CommonStructs.Side side,
        uint256 unrealizedPnL,
        uint16 leverage
    ) external onlyPositionManager whenCircuitNotActive whenNotEmergencyPaused {
        // Only include profitable positions in ADL queue
        if (unrealizedPnL == 0) {
            _removePositionFromQueue(marketId, positionId, side);
            return;
        }

        // Calculate ADL score: higher PnL + higher leverage = higher score
        uint256 adlScore = (unrealizedPnL * leverage) / 100;

        ADLCandidate memory candidate = ADLCandidate({
            positionId: positionId,
            trader: trader,
            side: side,
            unrealizedPnL: unrealizedPnL,
            leverage: leverage,
            adlScore: adlScore,
            lastUpdateTime: block.timestamp
        });

        // Check if position already in queue
        uint256 existingIndex = queueIndices[positionId];
        ADLCandidate[] storage queue = adlQueues[marketId][side];

        if (existingIndex > 0 && existingIndex <= queue.length) {
            // Update existing entry
            queue[existingIndex - 1] = candidate;
        } else {
            // Add new entry
            queue.push(candidate);
            queueIndices[positionId] = queue.length + 1;
        }

        // Re-sort queue by ADL score (descending)
        _sortQueue(marketId, side);

        emit ADLQueueUpdated(marketId, side, queue.length);
    }

    /**
     * @notice Remove position from ADL queue
     * @param marketId Market identifier
     * @param positionId Position identifier
     * @param side Position side
     */
    function removeFromADLQueue(bytes32 marketId, bytes32 positionId, CommonStructs.Side side)
        external
        onlyPositionManager
        whenNotEmergencyPaused
        whenCircuitNotActive
    {
        _removePositionFromQueue(marketId, positionId, side);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Configure ADL for a market
     * @param marketId Market identifier
     * @param insuranceFundThreshold Insurance fund % before ADL (bps, e.g., 2000 = 20%)
     * @param maxPositionsPerADL Max positions to close per ADL event
     * @param gracePeriod Time to wait before ADL (seconds)
     */
    function configureADL(
        bytes32 marketId,
        uint16 insuranceFundThreshold,
        uint8 maxPositionsPerADL,
        uint256 gracePeriod
    ) external onlyAdmin {
        adlConfigs[marketId] = ADLConfig({
            isEnabled: true,
            insuranceFundThreshold: insuranceFundThreshold,
            maxPositionsPerADL: maxPositionsPerADL,
            gracePeriod: gracePeriod
        });

        emit ADLConfigUpdated(marketId);
    }

    /**
     * @notice Toggle ADL for a market
     * @param marketId Market identifier
     */
    function toggleADL(bytes32 marketId) external onlyAdmin whenNotEmergencyPaused {
        adlConfigs[marketId].isEnabled = !adlConfigs[marketId].isEnabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internally force-closes a trader's position during the ADL process.
     * @dev Invoked by the Auto-Deleverage (ADL) engine to close positions without user action.
     *      This function emits an internal ADL event and delegates the actual close
     *      execution to the PositionManager contract.
     *
     * @param params The parameters for force-closing a position:
     *        - positionId: The unique identifier of the position to close.
     *        - trader: The address of the position owner.
     *        - size: The portion of the position to close (in 18-decimal precision).
     *        - price: The execution price used to close the position (in 18-decimals).
     */
    function _forceClosePosition(ForceCloseParams memory params) internal {
        if (params.size == 0) revert InvalidInput();

        emit InternalADLForceClose(params.positionId, params.trader, params.size, params.price);
        IPositionManager(positionManager).forceClosePosition(
            params.positionId,
            params.price,
            false // Not a liquidation, it's ADL
        );
    }

    /**
     * @notice Get position size (internal)
     * @param positionId Position identifier
     * @return size Position size
     */
    function _getPositionSize(bytes32 positionId) internal view returns (uint256 size) {
        return IPositionManager(positionManager).getPositionSize(positionId);
    }

    /**
     * @notice Sort ADL queue by score (descending)
     * @param marketId Market identifier
     * @param side Position side
     */
    function _sortQueue(bytes32 marketId, CommonStructs.Side side) internal {
        ADLCandidate[] storage queue = adlQueues[marketId][side];

        // Simple bubble sort (fine for small queues, optimize for production)
        for (uint256 i = 0; i < queue.length; i++) {
            for (uint256 j = i + 1; j < queue.length; j++) {
                if (queue[j].adlScore > queue[i].adlScore) {
                    ADLCandidate memory temp = queue[i];
                    queue[i] = queue[j];
                    queue[j] = temp;
                }
            }
        }
    }

    /**
     * @notice Remove top N positions from queue
     * @param marketId Market identifier
     * @param side Position side
     * @param count Number to remove
     */
    function _removeFromQueue(bytes32 marketId, CommonStructs.Side side, uint256 count) internal {
        ADLCandidate[] storage queue = adlQueues[marketId][side];

        for (uint256 i = 0; i < count && queue.length > 0; i++) {
            delete queueIndices[queue[0].positionId];

            // Shift array left
            for (uint256 j = 0; j < queue.length - 1; j++) {
                queue[j] = queue[j + 1];
            }
            queue.pop();
        }
    }

    /**
     * @notice Remove specific position from queue
     * @param marketId Market identifier
     * @param positionId Position to remove
     * @param side Position side
     */
    function _removePositionFromQueue(bytes32 marketId, bytes32 positionId, CommonStructs.Side side) internal {
        uint256 index = queueIndices[positionId];
        if (index == 0) return;

        ADLCandidate[] storage queue = adlQueues[marketId][side];

        // Shift array left
        for (uint256 i = index - 1; i < queue.length - 1; i++) {
            queue[i] = queue[i + 1];
        }
        queue.pop();

        delete queueIndices[positionId];
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get ADL queue for market and side
     * @param marketId Market identifier
     * @param side Position side
     * @return queue Array of ADL candidates
     */
    function getADLQueue(bytes32 marketId, CommonStructs.Side side)
        external
        view
        returns (ADLCandidate[] memory queue)
    {
        return adlQueues[marketId][side];
    }

    /**
     * @notice Check if position is in ADL queue
     * @param positionId Position identifier
     * @return bool True if in queue
     */
    function isInADLQueue(bytes32 positionId) external view returns (bool) {
        return queueIndices[positionId] > 0;
    }

    /**
     * @notice Get position's ADL queue rank
     * @param positionId Position identifier
     * @return rank Position in queue (1 = first to be deleveraged)
     */
    function getADLRank(bytes32 positionId) external view returns (uint256 rank) {
        return queueIndices[positionId];
    }
}
