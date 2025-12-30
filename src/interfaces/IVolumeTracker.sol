// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title IVolumeTracker
 * @notice Interface for the VolumeTracker contract, which tracks user trading volumes over time.
 */
interface IVolumeTracker {
    /// @notice Struct representing a user's volume in a specific market
    struct MarketVolume {
        bytes32 marketId;
        uint256 volume30d;
        uint256 lifetimeVolume;
    }

    /// @notice Get user's total trading volume in the last 30 days
    function get30DayVolume(address user) external view returns (uint256);

    /// @notice Get user's total lifetime trading volume
    function getLifetimeVolume(address user) external view returns (uint256);

    /// @notice Record a trade for volume tracking
    function recordTrade(address user, bytes32 marketId, uint256 amount) external;

    /// @notice Get user's volume data for a specific market
    function getMarketVolume(address user, bytes32 marketId) external view returns (MarketVolume memory);
}
