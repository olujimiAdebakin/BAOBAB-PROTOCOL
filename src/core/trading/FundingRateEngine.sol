// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {PositionManager} from "./PositionManager.sol";
import {CommonStructs} from "../../libraries/structs/CommonStructs.sol";
import {RoleRegistry} from "../../access/RoleRegistry.sol";
import {AccessManager} from "../../access/AccessManager.sol";

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
contract FundingEngine {
    /// @notice Address of the PositionManager contract, used to access market configuration and position data.
    PositionManager public immutable positionManager;
    /// @notice Address of the AccessManager contract, used to verify keeper permissions.
    AccessManager public accessManager;

    /// @notice The absolute maximum funding rate allowed if not overridden by market config (0.3% per 8 hours).
    uint256 public constant MAX_FUNDING_RATE = 300;
    /// @notice The fixed duration for a funding calculation period (8 hours).
    uint256 public constant FUNDING_PERIOD = 8 hours;
    /// @notice Constant for Basis Points (10,000) used for scaling percentages.
    uint256 public constant BASIS_POINTS = 10_000;
    /// @notice Constant for 1e18 precision, used in rate calculation for fixed-point math.
    uint256 public constant PRECISION = 1e18;

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

    /**
     * @notice Initializes the FundingEngine with addresses for PositionManager and AccessManager.
     * @param _positionManager The address of the PositionManager contract.
     * @param _accessManager The address of the AccessManager contract.
     */
    constructor(address _positionManager, address _accessManager) {
        positionManager = PositionManager(_positionManager);
        accessManager = AccessManager(_accessManager);
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
    function applyFundingRate(bytes32 marketId) external onlyKeeper returns (int256 rateBps) {
        // Destructure only the required market config components
        (
            , // maxLev (unused)
            , // mmr (unused)
            uint16 maxFund,
            bool fundEnabled,
            uint256 interval // fundingInterval (unused)
        ) = positionManager.marketConfig(marketId);

        // Check if funding is disabled or interval is zero
        if (!fundEnabled || interval == 0) {
            lastFundingTime[marketId] = block.timestamp;
            return 0;
        }

        // Enforce the funding period time lock
        if (block.timestamp < lastFundingTime[marketId] + FUNDING_PERIOD) {
            revert FundingTooSoon();
        }

        uint256 longOI = positionManager.openInterest(marketId, CommonStructs.Side.LONG);
        uint256 shortOI = positionManager.openInterest(marketId, CommonStructs.Side.SHORT);
        uint256 totalOI = longOI + shortOI;

        // If no open interest, just update the last funding time and exit
        if (totalOI == 0) {
            lastFundingTime[marketId] = block.timestamp;
            return 0;
        }

        // Calculate the rate and number of periods
        rateBps = _calculateRate(longOI, shortOI, totalOI, maxFund);
        uint256 periods = (block.timestamp - lastFundingTime[marketId]) / FUNDING_PERIOD;

        // Apply funding to all positions
        _applyToPositions(marketId, rateBps, periods);

        // Update time and emit event
        lastFundingTime[marketId] = block.timestamp;
        emit FundingApplied(marketId, rateBps, longOI, shortOI);
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

    /**
     * @notice Iterates over all open positions in a market and updates their accumulated funding.
     * @param marketId The market ID.
     * @param rateBps The calculated funding rate in BPS.
     * @param periods The number of full funding intervals that have elapsed since the last funding.
     */
    function _applyToPositions(bytes32 marketId, int256 rateBps, uint256 periods) internal {
        // Fetch all position IDs for the given market
        bytes32[] memory posIds = positionManager.getMarketPositions(marketId);

        // Loop through each position ID
        for (uint256 i = 0; i < posIds.length; i++) {
            bytes32 posId = posIds[i];

            // Destructure the tuple returned from the public PositionManager.positions mapping accessor
            (
                CommonStructs.Position memory position,
                uint256 lastUpdateTime,
                int256 accumulatedFunding,
                bool isLiquidatable,
                bool inADLQueue
            ) = positionManager.positions(posId);

            // Rebuild the PositionData struct in memory (required for the subsequent logic if structs are used)
            PositionManager.PositionData memory data = PositionManager.PositionData({
                position: position,
                lastUpdateTime: lastUpdateTime,
                accumulatedFunding: accumulatedFunding,
                isLiquidatable: isLiquidatable,
                inADLQueue: inADLQueue
            });

            // Skip positions that are not opened (openedAt == 0 is an empty slot check)
            if (data.position.openedAt == 0) continue;

            // Calculate the funding payment
            int256 payment =
                _calcPayment(data.position.size, rateBps, periods, data.position.side == CommonStructs.Side.LONG);

            // Accumulate the funding payment
            data.accumulatedFunding += payment;

            // Update the accumulated funding in PositionManager
            positionManager.updateAccumulatedFunding(posId, data.accumulatedFunding);

            // Emit an event
            emit FundingPaid(posId, payment, data.position.side == CommonStructs.Side.LONG);
        }
    }

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
}
