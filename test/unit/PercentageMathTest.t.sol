// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "forge-std/console2.sol";

// import {PercentageMath} from "../../src/libraries/math/PercentageMath.sol";
// import {FixedPointMath} from "../../src/libraries/math/FixedPointMath.sol";

// /**
//  * @title PercentageMathTest
//  * @author BAOBAB Protocol
//  * @notice Comprehensive test suite for PercentageMath library
//  * @dev Tests percentage calculations, financial math, and edge cases
//  */
// contract PercentageMathTest is Test {
//     using PercentageMath for *;

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // TEST CONSTANTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
//     uint256 constant PERCENTAGE_FACTOR = 1e4;
//     uint256 constant ONE_HUNDRED_PERCENT = 100 * PercentageMath.BP;
//     uint256 constant FIFTY_PERCENT = 5000; // 50% in basis points
//     uint256 constant TEN_PERCENT = 1000;   // 10% in basis points
//     uint256 constant ONE_PERCENT = 100;    // 1% in basis points

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // BASIC PERCENTAGE OPERATION TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function test_AddPercent_Basic() public pure {
//         uint256 base = 1000;
//         uint256 percentage = ONE_PERCENT; // 1%
        
//         uint256 result = base.addPercent(percentage);
//         uint256 expected = 1010; // 1000 + 1% = 1010
        
//         console.log("Add Percent Test: %s + %s%% = %s", base);
//         console.log("Add Percent Test: %s + %s%% = %s", percentage);
//         console.log("Add Percent Test: %s + %s%% = %s", result);
//         console.log("Expected: %s", expected);
        
//         assertEq(result, expected, "1000 + 1% should equal 1010");
//     }

//     function test_AddPercent_ZeroBase() public pure {
//         uint256 base = 0;
//         uint256 percentage = ONE_PERCENT;
        
//         uint256 result = base.addPercent(percentage);
        
//         console.log("Add Percent Zero Base: 0 + %s%% = %s", percentage);
//         console.log("Add Percent Zero Base: 0 + %s%% = %s", result);
//         assertEq(result, 0, "0 + any percentage should equal 0");
//     }

//     function test_AddPercent_ZeroPercentage() public pure {
//         uint256 base = 1000;
//         uint256 percentage = 0;
        
//         uint256 result = base.addPercent(percentage);
        
//         console.log("Add Percent Zero Percentage: %s + 0%% = %s", base);
//         console.log("Add Percent Zero Percentage: %s + 0%% = %s", result);
//         assertEq(result, base, "Any value + 0% should equal itself");
//     }

//     function test_AddPercent_MaxPercentage() public pure {
//         uint256 base = 1000;
//         uint256 percentage = ONE_HUNDRED_PERCENT; // 100%
        
//         uint256 result = base.addPercent(percentage);
//         uint256 expected = 2000; // 1000 + 100% = 2000
        
//         console.log("Add Percent Max: %s + 100%% = %s", base, result);
//         assertEq(result, expected, "1000 + 100% should equal 2000");
//     }

//     function test_AddPercent_ExceedsMax_Reverts() public {
//         uint256 base = 1000;
//         uint256 percentage = ONE_HUNDRED_PERCENT + 1; // 100.01%
        
//         console.log("Testing percentage exceed max revert...");
//         vm.expectRevert(PercentageMath.PercentageExceedsMax.selector);
//         base.addPercent(percentage);
//         console.log(" Percentage exceed max correctly reverted");
//     }

//     function test_SubPercent_Basic() public pure {
//         uint256 base = 1000;
//         uint256 percentage = ONE_PERCENT; // 1%
        
//         uint256 result = base.subPercent(percentage);
//         uint256 expected = 990; // 1000 - 1% = 990
        
//         console.log("Sub Percent Test: %s - %s%% = %s", base);
//         console.log("Sub Percent Test: %s - %s%% = %s", percentage);
//         console.log("Sub Percent Test: %s - %s%% = %s", result);
//         console.log("Expected: %s", expected);
        
//         assertEq(result, expected, "1000 - 1% should equal 990");
//     }

//     function test_SubPercent_ToZero() public pure {
//         uint256 base = 1000;
//         uint256 percentage = ONE_HUNDRED_PERCENT; // 100%
        
//         uint256 result = base.subPercent(percentage);
//         uint256 expected = 0; // 1000 - 100% = 0
        
//         console.log("Sub Percent To Zero: %s - 100%% = %s", base, result);
//         assertEq(result, expected, "1000 - 100% should equal 0");
//     }

