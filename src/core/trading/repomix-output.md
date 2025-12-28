This file is a merged representation of the entire codebase, combined into a single document by Repomix.

# File Summary

## Purpose
This file contains a packed representation of the entire repository's contents.
It is designed to be easily consumable by AI systems for analysis, code review,
or other automated processes.

## File Format
The content is organized as follows:
1. This summary section
2. Repository information
3. Directory structure
4. Repository files (if enabled)
5. Multiple file entries, each consisting of:
  a. A header with the file path (## File: path/to/file)
  b. The full contents of the file in a code block

## Usage Guidelines
- This file should be treated as read-only. Any changes should be made to the
  original repository files, not this packed version.
- When processing this file, use the file path to distinguish
  between different files in the repository.
- Be aware that this file may contain sensitive information. Handle it with
  the same level of security as you would the original repository.

## Notes
- Some files may have been excluded based on .gitignore rules and Repomix's configuration
- Binary files are not included in this packed representation. Please refer to the Repository Structure section for a complete list of file paths, including binary files
- Files matching patterns in .gitignore are excluded
- Files matching default ignore patterns are excluded
- Files are sorted by Git change count (files with more changes are at the bottom)

# Directory Structure
```
engines/AutoDeleverageEngine.sol
engines/CrossMarginEngine.sol
engines/OrderBook.sol
engines/PerpEngine.sol
engines/README.md
engines/SpotEngine.sol
FundingRateEngine.sol
LiquidationEngine.sol
OrderManager.sol
PositionManager.sol
README.md
```

# Files

## File: engines/AutoDeleverageEngine.sol
````solidity
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
import {ModuleIds} from "../../../libraries/utils/ModuleIds.sol";
import {RateLimitBuckets} from "../../../libraries/utils/RateLimitBuckets.sol";
import {RateLimiter} from "../../../security/RateLimiter.sol";

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
    RateLimiter public rateLimiter;

    using AddressUtils for *;
    using ModuleIds for *;
    using RateLimitBuckets for *;
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════



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
    mapping(bytes32 => CommonStructs.ADLConfig) public adlConfigs;

    /**
     * @notice ADL candidate queue organized by market and side
     * @dev Two-dimensional mapping: market → side → array of ADL candidates
     * @dev Candidates are sorted by profitability (most profitable first)
     * @dev LONG side queue: Profitable long positions that can be force-closed to cover short liquidation deficits
     * @dev SHORT side queue: Profitable short positions that can be force-closed to cover long liquidation deficits
     * @dev When ADL triggers, system dequeues from the opposite side of the liquidated position
     */
    mapping(bytes32 => mapping(CommonStructs.Side => CommonStructs.ADLCandidate[])) public adlQueues;

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
    mapping(bytes32 => CommonStructs.ADLExecution) public adlExecutions;

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
    // address public liquidationEngine;

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
        bytes32 indexed positionId, address indexed trader, int256 realizedPnL, uint256 timestamp
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
        address _ratelimter
        // address _liquidationEngine
    ) {
        // Zero-address guard — prevents deployment with invalid core contracts
        if (
            _admin == address(0) || _liquidationEngine == address(0) || _insuranceVault == address(0)
                || _positionManager == address(0) || _ratelimter == address(0)
        ) {
            revert ADL__InvalidConfig();
        }

        _admin.validateNotZero();
        _liquidationEngine.validateContract();
        _insuranceVault.validateContract();
        _positionManager.validateContract();
        _ratelimter.validateContract();


        rateLimiter = RateLimiter(_ratelimter);
        positionManager = IPositionManager(_positionManager);
        if (_positionManager == address(0)) revert ADL__InvalidConfig();
        BaobabAdmin = _admin;
        insuranceVault = _insuranceVault;
        liquidationEngine = LiquidationEngine(_liquidationEngine);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyLiquidationEngine() {
        msg.sender.isZero();
        if (msg.sender != address(liquidationEngine)) revert ADL__OnlyLiquidationEngine();
        _;
    }

    modifier onlyPositionManager() {
        msg.sender.isZero();
        if (msg.sender !=address(positionManager)) revert ADL__onlyPositionManager();
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

    // /**
    //  * @notice Execute auto-deleveraging for a failed liquidation
    //  * @param marketId Market identifier
    //  * @param liquidatedPosition Position being liquidated
    //  * @param side Side of liquidated position (opposite side will be deleveraged)
    //  * @param sizeToClose Size that needs to be closed (18 decimals)
    //  * @param executionPrice Current market price (18 decimals)
    //  * @return success True if ADL completed successfully
    //  * @dev Only callable by LiquidationEngine when normal liquidation fails
    //  */

    // /**
    //  * @notice Executes the Auto-Deleveraging (ADL) process when a standard liquidation fails.
    //  * @dev This function is called exclusively by the LiquidationEngine to reduce risk
    //  *      by force-closing positions on the opposing side of the market until the
    //  *      liquidated size is covered. It iterates through the ADL queue, force-closes
    //  *      positions, updates records, and emits events for each deleveraged position.
    //  *
    //  * @param marketId The identifier of the market where the ADL is performed.
    //  * @param liquidatedPosition The position ID that triggered the ADL event.
    //  * @param side The side (LONG or SHORT) of the liquidated position. The function
    //  *             deleverages positions on the opposite side.
    //  * @param sizeToClose The total position size to be closed, in 18-decimal precision.
    //  * @param executionPrice The current execution price used to close positions, in 18-decimals.
    //  *
    //  * @return success A boolean indicating whether the ADL fully covered the required size.
    //  */
    // function executeADL(
    //     bytes32 marketId,
    //     bytes32 liquidatedPosition,
    //     CommonStructs.Side side,
    //     uint256 sizeToClose,
    //     uint256 executionPrice
    // ) external onlyLiquidationEngine whenNotEmergencyPaused nonReentrant returns (bool success) {

    //      CommonStructs.PositionData memory posData = positionManager.getPosition(liquidatedPosition);

    //     address trader = posData.position.trader;

    //       rateLimiter.checkRateLimit(trader, RateLimitBuckets.EXECUTE_ADL);

    //     CommonStructs.ADLConfig memory config = adlConfigs[marketId];

    //     if (!config.isEnabled) revert ADL__ADLNotEnabled();

    //     // Determine opposing side to deleverage
    //     CommonStructs.Side opposingSide =
    //         side == CommonStructs.Side.LONG ? CommonStructs.Side.SHORT : CommonStructs.Side.LONG;

    //     CommonStructs.ADLCandidate[] storage queue = adlQueues[marketId][opposingSide];

    //     if (queue.length == 0) revert ADL__InsufficientCandidates();

    //     // Generate ADL ID
    //     bytes32 adlId = keccak256(abi.encodePacked(marketId, liquidatedPosition, block.timestamp));

    //     bytes32[] memory deleveragedPositions = new bytes32[](config.maxPositionsPerADL);
    //     uint256 totalClosed = 0;
    //     uint256 deleveragedCount = 0;

    //     // Deleverage positions from top of queue until size covered
    //     for (uint256 i = 0; i < queue.length && totalClosed < sizeToClose; i++) {
    //         if (deleveragedCount >= config.maxPositionsPerADL) break;

    //         CommonStructs.ADLCandidate memory candidate = queue[i];

    //         // Calculate size to close from this position
    //         uint256 positionSize = _getPositionSize(candidate.positionId);
    //         uint256 closeSize = sizeToClose - totalClosed;

    //         if (closeSize > positionSize) {
    //             closeSize = positionSize;
    //         }

    //         // Force-close position
    //         ForceCloseParams memory params = ForceCloseParams({
    //             positionId: candidate.positionId,
    //             trader: candidate.trader,
    //             size: closeSize,
    //             price: executionPrice
    //         });
    //         _forceClosePosition(params);

    //         deleveragedPositions[deleveragedCount] = candidate.positionId;
    //         totalClosed += closeSize;
    //         deleveragedCount++;

    //         emit PositionDeleveraged(candidate.positionId, candidate.trader, candidate.unrealizedPnL, block.timestamp);
    //     }

    //     // Remove deleveraged positions from queue
    //     _removeFromQueue(marketId, opposingSide, deleveragedCount);

    //     // Record ADL execution
    //     adlExecutions[adlId] = CommonStructs.ADLExecution({
    //         adlId: adlId,
    //         marketId: marketId,
    //         liquidatedPosition: liquidatedPosition,
    //         deleveragedPositions: deleveragedPositions,
    //         totalSizeClosed: totalClosed,
    //         executionPrice: executionPrice,
    //         timestamp: block.timestamp
    //     });

    //     totalADLEvents[marketId]++;

    //     emit ADLTriggered(adlId, marketId, liquidatedPosition, totalClosed);

    //     return totalClosed >= sizeToClose;
    // }

    
    function executeADL(
    bytes32 marketId,
    bytes32 liquidatedPosition,
    CommonStructs.Side side,
    uint256 sizeToClose,
    uint256 executionPrice
) 
    external 
    onlyLiquidationEngine 
    whenNotEmergencyPaused 
    nonReentrant 
    returns (bool success) 
{
    CommonStructs.PositionData memory posData = positionManager.getPosition(liquidatedPosition);
    address trader = posData.position.trader;

    rateLimiter.checkRateLimit(trader, RateLimitBuckets.EXECUTE_ADL);

    CommonStructs.ADLConfig memory config = adlConfigs[marketId];
    if (!config.isEnabled) revert ADL__ADLNotEnabled();

    CommonStructs.Side opposingSide =
        side == CommonStructs.Side.LONG ? CommonStructs.Side.SHORT : CommonStructs.Side.LONG;

    CommonStructs.ADLCandidate[] storage queue = adlQueues[marketId][opposingSide];
    if (queue.length == 0) revert ADL__InsufficientCandidates();

    bytes32 adlId = keccak256(abi.encodePacked(marketId, liquidatedPosition, block.timestamp));

    (bytes32[] memory deleveragedPositions, uint256 totalClosed) =
        _processADLDeleverages(
            marketId,
            opposingSide,
            sizeToClose,
            executionPrice,
            queue,
            config
        );

    _removeFromQueue(marketId, opposingSide, deleveragedPositions.length);

    adlExecutions[adlId] = CommonStructs.ADLExecution({
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
        int256 unrealizedPnL,
        uint16 leverage
    ) external onlyPositionManager  whenNotEmergencyPaused whenCircuitNotActive(marketId){

        // CommonStructs.PositionData memory posData = positionManager.getPosition(positionId);

        // address user = posData.position.trader;

        // rateLimiter.checkRateLimit(user, keccak256(abi.encodePacked("UPDATE_ADL_QUEUE")));
        // Only include profitable positions in ADL queue
        require(unrealizedPnL > 0, "NEGATIVE_PNL");
        if (unrealizedPnL == 0) {
            _removePositionFromQueue(marketId, positionId, side);
            return;
        }

        // Calculate ADL score: higher PnL + higher leverage = higher score
        uint256 adlScore = (uint256(unrealizedPnL) * uint256(leverage)) / 100;

        CommonStructs.ADLCandidate memory candidate = CommonStructs.ADLCandidate({
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
        CommonStructs.ADLCandidate[] storage queue = adlQueues[marketId][side];

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
       whenCircuitNotActive(marketId)
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
        adlConfigs[marketId] = CommonStructs.ADLConfig({
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

    
    function _processADLDeleverages(
    bytes32 /* marketId */,
    CommonStructs.Side /* opposingSide */,
    uint256 sizeToClose,
    uint256 executionPrice,
    CommonStructs.ADLCandidate[] storage queue,
    CommonStructs.ADLConfig memory config
) 
    internal 
    returns (bytes32[] memory deleveragedPositions, uint256 totalClosed)
{
    deleveragedPositions = new bytes32[](config.maxPositionsPerADL);
    uint256 deleveragedCount = 0;

    for (uint256 i = 0; i < queue.length && totalClosed < sizeToClose; i++) {
        if (deleveragedCount >= config.maxPositionsPerADL) break;

        CommonStructs.ADLCandidate memory candidate = queue[i];
        uint256 positionSize = _getPositionSize(candidate.positionId);

        uint256 closeSize = sizeToClose - totalClosed;
        if (closeSize > positionSize) closeSize = positionSize;

        _forceClosePosition(
            ForceCloseParams({
                positionId: candidate.positionId,
                trader: candidate.trader,
                size: closeSize,
                price: executionPrice
            })
        );

        deleveragedPositions[deleveragedCount] = candidate.positionId;
        totalClosed += closeSize;
        deleveragedCount++;

        emit PositionDeleveraged(
            candidate.positionId,
            candidate.trader,
            candidate.unrealizedPnL,
            block.timestamp
        );
    }
}


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
        CommonStructs.ADLCandidate[] storage queue = adlQueues[marketId][side];

        // Simple bubble sort (fine for small queues, optimize for production)
        for (uint256 i = 0; i < queue.length; i++) {
            for (uint256 j = i + 1; j < queue.length; j++) {
                if (queue[j].adlScore > queue[i].adlScore) {
                    CommonStructs.ADLCandidate memory temp = queue[i];
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
        CommonStructs.ADLCandidate[] storage queue = adlQueues[marketId][side];

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

        CommonStructs.ADLCandidate[] storage queue = adlQueues[marketId][side];

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
        returns (CommonStructs.ADLCandidate[] memory queue)
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
````

## File: engines/CrossMarginEngine.sol
````solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CrossMarginEngine
 * @notice TODO: Add contract description
 */
contract CrossMarginEngine {
// TODO: Implement contract
}
````

## File: engines/OrderBook.sol
````solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title OrderStorage
 * @notice TODO: Add contract description
 */
contract OrderBook {
// TODO: Implement contract
}
````

## File: engines/PerpEngine.sol
````solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PerpEngine
 * @notice TODO: Add contract description
 */
contract PerpEngine {
// TODO: Implement contract
}
````

## File: engines/README.md
````markdown
# BAOBAB PROTOCOL

## Overview
A high-performance decentralized perpetual exchange (Perp-DEX) engine suite built on Solidity. The system features a robust Auto-Deleverage (ADL) mechanism and modular trading engines designed for institutional-grade risk management and capital efficiency.

## Features
- **AutoDeleverageEngine**: Sophisticated risk mitigation that ranks profitable positions by ADL score to protect the insurance fund.
- **PerpEngine**: Core logic for perpetual futures contract management and funding rate calculations.
- **CrossMarginEngine**: Advanced collateral management allowing shared margin across multiple trading positions.
- **OrderBook**: High-efficiency matching engine for decentralized limit and market order execution.
- **SpotEngine**: Integrated spot trading capabilities for underlying asset liquidity.

## Getting Started
### Installation
1. Clone the repository:
```bash
git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
```
2. Install dependencies (Foundry):
```bash
forge install
```
3. Compile the smart contracts:
```bash
forge build
```

### Environment Variables
Required variables for deployment and testing:
```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-api-key
PRIVATE_KEY=0xabc123...
ETHERSCAN_API_KEY=your-etherscan-key
ADMIN_ADDRESS=0x123...
INSURANCE_VAULT_ADDRESS=0x456...
```

## API Documentation
### Base URL
Smart Contract Deployment Address (Mainnet/Testnet)

### Endpoints
#### EXTERNAL executeADL
**Request**:
```json
{
  "marketId": "bytes32",
  "liquidatedPosition": "bytes32",
  "side": "uint8 (0 for Long, 1 for Short)",
  "sizeToClose": "uint256",
  "executionPrice": "uint256"
}
```

**Response**:
```json
{
  "success": "bool"
}
```

**Errors**:
- 403: ADL__OnlyLiquidationEngine
- 403: ADL_ENGINE__Paused
- 400: ADL__InsufficientCandidates
- 400: ADL__ADLNotEnabled

#### EXTERNAL updateADLQueue
**Request**:
```json
{
  "marketId": "bytes32",
  "positionId": "bytes32",
  "trader": "address",
  "side": "uint8",
  "unrealizedPnL": "int256",
  "leverage": "uint16"
}
```

**Response**:
```json
{
  "status": "void",
  "event": "ADLQueueUpdated"
}
```

**Errors**:
- 403: ADL__onlyPositionManager
- 400: NEGATIVE_PNL
- 423: ADL__CircuitActive

#### EXTERNAL configureADL
**Request**:
```json
{
  "marketId": "bytes32",
  "insuranceFundThreshold": "uint16",
  "maxPositionsPerADL": "uint8",
  "gracePeriod": "uint256"
}
```

**Response**:
```json
{
  "status": "void",
  "event": "ADLConfigUpdated"
}
```

**Errors**:
- 403: ADL__OnlyAdmin
- 400: ADL__InvalidConfig

#### VIEW getADLQueue
**Request**:
```json
{
  "marketId": "bytes32",
  "side": "uint8"
}
```

**Response**:
```json
[
  {
    "positionId": "bytes32",
    "trader": "address",
    "side": "uint8",
    "unrealizedPnL": "int256",
    "leverage": "uint16",
    "adlScore": "uint256",
    "lastUpdateTime": "uint256"
  }
]
```

## Technologies Used
| Technology | Purpose | Link |
|------------|---------|------|
| Solidity | Smart Contract Language | [soliditylang.org](https://soliditylang.org/) |
| Foundry | Development Framework | [book.getfoundry.sh](https://book.getfoundry.sh/) |
| OpenZeppelin | Security Standards | [openzeppelin.com](https://openzeppelin.com/) |

## Contributing
- 📥 Fork the repository and create your feature branch.
- 🛠️ Ensure all logic follows the existing safety patterns (SecurityBase).
- 🧪 Write comprehensive unit tests for all new engine logic.
- 📝 Document all external functions using NatSpec.
- 🚀 Submit a pull request with a detailed description of changes.

## Author Info
**[Your Name]**
- Twitter: [@your_handle]
- LinkedIn: [linkedin.com/in/your_username]
- Portfolio: [yourportfolio.com]

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-BUSL--1.1-blue)
![Solidity](https://img.shields.io/badge/solidity-%5E0.8.24-black)
````

## File: engines/SpotEngine.sol
````solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SpotEngine
 * @notice TODO: Add contract description
 */
contract SpotEngine {
// TODO: Implement contract
}
````

## File: FundingRateEngine.sol
````solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {PositionManager} from "./PositionManager.sol";
import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {RoleRegistry} from "../../access/RoleRegistry.sol";
import {AccessManager} from "../../access/AccessManager.sol";
import {RateLimiter} from "../../security/RateLimiter.sol";
import {RateLimitBuckets} from "../../libraries/utils/RateLimitBuckets.sol";
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";
import {SecurityBase} from "../../security/SecurityBase.sol";

/**
 * @title IAccessManager
 * @notice Interface for checking if an account has a specific role.
 */
interface IAccessManager {
    /// @notice Checks if the given account holds the specified role.
    function hasRole(bytes32 role, address account) external view returns (bool);
}




/**
 * @title FundingEngine
 * @notice Calculates and applies periodic funding rates to open positions based on Open Interest (OI) imbalance.
 *
 * @dev This contract is called by a whitelisted Keeper to execute the funding cycle.
 * It reads market configuration and position data directly from the PositionManager.
 *
 * **Contract Flow:**
 * 1.  A whitelisted Keeper calls the `applyFunding(marketId)`.
 * 2.  The function first checks the market's configuration (`fundingEnabled`) and enforces the `FUNDING_PERIOD` time lock via `FundingTooSoon` error.
 * 3.  It fetches Long and Short Open Interest (OI) from the `PositionManager`.
 * 4.  The current funding rate (`rateBps`) is calculated in `_calculateRate` based on the OI skew, capped by the market's `maxFundingRateBps`.
 * 5.  The number of full elapsed funding periods is calculated.
 * 6.  `_applyToPositions` iterates through all active positions in the market.
 * 7.  For each position, the payment is calculated in `_calcPayment` based on size, rate, and periods.
 * 8.  The position's `accumulatedFunding` (debt/credit) is updated in the `PositionManager`.
 * 9.  The `lastFundingTime` is updated to `block.timestamp`, and a `FundingApplied` event is emitted.
 */
contract FundingEngine is SecurityBase {
    /// @notice Address of the PositionManager contract, used to access market configuration and position data.
    PositionManager public immutable positionManager;
    /// @notice Address of the AccessManager contract, used to verify keeper permissions.
    AccessManager public accessManager;
    /// @notice Address of the RateLimiter contract, used to enforce rate limits on funding application.
    RateLimiter public rateLimiter;

    using RateLimitBuckets for *;

    using AddressUtils for address;

    /// @notice The absolute maximum funding rate allowed if not overridden by market config (0.3% per 8 hours).
    uint256 public constant MAX_FUNDING_RATE = 300;
    /// @notice The fixed duration for a funding calculation period (8 hours).
    uint256 public constant FUNDING_PERIOD = 8 hours;
    /// @notice Constant for Basis Points (10,000) used for scaling percentages.
    uint256 public constant BASIS_POINTS = 10_000;
    /// @notice Constant for 1e18 precision, used in rate calculation for fixed-point math.
    uint256 public constant PRECISION = 1e18;

    /// @notice Maps a market ID to its current funding state.
    mapping(bytes32 => FundingState) public fundingState;

    /// @notice Maps a market ID to the timestamp when funding was last successfully applied.
    mapping(bytes32 => uint256) public lastFundingTime;

    /// @dev Emitted when funding rates are successfully calculated and applied to a market.
    /// @param marketId The ID of the market.
    /// @param rateBps The calculated funding rate in basis points (BPS).
    /// @param longOI The total long open interest at the time of calculation.
    /// @param shortOI The total short open interest at the time of calculation.
    event FundingApplied(bytes32 indexed marketId, int256 rateBps, uint256 longOI, uint256 shortOI);
    /// @dev Emitted when funding is paid to a specific position.
    /// @param positionId The ID of the position.
    /// @param amount The funding amount paid (positive means funding credit, negative means funding debt).
    /// @param isLong True if the position is long, false if short.
    event FundingPaid(bytes32 indexed positionId, int256 amount, bool isLong);

    /// @notice Thrown when `applyFunding` is called before `FUNDING_PERIOD` has elapsed.
    error FundingTooSoon();
    /// @notice Thrown when a market ID is not recognized (currently stubbed).
    error MarketNotFound();

    struct FundingState {
    uint256 lastUpdateTime;
    int256 fundingRateBps;
    int256 cumulativeFunding;  // AFPU in basis points × time
    uint256 totalLongOI;
    uint256 totalShortOI;
}


    /**
     * @notice Initializes the FundingEngine with addresses for PositionManager and AccessManager.
     * @param _positionManager The address of the PositionManager contract.
     * @param _accessManager The address of the AccessManager contract.
     */
    constructor(address _positionManager, address _accessManager, address _rateLimiter) {

        _positionManager.validateContract();
        _accessManager.validateContract();
        _rateLimiter.validateContract();

        positionManager = PositionManager(_positionManager);
        accessManager = AccessManager(_accessManager);
        rateLimiter = RateLimiter(_rateLimiter);
    }

    /**
     * @dev Restricts function execution to addresses with the KEEPER_ROLE, as defined in the RoleRegistry.
     */
    modifier onlyKeeper() {
        require(accessManager.hasRole(RoleRegistry.KEEPER_ROLE, msg.sender), "Only keeper");
        _;
    }

    /**
     * @notice Applies funding fee to all positions in a market based on the calculated rate.
     * @dev This function can only be called by a whitelisted Keeper.
     * @param marketId The market ID.
     * @return rateBps The calculated funding rate in basis points (BPS).
     */
/**
 * @notice The core keeper function to update the market's Accumulated Funding Per Unit (AFPU) index.
 * @dev This is an O(1) gas cost function, replacing the unscalable position loop. 
 * Funding liability accrues here, but settlement is "pulled" by the user on interaction.
 * @param marketId The market ID.
 * @return rateBps The calculated funding rate in basis points (BPS) for the period.
 */
function applyFundingRate(bytes32 marketId) 
    external 
    nonReentrant 
    onlyKeeper 
    returns (int256 rateBps) 
{
    rateLimiter.checkRateLimit(msg.sender, RateLimitBuckets.APPLY_FUNDING);
    
    //  Fetch Config & State
    (
        , , // maxLev, mmr (not needed)
        uint16 maxFund,
        bool fundEnabled,
        uint256 fundingInterval // Market-specific funding period
    ) = positionManager.marketConfig(marketId);

    // Get the storage pointer to the market's AFPU data structure.
    FundingState storage fs = fundingState[marketId];

    // Initial Safety Checks
    if (!fundEnabled || fundingInterval == 0) {
        // If funding is disabled, update the time anchor and exit.
        fs.lastUpdateTime = block.timestamp;
        return 0;
    }
    
    //  Time Lock Enforcement
    uint256 elapsed = block.timestamp - fs.lastUpdateTime;
    
    // Use the market's configured interval to check if enough time has passed.
    if (elapsed < fundingInterval) {
        revert FundingTooSoon();
    }

    //  Check Open Interest (OI)
    uint256 longOI = positionManager.openInterest(marketId, CommonStructs.Side.LONG);
    uint256 shortOI = positionManager.openInterest(marketId, CommonStructs.Side.SHORT);
    uint256 totalOI = longOI + shortOI;

    if (totalOI == 0) {
        // No open interest means no rate, but consume the time period.
        fs.lastUpdateTime = block.timestamp;
        return 0;
    }

    // Calculate Rate and AFPU Update
    
    // Calculate the periodic rate based on current OI skew and the market's max cap.
    rateBps = _calculateRate(longOI, shortOI, totalOI, maxFund);

    // Calculate the change in the AFPU index based on the rate and elapsed time.
    // Delta = (rateBps * elapsed * PRECISION) / (fundingInterval * BASIS_POINTS)
    int256 deltaFunding = (
        int256(rateBps)
        * int256(elapsed) 
        * int256(PRECISION)
    ) / int256(fundingInterval * BASIS_POINTS);
    
    // Update the core AFPU index (O(1) storage write). 
    fs.cumulativeFunding += deltaFunding;
    
    // Store latest metrics in the struct (for off-chain readers/monitoring)
    fs.fundingRateBps = rateBps;
    fs.totalLongOI = longOI;
    fs.totalShortOI = shortOI;
    
    //  Finalize Cycle
    // Update the time anchor to block.timestamp for the next cycle's clock.
    fs.lastUpdateTime = block.timestamp; 

    emit FundingApplied(marketId, rateBps, longOI, shortOI);

    return rateBps;
}

    /**
     * @notice Calculates the periodic funding rate based on open interest imbalance, capped by maxRateBps.
     * @dev Rate calculation: rate = (longOI - shortOI) / totalOI * maxRateBps.
     * A positive rate means Longs pay Shorts. A negative rate means Shorts pay Longs.
     * @param longOI Total open interest on the long side.
     * @param shortOI Total open interest on the short side.
     * @param totalOI The sum of longOI and shortOI.
     * @param maxRateBps The maximum absolute funding rate (in BPS) allowed for this market.
     * @return int256 The calculated funding rate in basis points (BPS).
     */
    function _calculateRate(uint256 longOI, uint256 shortOI, uint256 totalOI, uint16 maxRateBps)
        internal
        pure
        returns (int256)
    {
        // Calculate imbalance factor scaled by PRECISION: (Long OI - Short OI) / Total OI * 1e18
        int256 imbalance = (int256(longOI) - int256(shortOI)) * int256(PRECISION) / int256(totalOI);
        // Calculate raw rate: (Imbalance Factor * maxRateBps) / 1e18
        int256 rate = (imbalance * int256(uint256(maxRateBps))) / int256(PRECISION);

        // Enforce max funding rate cap (symmetrically positive and negative)
        if (rate > int256(uint256(maxRateBps))) return int256(uint256(maxRateBps));
        if (rate < -int256(uint256(maxRateBps))) return -int256(uint256(maxRateBps));
        return rate;
    }

    // /**
    //  * @notice Iterates over all open positions in a market and updates their accumulated funding.
    //  * @param marketId The market ID.
    //  * @param rateBps The calculated funding rate in BPS.
    //  * @param periods The number of full funding intervals that have elapsed since the last funding.
    //  */
    // function _applyToPositions(bytes32 marketId, int256 rateBps, uint256 periods) internal {
    //     // Fetch all position IDs for the given market
    //     bytes32[] memory posIds = positionManager.getMarketPositions(marketId);

    //     // Loop through each position ID
    //     for (uint256 i = 0; i < posIds.length; i++) {
    //         bytes32 posId = posIds[i];

    //         // Destructure the tuple returned from the public PositionManager.positions mapping accessor
    //         (
    //             CommonStructs.Position memory position,
    //             uint256 lastUpdateTime,
    //             int256 accumulatedFunding,
    //             bool isLiquidatable,
    //             bool inADLQueue
    //         ) = positionManager.positions(posId);

    //         // Rebuild the PositionData struct in memory (required for the subsequent logic if structs are used)
    //         PositionManager.PositionData memory data = PositionManager.PositionData({
    //             position: position,
    //             lastUpdateTime: lastUpdateTime,
    //             accumulatedFunding: accumulatedFunding,
    //             isLiquidatable: isLiquidatable,
    //             inADLQueue: inADLQueue
    //         });

    //         // Skip positions that are not opened (openedAt == 0 is an empty slot check)
    //         if (data.position.openedAt == 0) continue;

    //         // Calculate the funding payment
    //         int256 payment =
    //             _calcPayment(data.position.size, rateBps, periods, data.position.side == CommonStructs.Side.LONG);

    //         // Accumulate the funding payment
    //         data.accumulatedFunding += payment;

    //         // Update the accumulated funding in PositionManager
    //         positionManager.updateAccumulatedFunding(posId, data.accumulatedFunding);

    //         // Emit an event
    //         emit FundingPaid(posId, payment, data.position.side == CommonStructs.Side.LONG);
    //     }
    // }

    /**
     * @notice Calculates the total funding payment for a single position.
     * @dev The payment sign is inverted for Longs because a positive rate means Longs pay Shorts.
     * @param size The size of the position.
     * @param rateBps The calculated funding rate in BPS.
     * @param periods The number of full funding intervals.
     * @param isLong True if the position is long, false if short.
     * @return int256 The funding payment amount.
     */
    function _calcPayment(uint256 size, int256 rateBps, uint256 periods, bool isLong) internal pure returns (int256) {
        // Base payment calculated: size * rateBps * periods / BASIS_POINTS
        int256 base = int256(size) * rateBps * int256(periods) / int256(BASIS_POINTS);
        // If the rate is positive (Longs pay Shorts), Longs have negative payment, Shorts have positive payment.
        return isLong ? -base : base;
    }

    // === VIEW ===

    /// @notice Reads the funding state for a given market
    /// @param marketId The market identifier
    /// @return lastUpdateTime The last time funding was updated
    /// @return fundingRateBps The current funding rate in basis points
    /// @return cumulativeFunding The cumulative funding value
    function readFundingState(bytes32 marketId) external view returns (uint256, int256, int256) {
    FundingState storage fs = fundingState[marketId];
    return (fs.lastUpdateTime, fs.fundingRateBps, fs.cumulativeFunding);
}

    /**
     * @notice Calculates the current funding rate for a given market based on open interest skew.
     * @dev This is the same rate calculation used internally by `applyFunding` but does not apply the funding.
     * @param marketId The identifier for the target market.
     * @return int256 The calculated funding rate in basis points (BPS).
     */
    function getCurrentRate(bytes32 marketId) external view returns (int256) {
        uint256 longOI = positionManager.openInterest(marketId, CommonStructs.Side.LONG);
        uint256 shortOI = positionManager.openInterest(marketId, CommonStructs.Side.SHORT);
        uint256 total = longOI + shortOI;

        // Fetch the max funding rate BPS (3rd component) from market config
        // NOTE: Uses tuple destructuring for efficiency, skipping unused fields.
        (,, uint16 maxRateBps,,) = positionManager.marketConfig(marketId);

        return total == 0 ? int256(0) : _calculateRate(longOI, shortOI, total, maxRateBps);
    }

    /**
     * @notice Calculates the time remaining until funding can be applied again.
     * @param marketId The market ID.
     * @return uint256 Time in seconds until the next funding period begins, or 0 if funding is overdue.
     */
    function timeUntilNext(bytes32 marketId) external view returns (uint256) {
        uint256 next = lastFundingTime[marketId] + FUNDING_PERIOD;
        return block.timestamp >= next ? 0 : next - block.timestamp;
    }

    /// @notice Gets the cumulative funding for a market
    /// @param marketId The market identifier
    /// @return The cumulative funding value
        function getCumulativeFunding(bytes32 marketId) external view returns (int256) {
        return fundingState[marketId].cumulativeFunding;
    }
    
    /// @notice Gets the entire funding state for a market
    /// @param marketId The market identifier
    /// @return The complete FundingState struct
    function getFundingState(bytes32 marketId) external view returns (FundingState memory) {
        return fundingState[marketId];
    }
}
````

## File: LiquidationEngine.sol
````solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LiquidationEngine
 * @notice TODO: Add contract description
 */
contract LiquidationEngine {
// TODO: Implement contract
}
````

## File: OrderManager.sol
````solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title OrderManager
 * @notice TODO: Add contract description
 */
contract OrderManager {

}
````

## File: PositionManager.sol
````solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../security/SecurityBase.sol";
import {AutoDeleverageEngine} from "../trading/engines/AutoDeleverageEngine.sol";
import {ICircuitBreaker} from "../../interfaces/ICircuitBreaker.sol";
import {IEmergencyPauser} from "../../interfaces/IEmergencyPauser.sol";
import {IVolumeTracker} from "../../interfaces/IVolumeTracker.sol"; 
import {AddressUtils} from "../../libraries/utils/AddressUtils.sol";
import {ModuleIds} from "../../libraries/utils/ModuleIds.sol";
import {RateLimiter} from "../../security/RateLimiter.sol";
// import {FeeDistributor} from "../../fees/FeeDistributor.sol";
import {FeeCalculator} from "../../fees/FeeCalculator.sol";
import {IncentiveManager} from "../../fees/IncentiveManager.sol";
import {MarketRegistry} from "../markets/MarketRegistry.sol";
import {SafeTransfer} from "../../libraries/utils/SafeTransfer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FundingEngine} from "./FundingRateEngine.sol";
// import {IPriceFeed} from "../../interfaces/IPriceFeed.sol";
// import {OrderStorage} from  "../data/OrderStorage.sol";

/**
 * @title PositionManager
 * @author BAOBAB Protocol
 * @notice Core contract managing perpetual positions, margin, PnL, and liquidation
 * @dev Integrates with AutoDeleverageEngine for ADL queue updates. Uses market-specific risk tiers.
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                      POSITION MANAGER - FLOW DOCUMENTATION
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *
 * POSITION LIFECYCLE FLOW:
 *
 * 1. POSITION OPENING:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Trading Engine  │ →  │ PositionManager  │ →  │ Risk Validation     │ →  │ Position Created│
 *    │ (openPosition)  │    │ (openPosition)   │    │ (leverage, margin)  │    │ & Events Emitted│
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 *
 * 2. POSITION MANAGEMENT:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Trading Engine  │ →  │ PositionManager  │ →  │ PnL Calculation     │ →  │ Position Updated│
 *    │ (modifyPosition)│    │ (modifyPosition) │    │ & State Update      │    │ & Portfolio Sync│
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 *
 * 3. RISK MANAGEMENT:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Price Updates   │ →  │ PositionManager  │ →  │ Liquidation Check   │ →  │ ADL Engine     │
 *    │ (oracle)        │    │ (updatePosition) │    │ & Margin Validation │    │ (if needed)     │
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 *
 * 4. POSITION CLOSING:
 *    ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
 *    │ Trading/Liquid. │ →  │ PositionManager  │ →  │ Final PnL Calc      │ →  │ Position Closed │
 *    │ Engine          │    │ (closePosition)  │    │ & Cleanup           │    │ & Funds Settled │
 *    └─────────────────┘    └──────────────────┘    └─────────────────────┘    └─────────────────┘
 *
 * KEY COMPONENTS:
 * - Market Risk Tiers: HIGH (0.5% MMR), MEDIUM (0.75% MMR), LOW (1% MMR)
 * - Dynamic Liquidation: Price-based using market-specific maintenance margin
 * - Portfolio Tracking: Real-time collateral and PnL aggregation per trader
 * - Open Interest: Market and side-specific position tracking
 * - ADL Integration: Auto-deleverage queue management for risk reduction
 *
 * RISK PARAMETERS PER TIER:
 * ┌─────────────┬────────────┬────────────┬──────────────┐
 * │ Liquidity   │ MMR        │ IMR        │ Max Leverage │
 * │ Tier        │ (BPS)      │ (BPS)      │              │
 * ├─────────────┼────────────┼────────────┼──────────────┤
 * │ HIGH        │ 50 (0.5%)  │ 100 (1%)   │ 100x         │
 * │ MEDIUM      │ 75 (0.75%) │ 150 (1.5%) │ 66x          │
 * │ LOW         │ 100 (1%)   │ 200 (2%)   │ 50x          │
 * └─────────────┴────────────┴────────────┴──────────────┘
 */
contract PositionManager is SecurityBase {
    ICircuitBreaker public circuitBreaker;
    IEmergencyPauser public emergencyPauser;
    AutoDeleverageEngine public adlEngine;
    RateLimiter public rateLimiter;
    FeeCalculator public feeCalculator;
    IncentiveManager public incentiveManager;
    IVolumeTracker public volumeTracker;
    MarketRegistry public marketRegistry;
    FundingEngine public fundingEngine;
    // IPriceFeed public priceFeed;
    // FeeDistributor public feeDistributor;



    using AddressUtils for address;
    using ModuleIds for *;

        // Example market IDs (adjust based on your system)
    bytes32 constant ETH_USD = keccak256(abi.encodePacked("ETH-USD"));
    bytes32 constant BTC_USD = keccak256(abi.encodePacked("BTC-USD"));

    // ══════════════════════════════════════════════════════════════════════════
    //                                          ENUMS & STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Liquidity tier determines risk parameters (MMR, IMR, max leverage)
     * @dev Three tiers with different risk profiles for market classification
     * - HIGH: Blue-chip assets (BTC, ETH) with lowest margin requirements
     * - MEDIUM: Established altcoins with moderate risk
     * - LOW: Events/illiquid markets with highest margin requirements
     */
    enum LiquidityTier {
        HIGH, // 0.5% MMR (BTC, ETH) - Highest liquidity, lowest risk
        MEDIUM, // 0.75% MMR (altcoins) - Moderate liquidity and risk
        LOW // 1% MMR (events, illiquid) - Lowest liquidity, highest risk

    }

    /**
     * @notice Extended position with runtime state and funding tracking
     * @dev Contains core position data plus dynamic state for risk management
     * @param position Core position structure from CommonStructs
     * @param lastUpdateTime Timestamp of last position state update
     * @param accumulatedFunding Total funding payments accumulated
     * @param isLiquidatable Flag indicating if position can be liquidated
     * @param inADLQueue Flag indicating if position is in auto-deleverage queue
     */
    struct PositionData {
        CommonStructs.Position position;
        uint256 lastUpdateTime;
        int256 accumulatedFunding;
        bool isLiquidatable;
        bool inADLQueue;
    }

    /**
     * @notice Market-specific risk configuration
     * @dev Defines risk parameters per market based on liquidity tier
     * @param liquidityTier Risk classification tier
     * @param maintenanceMarginBps Maintenance Margin Rate in basis points (e.g., 50 = 0.5%)
     * @param initialMarginBps Initial Margin Rate in basis points (e.g., 100 = 1%)
     * @param maxLeverage Maximum allowed leverage for the market
     * @param isActive Flag indicating if market is active for trading
     */
    struct MarketRiskConfig {
        LiquidityTier liquidityTier;
        uint16 maintenanceMarginBps;
        uint16 initialMarginBps;
        uint16 maxLeverage;
        bool isActive;
    }

    /// @notice Configuration parameters for each perpetual market
    /// @dev Defines leverage limits, margin requirements, and funding behavior
    struct MarketConfig {
        uint16 maxLeverage; // Maximum allowed leverage (e.g., 100 = 100x)
        uint16 mmrBps; // Maintenance margin requirement in basis points (e.g., 50 = 0.5%)
        uint16 maxFundingRateBps; // Maximum funding rate per interval in basis points (e.g., 300 = 0.3%)
        bool fundingEnabled; // Whether funding payments are active for this market
        uint256 fundingInterval; // Time interval for funding updates (in seconds, e.g., 8h = 28800)
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Mapping of position ID to position data
    mapping(bytes32 => PositionData) public positions;

    /// @notice Mapping of trader address to their position IDs
    mapping(address => bytes32[]) public userPositions;

    /// @notice Mapping of position ID to owner address
    mapping(bytes32 => address) positionOwner;

    /// @notice Mapping of market ID to position IDs in that market
    mapping(bytes32 => bytes32[]) public marketPositions;

    /// @notice Mapping of market ID and side to total open interest
    mapping(bytes32 => mapping(CommonStructs.Side => uint256)) public openInterest;

    /// @notice Mapping of market ID to risk configuration
    mapping(bytes32 => MarketRiskConfig) public marketRiskConfigs;

    mapping(bytes32 => MarketConfig) public marketConfig;

    /// @notice Mapping of trader address to their portfolio summary
    mapping(address => CommonStructs.Portfolio) public portfolios;

    mapping(address => int256) public totalRealizedPnL;

    // /// @notice Auto-deleverage engine for risk management
    // AutoDeleverageEngine public adlEngine;

    // /// @notice Oracle registry contract for price feeds
    // address public oracleRegistry;

    /// @notice Trading engine contract (authorized caller)
    address public tradingEngine;

    /// @notice Liquidation engine contract (authorized caller)
    address public liquidationEngine;

    /// @notice Protocol admin address
    address public BaobabAdmin;

    /// @notice Counter for generating unique position IDs
    uint256 private _positionIdCounter;

    // address public fundingEngine;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    event PositionIncreased(
    bytes32 indexed positionId,
    address indexed trader,
    uint256 additionalSize,
    uint256 additionalCollateral,
    uint256 newEntryPrice,
    uint16 newLeverage,
    uint256 timestamp
);


    event PositionDecreased(
    bytes32 indexed positionId,
    address indexed trader,
    uint256 reduceSize,
    uint256 withdrawCollateral,
    int256 realizedPnL,
    uint256 timestamp
);

event PnLRealized(
    bytes32 indexed positionId,
    address indexed trader,
    int256 realizedPnL,
    uint256 timestamp
);

    /**
     * @notice Emitted when a new position is opened
     * @param positionId Unique identifier for the position
     * @param trader Address of the position owner
     * @param marketId Market identifier
     * @param side LONG or SHORT position
     * @param size Position size in base asset units
     * @param entryPrice Entry price in quote asset units
     * @param leverage Leverage used (e.g., 10 for 10x)
     */
    event PositionOpened(
        bytes32 indexed positionId,
        address indexed trader,
        bytes32 indexed marketId,
        CommonStructs.Side side,
        uint256 size,
        uint256 entryPrice,
        uint16 leverage
    );

    /**
     * @notice Emitted when a position is modified (size/collateral change)
     * @param positionId Unique identifier for the position
     * @param newSize New position size after modification
     * @param newCollateral New collateral amount after modification
     * @param realizedPnL Realized profit/loss from the modification
     */
    event PositionModified(bytes32 indexed positionId, uint256 newSize, uint256 newCollateral, int256 realizedPnL);

    /**
     * @notice Emitted when a position is closed
     * @param positionId Unique identifier for the position
     * @param trader Address of the position owner
     * @param closePrice Closing price in quote asset units
     * @param realizedPnL Final realized profit/loss
     * @param isLiquidation Flag indicating if closure was due to liquidation
     */
    event PositionClosed(
        bytes32 indexed positionId, address indexed trader, uint256 closePrice, int256 realizedPnL, bool isLiquidation
    );

    /**
     * @notice Emitted when a position is liquidated
     * @param positionId Unique identifier for the position
     * @param trader Address of the position owner
     * @param liquidator Address of the liquidator
     * @param liquidationPrice Price at which liquidation occurred
     * @param liquidationFee Fee paid to the liquidator
     */
    event PositionLiquidated(
        bytes32 indexed positionId,
        address indexed trader,
        address indexed liquidator,
        uint256 liquidationPrice,
        uint256 liquidationFee
    );

    /**
 * @notice Emitted when a trader withdraws excess collateral from an open position
 * @param positionId Unique identifier of the position
 * @param trader Address of the position owner
 * @param amount Amount of collateral withdrawn (in quote asset units)
 * @param remainingCollateral Remaining collateral after withdrawal
 * @param timestamp Block timestamp when withdrawal occurred
 */
event CollateralWithdrawn(
    bytes32 indexed positionId,
    address indexed trader,
    uint256 amount,
    uint256 remainingCollateral,
    uint256 timestamp
);

    /**
     * @notice Emitted when funding is applied to a position
     * @param positionId Unique identifier for the position
     * @param fundingAmount Funding payment amount (positive = paid, negative = received)
     * @param newFundingIndex New funding index after application
     */
    event FundingPaid(bytes32 indexed positionId, int256 fundingAmount, int256 newFundingIndex);

    /**
     * @notice Emitted when funding is settled for a position
     * @param positionId Unique identifier for the position
     * @param fundingPayment Total funding payment settled
     */
    event FundingSettled(bytes32 indexed positionId, int256 fundingPayment,  uint256 timestamp);

    event FeeCollected(
    address indexed trader,
    uint256 amount,
    string reason
);

    /**
     * @notice Emitted when a position's ADL queue status changes
     * @param positionId Unique identifier for the position
     * @param inQueue Flag indicating if position is in ADL queue
     * @param adlScore ADL risk score used for queue prioritization
     */
    event ADLQueueStatusChanged(bytes32 indexed positionId, bool inQueue, uint256 adlScore);

    /**
     * @notice Emitted when market risk parameters are configured
     * @param marketId Market identifier
     * @param tier Liquidity tier assigned to the market
     * @param mmrBps Maintenance Margin Rate in basis points
     * @param maxLev Maximum allowed leverage
     */
    event MarketRiskConfigured(bytes32 indexed marketId, LiquidityTier tier, uint16 mmrBps, uint16 maxLev);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when caller is not the authorized trading engine
    error PositionManager__OnlyTradingEngine();

    /// @notice Thrown when caller is not the authorized liquidation engine
    error PositionManager__OnlyLiquidationEngine();

    /// @notice Thrown when caller is not the protocol admin
    error PositionManager__OnlyAdmin();

    /// @notice Thrown when position ID does not exist
    error PositionManager__PositionNotFound();

    /// @notice Thrown when collateral is insufficient for the operation
    error PositionManager__InsufficientCollateral();
    
    /// @notice Thrown when collateral is insufficient to cover trading fees
    error PositionManager__InsufficientCollateralForFee();

    /// @notice Thrown when position size is invalid (zero or too large)
    error PositionManager__InvalidSize();

    /// @notice Thrown when attempting to liquidate a non-liquidatable position
    error PositionManager__PositionNotLiquidatable();

    /// @notice Thrown when caller is not authorized for the operation
    error PositionManager__Unauthorized();

    /// @notice Thrown when market risk configuration is not found
    error PositionManager__MarketNotConfigured();

    /// @notice Thrown when requested leverage exceeds market maximum
    error PositionManager__LeverageExceedsMax();

    /// @notice Thrown when initial margin requirements are not met
    error PositionManager__InsufficientInitialMargin();

    /// @notice Thrown when an operation is attempted while the Emergency Pauser has the contract paused
    error PositionManager__Paused();

    /// @notice Thrown when an operation is attempted while the Circuit Breaker is active
    error PositionManager__CircuitBroken();

    error PositionManager__OnlyFundingEngine();

    error PositionManager__InvalidReduction();
    error PositionManager__ReductionExceedsPosition(uint256 reduceSize, uint256 currentSize);
    error PositionManager__InsufficientAllowance();
    error PositionManager__InvalidPosition();
    error PositionManager__InvalidTrader();
    error PositionManager__MarketConcentrationExceeded(bytes32 marketId, uint256 currentBps, uint256 limitBps);
    error PositionManager__MarketPositionExceedsHistory(uint256 notional, uint256 maxAllowed);
    error PositionManager__PositionExceedsVolumeLimit(uint256 notional, uint256 maxAllowed);
    error PositionManager__NewTraderLimitExceeded(uint256 notional, uint256 limit);
    error PositionManager__InsufficientMarginAfterWithdrawal();
    // error PositionManager__InvalidPosition();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the PositionManager with required dependencies
     * @dev Sets up admin, oracle registry, and ADL engine. Initializes default risk configs.
     * @param _admin Protocol admin address
     * @param _adlEngine Auto-deleverage engine contract address
     */
    constructor(
        address _admin,
        // address _oracleRegistry,
        address _adlEngine,
        address _fundingEngine,
        address _circuitBreaker,
        address _emergencyPauser,
        address _incentiveManager,
        address _feeCalculator,
        address _marketRegistry,
        address _volumeTracker
    ) {
        // if (_admin == address(0) || _oracleRegistry == address(0) || _adlEngine == address(0))
        //     revert PositionManager__Unauthorized();

        // Use library functions for validation
        _admin.validateNotZero();
        // _oracleRegistry.validateContract();
        _adlEngine.validateContract();
        _fundingEngine.validateContract();
        _circuitBreaker.validateContract();
        _emergencyPauser.validateContract();
        _incentiveManager.validateContract();
        _feeCalculator.validateContract();
        _marketRegistry.validateContract();
        _volumeTracker.validateContract();
        _fundingEngine.validateContract();

        BaobabAdmin = _admin;
        // oracleRegistry = _oracleRegistry;
        adlEngine = AutoDeleverageEngine(_adlEngine);
        fundingEngine = FundingEngine(_fundingEngine);
        circuitBreaker = ICircuitBreaker(_circuitBreaker);
        emergencyPauser = IEmergencyPauser(_emergencyPauser);
        incentiveManager = IncentiveManager(_incentiveManager);
        feeCalculator = FeeCalculator(_feeCalculator);
        marketRegistry = MarketRegistry(_marketRegistry);
        volumeTracker = IVolumeTracker(_volumeTracker);

        _setDefaultRiskConfigs();
    }

    // ════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if the Pauser contract has paused operations.
     */
    modifier whenNotEmergencyPaused() {
        if (emergencyPauser.protocolPaused() || emergencyPauser.isModulePaused(ModuleIds.POSITION_MANAGER)) {
            revert PositionManager__Paused();
        }
        _;
    }

    /**
     * @notice Ensures the circuit breaker is not triggered for this market or globally.
     * @dev Use this on functions that *add new exposure* — e.g. opening or increasing positions.
     *      If either the global circuit breaker or the market-specific breaker is active,
     *      the transaction will revert.
     * @param marketId The unique identifier of the market to check.
     */
    modifier whenCircuitActivated(bytes32 marketId) {
        // Optionally validate market ID is nonzero
        // marketId.validateNotZero();

        // Prevent any operation if system-wide or market-specific breaker is active
        if (circuitBreaker.globalHalt() || circuitBreaker.isCircuitTripped(marketId)) {
            revert PositionManager__CircuitBroken();
        }
        _;
    }

    /**
     * @notice Ensures only the global circuit breaker state is respected.
     * @dev Use this on functions that *reduce exposure* — e.g. closing or decreasing positions.
     *      Allows users to safely exit markets that are tripped locally while
     *      still respecting global system halts.
     */
    modifier whenGlobalCircuitActivated() {
        if (circuitBreaker.globalHalt()) {
            revert PositionManager__CircuitBroken();
        }
        _;
    }

    /**
     * @notice Restrict access to only the trading engine
     * @dev Used for position opening/modification functions
     */
    modifier onlyPerpEngine() {
        msg.sender.validateNotZero();
        if (msg.sender != tradingEngine) revert PositionManager__OnlyTradingEngine();
        _;
    }

    /**
     * @notice Restrict access to only the liquidation engine
     * @dev Used for position liquidation functions
     */
    modifier onlyLiquidationEngine() {
        msg.sender.validateNotZero();
        if (msg.sender != liquidationEngine) revert PositionManager__OnlyLiquidationEngine();
        _;
    }

    /**
     * @notice Restrict access to only the protocol admin
     * @dev Used for configuration and setup functions
     */
    modifier onlyAdmin() {
        msg.sender.isZeroAssembly();
        if (msg.sender != BaobabAdmin) revert PositionManager__OnlyAdmin();
        _;
    }

    modifier onlyFundingEngine() {
        msg.sender.validateNotZero();
        if (msg.sender != address(fundingEngine)) revert PositionManager__OnlyFundingEngine();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Set IncentiveManager address (admin only)
function setIncentiveManager(address _incentiveManager) external onlyAdmin {
    _incentiveManager.validateNotZero();
    incentiveManager = IncentiveManager(_incentiveManager);
}

    /**
     * @notice Configure risk parameters for a specific market
     * @dev Sets market-specific margin requirements and leverage limits based on liquidity tier
     * @param marketId Market identifier to configure
     * @param liquidityTier Risk classification tier (HIGH/MEDIUM/LOW)
     * @param maintenanceMarginBps Maintenance Margin Rate in basis points (e.g., 50 = 0.5%)
     * @param initialMarginBps Initial Margin Rate in basis points (e.g., 100 = 1%)
     * @param maxLeverage Maximum allowed leverage for the market
     *
     * Requirements:
     * - Caller must be admin
     * - Margin rates must be valid (non-zero, IMR > MMR)
     * - Max leverage must be between 1 and 100
     *
     * Emits {MarketRiskConfigured} event on success
     */
    function setMarketRiskConfig(
        bytes32 marketId,
        LiquidityTier liquidityTier,
        uint16 maintenanceMarginBps,
        uint16 initialMarginBps,
        uint16 maxLeverage
    ) external onlyAdmin whenNotEmergencyPaused whenCircuitActivated(marketId) {
        if (
            maintenanceMarginBps == 0 || initialMarginBps <= maintenanceMarginBps || maxLeverage == 0
                || maxLeverage > 100
        ) {
            revert PositionManager__InvalidSize();
        }

        marketRiskConfigs[marketId] = MarketRiskConfig({
            liquidityTier: liquidityTier,
            maintenanceMarginBps: maintenanceMarginBps,
            initialMarginBps: initialMarginBps,
            maxLeverage: maxLeverage,
            isActive: true
        });

        emit MarketRiskConfigured(marketId, liquidityTier, maintenanceMarginBps, maxLeverage);
    }

    function setMarketConfig(
        bytes32 marketId,
        uint16 maxLev,
        uint16 mmr,
        uint16 maxFund,
        bool fundEnabled,
        uint256 fundingInterval
    ) external onlyAdmin whenNotEmergencyPaused whenCircuitActivated(marketId) {
        marketConfig[marketId] = MarketConfig({
            maxLeverage: maxLev,
            mmrBps: mmr,
            maxFundingRateBps: maxFund,
            fundingEnabled: fundEnabled,
            fundingInterval: fundingInterval
        });
    }

    /**
     * @notice Set the trading engine address
     * @dev Trading engine is authorized to open/modify positions
     * @param _tradingEngine Address of the trading engine contract
     */
    function setTradingEngine(address _tradingEngine)
        external
        onlyAdmin
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
    {
        _tradingEngine.validateContract();
        tradingEngine = _tradingEngine;
    }

    /**
     * @notice Set the liquidation engine address
     * @dev Liquidation engine is authorized to liquidate positions
     * @param _liquidationEngine Address of the liquidation engine contract
     */
    function setLiquidationEngine(address _liquidationEngine)
        external
        onlyAdmin
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
    {
        _liquidationEngine.validateContract();
        liquidationEngine = _liquidationEngine;
    }
    /**
     * @notice Set the funding engine address
     * @dev Funding engine is authorized to apply funding payments
     * @param _fundingEngine Address of the funding engine contract
     */

    function setFundingEngine(address _fundingEngine)
        external
        onlyAdmin
        whenNotEmergencyPaused
        whenGlobalCircuitActivated
    {
        _fundingEngine.validateContract();
        fundingEngine = FundingEngine(_fundingEngine);
    }

    // ════════════════════════════════════════════════════════════════════════════
    //                                    POSITION LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

 

function openPosition(
    address trader,
    bytes32 marketId,
    CommonStructs.Side side,
    uint256 size,
    uint256 collateral,
    uint256 entryPrice,
    uint16 leverage
) external onlyPerpEngine whenCircuitActivated(marketId) nonReentrant returns (bytes32 positionId) {
    // Basic validation
    if (size == 0) revert PositionManager__InvalidSize();
    if (collateral == 0) revert PositionManager__InsufficientCollateral();

    // Get market config and validate
    MarketRiskConfig memory config = marketRiskConfigs[marketId];
    if (!config.isActive) revert PositionManager__MarketNotConfigured();
    if (leverage > config.maxLeverage) revert PositionManager__LeverageExceedsMax();

    // Calculate notional and check limits
    // Calculates the total value of the position (notional) and ensures it respects volume and market-specific limits.
    uint256 notional = (size * entryPrice) / 1e18;
    _checkVolumeBasedLimits(trader, marketId, notional);
    _checkMarketSpecificLimits(trader, marketId, notional);

    // Calculate and deduct fees
    // This shouldnt be handled by PostionManager but for now we do it here
    address quoteAsset = marketRegistry.getQuoteAsset(marketId);
    uint256 takerFee = feeCalculator.calculateTradingFeeTaker(
        quoteAsset, 
        trader, 
        notional
        );
    
    if (takerFee > collateral) revert PositionManager__InsufficientCollateralForFee();
    collateral -= takerFee;

    // Check margin requirements
    // Ensures the collateral left after fees is enough for initial margin.
    uint256 requiredInitialMargins = (notional * config.initialMarginBps) / 10000;
    if (collateral < requiredInitialMargins) revert PositionManager__InsufficientInitialMargin();

    // Record trade volume
    // Tracks trade volume for incentive programs if applicable.
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(
            trader, 
            marketId, 
            notional
            );
    }
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(trader, notional);
    }

    // Generate position 
    // Creates a unique position ID and initializes the position data structure.
    // Unique ID for the position, and ownership tracking.
    positionId = keccak256(abi.encodePacked(
        trader, 
        marketId, 
        _positionIdCounter++, 
        block.timestamp
        ));

    positionOwner[positionId] = trader;

    // Calculate liquidation price
    // Determines the price at which the position would be liquidated based on maintenance margin.
    // Calculates where the position will be liquidated based on risk parameters.
    uint256 liquidPrice = _calculateLiquidationPrice(
        marketId, 
        side, 
        entryPrice, 
        collateral, 
        size
        );

    // Create position
    CommonStructs.Position memory pos = CommonStructs.Position({
        positionId: positionId,
        marketId: marketId,
        trader: trader,
        side: side,
        size: size,
        collateral: collateral,
        entryPrice: entryPrice,
        leverage: leverage,
        lastFundingIndex: 0,
        lastCumulativeFunding: 0,
        unrealizedPnL: 0,
        liquidationPrice: liquidPrice,
        openedAt: block.timestamp
    });

    // Store position data
    positions[positionId] = PositionData({
        position: pos,
        lastUpdateTime: block.timestamp,
        accumulatedFunding: 0,
        isLiquidatable: false,
        inADLQueue: false
    });

    // Update mappings
    userPositions[trader].push(positionId);
    marketPositions[marketId].push(positionId);
    openInterest[marketId][side] += size;

    // Update systems
    _updatePortfolio(trader);
    adlEngine.updateADLQueue(
        marketId, 
        positionId, 
        trader, 
        side, 0, 
        leverage
        );

    // Emit events
    emit PositionOpened(
        positionId, 
        trader, 
        marketId, 
        side, 
        size, 
        entryPrice, 
        leverage
        );

    emit ADLQueueStatusChanged(positionId, false, 0);
}

function modifyPosition(
    bytes32 positionId,
    int256 sizeDelta,
    int256 collateralDelta,
    uint256 currentPrice
)
    external
    onlyPerpEngine
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    int256 currentPnL = _calculateUnrealizedPnL(pos, currentPrice);

    // Handle size changes
    if (sizeDelta != 0) {
        if (sizeDelta > 0) {
            // Increase position
            uint256 notional = (uint256(sizeDelta) * currentPrice) / 1e18;
            
            // Check volume limits for increase
            _checkVolumeBasedLimits(pos.trader, pos.marketId, notional);
            _checkMarketSpecificLimits(pos.trader, pos.marketId, notional);

            // Calculate and deduct fees
            address quoteAsset = marketRegistry.getQuoteAsset(pos.marketId);
            uint256 takerFee = feeCalculator.calculateTradingFeeTaker(quoteAsset, pos.trader, notional);
            
            if (takerFee > pos.collateral) revert PositionManager__InsufficientCollateralForFee();
            pos.collateral -= takerFee;

            // Record trade volume
            if (address(volumeTracker) != address(0)) {
                volumeTracker.recordTrade(pos.trader, pos.marketId, notional);
            }
            if (address(incentiveManager) != address(0)) {
                incentiveManager.recordTrade(pos.trader, notional);
            }

            // Update position size
            pos.size += uint256(sizeDelta);
            openInterest[pos.marketId][pos.side] += uint256(sizeDelta);
        } else {
            // Decrease position
            uint256 reduction = uint256(-sizeDelta);
            if (reduction > pos.size) revert PositionManager__InvalidSize();
            
            uint256 proportion = (reduction * 1e18) / pos.size;
            realizedPnL = (currentPnL * int256(proportion)) / 1e18;

            pos.size -= reduction;
            openInterest[pos.marketId][pos.side] -= reduction;
        }
    }

    // Handle collateral changes
    if (collateralDelta != 0) {
        if (collateralDelta > 0) {
            pos.collateral += uint256(collateralDelta);
        } else {
            uint256 withdrawal = uint256(-collateralDelta);
            if (withdrawal > pos.collateral) revert PositionManager__InsufficientCollateral();
            pos.collateral -= withdrawal;
        }
    }

    // Update position state
    pos.liquidationPrice = _calculateLiquidationPrice(
        pos.marketId,
        pos.side,
        pos.entryPrice,
        pos.collateral,
        pos.size
    );

    posData.lastUpdateTime = block.timestamp;
    _updatePositionState(positionId, currentPrice);

    emit PositionModified(positionId, pos.size, pos.collateral, realizedPnL);
}


// ============================================================================
// POSITION MODIFICATION FUNCTIONS
// ============================================================================

function increasePosition(
    bytes32 positionId,
    uint256 additionalSize,
    uint256 additionalCollateral,
    uint256 currentPrice
) 
    external 
    onlyPerpEngine
    whenNotEmergencyPaused
    nonReentrant 
{
    _validateIncreaseInputs(additionalSize, additionalCollateral);
    
    PositionData storage positionData = positions[positionId];
    CommonStructs.Position storage position = positionData.position;
    _validatePositionForIncrease(positionId, position);
    
    _processPositionIncrease(
        positionId, 
        positionData, 
        position,
        additionalSize, 
        additionalCollateral, 
        currentPrice
        );
}

function decreasePosition(
    bytes32 positionId,
    uint256 reduceSize,
    uint256 withdrawCollateral
)
    external
    onlyPerpEngine
    whenNotEmergencyPaused
    nonReentrant
{
    _validateDecreaseInputs(reduceSize, withdrawCollateral);
    
    PositionData storage positionData = positions[positionId];
    CommonStructs.Position storage position = positionData.position;
    _validatePositionForDecrease(positionId, position, reduceSize);
    
    _processPositionDecrease(
        positionId, 
        positionData, 
        position, 
        reduceSize, 
        withdrawCollateral
        );
}

// ============================================================================
// POSITION CLOSING FUNCTIONS
// ============================================================================

function closePosition(bytes32 positionId, uint256 closePrice)
    external
    onlyLiquidationEngine
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{

    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    
    // Calculate final PnL
    int256 finalPnL = _calculateUnrealizedPnL(pos, closePrice);
    uint256 notional = (pos.size * closePrice) / 1e18;

    // Record close volume
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(pos.trader, pos.marketId, notional);
    }
    
    // Calculate maker fee
    address quoteAsset = marketRegistry.getQuoteAsset(pos.marketId);
    int256 makerFeeRebate = feeCalculator.calculateTradingFeeMaker(
        quoteAsset, 
        pos.trader, 
        notional
        );
        
    uint256 makerFee = makerFeeRebate >= 0 ? uint256(makerFeeRebate) : 0;

    // Deduct fees from PnL or collateral
    if (finalPnL >= int256(makerFee)) {
        realizedPnL = finalPnL - int256(makerFee);
    } else {
        uint256 additionalFee = uint256(int256(makerFee) - finalPnL);
        if (additionalFee > pos.collateral) revert PositionManager__InsufficientCollateral();
        pos.collateral -= additionalFee;
        realizedPnL = finalPnL - int256(makerFee);
    }

    // Record for incentives
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(pos.trader, notional);
    }

    // Update open interest
    openInterest[pos.marketId][pos.side] -= pos.size;

    // Clean up position data
    _removeUserPosition(pos.trader, positionId);
    
    if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }

    emit PositionClosed(positionId, pos.trader, closePrice, realizedPnL, false);
    delete positions[positionId];
    _updatePortfolio(pos.trader);

    return realizedPnL;
}

function forceClosePosition(bytes32 positionId, uint256 executionPrice, bool isLiquidation)
    external
    nonReentrant
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
    returns (int256 realizedPnL)
{
    // Only ADL engine or liquidation engine can call this
    if (msg.sender != address(adlEngine) && msg.sender != liquidationEngine) {
        revert PositionManager__Unauthorized();
    }

    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) revert PositionManager__PositionNotFound();

    CommonStructs.Position storage pos = posData.position;
    realizedPnL = _calculateUnrealizedPnL(pos, executionPrice);

    // Update open interest
    openInterest[pos.marketId][pos.side] -= pos.size;
    
    // Clean up position data
    _removeUserPosition(pos.trader, positionId);
    
    if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }

    emit PositionClosed(positionId, pos.trader, executionPrice, realizedPnL, isLiquidation);
    delete positions[positionId];
    _updatePortfolio(pos.trader);

    return realizedPnL;
}

// ============================================================================
// POSITION STATE FUNCTIONS
// ============================================================================

function updatePositionState(bytes32 positionId, uint256 currentPrice)
    external
    onlyPerpEngine
    whenNotEmergencyPaused
    whenGlobalCircuitActivated
{
    _updatePositionState(positionId, currentPrice);
}

function updateAccumulatedFunding(bytes32 posId, int256 newAccumulatedFunding)
    external
    onlyFundingEngine
    whenGlobalCircuitActivated
    whenNotEmergencyPaused
{
    PositionData storage positionData = positions[posId];
    positionData.accumulatedFunding = newAccumulatedFunding;
}

function settlePositionFunding(bytes32 positionId) 
    external 
    onlyPerpEngine
    returns (int256 fundingPayment) 
{
    PositionData storage posData = positions[positionId];
    require(posData.position.openedAt != 0, "Position not found");
    
    // Calculate funding
    fundingPayment = _calculateFundingOwed(positionId);
    
    //  Apply to collateral (internal accounting)
    if (fundingPayment > 0) {
        posData.position.collateral -= uint256(fundingPayment);  // OWES
    } else if (fundingPayment < 0) {
        posData.position.collateral += uint256(-fundingPayment); // RECEIVES
    }
    
    // Update AFPU snapshot
    posData.position.lastCumulativeFunding = 
        fundingEngine.getCumulativeFunding(posData.position.marketId);
    
    emit FundingSettled(positionId, fundingPayment, block.timestamp);
    return fundingPayment;
}


function _calculateFundingOwed(bytes32 positionId) internal view returns (int256) {
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) return 0;
    
    // Get current AFPU index from FundingEngine
    // int256 currentCumulativeFee = fundingEngine.getCumulativeFunding(posData.position.marketId);

       (,, int256 currentCumulative) = fundingEngine.readFundingState(posData.position.marketId);

    
    // Funding owed = (Current index - Last recorded index) × Position size
    int256 fundingOwed = (currentCumulative - posData.position.lastCumulativeFunding) 
        * int256(posData.position.size) / int256(1e18); // Divide by precision
    
    // Adjust for position side
    // Positive funding rate = longs pay shorts
    if (posData.position.side == CommonStructs.Side.LONG) {
        return fundingOwed;  // Long pays positive funding
    } else {
        return -fundingOwed; // Short receives (negative means credit)
    }
}


// ============================================================================
// INTERNAL HELPER FUNCTIONS
// ============================================================================

/**
 * @notice Internal function to completely close a position during size reduction
 * @dev Handles full position closure when reduceSize brings size to zero.
 *      Updates open interest, removes from mappings/ADL queue, emits events,
 *      deletes position storage, and updates portfolio. Called from _processPositionDecrease.
 * @param positionId Unique position identifier
 * @param trader Address of the position owner
 * @param realizedPnL Realized profit/loss from the closure
 */
function _closePositionCompletely(
    bytes32 positionId,
    address trader,
    int256 realizedPnL
) internal {
    PositionData storage posData = positions[positionId];
    CommonStructs.Position storage pos = posData.position;
    
    // Update open interest (size already reduced to 0 in _handleSizeReduction)
    if (pos.size > 0) {  // Safety check
        openInterest[pos.marketId][pos.side] -= pos.size;
    }
    
    // Calculate close price (use current price or entry price as fallback)
    uint256 closePrice = pos.entryPrice;  // Fallback - ideally pass currentPrice as param
    
    // Record close volume for incentives/tracking
    uint256 closeNotional = (pos.size * closePrice) / 1e18;
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(trader, pos.marketId, closeNotional);
    }
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(trader, closeNotional);
    }
    
    // Remove from ADL queue if present
    if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(pos.marketId, positionId, pos.side);
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }
    
    // Remove from user and market position lists
    _removeUserPosition(trader, positionId);
    _removeMarketPosition(pos.marketId, positionId);
    
    // Emit closure event (non-liquidation)
    emit PositionClosed(positionId, trader, closePrice, realizedPnL, false);
    
    // Delete position storage (gas refund)
    delete positions[positionId];
    
    // Update trader portfolio
    _updatePortfolio(trader);
}

/**
 * @notice Remove position from market's position list
 * @dev Maintains accurate market position tracking for cleanup
 */
function _removeMarketPosition(bytes32 marketId, bytes32 positionId) internal {
    bytes32[] storage marketList = marketPositions[marketId];
    for (uint256 i = 0; i < marketList.length; i++) {
        if (marketList[i] == positionId) {
            marketList[i] = marketList[marketList.length - 1];
            marketList.pop();
            break;
        }
    }
}

function _validateIncreaseInputs(uint256 additionalSize, uint256 additionalCollateral) internal pure {
    if (additionalSize == 0) revert PositionManager__InvalidSize();
    if (additionalCollateral == 0) revert PositionManager__InsufficientCollateral();
}

function _validatePositionForIncrease(bytes32 positionId, CommonStructs.Position storage position) internal view {
    if (positionId != position.positionId) revert PositionManager__InvalidPosition();
    if (position.positionId == bytes32(0)) revert PositionManager__InvalidPosition();
    if (position.trader == address(0)) revert PositionManager__InvalidTrader();
}

function _validateDecreaseInputs(uint256 reduceSize, uint256 withdrawCollateral) internal pure {
    if (reduceSize == 0 && withdrawCollateral == 0) revert PositionManager__InvalidReduction();
}

function _validatePositionForDecrease(bytes32 positionId, CommonStructs.Position storage position, uint256 reduceSize) 
    internal view 
{
    if (positionId == bytes32(0)) revert PositionManager__InvalidPosition();
    if (positionId != position.positionId) revert PositionManager__InvalidPosition();
    if (position.positionId == bytes32(0)) revert PositionManager__InvalidPosition();
    if (position.trader == address(0)) revert PositionManager__InvalidTrader();
    if (reduceSize > position.size) revert PositionManager__ReductionExceedsPosition(reduceSize, position.size);
}

function _processPositionIncrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 additionalSize,
    uint256 additionalCollateral,
    uint256 currentPrice 
) internal {
    // uint256 currentPrice = _getCurrentPrice(position.marketId);
    uint256 additionalNotional = (additionalSize * currentPrice) / 1e18;
    
    _checkIncreaseLimits(position.trader, position.marketId, additionalNotional);
   
    
    uint256 netAdditionalCollateral = _handleIncreaseCollateralAndFees(
        position.trader,
        position.marketId,
        additionalCollateral,
        additionalNotional
    );
    
    _updatePositionAfterIncrease(
        positionId,
        positionData, 
        position, 
        additionalSize, 
        netAdditionalCollateral, 
        additionalNotional, 
        currentPrice
        );

     _updatePositionState(
        positionId, 
        currentPrice
     );

    _updateExternalSystemsAfterIncrease(
        positionId, 
        position, 
        additionalSize, 
        additionalNotional
    );

    emit PositionIncreased(positionId, position.trader, additionalSize, additionalCollateral, position.entryPrice, position.leverage, block.timestamp);
}

function _checkIncreaseLimits(address trader, bytes32 marketId, uint256 additionalNotional) internal view {
    if (address(volumeTracker) == address(0)) return;
    _checkVolumeBasedLimits(trader, marketId, additionalNotional);
    _checkMarketSpecificLimits(trader, marketId, additionalNotional);
}

function _handleIncreaseCollateralAndFees(
    address trader,
    bytes32 marketId,
    uint256 additionalCollateral,
    // uint256 grossAdditionalNotional,
    uint256 additionalNotional
) internal returns (uint256 netAdditionalCollateral) {
    address quoteAsset = marketRegistry.getQuoteAsset(marketId);
    uint256 increaseFee = feeCalculator.calculateTradingFeeTaker(
        quoteAsset,
        trader,
        additionalNotional
    );

    if (increaseFee > additionalCollateral) revert PositionManager__InsufficientCollateralForFee();

    netAdditionalCollateral = additionalCollateral - increaseFee;

    //     if (fee > grossAdditionalCollateral) {
    //     revert PositionManager__InsufficientCollateralForFee();
    // }
    
    // IERC20 collateralToken = IERC20(quoteAsset);
    // uint256 allowance = collateralToken.allowance(trader, address(this));
    // if (allowance < additionalCollateral) {
    //     revert PositionManager__InsufficientAllowance();
    // }
    //    SafeTransfer.safeTransferFrom(
    //     collateralToken, 
    //     msg.sender, 
    //     address(this), 
    //     additionalCollateral
    // );
    
    emit FeeCollected(trader, increaseFee, "position_increase");
    return netAdditionalCollateral;
}

function _updatePositionAfterIncrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 additionalSize,
    uint256 netAdditionalCollateral,
    uint256 additionalNotional,
    uint256 currentPrice
) internal {
    // Calculate new weighted average entry price
    if (currentPrice == 0) {
        currentPrice = _getCurrentPrice(position.marketId);
    }

    if (position.positionId != positionId) {
        revert PositionManager__InvalidPosition();
    }
    uint256 oldNotional = (position.size * position.entryPrice) / 1e18;
    uint256 newTotalSize = position.size + additionalSize;
    uint256 newEntryPrice = ((oldNotional + additionalNotional) * 1e18) / newTotalSize;
    
    // Update position storage
    position.size = newTotalSize;
    position.entryPrice = newEntryPrice;
    position.collateral += netAdditionalCollateral;
    
    // Recalculate leverage
    uint256 newNotional = (newTotalSize * newEntryPrice) / 1e18;
    position.leverage = uint16((newNotional * 100) / position.collateral);
    
    // Update liquidation price
    position.liquidationPrice = _calculateLiquidationPrice(
        position.marketId,
        position.side,
        newEntryPrice,
        position.collateral,
        newTotalSize
    );
    
    // Update timestamp when state changes
    positionData.lastUpdateTime = block.timestamp;
    
    // Update market open interest
    openInterest[position.marketId][position.side] += additionalSize;
}

function _updateExternalSystemsAfterIncrease(
    bytes32 positionId,
    CommonStructs.Position storage position,
    uint256 additionalSize,
    uint256 additionalNotional
) internal {

    if (additionalSize == 0) revert PositionManager__InvalidSize();

    // Record trade volume
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(position.trader, position.marketId, additionalNotional);
    }
    
    // Update incentive rewards
    if (address(incentiveManager) != address(0)) {
        incentiveManager.recordTrade(position.trader, additionalNotional);
    }
    
    // Update ADL engine
    PositionData storage positionData = positions[positionId];
    // Update timestamp when state changes
    positionData.lastUpdateTime = block.timestamp;

    adlEngine.updateADLQueue(
        position.marketId,
        positionId,
        position.trader,
        position.side,
        position.unrealizedPnL,
        position.leverage
    );
    
    // Update portfolio
    _updatePortfolio(position.trader);
}

function _processPositionDecrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 reduceSize,
    uint256 withdrawCollateral
) internal {
    uint256 currentPrice = _getCurrentPrice(
        position.marketId
        );

    _updatePositionState(
        positionId, 
        currentPrice
        );
    
    int256 realizedPnL = 0;
    if (reduceSize > 0) {
    // Calculate realized PnL from size reduction
        realizedPnL = _handleSizeReduction(
            positionId, 
            positionData, 
            position, 
            reduceSize, 
            currentPrice
            );
        if (position.size == 0) {
            _closePositionCompletely(
                positionId, 
                position.trader, 
                realizedPnL
                );
            return;
        }
    }
    
    if (withdrawCollateral > 0) {
        _handleCollateralWithdrawal(
            positionId, 
            position, 
            withdrawCollateral
            );
    }
    
      //  Update position state
    _updatePositionAfterDecrease(
        positionId,
        positionData, 
        position, 
        reduceSize, 
        realizedPnL
        );
    
    emit PositionDecreased(positionId, position.trader, reduceSize, withdrawCollateral, realizedPnL, block.timestamp);
    if (realizedPnL != 0) emit PnLRealized(positionId, position.trader, realizedPnL, block.timestamp);
}
function _getCurrentPrice(bytes32 marketId) internal pure returns (uint256) {
    return _getMockPrice(marketId);
}

function _getMockPrice(bytes32 marketId) internal pure returns (uint256) {
    // TODO: Replace with actual oracle implementation
    // This is a temporary mock for development
    

    if (marketId == ETH_USD) return 3000 * 1e18;
    if (marketId == BTC_USD) return 60000 * 1e18;
    return 100 * 1e18;
}

function _handleSizeReduction(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 reduceSize,
    uint256 currentPrice
) internal returns (int256 realizedPnL) {
    require(reduceSize <= position.size, "INVALID_REDUCTION");
    if (positionId != position.positionId) {
        revert PositionManager__InvalidPosition();
    }

    uint256 reductionRatio = (reduceSize * 1e18) / position.size;
    
    realizedPnL = (position.unrealizedPnL * int256(reductionRatio)) / 1e18;
    uint256 reducedNotional = (reduceSize * currentPrice) / 1e18;
    
    if (address(volumeTracker) != address(0)) {
        volumeTracker.recordTrade(position.trader, position.marketId, reducedNotional);
    }

    // Update timestamp when state changes
    positionData.lastUpdateTime = block.timestamp;
    
    position.size -= reduceSize;
    openInterest[position.marketId][position.side] -= reduceSize;
    position.unrealizedPnL -= realizedPnL;
    
    return realizedPnL;
}


function _handleCollateralWithdrawal(
    bytes32 positionId,
    CommonStructs.Position storage position,
    uint256 withdrawCollateral
) internal {
    if (withdrawCollateral > position.collateral) revert PositionManager__InsufficientCollateral();
    
    uint256 newCollateral = position.collateral - withdrawCollateral;
    uint256 notional = (position.size * position.entryPrice) / 1e18;
    MarketRiskConfig memory config = marketRiskConfigs[position.marketId];
    uint256 requiredIM = (notional * config.initialMarginBps) / 10000;
    
    if (newCollateral < requiredIM) revert PositionManager__InsufficientMarginAfterWithdrawal();
    
    position.collateral = newCollateral;
    address collateralToken = marketRegistry.getQuoteAsset(position.marketId);
    SafeTransfer.safeTransfer(IERC20(collateralToken), msg.sender, withdrawCollateral);

    emit CollateralWithdrawn(positionId, position.trader, withdrawCollateral, position.collateral,
    block.timestamp);
}

function _updatePositionAfterDecrease(
    bytes32 positionId,
    PositionData storage positionData,
    CommonStructs.Position storage position,
    uint256 reduceSize,
    int256 realizedPnL
) internal {

      _applyRealizedPnLToCollateral(position, realizedPnL);

       totalRealizedPnL[position.trader] += realizedPnL;

//     if (realizedPnL > 0 ){
//    position.collateral += uint256(realizedPnL);
//     } else if (realizedPnL < 0) {
//         // Loss subtracts from collateral
//         uint256 loss = uint256(-realizedPnL);
//         if (loss > position.collateral) {
//             revert PositionManager__InsufficientCollateral();
//         }
//    }
//         position.collateral -= loss;

  


    if (reduceSize > 0) {
        uint256 notional = (position.size * position.entryPrice) / 1e18;
        position.leverage = uint16((notional * 100) / position.collateral);
    }

     uint256 newNotional = (position.size * position.entryPrice) / 1e18;
    position.leverage = uint16((newNotional * 100) / position.collateral);
    
    position.liquidationPrice = _calculateLiquidationPrice(
        position.marketId,
        position.side,
        position.entryPrice,
        position.collateral,
        position.size
    );

    positionData.lastUpdateTime = block.timestamp;
    
    adlEngine.updateADLQueue(
        position.marketId,
        positionId,
        position.trader,
        position.side,
        position.unrealizedPnL,
        position.leverage
    );
    
    _updatePortfolio(position.trader);
}

function _applyRealizedPnLToCollateral(
    CommonStructs.Position storage position, 
    int256 realizedPnL
) internal {
    if (realizedPnL > 0) {
        // Profit: add to collateral
        position.collateral += uint256(realizedPnL);
    } else if (realizedPnL < 0) {
        // Loss: subtract from collateral
        uint256 loss = uint256(-realizedPnL);
        require(loss <= position.collateral, "Insufficient collateral for loss");
        position.collateral -= loss;
    }
    // if realizedPnL == 0,  simply do nothing, No profit/loss realized → collateral stays same
}

// ============================================================================
// LIMIT CHECK FUNCTIONS
// ============================================================================

function _checkMarketSpecificLimits(address trader, bytes32 marketId, uint256 notional) internal view {
    if (address(volumeTracker) == address(0)) return;
    
    uint256 totalVolume30d = volumeTracker.get30DayVolume(trader);
    IVolumeTracker.MarketVolume memory marketVol = volumeTracker.getMarketVolume(trader, marketId);
    uint256 marketVolume30d = marketVol.volume30d;
    
    // Prevent > 50% concentration in one market
    if (totalVolume30d > 0) {
        uint256 concentrationBps = (marketVolume30d * 10000) / totalVolume30d;
        if (concentrationBps > 5000) revert PositionManager__MarketConcentrationExceeded(marketId, concentrationBps, 5000);
    }
    
    // New position can't exceed 20% of existing market volume
    uint256 maxNewPosition = (marketVolume30d * 20) / 100;
    if (notional > maxNewPosition) revert PositionManager__MarketPositionExceedsHistory(notional, maxNewPosition);
}

function _checkVolumeBasedLimits(address trader, bytes32 marketId, uint256 notional) internal view {
    if (address(volumeTracker) == address(0)) return;
    
    uint256 volume30d = volumeTracker.get30DayVolume(trader);
    uint256 lifetimeVolume = volumeTracker.getLifetimeVolume(trader);

    // using marketId to get market-specific volume
    uint256 marketVolume30d = volumeTracker.getMarketVolume(trader, marketId).volume30d;

    
    // Single position cannot exceed 10% of 30-day volume
    uint256 maxSinglePosition = (volume30d * 10) / 100;
    if (notional > maxSinglePosition) revert PositionManager__PositionExceedsVolumeLimit(notional, maxSinglePosition);
    
    // Stricter limits for new traders
    if (lifetimeVolume < 10_000e18) {
        uint256 newTraderLimit = 1_000e18;
        if (notional > newTraderLimit) revert PositionManager__NewTraderLimitExceeded(notional, newTraderLimit);
    }

       // Over-Engineering add market-specific limit
    uint256 maxMarketPosition = (marketVolume30d * 20) / 100;
    if (notional > maxMarketPosition) {
    }
}

// ============================================================================
// POSITION STATE MANAGEMENT
// ============================================================================

function _updatePositionState(bytes32 positionId, uint256 currentPrice) internal {
    PositionData storage posData = positions[positionId];
    if (posData.position.openedAt == 0) return;

    CommonStructs.Position storage pos = posData.position;
    int256 unrealizedPnL = _calculateUnrealizedPnL(pos, currentPrice);
    pos.unrealizedPnL = unrealizedPnL;

    // Update liquidation status
    bool shouldBeLiquidatable = (pos.side == CommonStructs.Side.LONG && currentPrice <= pos.liquidationPrice)
        || (pos.side == CommonStructs.Side.SHORT && currentPrice >= pos.liquidationPrice);
    posData.isLiquidatable = shouldBeLiquidatable;
    posData.lastUpdateTime = block.timestamp;

    // ADL Queue Logic
    if (unrealizedPnL > 0) {
        // int256 pnlUint = unrealizedPnL;
        uint256 adlScore =
            (uint256(unrealizedPnL) * uint256(pos.leverage)) / 100;

        
        adlEngine.updateADLQueue(
            pos.marketId, 
            positionId, 
            pos.trader, 
            pos.side, 
            unrealizedPnL, 
            pos.leverage
            );
        
        if (!posData.inADLQueue) {
            posData.inADLQueue = true;
            emit ADLQueueStatusChanged(positionId, true, adlScore);
        }
    } else if (posData.inADLQueue) {
        adlEngine.removeFromADLQueue(
            pos.marketId, 
            positionId, 
            pos.side
            );
        posData.inADLQueue = false;
        emit ADLQueueStatusChanged(positionId, false, 0);
    }
}

function _calculateLiquidationPrice(
    bytes32 marketId,
    CommonStructs.Side side,
    uint256 entryPrice,
    uint256 collateral,
    uint256 size
) internal view returns (uint256 liquidPrice) {
    if (size == 0) return side == CommonStructs.Side.LONG ? 0 : type(uint256).max;

    MarketRiskConfig memory config = marketRiskConfigs[marketId];
    uint16 mmrBps = config.maintenanceMarginBps > 0 ? config.maintenanceMarginBps : 50; // default 0.5%

    uint256 notional = (size * entryPrice) / 1e18;
    uint256 mmr = (notional * mmrBps) / 10000;

    if (collateral <= mmr) {
        return side == CommonStructs.Side.LONG ? 0 : type(uint256).max;
    }

    uint256 buffer = collateral - mmr;
    uint256 priceMove = (buffer * 1e18) / size;

    if (side == CommonStructs.Side.LONG) {
        liquidPrice = priceMove >= entryPrice ? 1 : entryPrice - priceMove;
    } else {
        liquidPrice = priceMove > type(uint256).max - entryPrice ? type(uint256).max : entryPrice + priceMove;
    }
}

function _calculateUnrealizedPnL(CommonStructs.Position storage pos, uint256 currentPrice) internal view returns (int256) {
    int256 diff = pos.side == CommonStructs.Side.LONG
        ? int256(currentPrice) - int256(pos.entryPrice)
        : int256(pos.entryPrice) - int256(currentPrice);
    return (diff * int256(pos.size)) / 1e18;
}

function _updatePortfolio(address trader) internal {
    // Get all position IDs belonging to this trader
    bytes32[] memory ids = userPositions[trader];

    // Initialize counters
    uint256 totalCol = 0;  // Get all position IDs belonging to this trader
    int256 totalPnL = 0;   // Total paper profit/loss
    uint256 count = 0;    // Number of open positions

    // Loop through each position ID
    for (uint256 i = 0; i < ids.length; i++) {
          // Get the position data using the ID
        PositionData storage pd = positions[ids[i]];
        // Skip deleted/closed positions (openedAt == 0 means empty slot)
        if (pd.position.openedAt == 0) continue;
        // Add this position's values to totals
        totalCol += pd.position.collateral; // Add collateral
        totalPnL += pd.position.unrealizedPnL; // Add paper PnL
        count++;   // Count position
    }

    uint256 marginRatio = totalCol > 0 
    
        ? ((totalCol + uint256(totalPnL > 0 ? totalPnL : int256(0))) * 10000) / totalCol 
        : 0;

    portfolios[trader] = CommonStructs.Portfolio({
        trader: trader,
        totalCollateral: totalCol,
        totalRealizedPnL: totalRealizedPnL[trader],
        totalUnrealizedPnL: totalPnL,
        marginRatio: marginRatio,
        positionCount: count,
        lastUpdateTime: block.timestamp
    });
}

function _removeUserPosition(address trader, bytes32 positionId) internal {
    bytes32[] storage list = userPositions[trader];
    for (uint256 i = 0; i < list.length; i++) {
        if (list[i] == positionId) {
            list[i] = list[list.length - 1];
            list.pop();
            break;
        }
    }
}

function _setDefaultRiskConfigs() internal {
    // Defaults - can be extended with specific market configurations
}

// ============================================================================
// VIEW FUNCTIONS
// ============================================================================

function getPositionNetValue(bytes32 positionId, uint256 currentPrice) external view returns (int256) {
    PositionData storage posData = positions[positionId];
    // Current unrealized PnL
    int256 unrealizedPnL = _calculateUnrealizedPnL(posData.position, currentPrice);
    
    // Pending funding (negative if owed, positive if receiving)
    int256 pendingFunding = _calculateFundingOwed(positionId);
    
    // Net value = collateral + unrealizedPnL - pendingFunding
    return int256(posData.position.collateral) + unrealizedPnL - pendingFunding;
}

function getPendingFunding(bytes32 positionId) external view returns (int256) {
    return _calculateFundingOwed(positionId);
}

function getFundingOwed(bytes32 positionId) external view returns (int256) {
    return _calculateFundingOwed(positionId);
}

function getPosition(bytes32 positionId) external view returns (PositionData memory) {
    return positions[positionId];
}

function getPositionOwner(bytes32 positionId) external view returns (address) {
    return positionOwner[positionId];
}

function getPositionSize(bytes32 positionId) external view returns (uint256) {
    return positions[positionId].position.size;
}

function getUserPositions(address trader) external view returns (bytes32[] memory) {
    return userPositions[trader];
}

function getPortfolio(address trader) external view returns (CommonStructs.Portfolio memory) {
    return portfolios[trader];
}

function getOpenInterest(bytes32 marketId, CommonStructs.Side side) external view returns (uint256) {
    return openInterest[marketId][side];
}

function getMarketPositions(bytes32 marketId) external view returns (bytes32[] memory) {
    return marketPositions[marketId];
}

function getMarketPositionsBatch(bytes32 marketId) external view returns (bytes32[] memory) {
    return marketPositions[marketId];
}

}
````

