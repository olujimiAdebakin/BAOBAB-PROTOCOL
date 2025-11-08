// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../../../libraries/structs/CommonStructs.sol";
import {SecurityBase} from "../../../security/SecurityBase.sol";

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
 * ADL MECHANISM:
 * 1. Liquidation occurs but can't fill (no buyers/sellers)
 * 2. Insurance fund insufficient to cover loss
 * 3. Protocol ranks profitable opposing positions by PnL + leverage
 * 4. Force-closes top positions until liquidation covered
 * 5. Deleveraged traders keep their profits
 * 
 * EXAMPLE:
 * - Alice LONG liquidated, needs $100k to close
 * - Insurance fund only has $20k
 * - Protocol ADLs Bob (SHORT, +$50k profit) and Carol (SHORT, +$30k profit)
 * - Alice's position closed, insurance fund saved
 * 
 */
contract AutoDeleverageEngine is SecurityBase {
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

    /// @notice Per-market ADL configuration
    mapping(bytes32 => ADLConfig) public adlConfigs;

    /// @notice ADL queue: market => side => ranked candidates
    mapping(bytes32 => mapping(CommonStructs.Side => ADLCandidate[])) public adlQueues;

    /// @notice Position to queue index mapping
    mapping(bytes32 => uint256) public queueIndices;

    /// @notice ADL execution history
    mapping(bytes32 => ADLExecution) public adlExecutions;

    /// @notice Total ADL events per market
    mapping(bytes32 => uint256) public totalADLEvents;

    /// @notice Authorized liquidation engine
    address public liquidationEngine;

    /// @notice Insurance vault address
    address public insuranceVault;

    /// @notice Protocol admin
    address public admin;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event ADLTriggered(
        bytes32 indexed adlId,
        bytes32 indexed marketId,
        bytes32 liquidatedPosition,
        uint256 totalSizeClosed
    );

    event PositionDeleveraged(
        bytes32 indexed positionId,
        address indexed trader,
        uint256 realizedPnL,
        uint256 timestamp
    );

    event ADLQueueUpdated(
        bytes32 indexed marketId,
        CommonStructs.Side side,
        uint256 queueLength
    );

    event ADLConfigUpdated(bytes32 indexed marketId);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error ADL__OnlyLiquidationEngine();
    error ADL__OnlyAdmin();
    error ADL__ADLNotEnabled();
    error ADL__InsufficientCandidates();
    error ADL__InvalidConfig();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor(
        address _admin,
        address _liquidationEngine,
        address _insuranceVault
    ) {
        if (_admin == address(0) || _liquidationEngine == address(0) || _insuranceVault == address(0)) {
            revert ADL__InvalidConfig();
        }

        admin = _admin;
        liquidationEngine = _liquidationEngine;
        insuranceVault = _insuranceVault;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyLiquidationEngine() {
        if (msg.sender != liquidationEngine) revert ADL__OnlyLiquidationEngine();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert ADL__OnlyAdmin();
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
    function executeADL(
        bytes32 marketId,
        bytes32 liquidatedPosition,
        CommonStructs.Side side,
        uint256 sizeToClose,
        uint256 executionPrice
    ) external onlyLiquidationEngine nonReentrant returns (bool success) {
        ADLConfig memory config = adlConfigs[marketId];

        if (!config.isEnabled) revert ADL__ADLNotEnabled();

        // Determine opposing side to deleverage
        CommonStructs.Side opposingSide = side == CommonStructs.Side.LONG 
            ? CommonStructs.Side.SHORT 
            : CommonStructs.Side.LONG;

        ADLCandidate[] storage queue = adlQueues[marketId][opposingSide];

        if (queue.length == 0) revert ADL__InsufficientCandidates();

        // Generate ADL ID
        bytes32 adlId = keccak256(
            abi.encodePacked(marketId, liquidatedPosition, block.timestamp)
        );

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
            _forceClosePosition(
                candidate.positionId,
                candidate.trader,
                closeSize,
                executionPrice
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
    ) external {
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
            queueIndices[positionId] = queue.length;
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
    function removeFromADLQueue(
        bytes32 marketId,
        bytes32 positionId,
        CommonStructs.Side side
    ) external {
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
    function toggleADL(bytes32 marketId) external onlyAdmin {
        adlConfigs[marketId].isEnabled = !adlConfigs[marketId].isEnabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Force-close a position (internal)
     * @param positionId Position to close
     * @param trader Position owner
     * @param size Size to close
     * @param price Execution price
     * @dev Calls PositionManager to execute close
     */
    function _forceClosePosition(
        bytes32 positionId,
        address trader,
        uint256 size,
        uint256 price
    ) internal {
        // TODO: Call PositionManager.forceClosePosition()
        // This would interact with your PositionManager contract
    }

    /**
     * @notice Get position size (internal)
     * @param positionId Position identifier
     * @return size Position size
     */
    function _getPositionSize(bytes32 positionId) internal view returns (uint256 size) {
        // TODO: Call PositionManager.getPositionSize()
        return 0; // Placeholder
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
    function _removeFromQueue(
        bytes32 marketId,
        CommonStructs.Side side,
        uint256 count
    ) internal {
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
    function _removePositionFromQueue(
        bytes32 marketId,
        bytes32 positionId,
        CommonStructs.Side side
    ) internal {
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
    function getADLQueue(
        bytes32 marketId,
        CommonStructs.Side side
    ) external view returns (ADLCandidate[] memory queue) {
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