//     function test_Percent_Basic() public pure {
//         uint256 base = 1000;
//         uint256 percentage = TEN_PERCENT; // 10%
        
//         uint256 result = base.percent(percentage);
//         uint256 expected = 100; // 10% of 1000 = 100
        
//         console.log("Percent Test: %s%% of %s = %s", percentage);
//         console.log("Percent Test: %s%% of %s = %s", base);
//         console.log("Percent Test: %s%% of %s = %s", result);
//         console.log("Expected: %s", expected);
        
//         assertEq(result, expected, "10% of 1000 should equal 100");
//     }

//     function test_PercentUp_Rounding() public pure {
//         uint256 base = 100;
//         uint256 percentage = 1; // 0.01%
        
//         uint256 result = base.percentUp(percentage);
//         uint256 regularResult = base.percent(percentage);
        
//         console.log("Percent Up Test: %s%% of %s = %s (rounded up)", percentage);
//         console.log("Percent Up Test: %s%% of %s = %s (rounded up)", base);
//         console.log("Percent Up Test: %s%% of %s = %s (rounded up)", result);
//         console.log("Regular result: %s", regularResult);
        
//         assertTrue(result >= regularResult, "Percent up should round up");
//     }

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // RATIO AND CHANGE CALCULATION TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function test_RatioAsPercent_Basic() public pure {
//         uint256 part = 250;
//         uint256 total = 1000;
        
//         uint256 result = PercentageMath.ratioAsPercent(part, total);
//         uint256 expected = 2500; // 250/1000 = 25% = 2500 bps
        
//         console.log("Ratio Test: %s/%s = %s bps", part, total, result);
//         console.log("Expected: %s bps (25%%)", expected);
        
//         assertEq(result, expected, "250/1000 should equal 25% (2500 bps)");
//     }

//     function test_RatioAsPercent_ZeroTotal() public pure {
//         uint256 result = PercentageMath.ratioAsPercent(100, 0);
        
//         console.log("Ratio Zero Total Test: 100/0 = %s bps", result);
//         assertEq(result, 0, "Ratio with zero total should return 0");
//     }

//     function test_RatioAsPercent_HundredPercent() public pure {
//         uint256 result = PercentageMath.ratioAsPercent(1000, 1000);
        
//         console.log("Ratio 100%% Test: 1000/1000 = %s bps", result);
//         assertEq(result, ONE_HUNDRED_PERCENT, "1000/1000 should equal 100%");
//     }

//     function test_CalculatePercentChange_Increase() public pure {
//         uint256 oldValue = 1000;
//         uint256 newValue = 1100;
        
//         int256 result = PercentageMath.calculatePercentChange(oldValue, newValue);
//         int256 expected = 1000; // 10% increase = 1000 bps
        
//         // console.log("Percent Change Increase: %s -> %s = %s bps", oldValue, newValue, result);
//         console.log("Percent Change Increase:");
// console.log(oldValue);
// console.log(newValue);
// console.log(result);

//         console.log("Expected: %s bps (10%% increase)", expected);
        
//         assertEq(result, expected, "1000->1100 should be 10% increase");
//     }

//     function test_CalculatePercentChange_Decrease() public pure {
//         uint256 oldValue = 1000;
//         uint256 newValue = 900;
        
//         int256 result = PercentageMath.calculatePercentChange(oldValue, newValue);
//         int256 expected = -1000; // 10% decrease = -1000 bps
        
//         console.log("Percent Change Decrease: %s -> %s = %s bps", oldValue);
//         console.log("Percent Change Decrease: %s -> %s = %s bps", newValue);
//          console.log("Percent Change Decrease: %s -> %s = %s bps", result);
//         console.log("Expected: %s bps (10%% decrease)", expected);
        
//         assertEq(result, expected, "1000->900 should be 10% decrease");
//     }

//     function test_CalculatePercentChange_ZeroOld_Reverts() public {
//         console.log("Testing percent change with zero old value...");
//         vm.expectRevert(PercentageMath.DivisionByZero.selector);
//         PercentageMath.calculatePercentChange(0, 1000);
//         console.log("Zero old value correctly reverted");
//     }

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // FINANCIAL MATHEMATICS TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function test_Compound_Simple() public pure {
//         uint256 principal = 1000;
//         uint256 rate = ONE_PERCENT; // 1% per period
//         uint256 periods = 1;
        