## File: README.md
````markdown
# Baobab Protocol

## Overview
The Baobab Protocol is a high-performance perpetual decentralized exchange (DEX) core engine, meticulously developed in Solidity for EVM-compatible blockchain environments. It features a robust architecture designed for managing perpetual futures positions, integrating advanced risk management strategies, an automated deleveraging (ADL) mechanism, and dynamic funding rate calculations to ensure market stability and capital efficiency. It represents a comprehensive Perp-DEX engine suite built on Solidity, emphasizing institutional-grade risk management and capital efficiency.

## Features
*   **Core Perpetual Trading Engine**: Manages the complete lifecycle of perpetual positions, including opening, increasing, decreasing, and closing. It handles intricate margin requirements, calculates real-time Profit & Loss (PnL), and tracks comprehensive portfolio data for each trader. This includes the core logic for perpetual futures contract management.
*   **Automated Deleveraging (ADL)**: Implements a sophisticated, profit-based deleveraging system. In scenarios where liquidations cannot be fully filled or the insurance fund is insufficient, the ADL engine automatically closes profitable opposing positions, safeguarding the insurance fund by proportionally socializing losses among top-ranked profitable traders based on their ADL score (`unrealizedPnL × leverage / 100`).
*   **Dynamic Funding Rate System**: Calculates and applies periodic funding rates (fixed at 8 hours) to open positions based on the Open Interest (OI) imbalance between long and short positions. This mechanism stabilizes market prices by incentivizing traders to balance the market, reducing large market distortions. Rates are capped by market-specific configurations.
*   **Modular Risk Management Framework**: Built on a secure foundation utilizing `SecurityBase` for core security patterns, `CircuitBreaker` for emergency market-wide halts, `EmergencyPauser` for controlled protocol pauses, and `RateLimiter` for regulating throughput on critical functions.
*   **Tiered Market Risk Configuration**: Supports flexible market classification with various liquidity tiers (HIGH, MEDIUM, LOW), allowing for distinct maintenance margin (MMR), initial margin (IMR), and maximum leverage parameters tailored to different asset risk profiles. Default MMR for HIGH liquidity is 0.5%, MEDIUM is 0.75%, and LOW is 1%.
*   **Volume and Concentration Limits**: Incorporates mechanisms to prevent excessive market concentration by a single trader and to cap position sizes based on historical trading volume, thereby promoting overall market health and stability.
*   **Fee Calculation and Incentives Integration**: Seamlessly integrates with `FeeCalculator` to manage taker and maker trading fees, and `IncentiveManager` to track trade volumes, facilitating potential reward and incentive programs.
*   **On-chain Portfolio Tracking**: Provides real-time aggregation of total collateral, unrealized PnL, realized PnL, and margin ratios for each trader, offering transparency and enabling comprehensive risk monitoring.
*   **ERC20 Collateral Support**: Designed to handle standard ERC20 tokens as collateral for margin requirements, enabling flexible and secure asset management within the protocol.
*   **Cross-Margin Engine**: The protocol architecture includes a `CrossMarginEngine` for advanced collateral management, allowing shared margin across multiple trading positions.
*   **Decentralized Order Execution**: Features an `OrderBook` component for high-efficiency matching of decentralized limit and market order execution.
*   **Integrated Spot Trading**: The system integrates a `SpotEngine` to provide spot trading capabilities for underlying asset liquidity.

