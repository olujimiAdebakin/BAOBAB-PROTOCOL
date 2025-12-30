// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IPriceFeed} from "../../../interfaces/IPriceFeed.sol";
import {FixedPointMath} from "../../../libraries/math/FixedPointMath.sol";
// import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {BaobabOracleRegistry} from "../OracleRegistry.sol";
import {AddressUtils} from "../../../libraries/utils/AddressUtils.sol";

/**
 * @title ComputedOracle
 * @notice Derives the price of a target asset (e.g., ETH/BTC) by performing a fixed operation
 * on two underlying base asset prices (e.g., ETH/USD and BTC/USD).
 * @dev This contract is immutable after deployment. A new instance is deployed for every derived price needed.
 */
contract ComputedOracle is IPriceFeed {
    using FixedPointMath for uint256;
    using AddressUtils for address;

    IPriceFeed private immutable A_FEED;
    IPriceFeed private immutable B_FEED;
    Operation public immutable operation;
    // address private immutable ORACLE_REGISTRY;

    // Standardize to 8 decimals like Chainlink
    uint8 public constant OVERRIDE_DECIMALS = 8;
    // Sentinel value for invalid price
    int256 private constant INVALID_PRICE = -1;
    // Used for fixed-point math scaling
    uint256 private constant PRECISION = 10 ** 18;
    // Used for fixed-point math scaling
    uint256 private constant ONE_UNIT = 10 ** 8;

    enum Operation {
        DIVIDE,
        MULTIPLY
    }

    error ComputedOracle__InvalidPrice(address feed);
    error ComputedOracle__DivisionByZero();

    constructor(address feedA_, address feedB_, Operation operation_ /*address oracleRegistry*/ ) {
        // Validation checks
        feedA_.validateNotZero();
        feedB_.validateNotZero();

        // oracleRegistry_.validateContract();

        A_FEED = IPriceFeed(feedA_);
        B_FEED = IPriceFeed(feedB_);
        operation = operation_;
        // ORACLE_REGISTRY = oracleRegistry_;
    }

    function latestAnswer() public view override returns (int256) {
        // 1. Fetch Prices
        int256 priceA = _getValidatedPrice(A_FEED);
        int256 priceB = _getValidatedPrice(B_FEED);

        // 2. Execute based on operation type
        if (operation == Operation.DIVIDE) {
            return _computeDivide(priceA, priceB);
        } else {
            // Operation.MULTIPLY
            return _computeMultiply(priceA, priceB);
        }
    }

    /**
     * @notice Returns the lowest timestamp of the two component prices.
     */
    function latestTimestamp() public view override returns (uint256) {
        // For a derived price, the security is as good as the oldest component.
        uint256 tsA = A_FEED.latestTimestamp();
        uint256 tsB = B_FEED.latestTimestamp();

        // return tsA < tsB ? tsB : tsA;
        return tsA > tsB ? tsA : tsB;
    }

    function decimals() external pure override returns (uint8) {
        return OVERRIDE_DECIMALS;
    }

    function description() external pure override returns (string memory) {
        return "BAOBAB Computed Oracle";
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound,
            uint256 confidence
        )
    {
        answer = latestAnswer();
        updatedAt = latestTimestamp();

        // Calculate confidence (max of both sources)
        (,,,,, uint256 confA) = A_FEED.latestRoundData();
        (,,,,, uint256 confB) = B_FEED.latestRoundData();

        confidence = operation == Operation.DIVIDE
            ? confA + confB // Uncertainties add for division
            : (confA > confB ? confA : confB); // Max for multiplication

        return (0, latestAnswer(), 0, latestTimestamp(), 0, confidence);
    }

    // =========================================================================
    // INTERNAL HELPER FUNCTIONS
    // =========================================================================

    function _computeDivide(int256 priceA, int256 priceB) internal pure returns (int256) {
        // Security: Division by zero
        if (priceB == 0) revert ComputedOracle__DivisionByZero();

        // Convert to uint256 for safe math (prices are validated positive)
        uint256 a = uint256(priceA);
        uint256 b = uint256(priceB);

        // Formula: (priceA × 10^18) ÷ priceB ÷ 10^10
        // priceA × 10^18 → scale up for precision
        uint256 scaledA = a * PRECISION;

        // (scaledA ÷ priceB) → result in 18 decimals
        uint256 result18dec = scaledA / b;

        // Convert 18 decimals → 8 decimals (÷ 10^10)
        uint256 result8dec = result18dec / 10 ** 10;

        return int256(result8dec);
    }

    function _computeMultiply(int256 priceA, int256 priceB) internal pure returns (int256) {
        // Convert to uint256 for safe math
        uint256 a = uint256(priceA);
        uint256 b = uint256(priceB);

        // Formula: (priceA × priceB) ÷ 10^8
        //  Multiply prices
        uint256 multiplied = a * b;

        //  Convert 16 decimals → 8 decimals (÷ 10^8)
        uint256 result8dec = multiplied / ONE_UNIT;

        return int256(result8dec);
    }

    /**
     * @notice Safely calls the base price feed and validates the returned price.
     * @dev Assumes all external feeds (Pyth, Chainlink) revert or return price <= 0 on failure.
     */
    function _getValidatedPrice(IPriceFeed feed) private view returns (int256) {
        // Attempt to fetch the latest price from the feed.
        try feed.latestAnswer() returns (int256 price) {
            if (price <= 0) revert ComputedOracle__InvalidPrice(address(feed));
            return price;
        } catch {
            revert ComputedOracle__InvalidPrice(address(feed));
        }
    }
}
