// src/libraries/structs/FundingStructs.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "./CommonStructs.sol";

/**
 * @title FundingStructs — BAOBAB Funding Rate & Payment Structures
 * @notice Only used by FundingEngine and PerpEngine
 */
library FundingStructs {

      
    struct FundingRateState {
        bytes32 marketId;
        int256 fundingRate;              // 8h rate in bps (can be negative)
        int256 fundingRateVelocity;      // rate of change
        int256 premiumIndex;             // perp vs spot deviation
        uint256 openInterestLong;        // 18 decimals
        uint256 openInterestShort;       // 18 decimals
        int256 imbalance;                // long - short OI
        uint256 lastUpdateTime;
        uint256 nextFundingTime;
    }

    struct FundingPayment {
        bytes32 positionId;
        int256 paymentAmount;            // positive = pay, negative = receive
        int256 fundingRateApplied;       // bps
        uint256 timestamp;
    }

    struct CumulativeFunding {
        bytes32 marketId;
        int256 longCumulativeFunding;    // cumulative funding longs paid
        int256 shortCumulativeFunding;   // cumulative funding shorts paid
        uint256 lastUpdateTime;
    }
}