## Stacks / Technologies
| Technology | Purpose | Link |
| :----------------------------- | :----------------------------------------------- | :----------------------------------------------------------------- |
| Solidity | Smart contract programming language | [soliditylang.org](https://soliditylang.org/) |
| Foundry | Development framework for testing and deployment | [book.getfoundry.sh](https://book.getfoundry.sh/) |
| Ethereum Virtual Machine (EVM) | Runtime environment for smart contracts | [ethereum.org](https://ethereum.org/en/developers/docs/evm/) |
| OpenZeppelin Contracts | Secure, community-vetted smart contract libraries | [docs.openzeppelin.com/contracts](https://docs.openzeppelin.com/contracts/) |

## Getting Started
### Installation
To get a local copy up and running, follow these steps.

1.  Clone the repository:
    ```bash
    git clone https://github.com/olujimiAdebakin/BAOBAB-PROTOCOL.git
    ```
2.  Navigate to the project directory:
    ```bash
    cd BAOBAB-PROTOCOL
    ```
3.  Install dependencies (Foundry is required):
    ```bash
    forge install
    ```
4.  Compile the smart contracts:
    ```bash
    forge build
    ```
5.  Run tests to ensure everything is working correctly:
    ```bash
    forge test
    ```

### Environment Variables
Create a `.env` file in the root of your project and set the following variables:
```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your-api-key
PRIVATE_KEY=0xabc123... (Deployer/Admin private key)
ETHERSCAN_API_KEY=your-etherscan-key
ADMIN_ADDRESS=0x... (Protocol administrator address)
KEEPER_ADDRESS=0x... (Authorized funding keeper address)
INSURANCE_VAULT_ADDRESS=0x... (Insurance fund address, specific for ADL)
```

## Usage
Interact with the smart contracts directly on an EVM-compatible blockchain. Below are example JSON requests and responses for key API endpoints.

### Base URL
The base URL will be the deployed contract address on the respective blockchain network.

### Endpoints

#### `POST /openPosition`
Opens a new perpetual position for a trader.

**Request**:
```json
{
  "trader": "0x123...abc",
  "marketId": "0x... (bytes32)",
  "side": "0 (LONG) or 1 (SHORT)",
  "size": "1000000000000000000 (uint256)",
  "collateral": "100000000000000000 (uint256)",
  "entryPrice": "50000000000000000000000 (uint256)",
  "leverage": "10 (uint16)"
}
```

**Response**:
```json
{
  "positionId": "0x... (bytes32)",
  "status": "Success",
  "blockNumber": 19283746
}
```

**Errors**:
*   `400: PositionManager__InvalidSize`
*   `402: PositionManager__InsufficientInitialMargin`
*   `403: PositionManager__OnlyTradingEngine`

#### `POST /applyFundingRate`
Applies funding rates to all positions in a specified market. This function is typically called by an authorized keeper.

**Request**:
```json
{
  "marketId": "0x... (bytes32)"
}
```

**Response**:
```json
{
  "rateBps": "-15 (int256)",
  "lastFundingTime": 1715432100
}
```

**Errors**:
*   `400: FundingTooSoon` (Interval not elapsed)
*   `403: Only keeper`

#### `POST /executeADL`
Triggers the Auto-Deleveraging process in a specific market to cover liquidation shortfalls.

**Request**:
```json
{
  "marketId": "0x... (bytes32)",
  "liquidatedPosition": "0x... (bytes32)",
  "side": "0 (LONG)",
  "sizeToClose": "500000000000000000",
  "executionPrice": "49500000000000000000000"
}
```

**Response**:
```json
{
  "success": true,
  "adlId": "0x... (bytes32)",
  "totalClosed": "500000000000000000"
}
```

**Errors**:
*   `403: ADL__OnlyLiquidationEngine`
*   `404: ADL__InsufficientCandidates`

#### `POST /modifyPosition`
Modifies an existing position by adjusting its size and/or collateral.

**Request**:
```json
{
  "positionId": "0x... (bytes32)",
  "sizeDelta": "500000000000000000 (int256)",
  "collateralDelta": "-10000000000000000 (int256)",
  "currentPrice": "51000000000000000000000"
}
```

**Response**:
```json
{
  "realizedPnL": "2500000000000000000",
  "newLiquidationPrice": "45000000000000000000000"
}
```

**Errors**:
*   `401: PositionManager__PositionNotFound`
*   `402: PositionManager__InsufficientCollateral`

#### `GET /getPosition`
Retrieves the detailed data for a specific position.

**Request**:
```json
{
  "positionId": "0x... (bytes32)"
}
```

**Response**:
```json
{
  "position": {
    "trader": "0x...",
    "size": "1000000000000000000",
    "collateral": "100000000000000000",
    "entryPrice": "50000000000000000000000",
    "leverage": 10
  },
  "isLiquidatable": false,
  "inADLQueue": true,
  "accumulatedFunding": "1500000000000000"
}
```

**Errors**:
*   `404: PositionManager__PositionNotFound`

## Contributing
We welcome contributions to the Baobab Protocol! Please follow these guidelines:
*   Fork the repository to your GitHub account.
*   Create a feature branch with a descriptive name (e.g., `feature/add-new-module`).
*   Ensure all existing tests pass by running `forge test`.
*   Write clear, concise code and new tests for your changes.
*   Submit a Pull Request with a detailed description of your modifications and their purpose.
*   Ensure all logic follows the existing safety patterns (`SecurityBase`).
*   Document all external functions using NatSpec.

## Author Info
*   **GitHub**: [olujimiAdebakin](https://github.com/olujimiAdebakin)
*   **Email**: omoladebu231@gmail.com
*   **Twitter**: [@olujimi_the_dev](https://twitter.com/olujimi_the_dev)

## License
This project is licensed under the **BUSL-1.1 License**.
````
