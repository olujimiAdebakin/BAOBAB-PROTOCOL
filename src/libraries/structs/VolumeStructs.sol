
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title VolumeStructs — BAOBAB Volume & Tier Data Structures
 * @notice Dedicated structs for VolumeTracker only — used nowhere else
 */
library VolumeStructs {
    /**
     * @dev Daily volume bucket used in mapping(address => mapping(uint256 => VolumeBucket))
     *      Bucket ID = timestamp normalized to midnight UTC
     */
    struct VolumeBucket {
        uint256 volume;     // USD notional traded that day (18 decimals)
        uint256 timestamp;  // When bucket was last updated
    }

    /**
     * @dev Optional: for future circular buffer implementation (currently not used)
     *      We use mapping + bucket rolling instead — cheaper and safer
     */
    struct DailyVolume {
        uint256 amount;
        uint256 timestamp;
    }

    /**
     * @dev Market-specific volume analytics — used by analytics dashboard
     */
    struct MarketVolume {
        bytes32 marketId;
        uint256 volume30d;
        uint256 lifetimeVolume;
    }
}