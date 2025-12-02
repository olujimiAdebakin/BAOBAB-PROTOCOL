// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "./CommonStructs.sol";

library LiquidationStructs {

      /**
       * @dev Daily volume bucket used in mapping(address => mapping(uint256 => VolumeBucket))
       *      Bucket ID = timestamp normalized to midnight UTC
       * @param volume USD notional traded that day (18 decimals)
       * @param timestamp When bucket was last updated
       */
      struct VolumeBucket {
            uint256 volume;     
            uint256 timestamp;
      }

       /**
     * @notice Liquidation event data
      * @param volume30d User's rolling 30-day volume (18 decimals)
      * @param lastUpdatedBucket Timestamp of last updated volume bucket
      * @param tier User's current tier based on 30-day volume
     */
      struct UserVolume {
            uint256 volume30d;
            uint256 lastUpdatedBucket;
            uint8 tier; 
      }

    /**
     * @notice Liquidation event data
     * @param positionId Position being liquidated
     * @param trader Owner of liquidated position
     * @param liquidator Address executing liquidation
     * @param marketId Market of position
     * @param side LONG or SHORT
     * @param size Position size (18 decimals)
     * @param collateral Collateral seized (18 decimals)
     * @param markPrice Price at liquidation (18 decimals)
     * @param liquidationPrice Trigger price (18 decimals)
     * @param liquidationFee Fee charged (18 decimals)
     * @param insuranceFundContribution Amount to insurance fund (18 decimals)
     * @param timestamp Liquidation time
     */
    struct Liquidation {
        bytes32 positionId;
        address trader;
        address liquidator;
        bytes32 marketId;
        CommonStructs.Side side;
        uint256 size;
        uint256 collateral;
        uint256 markPrice;
        uint256 liquidationPrice;
        uint256 liquidationFee;
        uint256 insuranceFundContribution;
        uint256 timestamp;
    }

    /**
     * @notice Position health metrics for liquidation checking
     * @param positionId Position identifier
     * @param marginRatio Current margin / required margin (basis points)
     * @param maintenanceMarginRequired Minimum to avoid liquidation (18 decimals)
     * @param availableMargin Margin after unrealized PnL (18 decimals)
     * @param liquidationPrice Price triggering liquidation (18 decimals)
     * @param distanceToLiquidation Percentage away from liquidation (basis points)
     * @param isLiquidatable Whether position can be liquidated now
     */
    struct PositionHealth {
        bytes32 positionId;
        uint256 marginRatio;
        uint256 maintenanceMarginRequired;
        uint256 availableMargin;
        uint256 liquidationPrice;
        uint256 distanceToLiquidation;
        bool isLiquidatable;
    }

    /**
     * @notice 
     * @dev Configuration for partial liquidations and ADL
     * @param maxLiquidationRatioBps Max % of position to liquidate per tx (basis points)
     * @param partialLiquidationCloseRatioBps % of position to close in partial liqs (basis points)
     * @param insuranceFundFeeBps % of collateral sent to insurance fund (basis points)
     * @param liquidatorRewardBps % of collateral paid to liquidator (basis points)
     * @param adlEnabled Whether auto-deleveraging is enabled
     */
    struct LiquidationConfig {
        uint256 maxLiquidationRatioBps;  // max % of position to liquidate per tx
        uint256 partialLiquidationCloseRatioBps; // for partial liqs
        uint256 insuranceFundFeeBps;     // % of collateral sent to insurance
        uint256 liquidatorRewardBps;     // % of collateral paid to liquidator
        bool adlEnabled;                 // auto-deleveraging enabled
    }

    /**
     * @notice 
     * @dev Insurance fund claim after catastrophic loss
     * @param claimId Unique identifier for the claim
     * @param claimant Address requesting the claim
     * @param amount Amount requested (18 decimals)
     * @param timestamp When the claim was created
     * @param executed Whether the claim has been processed
     */
    struct InsuranceClaim {
        bytes32 claimId;
        address claimant;
        uint256 amount;             
        uint256 timestamp;
        bool executed;
    }
}