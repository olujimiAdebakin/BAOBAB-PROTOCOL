// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title BaobabMath – Unified Math Library for BAOBAB Protocol
 * @notice Provides safe casts, BPS calculations, and key financial math for the protocol
 */
library BaobabMath {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 internal constant BPS = 10_000; // 100%
    uint256 internal constant MAX_FEE_BPS = 500; // 5%
    uint256 internal constant MAX_LEVERAGE = 100; // 100x leverage max
    uint256 internal constant FUNDING_PRECISION = 1e18; // Precision scale for funding rate

    // ==== SafeCast helpers ====

    /// Convert uint256 → int128 safely (throws if out of bounds)
    function toInt128(uint256 value) internal pure returns (int128) {
        int256 asInt = SafeCast.toInt256(value);
        return SafeCast.toInt128(asInt);
    }

    /// Convert uint256 → int256 safely (throws if out of bounds)
    function toInt256(uint256 value) internal pure returns (int256) {
        return SafeCast.toInt256(value);
    }

    /// Downcast uint256 → uint128 safely
    function toUint128(uint256 value) internal pure returns (uint128) {
        return SafeCast.toUint128(value);
    }

    /// Downcast int256 → int128 safely
    function toInt128(int256 value) internal pure returns (int128) {
        return SafeCast.toInt128(value);
    }

    /// Downcast int256 → uint256 safely (throws if negative)
    function toUint256(int256 value) internal pure returns (uint256) {
        return SafeCast.toUint256(value);
    }

    // ==== BPS Math ====

    /// Apply basis points to a value: (value * bps) / 10000
    function applyBps(uint256 value, uint256 bps) internal pure returns (uint256) {
        return (value * bps) / BPS;
    }

    /// Apply discount in bps: value * (10000 - discountBps) / 10000
    function applyDiscountBps(uint256 value, uint256 discountBps) internal pure returns (uint256) {
        if (discountBps >= BPS) return 0;
        return (value * (BPS - discountBps)) / BPS;
    }

    /// Safe subtraction for bps values (prevents underflow)
    function safeBpsSubtract(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /// Apply multiplier in bps (e.g. volatility multiplier)
    function applyMultiplier(uint256 base, uint256 multiplierBps) internal pure returns (uint256) {
        return (base * multiplierBps) / BPS;
    }

    // Add to BaobabMath.sol:
    function applyVolatilityMultiplier(uint256 feeBps, uint256 volatilityMultiplierBps)
        internal
        pure
        returns (uint256)
    {
        return applyMultiplier(feeBps, volatilityMultiplierBps);
    }

    // ==== Fee & Rebate calculations ====

    /// Calculate fee after tier discount (returns 0 if discount >= baseFee)
    function calculateFeeWithDiscount(uint256 baseFee, uint256 discountBps) internal pure returns (uint256) {
        return discountBps >= baseFee ? 0 : baseFee - discountBps;
    }

    /// Maker rebate, which can be negative or positive (passed as int256)
    function calculateMakerRebate(int256 rebateBps) internal pure returns (int256) {
        return rebateBps;
    }

    /// Borrow fee scales with utilization: base 5% + 0.1% per 1% utilization (bps)
    function calculateBorrowFee(uint256 utilizationBps) internal pure returns (uint256) {
        // 500 bps (5%) + utilization * 10 / 100 (0.1% per 1%)
        return 500 + (utilizationBps * 10) / 100;
    }

    // ==== Funding & Liquidation calculations ====

    /**
     * Calculate funding rate based on open interest imbalance
     * @param longOi Long open interest
     * @param shortOi Short open interest
     * @param timeElapsed Seconds elapsed since last funding
     * @return fundingRate Signed funding rate scaled by FUNDING_PRECISION
     */
    function calculateFundingRate(uint256 longOi, uint256 shortOi, uint256 timeElapsed)
        internal
        pure
        returns (int256 fundingRate)
    {
        uint256 totalOi = longOi + shortOi;
        if (totalOi == 0) return 0;

        int256 imbalance = (toInt256(longOi) - toInt256(shortOi)) * toInt256(FUNDING_PRECISION) / toInt256(totalOi);
        // Rough example: 0.01% per hour per 1% imbalance
        fundingRate = (imbalance * 100) / toInt256(FUNDING_PRECISION);
        // Scale by time elapsed in seconds, normalized to per hour (3600s)
        fundingRate = (fundingRate * toInt256(timeElapsed)) / 3600;

        return fundingRate;
    }

    /**
     * Calculate liquidation price of a position
     * @param entryPrice Entry price of position (scaled)
     * @param collateral Collateral amount
     * @param size Position size (scaled)
     * @param mmrBps Maintenance margin requirement (bps)
     * @param isLong Long or short position
     * @return liquidationPrice Price at which position liquidates
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
            if (liquidationPrice < entryPrice) {
                // overflow protection
                liquidationPrice = type(uint256).max - 1;
            }
        }

        return liquidationPrice;
    }

    // ==== Leverage & Risk ====

    /**
     * Calculate max leverage based on volatility and base leverage
     * Reduces max leverage as volatility increases above 50%
     */
    function calculateMaxLeverage(uint256 volatilityBps, uint256 baseLeverage) internal pure returns (uint256) {
        uint256 volatilityAdjustment = 0;
        if (volatilityBps > 5000) {
            volatilityAdjustment = ((volatilityBps - 5000) * 100) / BPS;
        }
        uint256 adjusted = (baseLeverage * (BPS - volatilityAdjustment)) / BPS;
        return adjusted > MAX_LEVERAGE ? MAX_LEVERAGE : adjusted;
    }

    /**
     * Calculate margin ratio for position
     * @param collateral Collateral amount
     * @param unrealizedPnL Unrealized profit or loss (can be negative)
     * @param notional Position notional value
     * @return Margin ratio in BPS
     */
    function calculateMarginRatio(uint256 collateral, int256 unrealizedPnL, uint256 notional)
        internal
        pure
        returns (uint256)
    {
        if (notional == 0) return type(uint256).max;

        int256 netValue = toInt256(collateral) + unrealizedPnL;
        if (netValue <= 0) return 0;

        return (uint256(netValue) * BPS) / notional;
    }

    // ==== Validation helpers ====

    /// Validate fee BPS is within allowed max
    function isValidFeeBps(uint256 feeBps) internal pure returns (bool) {
        return feeBps <= MAX_FEE_BPS;
    }

    /// Validate leverage is within protocol bounds
    function isValidLeverage(uint256 leverage) internal pure returns (bool) {
        return leverage > 0 && leverage <= MAX_LEVERAGE;
    }

    /// Safe value bounding helper
    function safeBound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }
}