//         uint256 result = PercentageMath.compound(principal, rate, periods);
//         uint256 expected = 1010; // 1000 + 1% = 1010
        
//         console.log("Compound Test: %s at %s%% for %s periods = %s", principal);
//           console.log("Compound Test: %s at %s%% for %s periods = %s", rate);
//             console.log("Compound Test: %s at %s%% for %s periods = %s", periods);
//               console.log("Compound Test: %s at %s%% for %s periods = %s",result);
//         console.log("Expected: %s", expected);
        
//         assertEq(result, expected, "Simple compounding should work");
//     }

//     function test_Compound_MultiplePeriods() public pure {
//         uint256 principal = 1000;
//         uint256 rate = ONE_PERCENT; // 1% per period
//         uint256 periods = 2;
        
//         uint256 result = PercentageMath.compound(principal, rate, periods);
//         uint256 expected = (10201 * 1e18) / 1000;

        
//         console.log("Compound Test: %s at %s%% for %s periods = %s", principal);
//           console.log("Compound Test: %s at %s%% for %s periods = %s", rate);
//             console.log("Compound Test: %s at %s%% for %s periods = %s", periods);
//               console.log("Compound Test: %s at %s%% for %s periods = %s",result);
//         console.log("Expected: ~%s", expected);
        
//         assertApproxEqAbs(result, 1020, 1, "Multiple period compounding should work");
//     }

//     function test_Compound_ZeroRate() public pure {
//         uint256 result = PercentageMath.compound(1000, 0, 10);
        
//         console.log("Compound Zero Rate: 1000 at 0%% for 10 periods = %s", result);
//         assertEq(result, 1000, "Zero rate should return principal");
//     }

//     function test_Compound_ZeroPeriods() public pure {
//         uint256 result = PercentageMath.compound(1000, ONE_PERCENT, 0);
        
//         console.log("Compound Zero Periods: 1000 at 1%% for 0 periods = %s", result);
//         assertEq(result, 1000, "Zero periods should return principal");
//     }

//     function test_AprToDaily() public pure {
//         uint256 apr = 36500; // 365% APR
//         uint256 result = PercentageMath.aprToDaily(apr);
//         uint256 expected = 100; // 365% / 365 = 1% daily
        
//         console.log("APR to Daily: %s%% APR = %s%% daily", apr);
//          console.log("APR to Daily: %s%% APR = %s%% daily", result);
//         console.log("Expected: %s%% daily", expected);
        
//         assertEq(result, expected, "365% APR should equal 1% daily");
//     }

//     function test_UtilizationRate() public pure {
//         uint256 borrowed = 750;
//         uint256 available = 250;
        
//         uint256 result = PercentageMath.utilizationRate(borrowed, available);
//         uint256 expected = 7500; // 750/(750+250) = 75% = 7500 bps
        
//         console.log("Utilization Rate: %s borrowed, %s available = %s bps", borrowed);
//          console.log("Utilization Rate: %s borrowed, %s available = %s bps", available);
//           console.log("Utilization Rate: %s borrowed, %s available = %s bps", result);
//         console.log("Expected: %s bps (75%%)", expected);
        
//         assertEq(result, expected, "Utilization rate should be 75%");
//     }

//     function test_UtilizationRate_ZeroAvailable() public pure {
//         uint256 result = PercentageMath.utilizationRate(100, 0);
        
//         console.log("Utilization Zero Available: 100 borrowed, 0 available = %s bps", result);
//         assertEq(result, ONE_HUNDRED_PERCENT, "Zero available with borrowed should be 100%");
//     }

//     function test_UtilizationRate_ZeroBorrowed() public pure {
//         uint256 result = PercentageMath.utilizationRate(0, 100);
        
//         console.log("Utilization Zero Borrowed: 0 borrowed, 100 available = %s bps", result);
//         assertEq(result, 0, "Zero borrowed should be 0% utilization");
//     }

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // TRADING AND RISK MANAGEMENT TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function test_LiquidationPriceLong() public pure {
//         uint256 entryPrice = 2000;
//         uint256 collateral = 1000;
//         uint256 positionSize = 10;
//         uint256 maintenanceMargin = 500; // 5%
        
//         uint256 result = PercentageMath.liquidationPriceLong(entryPrice, collateral, positionSize, maintenanceMargin);
        
//         console.log("Liquidation Price Long:");
//         console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", entryPrice);
//          console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", collateral);
//           console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", positionSize);
//            console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", maintenanceMargin);
//         console.log("  Liquidation Price: %s", result);
        
