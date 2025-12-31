// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @author Consonant Labs, Inc.
 * @title ChainlinkAdapter
 * @notice Adapter contract that wraps the standard Chainlink AggregatorV3Interface 
 * to conform to the custom, unified **IPriceFeed** interface.
 *
 * @dev This contract provides a robust, fail-safe layer around Chainlink's data feeds.
 * It strictly adheres to the design principle of *returning sentinel values on failure* * rather than reverting, ensuring that consuming contracts can handle oracle issues 
 * gracefully. 
 *
 * **Key Implementation Details:**
 * 1. **Data Source:** Fetches data via `AGGREGATOR.latestRoundData()`.
 * 2. **Failure Handling:** Uses `try/catch` to suppress Chainlink's internal reverts, 
 * returning `type(int256).min` (the sentinel value) for all errors, including:
 * * RPC/Call failures.
 * * Negative/Zero price (`answer <= 0`).
 * * Staleness checks (specifically `answeredInRound < roundId`).
 * * Zero `updatedAt` timestamp.
 * 3. **Raw Decimals:** The `answer` is returned with the raw decimals provided by the 
 * Chainlink feed. Normalization (e.g., to 18 decimals) is delegated to the external 
 * system (like an OracleRegistry), adhering to the principle of single responsibility.
 * 4. **Confidence:** Returns `0` for the confidence value, as Chainlink's primary 
 * interface does not expose this metric, maintaining a consistent output structure 
 * required by the `IPriceFeed` interface.
 */

import {AggregatorV3Interface} from "@chainlink/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {IPriceFeed} from "../../../interfaces/IPriceFeed.sol";

/**
 * @title ChainlinkAdapter
 * @author BAOBAB Protocol
 * @notice Chainlink adapter implementing the unified IPriceFeed interface
 *
 * DESIGN PRINCIPLES:
 * - Chainlink is an implementation detail, not a dependency
 * - No reverts → return sentinel values on failure
 * - Raw decimals preserved (OracleRegistry normalizes)
 * - Confidence returned as 0 (Chainlink does not provide it)
 */
contract ChainlinkAdapter is IPriceFeed {
    // =============================================================
    // Immutable State
    // =============================================================

    /// @notice Chainlink aggregator
    AggregatorV3Interface public immutable AGGREGATOR;

    /// @notice Cached decimals
    uint8 private immutable _decimals;

    /// @notice Cached description
    string private _description;

    // =============================================================
    // Constructor
    // =============================================================

    /**
     * @param aggregator Chainlink AggregatorV3Interface address
     */
    constructor(address aggregator) {
        require(aggregator != address(0), "INVALID_AGGREGATOR");

        AGGREGATOR = AggregatorV3Interface(aggregator);
        _decimals = AGGREGATOR.decimals();
        _description = AGGREGATOR.description();
    }

    // =============================================================
    // IPriceFeed — Fast Path
    // =============================================================

    /**
     * @notice Latest price
     * @dev Returns negative value if invalid
     */
    function latestAnswer() external view override returns (int256) {
        try AGGREGATOR.latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, /*startedAt*/ uint256 updatedAt, uint80 answeredInRound
        ) {
            // Invariants only
            if (answer <= 0) return type(int256).min;
            if (answeredInRound < roundId) return type(int256).min;
            if (updatedAt == 0) return type(int256).min;

            return answer;
        } catch {
            return type(int256).min;
        }
    }

    /**
     * @notice Last update timestamp
     */
    function latestTimestamp() external view override returns (uint256) {
        try AGGREGATOR.latestRoundData() returns (
            uint80, /*roundId*/ int256, /*answer*/ uint256, /*startedAt*/ uint256 updatedAt, uint80 answeredInRound
        ) {
            if (updatedAt == 0 || answeredInRound == 0) return 0;
            return updatedAt;
        } catch {
            return 0;
        }
    }

    // =============================================================
    // IPriceFeed — Metadata
    // =============================================================

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    // =============================================================
    // IPriceFeed — Extended Data
    // =============================================================

    /**
     * @notice Extended round data
     *
     * confidence:
     * - Chainlink does NOT provide confidence intervals
     * - Returning 0 explicitly signals "unknown"
     */
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
        try AGGREGATOR.latestRoundData() returns (
            uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound
        ) {
            // Invalidate bad prices
            if (_answer <= 0) {
                return (0, type(int256).min, 0, 0, 0, 0);
            }

            return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound, 0);
        } catch {
            return (0, type(int256).min, 0, 0, 0, 0);
        }
    }
}
