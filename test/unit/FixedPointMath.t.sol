// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Add console.sol import
import "../../src/libraries/math/FixedPointMath.sol";

/**
 * @title FixedPointMathTest
 * @author BAOBAB Protocol  
 * @notice Comprehensive test suite for FixedPointMath library
 * @dev Tests edge cases, precision, and gas efficiency
 */
contract FixedPointMathTest is Test {
    using FixedPointMath for uint256;

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TEST CONSTANTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    uint256 constant Q96 = 2 ** 96;
    uint256 constant ONE = 1 * Q96; // 1.0 in Q64.96
    uint256 constant TWO = 2 * Q96; // 2.0 in Q64.96

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CORE OPERATION TESTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    function test_Multiplication_Basic() public pure {
        uint256 a = ONE;  // 1.0
        uint256 b = TWO;  // 2.0
        
        uint256 result = a.mul(b);
        console.log("Multiplication Test: %s * %s = %s", a, b, result);
        assertEq(result, TWO, "1 * 2 should equal 2");
    }

    function test_Multiplication_Zero() public pure {
        uint256 a = ONE;
        uint256 b = 0;
        
        uint256 result = a.mul(b);
        console.log("Multiplication Zero Test: %s * %s = %s", a, b, result);
        assertEq(result, 0, "Any number * 0 should equal 0");
    }

    function test_Division_Basic() public pure {
        uint256 a = TWO;  // 2.0
        uint256 b = TWO;  // 2.0
        
        uint256 result = a.div(b);
        console.log("Division Test: %s / %s = %s", a, b, result);
        assertEq(result, ONE, "2 / 2 should equal 1");
    }

    function test_Division_ByZero_Reverts() public {
        uint256 a = ONE;
        uint256 b = 0;
        
        console.log("Testing division by zero revert...");
        vm.expectRevert(FixedPointMath.DivByZero.selector);
        a.div(b);
        console.log(" Division by zero correctly reverted");
    }

    function test_Multiplication_Rounding() public pure {
        uint256 a = ONE + 1;  // 1.0 + epsilon
        uint256 b = ONE;       // 1.0
        
        uint256 resultDown = a.mul(b);
        uint256 resultUp = a.mulUp(b);
        
        console.log("Rounding Test - Down: %s, Up: %s", resultDown, resultUp);
        console.log("Difference: %s", resultUp - resultDown);
        
        assertTrue(resultUp >= resultDown, "Round up should be >= round down");
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CONVERSION TESTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    function test_FromUint() public pure {
        uint256 input = 5;
        uint256 result = FixedPointMath.fromUint(input);
        
        console.log("FromUint Test: %s -> %s", input, result);
        console.log("Expected: %s", 5 * Q96);
        
        assertEq(result, 5 * Q96, "fromUint(5) should equal 5 * Q96");
    }

    function test_ToUint() public pure {
        uint256 qValue = 5 * Q96;
        uint256 result = FixedPointMath.toUint(qValue);
        
        console.log("ToUint Test: %s -> %s", qValue, result);
        assertEq(result, 5, "toUint(5 * Q96) should equal 5");
    }

    function test_ToUint_Truncates() public pure {
        uint256 qValue = (5 * Q96) + (Q96 / 2); // 5.5 in Q64.96
        uint256 result = FixedPointMath.toUint(qValue);
        
        console.log("ToUint Truncate Test: %s -> %s", qValue, result);
        console.log("Original Q64.96: %s", qValue);
        console.log("Truncated uint: %s", result);
        
        assertEq(result, 5, "toUint should truncate fractional part");
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ADVANCED MATH TESTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    function test_SquareRoot_PerfectSquare() public pure {
        uint256 x = FixedPointMath.fromUint(16); // 16.0
        uint256 result = x.sqrt();
        uint256 expected = FixedPointMath.fromUint(4); // 4.0
        
        console.log("Square Root Test: sqrt(%s) = %s", x, result);
        console.log("Expected: %s", expected);
        
        assertEq(result, expected, "sqrt(16) should equal 4");
    }

    function test_SquareRoot_Zero() public pure {
        uint256 result = FixedPointMath.fromUint(0).sqrt();
        
        console.log("Square Root Zero Test: sqrt(0) = %s", result);
        assertEq(result, 0, "sqrt(0) should equal 0");
    }

    function test_SquareRoot_LargeNumber() public pure {
        uint256 x = FixedPointMath.fromUint(1e18); // 1,000,000,000,000,000,000
        uint256 result = x.sqrt();
        uint256 expected = FixedPointMath.fromUint(1e9); // 1,000,000,000
        
        console.log("Large Square Root Test: sqrt(1e18) = %s", result);
        console.log("Expected: %s", expected);
        
        assertEq(result, expected, "sqrt(1e18) should equal 1e9");
    }

    function test_Power_PositiveExponent() public pure {
        uint256 x = FixedPointMath.fromUint(2); // 2.0
        int256 y = 3;
        
        uint256 result = x.pow(y);
        uint256 expected = FixedPointMath.fromUint(8); // 8.0
        
      //   console.log("Power Test: %s ^ %s = %s", x, y, result);
        console.log("Expected: %s", expected);
        
        assertEq(result, expected, "2^3 should equal 8");
    }

    function test_Power_NegativeExponent() public pure {
        uint256 x = FixedPointMath.fromUint(2); // 2.0
        int256 y = -1;
        
        uint256 result = x.pow(y);
        uint256 expected = FixedPointMath.fromUint(1).div(FixedPointMath.fromUint(2)); // 0.5
        
      //   console.log("Negative Power Test: %s ^ %s = %s", x, y, result);
        console.log("Expected: %s", expected);
        
        assertEq(result, expected, "2^-1 should equal 0.5");
    }

    function test_Power_ZeroExponent() public pure {
        uint256 x = FixedPointMath.fromUint(100);
        int256 y = 0;
        
        uint256 result = x.pow(y);
        uint256 expected = FixedPointMath.fromUint(1);
        
        console.log("Zero Exponent Test: %s ^ %s = %s", x, y, result);
        console.log("Expected: %s", expected);
        
        assertEq(result, expected, "x^0 should equal 1 for any x");
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TRANSCENDENTAL FUNCTION TESTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    function test_Exponential_Zero() public pure {
        uint256 result = FixedPointMath.fromUint(0).exp();
        uint256 expected = FixedPointMath.fromUint(1);
        
        console.log("Exponential Zero Test: exp(0) = %s", result);
        console.log("Expected: %s", expected);
        
        assertEq(result, expected, "exp(0) should equal 1");
    }

    function test_Exponential_One() public pure {
        uint256 x = FixedPointMath.fromUint(1);
        uint256 result = x.exp();
        
        // e ≈ 2.71828, allow small approximation error
        uint256 expected = 271828 * (Q96 / 100000); // 2.71828
        
        console.log("Exponential One Test: exp(1) = %s", result);
        console.log("Expected (e): %s", expected);
        console.log("Difference: %s", result > expected ? result - expected : expected - result);
        
        assertApproxEqAbs(result, expected, Q96 / 10000, "exp(1) should approximate e");
    }

    function test_Logarithm_One() public pure {
        uint256 result = FixedPointMath.fromUint(1).ln();
        
        console.log("Logarithm One Test: ln(1) = %s", result);
        assertEq(result, 0, "ln(1) should equal 0");
    }

    function test_Logarithm_E() public pure {
        uint256 e = 271828 * (Q96 / 100000); // e ≈ 2.71828
        uint256 result = e.ln();
        uint256 expected = FixedPointMath.fromUint(1); // ln(e) = 1
        
        console.log("Logarithm E Test: ln(e) = %s", result);
        console.log("Expected: 1.0 = %s", expected);
        console.log("Difference: %s", result > expected ? result - expected : expected - result);
        
        assertApproxEqAbs(result, expected, Q96 / 1000, "ln(e) should approximate 1");
    }

    function test_Logarithm_ByZero_Reverts() public {
        console.log("Testing ln(0) revert...");
        vm.expectRevert(FixedPointMath.DivByZero.selector);
        FixedPointMath.fromUint(0).ln();
        console.log(" ln(0) correctly reverted");
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS (PURE)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    function testFuzz_Multiplication_Commutative(uint256 x, uint256 y) public pure {
        // Bound inputs to prevent overflow in fuzzing
        x = bound(x, 0, type(uint128).max);
        y = bound(y, 0, type(uint128).max);
        
        uint256 qx = FixedPointMath.fromUint(x);
        uint256 qy = FixedPointMath.fromUint(y);
        
        uint256 result1 = qx.mul(qy);
        uint256 result2 = qy.mul(qx);
        
        console.log("Fuzz Multiplication Commutative:");
        console.log("  %s * %s = %s", x, y, result1);
        console.log("  %s * %s = %s", y, x, result2);
        
        assertEq(result1, result2, "Multiplication should be commutative");
    }

    function testFuzz_Division_Identity(uint256 x) public pure {
        // Avoid division by zero and overflow
        x = bound(x, 1, type(uint128).max);
        
        uint256 qx = FixedPointMath.fromUint(x);
        uint256 result = qx.div(qx);
        uint256 expected = FixedPointMath.fromUint(1);
        
        console.log("Fuzz Division Identity: %s / %s = %s", x, x, result);
        console.log("Expected: 1.0 = %s", expected);
        
        assertEq(result, expected, "x / x should equal 1");
    }

    function testFuzz_SquareRoot_Squared(uint256 x) public pure {
        // Bound to avoid overflow and ensure meaningful tests
        x = bound(x, 1, 1e18);
        
        uint256 qx = FixedPointMath.fromUint(x);
        uint256 root = qx.sqrt();
        uint256 squared = root.mul(root);
        
        console.log("Fuzz Square Root Squared:");
        console.log("  Input: %s", x);
        console.log("  Square Root: %s", root);
        console.log("  Squared Back: %s", squared);
        console.log("  Original: %s", qx);
        console.log("  Difference: %s", squared > qx ? squared - qx : qx - squared);
        console.log("  Relative Error: %s%%", ((squared > qx ? squared - qx : qx - squared) * 100) / qx);
        
        // Allow 0.1% tolerance for approximation
        assertApproxEqRel(squared, qx, 0.001e18, "sqrt(x)^2 should approximate x");
    }

    function testFuzz_Power_Of_One(uint256 x) public pure {
        // Test that x^1 = x
        x = bound(x, 0, type(uint128).max);
        
        uint256 qx = FixedPointMath.fromUint(x);
        uint256 result = qx.pow(1);
        
        console.log("Fuzz Power of One: %s^1 = %s", x, result);
        console.log("Expected: %s", qx);
        
        assertEq(result, qx, "x^1 should equal x");
    }

    function testFuzz_Power_Of_Zero(uint256 x) public pure {
        // Test that x^0 = 1 for any x (except 0^0 which is undefined but we handle as 1)
        x = bound(x, 1, type(uint128).max);
        
        uint256 qx = FixedPointMath.fromUint(x);
        uint256 result = qx.pow(0);
        uint256 expected = FixedPointMath.fromUint(1);
        
        console.log("Fuzz Power of Zero: %s^0 = %s", x, result);
        console.log("Expected: 1.0 = %s", expected);
        
        assertEq(result, expected, "x^0 should equal 1 for any x > 0");
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARK TESTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    function test_Gas_Multiplication() public pure {
        uint256 a = FixedPointMath.fromUint(12345);
        uint256 b = FixedPointMath.fromUint(67890);
        
        uint256 gasBefore = gasleft();
        uint256 result = a.mul(b);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for multiplication: %s", gasUsed);
        console.log("Result: %s", result);
        
        assertTrue(gasUsed < 1000, "Multiplication should be gas efficient");
    }

    function test_Gas_SquareRoot() public pure {
        uint256 x = FixedPointMath.fromUint(1e18);
        
        uint256 gasBefore = gasleft();
        uint256 result = x.sqrt();
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for square root: %s", gasUsed);
        console.log("Result: %s", result);
        
        assertTrue(gasUsed < 5000, "Square root should be reasonably gas efficient");
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    function test_EdgeCase_MaxValues() public pure {
        uint256 maxSafe = type(uint128).max;
        uint256 qMax = FixedPointMath.fromUint(maxSafe);
        
        console.log("Testing edge case - max safe value: %s", maxSafe);
        
        // Test that we can handle large values without reverting
        uint256 squared = qMax.mul(qMax);
        uint256 root = squared.sqrt();
        
        console.log("Max value: %s", qMax);
        console.log("Squared: %s", squared);
        console.log("Square root of squared: %s", root);
        
        assertApproxEqRel(root, qMax, 0.01e18, "Should handle large values correctly");
    }

    function test_EdgeCase_VerySmallValues() public pure {
        uint256 small = 1; // Very small integer
        uint256 qSmall = FixedPointMath.fromUint(small);
        
        console.log("Testing edge case - very small value: %s", small);
        
        uint256 root = qSmall.sqrt();
        uint256 squared = root.mul(root);
        
        console.log("Small value: %s", qSmall);
        console.log("Square root: %s", root);
        console.log("Squared back: %s", squared);
        
        assertApproxEqRel(squared, qSmall, 0.01e18, "Should handle small values correctly");
    }
}