//         // Manual calculation: (1000 * 10000) / (10 * 500/10000) = margin ratio
//         // Should be less than entry price
//         assertTrue(result < entryPrice, "Liquidation price should be below entry");
//         assertTrue(result > 0, "Liquidation price should be positive");
//     }

//     function test_LiquidationPriceShort() public view {
//         uint256 entryPrice = 2000;
//         uint256 collateral = 1000;
//         uint256 positionSize = 10;
//         uint256 maintenanceMargin = 500; // 5%
        
//         uint256 result = PercentageMath.liquidationPriceShort(entryPrice, collateral, positionSize, maintenanceMargin);
        
//         console.log("Liquidation Price Short:");
//          console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", entryPrice);
//          console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", collateral);
//           console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", positionSize);
//            console.log("  Entry: %s, Collateral: %s, Size: %s, MM: %s bps", maintenanceMargin);
//         console.log("  Liquidation Price: %s", result);
        
//         assertTrue(result > entryPrice, "Liquidation price for short should be above entry");
//     }

//     function test_CalculatePnlPercent_LongProfit() public pure {
//         uint256 entryPrice = 1000;
//         uint256 exitPrice = 1100;
//         bool isLong = true;
        
//         int256 result = PercentageMath.calculatePnlPercent(entryPrice, exitPrice, isLong);
//         int256 expected = 1000; // 10% profit
        
//         console.log("Pnl Percent Long Profit: %s -> %s = %s bps", entryPrice);
//         console.log("Pnl Percent Long Profit: %s -> %s = %s bps", exitPrice);
//         console.log("Pnl Percent Long Profit: %s -> %s = %s bps", result);
//         console.log("Expected: %s bps (10%% profit)", expected);
        
//         assertEq(result, expected, "Long 1000->1100 should be 10% profit");
//     }

//     function test_CalculatePnlPercent_ShortProfit() public pure {
//         uint256 entryPrice = 1000;
//         uint256 exitPrice = 900;
//         bool isLong = false;
        
//         int256 result = PercentageMath.calculatePnlPercent(entryPrice, exitPrice, isLong);
//         int256 expected = 1000; // 10% profit
        
//         console.log("Pnl Percent Short Profit: %s -> %s = %s bps", entryPrice);
//         console.log("Pnl Percent Short Profit: %s -> %s = %s bps", exitPrice);
//         console.log("Pnl Percent Short Profit: %s -> %s = %s bps", result);
//         console.log("Expected: %s bps (10%% profit)", expected);
        
//         assertEq(result, expected, "Short 1000->900 should be 10% profit");
//     }

//     function test_SlippageBounds_Buy() public pure {
//         uint256 price = 1000;
//         uint256 slippage = 100; // 1%
//         bool isBuy = true;
        
//         (uint256 minPrice, uint256 maxPrice) = PercentageMath.slippageBounds(price, slippage, isBuy);
        
//         console.log("Slippage Bounds Buy:");
//         console.log("  Price: %s, Slippage: %s bps, Min: %s, Max: %s", price);
//         console.log("  Price: %s, Slippage: %s bps, Min: %s, Max: %s", slippage);
//         console.log("  Price: %s, Slippage: %s bps, Min: %s, Max: %s", minPrice);
//         console.log("  Price: %s, Slippage: %s bps, Min: %s, Max: %s", maxPrice);
        
//         uint256 expectedSlippageAmount = 10; // 1% of 1000
//         assertEq(minPrice, price - expectedSlippageAmount, "Min price should be price - slippage");
//         assertEq(maxPrice, price + expectedSlippageAmount, "Max price should be price + slippage");
//     }

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // FEE CALCULATION TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function test_CalculateFee() public pure {
//         uint256 amount = 1000;
//         uint256 feeBps = 300; // 3%
        
//         uint256 result = PercentageMath.calculateFee(amount, feeBps);
//         uint256 expected = 30; // 3% of 1000
        
//         console.log("Calculate Fee: %s at %s bps = %s", amount);
//         console.log("Calculate Fee: %s at %s bps = %s", feeBps);
//         console.log("Calculate Fee: %s at %s bps = %s", result);
//         console.log("Expected: %s", expected);
        
//         assertEq(result, expected, "3% fee on 1000 should be 30");
//     }

//     function test_AmountAfterFee() public pure {
//         uint256 amount = 1000;
//         uint256 feeBps = 300; // 3%
        
