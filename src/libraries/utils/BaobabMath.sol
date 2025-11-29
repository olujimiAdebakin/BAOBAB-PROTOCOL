// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title BaobabMath – Unified Math Library for BAOBAB Protocol
 * @notice Combines SafeCast with protocol-specific math utilities
 * @dev Provides safe arithmetic operations, BPS calculations, and BAOBAB-specific math functions
 */
library BaobabMath {
    using SafeCast for uint256;
    using SafeCast for int256;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       PROTOCOL CONSTANTS                                        */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /// @notice Basis points denominator (100% = 10,000 BPS)
    uint256 public constant BPS = 10_000;
    
    /// @notice Maximum fee in basis points (5%)
    uint256 public constant MAX_FEE_BPS = 500;
    
    /// @notice Maximum leverage multiplier (100x)
    uint256 public constant MAX_LEVERAGE = 100;
    
    /// @notice Precision for funding rate calculations
    uint256 public constant FUNDING_PRECISION = 1e18;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       SAFE CAST RE-EXPORTS                                      */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    // uint256 → int256 conversions
    function toInt256(uint256 value) internal pure returns (int256) {
        return value.toInt256();
    }

    function toInt128(uint256 value) internal pure returns (int128) {
        return value.toInt128();
    }

    // int256 → uint256 conversions
    function toUint256(int256 value) internal pure returns (uint256) {
        return value.toUint256();
    }

    function toUint128(int256 value) internal pure returns (uint128) {
        return value.toUint128();
    }

    // uint256 → uint256 (downcasting)
    function toUint128(uint256 value) internal pure returns (uint128) {
        return value.toUint128();
    }

    function toUint64(uint256 value) internal pure returns (uint64) {
        return value.toUint64();
    }

    // int256 → int256 (downcasting)
    function toInt128(int256 value) internal pure returns (int128) {
        return value.toInt128();
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                  BPS & PERCENTAGE OPERATIONS                                    */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Calculate value with BPS percentage applied
     * @param value Base value to apply percentage to
     * @param bps Percentage in basis points (e.g., 100 = 1%)
     * @return Result with percentage applied
     */
    function applyBps(uint256 value, uint256 bps) internal pure returns (uint256) {
        return (value * bps) / BPS;
    }

    /**
     * @notice Calculate value with BPS discount applied
     * @param value Base value to discount
     * @param discountBps Discount in basis points
     * @return Discounted value (safe from underflow)
     */
    function applyDiscountBps(uint256 value, uint256 discountBps) internal pure returns (uint256) {
        if (discountBps >= BPS) return 0;
        return (value * (BPS - discountBps)) / BPS;
    }

    /**
     * @notice Safe BPS subtraction (prevents underflow)
     * @param a First value in BPS
     * @param b Second value in BPS  
     * @return Difference or 0 if result would be negative
     */
    function safeBpsSubtract(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /**
     * @notice Apply volatility multiplier to fee
     * @param baseFee Base fee in BPS
     * @param multiplierBps Multiplier in BPS (e.g., 15000 = 1.5x)
     * @return Adjusted fee with multiplier applied
     */
    function applyVolatilityMultiplier(uint256 baseFee, uint256 multiplierBps) internal pure returns (uint256) {
        return (baseFee * multiplierBps) / BPS;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       FEE CALCULATIONS                                          */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Calculate trading fee with tier discount
     * @param baseFee Base fee in BPS
     * @param discountBps Tier discount in BPS
     * @return Final fee after discount (capped at 0)
     */
    function calculateFeeWithDiscount(uint256 baseFee, uint256 discountBps) internal pure returns (uint256) {
        if (discountBps >= baseFee) return 0;
        return baseFee - discountBps;
    }

    /**
     * @notice Calculate maker rebate (can be negative)
     * @param rebateBps Rebate in BPS (negative for fee, positive for rebate)
     * @return Safe rebate value
     */
    function calculateMakerRebate(int256 rebateBps) internal pure returns (int256) {
        return rebateBps;
    }

    /**
     * @notice Calculate borrow fee based on utilization
     * @param utilizationBps Utilization rate in BPS
     * @return Borrow fee in BPS (5-15% range)
     */
    function calculateBorrowFee(uint256 utilizationBps) internal pure returns (uint256) {
        // 5% base + 0.1% per 1% utilization
        return 500 + (utilizationBps * 10 / 100);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                  FUNDING & FINANCIAL MATH                                       */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Calculate funding rate based on OI imbalance
     * @param longOi Long open interest
     * @param shortOi Short open interest  
     * @param timeElapsed Time elapsed in seconds
     * @return fundingRate Funding rate with precision
     */
    function calculateFundingRate(
        uint256 longOi,
        uint256 shortOi,
        uint256 timeElapsed
    ) internal pure returns (int256 fundingRate) {
        if (longOi + shortOi == 0) return 0;

        int256 imbalance = (int256(longOi) - int256(shortOi)) * int256(FUNDING_PRECISION) / 
                          int256(longOi + shortOi);
        
        // 0.01% per hour per 1% imbalance
        fundingRate = (imbalance * 100) / int256(FUNDING_PRECISION);
        
        // Apply time scaling
        fundingRate = fundingRate * int256(timeElapsed) / 3600;
        
        return fundingRate;
    }

    /**
     * @notice Calculate liquidation price for position
     * @param entryPrice Position entry price
     * @param collateral Collateral amount
     * @param size Position size
     * @param mmrBps Maintenance margin requirement in BPS
     * @param isLong Whether position is long
     * @return liquidationPrice Price where position gets liquidated
     */
    function calculateLiquidationPrice(
        uint256 entryPrice,
        uint256 collateral,
        uint256 size,
        uint256 mmrBps,
        bool isLong
    ) internal pure returns (uint256 liquidationPrice) {
        if (size == 0) return isLong ? 0 : type(uint256).max;

        uint256 notional = (size * entryPrice) / FUNDING_PRECISION;
        uint256 mmr = (notional * mmrBps) / BPS;

        if (collateral <= mmr) {
            return isLong ? 1 : type(uint256).max - 1;
        }

        uint256 buffer = collateral - mmr;
        uint256 priceMove = (buffer * FUNDING_PRECISION) / size;

        if (isLong) {
            liquidationPrice = priceMove >= entryPrice ? 1 : entryPrice - priceMove;
        } else {
            liquidationPrice = entryPrice + priceMove;
            if (liquidationPrice < entryPrice) { // Overflow protection
                liquidationPrice = type(uint256).max - 1;
            }
        }

        return liquidationPrice;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                  LEVERAGE & RISK CALCULATIONS                                   */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Calculate maximum leverage based on risk parameters
     * @param volatilityBps Market volatility in BPS
     * @param baseLeverage Base leverage for market
     * @return Max allowed leverage (capped at protocol max)
     */
    function calculateMaxLeverage(uint256 volatilityBps, uint256 baseLeverage) internal pure returns (uint256) {
        // Reduce leverage by 1% for every 1% increase in volatility over 50%
        uint256 volatilityAdjustment = volatilityBps > 5000 
            ? ((volatilityBps - 5000) * 100) / BPS 
            : 0;
        
        uint256 adjustedLeverage = baseLeverage * (BPS - volatilityAdjustment) / BPS;
        
        return adjustedLeverage > MAX_LEVERAGE ? MAX_LEVERAGE : adjustedLeverage;
    }

    /**
     * @notice Calculate margin ratio for position
     * @param collateral Collateral amount
     * @param unrealizedPnL Unrealized PnL
     * @param notional Position notional value
     * @return Margin ratio in BPS
     */
    function calculateMarginRatio(
        uint256 collateral,
        int256 unrealizedPnL,
        uint256 notional
    ) internal pure returns (uint256) {
        if (notional == 0) return type(uint256).max;

        int256 netValue = int256(collateral) + unrealizedPnL;
        if (netValue <= 0) return 0;

        return (uint256(netValue) * BPS) / notional;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      VALIDATION & SAFETY                                        */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Validate fee BPS is within allowed range
     * @param feeBps Fee to validate
     * @return isValid Whether fee is valid
     */
    function isValidFeeBps(uint256 feeBps) internal pure returns (bool) {
        return feeBps <= MAX_FEE_BPS;
    }

    /**
     * @notice Validate leverage is within allowed range
     * @param leverage Leverage to validate
     * @return isValid Whether leverage is valid
     */
    function isValidLeverage(uint256 leverage) internal pure returns (bool) {
        return leverage > 0 && leverage <= MAX_LEVERAGE;
    }

    /**
     * @notice Safe conversion with bounds checking
     * @param value Value to convert
     * @param min Minimum allowed value
     * @param max Maximum allowed value
     * @return Converted and bounded value
     */
    function safeConvertWithBounds(
        uint256 value,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }
}