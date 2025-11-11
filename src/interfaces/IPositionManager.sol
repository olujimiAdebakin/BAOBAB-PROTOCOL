// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../libraries/structs/CommonStructs.sol";

/**
 * @title IPositionManager
 * @notice Interface for PositionManager contract
 * @dev Used by AutoDeleverageEngine, LiquidationEngine, and TradingEngine
 */
interface IPositionManager {
    // ══════════════════════════════════════════════════════════════
    //                      POSITION LIFECYCLE
    // ══════════════════════════════════════════════════════════════

    function openPosition(
        address trader,
        bytes32 marketId,
        CommonStructs.Side side,
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        uint16 leverage
    ) external returns (bytes32 positionId);

    function modifyPosition(bytes32 positionId, int256 sizeDelta, int256 collateralDelta, uint256 currentPrice)
        external
        returns (int256 realizedPnL);

    function closePosition(bytes32 positionId, uint256 closePrice) external returns (int256 realizedPnL);

    function forceClosePosition(bytes32 positionId, uint256 closePrice, bool isLiquidation)
        external
        returns (int256 realizedPnL);

    // ══════════════════════════════════════════════════════════════
    //                      POSITION UPDATES
    // ══════════════════════════════════════════════════════════════

    function updatePositionState(bytes32 positionId, uint256 currentPrice) external;

    function applyFunding(bytes32 positionId, int256 fundingRate) external;

    // ══════════════════════════════════════════════════════════════
    //                         VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function getPositionSize(bytes32 positionId) external view returns (uint256 size);

    function getPosition(bytes32 positionId) external view returns (CommonStructs.PositionData memory positionData);

    function getUserPositions(address trader) external view returns (bytes32[] memory);

    function getOpenInterest(bytes32 marketId, CommonStructs.Side side) external view returns (uint256);
}