//         uint256 result = PercentageMath.amountAfterFee(amount, feeBps);
//         uint256 expected = 970; // 1000 - 3%
        
//         console.log("Amount After Fee: %s - %s bps fee = %s", amount);
//            console.log("Amount After Fee: %s - %s bps fee = %s", feeBps);
//               console.log("Amount After Fee: %s - %s bps fee = %s", result);
//         console.log("Expected: %s", expected);
        
//         assertEq(result, expected, "1000 after 3% fee should be 970");
//     }

//     function test_AmountBeforeFee() public pure {
//         uint256 netAmount = 970;
//         uint256 feeBps = 300; // 3%
        
//         uint256 result = PercentageMath.amountBeforeFee(netAmount, feeBps);
//         uint256 expected = 1000; // 970 / (1 - 3%) = 1000
        
//         console.log("Amount After Fee: %s - %s bps fee = %s", netAmount);
//            console.log("Amount After Fee: %s - %s bps fee = %s", feeBps);
//               console.log("Amount After Fee: %s - %s bps fee = %s", result);
//         console.log("Expected: %s", expected);
        
//         assertEq(result, expected, "970 net with 3% fee should come from 1000");
//     }

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // VALIDATION AND CONVERSION TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function test_IsValidPercentage() public pure {
//         bool valid = PercentageMath.isValidPercentage(5000);
//         bool invalid = PercentageMath.isValidPercentage(10001);
        
//         console.log("Is Valid Percentage: 5000 bps = %s, 10001 bps = %s", valid);
//         console.log("Is Valid Percentage: 5000 bps = %s, 10001 bps = %s", invalid);
        
//         assertTrue(valid, "5000 bps should be valid");
//         assertTrue(!invalid, "10001 bps should be invalid");
//     }

//     function test_ClampPercentage() public pure {
//         uint256 result = PercentageMath.clampPercentage(15000);
        
//         console.log("Clamp Percentage: 15000 bps -> %s bps", result);
//         assertEq(result, ONE_HUNDRED_PERCENT, "15000 bps should clamp to 10000 bps");
//     }

//     function test_BpsToDecimal() public pure {
//         uint256 result = PercentageMath.bpsToDecimal(100); // 1%
        
//         console.log("BPS to Decimal: 100 bps = %s", result);
//         // 1% in Q64.96 should be 0.01 * 2^96
//         uint256 expected = FixedPointMath.fromUint(1) / 100;
        
//         assertEq(result, expected, "100 bps should equal 0.01 in decimal");
//     }

//     function test_DecimalToBps() public pure {
//         uint256 decimal = FixedPointMath.fromUint(1) / 100; // 0.01
//         uint256 result = PercentageMath.decimalToBps(decimal);
        
//         console.log("Decimal to BPS: 0.01 = %s bps", result);
//         assertEq(result, 100, "0.01 should equal 100 bps");
//     }

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // FUZZ TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function testFuzz_AddSubPercent_Inverse(uint256 base, uint256 percentage) public pure {
//         // Bound inputs to reasonable ranges
//         base = bound(base, 1, type(uint128).max);
//         percentage = bound(percentage, 0, ONE_HUNDRED_PERCENT);
        
//         uint256 afterAdd = base.addPercent(percentage);
//         uint256 afterSub = afterAdd.subPercent(percentage);
        
//         console.log("Fuzz Add/Sub Inverse:");
//         console.log("  Base: %s, Percentage: %s bps", base);
//         console.log("  Base: %s, Percentage: %s bps", percentage);
//         console.log("  After Add: %s, After Sub: %s", afterAdd);
//          console.log("  After Add: %s, After Sub: %s", afterSub);
        
//         // Allow small rounding error due to integer division
//         assertApproxEqAbs(afterSub, base, 1, "Add then subtract percentage should return original");
//     }

//     function testFuzz_Percent_Proportional(uint256 base, uint256 percentage) public pure {
//         base = bound(base, 1, type(uint128).max);
//         percentage = bound(percentage, 0, ONE_HUNDRED_PERCENT);
        
//         uint256 result = base.percent(percentage);
        
//         console.log("Fuzz Percent Proportional: %s%% of %s = %s", percentage);
//         console.log("Fuzz Percent Proportional: %s%% of %s = %s", base);
//         console.log("Fuzz Percent Proportional: %s%% of %s = %s", result);
        
