// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {FixedPointMath} from "./FixedPointMath.sol";

/**
 * @title PercentageMath
 * @author BAOBAB Protocol
 * @notice High-precision percentage calculations with basis points precision
 * @dev Optimized for DeFi applications: fees, interest rates, risk parameters
 * @dev 1 basis point = 0.01% (10,000 basis points = 100%)
 */
library PercentageMath {
    using FixedPointMath for uint256;

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev Scaling factor for percentages (100.00% = 10,000 basis points)
    uint256 internal constant PERCENTAGE_FACTOR = 1e4;

    /// @dev Half percentage factor for rounding operations
    uint256 internal constant HALF_PERCENTAGE = PERCENTAGE_FACTOR / 2;

    /// @dev One basis point (0.01%)
    uint256 internal constant BP = 1;

    /// @dev Maximum possible percentage (100%)
    uint256 internal constant MAX_PERCENTAGE = PERCENTAGE_FACTOR;

    /// @dev One hundred percent in basis points
    uint256 internal constant ONE_HUNDRED_PERCENT = 100 * BP;

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev Reverts when percentage exceeds 100%
    error PercentageExceedsMax();

    /// @dev Reverts when division by zero attempted
    error DivisionByZero();

    /// @dev Reverts when input parameters are invalid
    error InvalidInput();

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // BASIC PERCENTAGE OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate x plus percentage of x
     * @param x Base value to apply percentage to
     * @param percentage Percentage in basis points (e.g., 100 = 1%, 50 = 0.5%)
     * @return result x + (x * percentage / PERCENTAGE_FACTOR)
     * @dev Reverts if percentage exceeds 100%
     */
    function addPercent(uint256 x, uint256 percentage) internal pure returns (uint256 result) {
        if (percentage > MAX_PERCENTAGE) revert PercentageExceedsMax();

        if (percentage == 0) return x;
        if (x == 0) return 0;

        uint256 increment = (x * percentage) / PERCENTAGE_FACTOR;
        result = x + increment;
    }

    /**
     * @notice Calculate x minus percentage of x
     * @param x Base value to apply percentage to
     * @param percentage Percentage in basis points (e.g., 100 = 1%, 50 = 0.5%)
     * @return result x - (x * percentage / PERCENTAGE_FACTOR)
     * @dev Reverts if percentage exceeds 100%
     */
    function subPercent(uint256 x, uint256 percentage) internal pure returns (uint256 result) {
        if (percentage > MAX_PERCENTAGE) revert PercentageExceedsMax();

        if (percentage == 0) return x;
        if (x == 0) return 0;

        uint256 decrement = (x * percentage) / PERCENTAGE_FACTOR;
        result = x - decrement;
    }

    /**
     * @notice Calculate percentage of x
     * @param x Base value to calculate percentage of
     * @param percentage Percentage in basis points (e.g., 100 = 1%, 50 = 0.5%)
     * @return result (x * percentage) / PERCENTAGE_FACTOR
     * @dev Reverts if percentage exceeds 100%
     */
    function percent(uint256 x, uint256 percentage) internal pure returns (uint256 result) {
        if (percentage > MAX_PERCENTAGE) revert PercentageExceedsMax();

        if (x == 0 || percentage == 0) return 0;

        result = (x * percentage) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Calculate percentage of x with rounding up
     * @param x Base value to calculate percentage of
     * @param percentage Percentage in basis points (e.g., 100 = 1%, 50 = 0.5%)
     * @return result (x * percentage + HALF_PERCENTAGE) / PERCENTAGE_FACTOR
     * @dev Reverts if percentage exceeds 100%
     */
    function percentUp(uint256 x, uint256 percentage) internal pure returns (uint256 result) {
        if (percentage > MAX_PERCENTAGE) revert PercentageExceedsMax();

        if (x == 0 || percentage == 0) return 0;

        result = (x * percentage + HALF_PERCENTAGE) / PERCENTAGE_FACTOR;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // RATIO AND CHANGE CALCULATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate ratio of part to total as percentage
     * @param part Partial value
     * @param total Total value
     * @return percentage Ratio expressed in basis points (0-10,000)
     * @dev Returns 0 if total is zero
     */
    function ratioAsPercent(uint256 part, uint256 total) internal pure returns (uint256 percentage) {
        if (total == 0) return 0;
        if (part == 0) return 0;

        percentage = (part * PERCENTAGE_FACTOR) / total;
    }

    /**
     * @notice Calculate percentage change from old to new value
     * @param oldValue Original value
     * @param newValue New value
     * @return change Percentage change in basis points (positive for increase, negative for decrease)
     */
    function calculatePercentChange(uint256 oldValue, uint256 newValue) internal pure returns (int256 change) {
        if (oldValue == 0) revert DivisionByZero();

        if (newValue > oldValue) {
            uint256 increase = newValue - oldValue;
            change = int256((increase * PERCENTAGE_FACTOR) / oldValue);
        } else {
            uint256 decrease = oldValue - newValue;
            change = -int256((decrease * PERCENTAGE_FACTOR) / oldValue);
        }
    }

    /**
     * @notice Calculate basis points change from old to new value
     * @param oldValue Original value
     * @param newValue New value
     * @return bpChange Change in basis points (positive for increase, negative for decrease)
     */
    function calculateBpChange(uint256 oldValue, uint256 newValue) internal pure returns (int256 bpChange) {
        if (oldValue == 0) revert DivisionByZero();

        if (newValue > oldValue) {
            uint256 increase = newValue - oldValue;
            bpChange = int256((increase * PERCENTAGE_FACTOR) / oldValue);
        } else {
            uint256 decrease = oldValue - newValue;
            bpChange = -int256((decrease * PERCENTAGE_FACTOR) / oldValue);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // FINANCIAL MATHEMATICS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Compound principal with interest rate over multiple periods
     * @param principal Initial amount
     * @param ratePerPeriod Interest rate per period in basis points
     * @param periods Number of compounding periods
     * @return compoundedAmount Principal compounded with interest
     * @dev Uses iterative compounding for precision
     */
    function compound(uint256 principal, uint256 ratePerPeriod, uint256 periods)
        internal
        pure
        returns (uint256 compoundedAmount)
    {
        if (ratePerPeriod == 0) return principal;
        if (periods == 0) return principal;
        if (principal == 0) return 0;

        compoundedAmount = principal;
        uint256 factor = PERCENTAGE_FACTOR + ratePerPeriod;

        for (uint256 i = 0; i < periods; i++) {
            uint256 temp = compoundedAmount * factor;
            if (temp / factor != compoundedAmount) revert InvalidInput(); // Overflow check
            compoundedAmount = temp / PERCENTAGE_FACTOR;
        }
    }

    /**
     * @notice Convert annual percentage rate (APR) to daily rate
     * @param apr Annual percentage rate in basis points
     * @return dailyRate Daily rate in basis points
     * @dev Uses simple division approximation (APR / 365)
     */
    function aprToDaily(uint256 apr) internal pure returns (uint256 dailyRate) {
        if (apr == 0) return 0;

        dailyRate = apr / 365;
    }

    /**
     * @notice Convert annual percentage rate to periodic rate
     * @param apr Annual percentage rate in basis points
     * @param periodsPerYear Number of compounding periods per year
     * @return periodicRate Rate per period in basis points
     */
    function aprToPeriodic(uint256 apr, uint256 periodsPerYear) internal pure returns (uint256 periodicRate) {
        if (apr == 0 || periodsPerYear == 0) return 0;

        periodicRate = apr / periodsPerYear;
    }

    /**
     * @notice Calculate utilization rate (borrowed / total)
     * @param borrowed Amount currently borrowed
     * @param available Amount available to borrow
     * @return utilization Utilization rate in basis points (0-10,000)
     */
    function utilizationRate(uint256 borrowed, uint256 available) internal pure returns (uint256 utilization) {
        if (available == 0) return borrowed > 0 ? MAX_PERCENTAGE : 0;

        uint256 total = borrowed + available;
        utilization = (borrowed * PERCENTAGE_FACTOR) / total;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TRADING AND RISK MANAGEMENT
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate liquidation price for long position
     * @param entryPrice Entry price of the position
     * @param collateral Collateral amount
     * @param positionSize Size of the position
     * @param maintenanceMargin Maintenance margin requirement in basis points
     * @return liquidationPrice Price at which position gets liquidated
     */
    function liquidationPriceLong(
        uint256 entryPrice,
        uint256 collateral,
        uint256 positionSize,
        uint256 maintenanceMargin
    ) internal pure returns (uint256 liquidationPrice) {
        if (positionSize == 0 || maintenanceMargin == 0) revert InvalidInput();

        uint256 marginValue = (collateral * PERCENTAGE_FACTOR) / (positionSize * maintenanceMargin / PERCENTAGE_FACTOR);

        if (marginValue >= PERCENTAGE_FACTOR) {
            return 0; // Position never liquidates
        }

        liquidationPrice = entryPrice * (PERCENTAGE_FACTOR - marginValue) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Calculate liquidation price for short position
     * @param entryPrice Entry price of the position
     * @param collateral Collateral amount
     * @param positionSize Size of the position
     * @param maintenanceMargin Maintenance margin requirement in basis points
     * @return liquidationPrice Price at which position gets liquidated
     */
    function liquidationPriceShort(
        uint256 entryPrice,
        uint256 collateral,
        uint256 positionSize,
        uint256 maintenanceMargin
    ) internal pure returns (uint256 liquidationPrice) {
        if (positionSize == 0 || maintenanceMargin == 0) revert InvalidInput();

        uint256 marginValue = (collateral * PERCENTAGE_FACTOR) / (positionSize * maintenanceMargin / PERCENTAGE_FACTOR);
        liquidationPrice = entryPrice * (PERCENTAGE_FACTOR + marginValue) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Calculate profit/loss percentage for a position
     * @param entryPrice Entry price
     * @param exitPrice Exit price
     * @param isLong Whether position is long
     * @return pnlPercent Profit/loss as percentage in basis points
     */
    function calculatePnlPercent(uint256 entryPrice, uint256 exitPrice, bool isLong)
        internal
        pure
        returns (int256 pnlPercent)
    {
        if (entryPrice == 0) revert DivisionByZero();

        if (isLong) {
            if (exitPrice > entryPrice) {
                uint256 profit = exitPrice - entryPrice;
                pnlPercent = int256((profit * PERCENTAGE_FACTOR) / entryPrice);
            } else {
                uint256 loss = entryPrice - exitPrice;
                pnlPercent = -int256((loss * PERCENTAGE_FACTOR) / entryPrice);
            }
        } else {
            if (exitPrice < entryPrice) {
                uint256 profit = entryPrice - exitPrice;
                pnlPercent = int256((profit * PERCENTAGE_FACTOR) / entryPrice);
            } else {
                uint256 loss = exitPrice - entryPrice;
                pnlPercent = -int256((loss * PERCENTAGE_FACTOR) / entryPrice);
            }
        }
    }

    /**
     * @notice Calculate slippage tolerance bounds
     * @param price Reference price
     * @param slippageBps Slippage tolerance in basis points
     * @param isBuy Whether calculating for buy or sell
     * @return minPrice Minimum acceptable price
     * @return maxPrice Maximum acceptable price
     */
    function slippageBounds(uint256 price, uint256 slippageBps, bool isBuy)
        internal
        pure
        returns (uint256 minPrice, uint256 maxPrice)
    {
        if (slippageBps > MAX_PERCENTAGE) revert PercentageExceedsMax();

        uint256 slippageAmount = (price * slippageBps) / PERCENTAGE_FACTOR;

        if (isBuy) {
            minPrice = price - slippageAmount;
            maxPrice = price + slippageAmount;
        } else {
            minPrice = price - slippageAmount;
            maxPrice = price + slippageAmount;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // FEE CALCULATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate fee amount
     * @param amount Base amount to calculate fee from
     * @param feeBps Fee rate in basis points
     * @return feeAmount Calculated fee amount
     */
    function calculateFee(uint256 amount, uint256 feeBps) internal pure returns (uint256 feeAmount) {
        if (feeBps > MAX_PERCENTAGE) revert PercentageExceedsMax();
        if (amount == 0 || feeBps == 0) return 0;

        feeAmount = (amount * feeBps) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Calculate amount after deducting fee
     * @param amount Base amount
     * @param feeBps Fee rate in basis points
     * @return netAmount Amount after fee deduction
     */
    function amountAfterFee(uint256 amount, uint256 feeBps) internal pure returns (uint256 netAmount) {
        if (feeBps > MAX_PERCENTAGE) revert PercentageExceedsMax();
        if (amount == 0) return 0;
        if (feeBps == 0) return amount;

        uint256 feeAmount = (amount * feeBps) / PERCENTAGE_FACTOR;
        netAmount = amount - feeAmount;
    }

    /**
     * @notice Calculate amount before fee was applied
     * @param netAmount Amount after fee
     * @param feeBps Fee rate in basis points
     * @return grossAmount Original amount before fee
     */
    function amountBeforeFee(uint256 netAmount, uint256 feeBps) internal pure returns (uint256 grossAmount) {
        if (feeBps >= MAX_PERCENTAGE) revert PercentageExceedsMax();
        if (netAmount == 0) return 0;
        if (feeBps == 0) return netAmount;

        grossAmount = (netAmount * PERCENTAGE_FACTOR) / (PERCENTAGE_FACTOR - feeBps);
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // VALIDATION FUNCTIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate that percentage is within bounds (0-100%)
     * @param percentage Percentage to validate in basis points
     * @return isValid Whether percentage is valid
     */
    function isValidPercentage(uint256 percentage) internal pure returns (bool isValid) {
        isValid = percentage <= MAX_PERCENTAGE;
    }

    /**
     * @notice Validate and clamp percentage to maximum 100%
     * @param percentage Percentage to clamp in basis points
     * @return clampedPercentage Percentage clamped to 0-100%
     */
    function clampPercentage(uint256 percentage) internal pure returns (uint256 clampedPercentage) {
        clampedPercentage = percentage > MAX_PERCENTAGE ? MAX_PERCENTAGE : percentage;
    }

    /**
     * @notice Convert basis points to decimal representation
     * @param bps Value in basis points
     * @return decimalValue Decimal representation (e.g., 100 bps = 0.01)
     */
    function bpsToDecimal(uint256 bps) internal pure returns (uint256 decimalValue) {
        decimalValue = (bps * FixedPointMath.Q96) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Convert decimal to basis points
     * @param decimalValue Decimal value (e.g., 0.01 = 1%)
     * @return bps Value in basis points
     */
    function decimalToBps(uint256 decimalValue) internal pure returns (uint256 bps) {
        bps = (decimalValue * PERCENTAGE_FACTOR) / FixedPointMath.Q96;
    }
}
