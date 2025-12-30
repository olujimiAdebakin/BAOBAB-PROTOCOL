// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title IncentiveStructs — BAOBAB Rebates, Rewards & Tier System
 * @notice Used by FeeCalculator, VolumeTracker, and future staking
 */
library IncentiveStructs {
    /**
     * @dev VIP tier configuration — stored in FeeCalculator
     */
    struct Tier {
        uint256 minVolume30d; // USD threshold (18 decimals)
        int256 makerRebateBps; // negative = rebate (e.g. -5 = 5 bps rebate)
        uint256 takerDiscountBps; // discount on taker fee
        uint256 referralBonusBps; // extra for referrers
    }

    /**
     * @dev Pending rebate claim
     */
    struct RebateClaim {
        address user;
        uint256 amount; // 18 decimals
        uint256 claimableAfter;
        bool claimed;
    }

    /**
     * @dev Referral relationship
     */
    struct Referral {
        address referrer;
        address referee;
        uint256 refereeVolume30d;
        uint256 totalRebatesPaid;
        uint256 joinTimestamp;
    }

    /**
     * @dev Tier upgrade event snapshot
     */
    struct TierSnapshot {
        address user;
        uint8 fromTier;
        uint8 toTier;
        uint256 volume30d;
        uint256 timestamp;
    }
}