//         // Result should be proportional to both base and percentage
//         assertTrue(result <= base, "Percentage of base should not exceed base");
//         if (percentage == 0) assertEq(result, 0, "0% of anything should be 0");
//         if (percentage == ONE_HUNDRED_PERCENT) assertEq(result, base, "100% of base should equal base");
//     }

//     function testFuzz_UtilizationRate_Bounds(uint256 borrowed, uint256 available) public pure {
//         borrowed = bound(borrowed, 0, type(uint128).max);
//         available = bound(available, 0, type(uint128).max);
        
//         uint256 utilization = PercentageMath.utilizationRate(borrowed, available);
        
//         console.log("Fuzz Utilization Bounds:");
//         console.log("  Borrowed: %s, Available: %s, Utilization: %s bps", borrowed);
//          console.log("  Borrowed: %s, Available: %s, Utilization: %s bps", available);
//           console.log("  Borrowed: %s, Available: %s, Utilization: %s bps", utilization);
        
//         assertTrue(utilization <= ONE_HUNDRED_PERCENT, "Utilization should never exceed 100%");
//         assertTrue(utilization >= 0, "Utilization should never be negative");
        
//         if (borrowed == 0) assertEq(utilization, 0, "Zero borrowed should mean zero utilization");
//         if (available == 0 && borrowed > 0) assertEq(utilization, ONE_HUNDRED_PERCENT, "Zero available with borrowed should be 100%");
//     }

//     function testFuzz_AmountBeforeAfterFee_Consistent(uint256 amount, uint256 feeBps) public pure {
//         amount = bound(amount, 100, type(uint128).max);
//         feeBps = bound(feeBps, 0, ONE_HUNDRED_PERCENT - 1); // Avoid 100% fee
        
//         uint256 afterFee = PercentageMath.amountAfterFee(amount, feeBps);
//         uint256 beforeFee = PercentageMath.amountBeforeFee(afterFee, feeBps);
        
//         console.log("Fuzz Fee Consistency:");
//         console.log("  Original: %s, Fee: %s bps", amount);
//         console.log("  Original: %s, Fee: %s bps", feeBps);
//         console.log("  After Fee: %s, Reconstructed: %s", afterFee);
//         console.log("  After Fee: %s, Reconstructed: %s", beforeFee);
        
//         // Allow small rounding error
//         assertApproxEqAbs(beforeFee, amount, 1, "Amount before/after fee should be consistent");
//     }

//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//     // EDGE CASE AND GAS TESTS
//     // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

//     function test_Gas_PercentCalculation() public view {
//         uint256 gasBefore = gasleft();
//         uint256 result = 1000.percent(ONE_PERCENT);
//         uint256 gasUsed = gasBefore - gasleft();
        
//         console.log("Gas used for percent calculation: %s", gasUsed);
//         console.log("Result: %s", result);
        
//         assertTrue(gasUsed < 100, "Percent calculation should be gas efficient");
//     }

//     function test_Gas_CompoundCalculation() public view {
//         uint256 gasBefore = gasleft();
//         uint256 result = PercentageMath.compound(1000, ONE_PERCENT, 10);
//         uint256 gasUsed = gasBefore - gasleft();
        
//         console.log("Gas used for compound calculation: %s", gasUsed);
//         console.log("Result: %s", result);
        
//         assertTrue(gasUsed < 1000, "Compound calculation should be reasonably efficient");
//     }

//     function test_EdgeCase_VerySmallPercentages() public pure {
//         uint256 base = 1e18; // Large number
//         uint256 tinyPercentage = 1; // 0.01%
        
//         uint256 result = base.percent(tinyPercentage);
        
//         console.log("Edge Case - Tiny Percentage: 0.01%% of %s = %s", base);
//         console.log("Edge Case - Tiny Percentage: 0.01%% of %s = %s", result);
        
//         assertTrue(result > 0, "Tiny percentage of large number should be positive");
//         assertTrue(result < base, "Result should be less than base");
//     }

//     function test_EdgeCase_MaxValues() public pure {
//         uint256 maxSafe = type(uint128).max;
//         uint256 result = maxSafe.percent(FIFTY_PERCENT);
        
//         console.log("Edge Case - Max Values: 50%% of %s = %s", maxSafe);
//         console.log("Edge Case - Max Values: 50%% of %s = %s", result);
        
//         assertTrue(result <= maxSafe / 2, "50% of max should be about half");
//         assertTrue(result > 0, "Result should be positive");
//     }
// }