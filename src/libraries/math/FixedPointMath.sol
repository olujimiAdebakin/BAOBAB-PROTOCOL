// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title FixedPointMath
 * @author BAOBAB Protocol
 * @notice High-precision fixed-point arithmetic library using Q64.96 format
 * @dev 64 bits for integer part, 96 bits for fractional part
 * @dev Optimized for DeFi applications with gas-efficient assembly operations
 */
library FixedPointMath {
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev Scaling factor for Q64.96 fixed-point numbers
    uint256 internal constant Q64 = 2 ** 64;

    /// @dev Primary scaling factor (64 + 96 = 160 bits total precision)
    uint256 internal constant Q96 = 2 ** 96;

    /// @dev Extended precision for intermediate calculations
    uint256 internal constant Q192 = 2 ** 192;

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev Reverts when arithmetic operation overflows
    error Overflow();

    /// @dev Reverts when division by zero attempted
    error DivByZero();

    /// @dev Reverts when input parameters are invalid
    error InvalidInput();

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CORE ARITHMETIC OPERATIONS (Q64.96 × Q64.96 → Q64.96)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Multiply two Q64.96 numbers, rounding down
     * @param x First Q64.96 number
     * @param y Second Q64.96 number
     * @return result x * y as Q64.96 (rounded down)
     * @dev Uses assembly for gas-efficient overflow protection
     */
    function mul(uint256 x, uint256 y) internal pure returns (uint256 result) {
        // Gas optimization: early return for zero values
        if (x == 0 || y == 0) return 0;

        assembly {
            // Multiply with overflow detection using mulmod
            let mm := mulmod(x, y, not(0))

            // Check for overflow: if (x * y) / x != y
            if iszero(eq(div(mm, x), y)) { revert(0, 0) } // Bubble up overflow error

            // Divide by Q96 to maintain Q64.96 precision
            result := div(mm, Q96)
        }
    }

    /**
     * @notice Multiply two Q64.96 numbers, rounding up
     * @param x First Q64.96 number
     * @param y Second Q64.96 number
     * @return result x * y as Q64.96 (rounded up)
     */
    function mulUp(uint256 x, uint256 y) internal pure returns (uint256 result) {
        result = mul(x, y);

        // Round up if there's a remainder
        if (result != 0 && mulmod(x, y, Q96) != 0) {
            unchecked {
                result += 1;
            }
        }
    }

    /**
     * @notice Divide two Q64.96 numbers, rounding down
     * @param x Numerator in Q64.96 format
     * @param y Denominator in Q64.96 format
     * @return result x / y as Q64.96 (rounded down)
     * @dev Reverts on division by zero
     */
    function div(uint256 x, uint256 y) internal pure returns (uint256 result) {
        if (y == 0) revert DivByZero();
        if (x == 0) return 0;

        // Multiply by Q96 before division to maintain precision
        result = (x * Q96) / y;
    }

    /**
     * @notice Divide two Q64.96 numbers, rounding up
     * @param x Numerator in Q64.96 format
     * @param y Denominator in Q64.96 format
     * @return result x / y as Q64.96 (rounded up)
     * @dev Reverts on division by zero
     */
    function divUp(uint256 x, uint256 y) internal pure returns (uint256 result) {
        if (y == 0) revert DivByZero();
        if (x == 0) return 0;

        // Add (denominator - 1) to numerator before division for ceiling rounding
        result = (x * Q96 + y - 1) / y;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TYPE CONVERSIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert uint256 to Q64.96 fixed-point number
     * @param x Unsigned integer to convert
     * @return Q64.96 representation of x
     */
    function fromUint(uint256 x) internal pure returns (uint256) {
        return x * Q96;
    }

    /**
     * @notice Convert Q64.96 to uint256 (truncating fractional part)
     * @param x Q64.96 number to convert
     * @return Truncated integer value
     */
    function toUint(uint256 x) internal pure returns (uint256) {
        return x / Q96;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ADVANCED MATHEMATICAL FUNCTIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate square root using Babylonian method
     * @param x Q64.96 number to calculate square root of
     * @return r Square root of x in Q64.96 format
     * @dev Uses iterative approximation with convergence check
     */
    function sqrt(uint256 x) internal pure returns (uint256 r) {
        if (x == 0) return 0;

        // Handle edge case for maximum value
        if (x == type(uint256).max) return fromUint(type(uint128).max);

        // Initial guess: x / 2 + 1
        r = x;
        uint256 rOld;

        // Babylonian method with convergence check
        do {
            rOld = r;
            r = (r + x / r) >> 1; // bit-shift for division by 2
        } while (r < rOld && rOld - r > 1);

        // Final adjustment for optimal precision
        uint256 r1 = x / r;
        return r < r1 ? r : r1;
    }

    /**
     * @notice Calculate x raised to the power of y
     * @param x Base in Q64.96 format
     * @param y Exponent (can be negative)
     * @return result x^y in Q64.96 format
     * @dev Supports negative exponents via reciprocal
     */
    function pow(uint256 x, int256 y) internal pure returns (uint256 result) {
        if (y == 0) return fromUint(1);
        if (y == 1) return x;
        if (y == -1) return div(fromUint(1), x);

        // Handle negative exponents
        bool negative = y < 0;
        uint256 exp = negative ? uint256(-y) : uint256(y);
        uint256 base = negative ? div(fromUint(1), x) : x;

        // Exponentiation by squaring
        result = fromUint(1);
        while (exp > 0) {
            if (exp & 1 == 1) {
                result = mul(result, base);
            }
            base = mul(base, base);
            exp >>= 1;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TRANSCENDENTAL FUNCTIONS (APPROXIMATIONS)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate exponential function e^x using Taylor series
     * @param x Exponent in Q64.96 format
     * @return result e^x in Q64.96 format
     * @dev 10-term Taylor series approximation for reasonable precision
     */
    function expo(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return fromUint(1);

        result = fromUint(1);
        uint256 term = x;
        uint256 factorial = fromUint(1);

        // Taylor series: e^x = 1 + x + x²/2! + x³/3! + ...
        for (uint256 i = 1; i <= 10; ++i) {
            factorial = mul(factorial, fromUint(i));
            term = div(mul(term, x), fromUint(i));
            result += term;
        }
    }

    /**
     * @notice Calculate natural logarithm ln(x)
     * @param x Input in Q64.96 format (must be > 0)
     * @return result ln(x) in Q64.96 format
     * @dev Uses range reduction + Newton iteration for precision
     */
    function ln(uint256 x) internal pure returns (uint256) {
        if (x == 0) revert DivByZero();
        if (x == fromUint(1)) return 0;

        int256 y = 0;
        uint256 z = x;

        // Range reduction: bring z into [1, 2)
        while (z >= fromUint(2)) {
            z >>= 1;
            y += int256(Q96);
        }
        while (z < fromUint(1)) {
            z <<= 1;
            y -= int256(Q96);
        }

        // Newton iteration for enhanced precision
        int256 w = int256(z) - int256(Q96);
        int256 w2 = mulInt(w, w) / int256(Q96);
        y += w - w2 / 2 + mulInt(w2, w) / 3 - mulInt(mulInt(w2, w2), w) / 4;

        return uint256(y);
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPER FUNCTIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Multiply two signed Q64.96 numbers
     * @param x First signed Q64.96 number
     * @param y Second signed Q64.96 number
     * @return result x * y as signed Q64.96
     * @dev Internal function for signed arithmetic
     */
    function mulInt(int256 x, int256 y) internal pure returns (int256) {
        return (x * y) / int256(Q96);
    }
}
