// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "./FixedPointMath.sol";
import "./PercentageMath.sol";

/**
 * @title Statistics
 * @author BAOBAB Protocol
 * @notice Advanced statistical functions for risk management, analytics, and trading strategies
 * @dev Provides mean, standard deviation, correlation, VaR, and other statistical measures
 * @dev Optimized for on-chain DeFi applications with gas-efficient algorithms
 */
library Statistics {
    using FixedPointMath for uint256;
    using PercentageMath for uint256;

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Reverts when insufficient data is provided for statistical calculations
    error InsufficientData();
    
    /// @dev Reverts when input arrays have mismatched lengths
    error ArrayLengthMismatch();
    
    /// @dev Reverts when input parameters are invalid
    error InvalidInput();

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // DATA STRUCTURES
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Statistical summary of a data series
    struct Summary {
        uint256 count;
        uint256 mean;
        uint256 median;
        uint256 standardDeviation;
        uint256 variance;
        uint256 min;
        uint256 max;
        uint256 sum;
    }

    /// @notice Risk metrics for a portfolio or position
    struct RiskMetrics {
        uint256 volatility;
        uint256 var95; // Value at Risk at 95% confidence
        uint256 var99; // Value at Risk at 99% confidence
        uint256 maxDrawdown;
        int256 sharpeRatio;
        int256 sortinoRatio;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // DESCRIPTIVE STATISTICS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate mean (average) of values
     * @param values Array of numerical values
     * @return meanValue Arithmetic mean of the values
     * @dev Reverts if array is empty
     */
    function mean(uint256[] memory values) internal pure returns (uint256 meanValue) {
        if (values.length == 0) revert InsufficientData();
        
        uint256 total = 0;
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
        
        meanValue = total / values.length;
    }

    /**
     * @notice Calculate median of values
     * @param values Array of numerical values
     * @return medianValue Median value (middle value when sorted)
     * @dev For even-length arrays, returns average of two middle values
     */
    function median(uint256[] memory values) internal pure returns (uint256 medianValue) {
        if (values.length == 0) revert InsufficientData();
        
        uint256[] memory sorted = _sort(values);
        
        if (sorted.length % 2 == 0) {
            // Even number of elements - average two middle values
            uint256 mid1 = sorted[sorted.length / 2 - 1];
            uint256 mid2 = sorted[sorted.length / 2];
            medianValue = (mid1 + mid2) / 2;
        } else {
            // Odd number of elements - take middle value
            medianValue = sorted[sorted.length / 2];
        }
    }

    /**
     * @notice Calculate standard deviation
     * @param values Array of numerical values
     * @return stdDev Standard deviation (population)
     * @dev Uses population standard deviation formula
     */
    function standardDeviation(uint256[] memory values) internal pure returns (uint256 stdDev) {
        if (values.length < 2) revert InsufficientData();
        
        uint256 avg = mean(values);
        uint256 sumSquaredDiffs = 0;
        
        for (uint256 i = 0; i < values.length; i++) {
            uint256 diff = values[i] > avg ? values[i] - avg : avg - values[i];
            sumSquaredDiffs += diff * diff;
        }
        
        uint256 variance = sumSquaredDiffs / values.length;
        stdDev = variance.sqrt();
    }

    /**
     * @notice Calculate variance
     * @param values Array of numerical values
     * @return varianceValue Variance of the values
     */
    function variance(uint256[] memory values) internal pure returns (uint256 varianceValue) {
        if (values.length < 2) revert InsufficientData();
        
        uint256 avg = mean(values);
        uint256 sumSquaredDiffs = 0;
        
        for (uint256 i = 0; i < values.length; i++) {
            uint256 diff = values[i] > avg ? values[i] - avg : avg - values[i];
            sumSquaredDiffs += diff * diff;
        }
        
        varianceValue = sumSquaredDiffs / values.length;
    }

    /**
     * @notice Calculate minimum value in array
     * @param values Array of numerical values
     * @return minValue Minimum value
     */
    function min(uint256[] memory values) internal pure returns (uint256 minValue) {
        if (values.length == 0) revert InsufficientData();
        
        minValue = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] < minValue) {
                minValue = values[i];
            }
        }
    }

    /**
     * @notice Calculate maximum value in array
     * @param values Array of numerical values
     * @return maxValue Maximum value
     */
    function max(uint256[] memory values) internal pure returns (uint256 maxValue) {
        if (values.length == 0) revert InsufficientData();
        
        maxValue = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] > maxValue) {
                maxValue = values[i];
            }
        }
    }

    /**
     * @notice Generate comprehensive statistical summary
     * @param values Array of numerical values
     * @return summary Statistical summary containing all key metrics
     */
    function summary(uint256[] memory values) internal pure returns (Summary memory summary_) {
        if (values.length == 0) revert InsufficientData();
        
        summary_.count = values.length;
        summary_.mean = mean(values);
        summary_.median = median(values);
        summary_.standardDeviation = standardDeviation(values);
        summary_.variance = variance(values);
        summary_.min = min(values);
        summary_.max = max(values);
        
        uint256 total = 0;
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
        summary_.sum = total;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CORRELATION AND COVARIANCE
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate correlation coefficient between two series
     * @param x First data series
     * @param y Second data series
     * @return correlation Correlation coefficient in Q64.96 format (-1.0 to 1.0)
     * @dev Pearson correlation coefficient
     */
    function correlation(uint256[] memory x, uint256[] memory y) internal pure returns (int256) {
        if (x.length != y.length) revert ArrayLengthMismatch();
        if (x.length < 2) revert InsufficientData();
        
        uint256 meanX = mean(x);
        uint256 meanY = mean(y);
        
        int256 covariance = 0;
        uint256 varianceX = 0;
        uint256 varianceY = 0;
        
        for (uint256 i = 0; i < x.length; i++) {
            int256 diffX = int256(x[i]) - int256(meanX);
            int256 diffY = int256(y[i]) - int256(meanY);
            
            covariance += diffX * diffY;
            varianceX += uint256(diffX * diffX);
            varianceY += uint256(diffY * diffY);
        }
        
        if (varianceX == 0 || varianceY == 0) return 0;
        
        uint256 denominator = (varianceX.sqrt()).mul(varianceY.sqrt());
        return (covariance * int256(FixedPointMath.Q96)) / int256(denominator);
    }

    /**
     * @notice Calculate covariance between two series
     * @param x First data series
     * @param y Second data series
     * @return covarianceValue Covariance between x and y
     */
    function covariance(uint256[] memory x, uint256[] memory y) internal pure returns (int256) {
        if (x.length != y.length) revert ArrayLengthMismatch();
        if (x.length < 2) revert InsufficientData();
        
        uint256 meanX = mean(x);
        uint256 meanY = mean(y);
        
        int256 sum = 0;
        for (uint256 i = 0; i < x.length; i++) {
            sum += (int256(x[i]) - int256(meanX)) * (int256(y[i]) - int256(meanY));
        }
        
        return sum / int256(x.length);
    }

    /**
     * @notice Calculate beta coefficient (asset sensitivity to market)
     * @param assetReturns Asset returns series
     * @param marketReturns Market returns series
     * @return beta Beta coefficient in Q64.96 format
     */
    function beta(uint256[] memory assetReturns, uint256[] memory marketReturns) internal pure returns (int256) {
        int256 cov = covariance(assetReturns, marketReturns);
        uint256 marketVariance = variance(marketReturns);
        
        if (marketVariance == 0) return 0;
        
        return (cov * int256(FixedPointMath.Q96)) / int256(marketVariance);
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // RISK METRICS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate Value at Risk (VaR) at given confidence level
     * @param returns Array of returns (as percentages in basis points)
     * @param confidence Confidence level in basis points (e.g., 9500 for 95%)
     * @return varValue Value at Risk in basis points (negative indicates loss)
     * @dev Historical simulation method
     */
    function valueAtRisk(int256[] memory returns_, uint256 confidence) internal pure returns (int256) {
        if (returns_.length == 0) revert InsufficientData();
        if (confidence > PercentageMath.ONE_HUNDRED_PERCENT) revert InvalidInput();
        
        // Sort returns
        int256[] memory sortedReturns = _sortInt(returns_);
        
        // Find percentile index (VaR is the negative of the percentile)
        uint256 index = (sortedReturns.length * (PercentageMath.ONE_HUNDRED_PERCENT - confidence)) / PercentageMath.PERCENTAGE_FACTOR;
        index = index >= sortedReturns.length ? sortedReturns.length - 1 : index;
        
        return -sortedReturns[index];
    }

    /**
     * @notice Calculate Conditional Value at Risk (CVaR)
     * @param returns Array of returns (as percentages in basis points)
     * @param confidence Confidence level in basis points
     * @return cvarValue Conditional VaR in basis points
     * @dev Average of losses beyond VaR
     */
    function conditionalValueAtRisk(int256[] memory returns_, uint256 confidence) internal pure returns (int256) {
        if (returns_.length == 0) revert InsufficientData();
        
        int256 varValue = valueAtRisk(returns_, confidence); // FIXED: Changed 'var' to 'varValue'
        
        // Calculate average of returns worse than VaR
        int256 sum = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < returns_.length; i++) {
            if (returns_[i] < -varValue) { // FIXED: Changed 'var' to 'varValue'
                sum += returns_[i];
                count++;
            }
        }
        
        if (count == 0) return varValue; // FIXED: Changed 'var' to 'varValue'
        return -sum / int256(count);
    }

    /**
     * @notice Calculate maximum drawdown
     * @param values Array of portfolio values over time
     * @return maxDrawdown Maximum drawdown in basis points
     */
    function maxDrawdown(uint256[] memory values) internal pure returns (uint256) {
        if (values.length < 2) revert InsufficientData();
        
        uint256 peak = values[0];
        uint256 maxDD = 0;
        
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] > peak) {
                peak = values[i];
            } else {
                uint256 drawdown = ((peak - values[i]) * PercentageMath.PERCENTAGE_FACTOR) / peak;
                if (drawdown > maxDD) {
                    maxDD = drawdown;
                }
            }
        }
        
        return maxDD;
    }

    /**
     * @notice Calculate Sharpe ratio
     * @param returns Array of returns (as percentages in basis points)
     * @param riskFreeRate Risk-free rate in basis points
     * @return sharpeRatioValue Sharpe ratio in Q64.96 format
     */
    function sharpeRatio(int256[] memory returns_, uint256 riskFreeRate) internal pure returns (int256) {
        if (returns_.length < 2) revert InsufficientData();
        
        // Convert returns to uint256 for calculations
        uint256[] memory absReturns = new uint256[](returns_.length);
        int256 sum = 0;
        
        for (uint256 i = 0; i < returns_.length; i++) {
            absReturns[i] = returns_[i] > 0 ? uint256(returns_[i]) : uint256(-returns_[i]);
            sum += returns_[i];
        }
        
        int256 avgReturn = sum / int256(returns_.length);
        uint256 stdDev = standardDeviation(absReturns);
        
        if (stdDev == 0) return type(int256).max;
        
        int256 excessReturn = avgReturn - int256(riskFreeRate);
        return (excessReturn * int256(FixedPointMath.Q96)) / int256(stdDev);
    }

    /**
     * @notice Calculate Sortino ratio (only considers downside deviation)
     * @param returns Array of returns (as percentages in basis points)
     * @param riskFreeRate Risk-free rate in basis points
     * @return sortinoRatioValue Sortino ratio in Q64.96 format
     */
    function sortinoRatio(int256[] memory returns_, uint256 riskFreeRate) internal pure returns (int256) {
        if (returns_.length < 2) revert InsufficientData();
        
        int256 sum = 0;
        uint256 downsideVariance = 0;
        uint256 downsideCount = 0;
        
        for (uint256 i = 0; i < returns_.length; i++) {
            sum += returns_[i];
            
            if (returns_[i] < int256(riskFreeRate)) {
                int256 downside = returns_[i] - int256(riskFreeRate);
                downsideVariance += uint256(downside * downside);
                downsideCount++;
            }
        }
        
        int256 avgReturn = sum / int256(returns_.length);
        
        if (downsideCount == 0) return type(int256).max;
        
        uint256 downsideStdDev = (downsideVariance / downsideCount).sqrt();
        if (downsideStdDev == 0) return type(int256).max;
        
        int256 excessReturn = avgReturn - int256(riskFreeRate);
        return (excessReturn * int256(FixedPointMath.Q96)) / int256(downsideStdDev);
    }

    /**
     * @notice Calculate volatility (annualized standard deviation)
     * @param returns Array of returns (as percentages in basis points)
     * @param periodsPerYear Number of periods per year for annualization
     * @return volatilityValue Annualized volatility in basis points
     */
    function volatility(uint256[] memory returns_, uint256 periodsPerYear) internal pure returns (uint256) {
        if (returns_.length < 2) revert InsufficientData();
        
        uint256 stdDev = standardDeviation(returns_);
        return stdDev * (periodsPerYear.sqrt());
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TECHNICAL ANALYSIS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate simple moving average (SMA)
     * @param values Array of price values
     * @param period Number of periods for moving average
     * @return smaValues Array of SMA values
     */
    function simpleMovingAverage(
        uint256[] memory values,
        uint256 period
    ) internal pure returns (uint256[] memory smaValues) {
        if (values.length < period) revert InsufficientData();
        
        smaValues = new uint256[](values.length - period + 1);
        
        for (uint256 i = 0; i <= values.length - period; i++) {
            uint256 sum = 0;
            for (uint256 j = 0; j < period; j++) {
                sum += values[i + j];
            }
            smaValues[i] = sum / period;
        }
    }

    /**
     * @notice Calculate exponential moving average (EMA)
     * @param values Array of price values
     * @param period Number of periods for EMA
     * @return emaValues Array of EMA values
     */
    function exponentialMovingAverage(
        uint256[] memory values,
        uint256 period
    ) internal pure returns (uint256[] memory emaValues) {
        if (values.length < period) revert InsufficientData();
        
        emaValues = new uint256[](values.length - period + 1);
        
        // Calculate SMA for first value
        uint256 sum = 0;
        for (uint256 i = 0; i < period; i++) {
            sum += values[i];
        }
        emaValues[0] = sum / period;
        
        // Calculate multiplier
        uint256 multiplier = (2 * FixedPointMath.Q96) / (period + 1);
        
        // Calculate EMA for remaining values
        for (uint256 i = period; i < values.length; i++) {
            uint256 ema = (values[i] * multiplier + emaValues[i - period] * (FixedPointMath.Q96 - multiplier)) / FixedPointMath.Q96;
            emaValues[i - period + 1] = ema;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // PRIVATE HELPER FUNCTIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Sort array of uint256 values (bubble sort for small arrays)
     */
    function _sort(uint256[] memory arr) private pure returns (uint256[] memory) {
        uint256[] memory sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }
        
        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (sorted[i] > sorted[j]) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }
        
        return sorted;
    }

    /**
     * @dev Sort array of int256 values
     */
    function _sortInt(int256[] memory arr) private pure returns (int256[] memory) {
        int256[] memory sorted = new int256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }
        
        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (sorted[i] > sorted[j]) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }
        
        return sorted;
    }
}