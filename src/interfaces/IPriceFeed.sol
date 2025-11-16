// // SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title IPriceFeed
 * @notice Unified interface for ALL oracle adapters in BAOBAB
 * @dev Every adapter (Chainlink, Pyth, TWAP, Trusted, Computed) implements this
 */
interface IPriceFeed {
    /**
     * @notice Latest price with 8 decimals (Chainlink-style)
     * @return int256 Price (negative = invalid/stale)
     */
    function latestAnswer() external view returns (int256);

    /**
     * @notice Timestamp of last update
     */
    function latestTimestamp() external view returns (uint256);

    /**
     * @notice Number of decimals in price
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Human-readable description
     */
    function description() external view returns (string memory);

    /**
     * @notice Extended round data with confidence
     * @return roundId        Round ID (0 for non-Chainlink)
     * @return answer         Price
     * @return startedAt      N/A
     * @return updatedAt      Last update timestamp
     * @return answeredInRound N/A
     * @return confidence     Confidence interval in basis points (e.g., 50 = ±0.5%)
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound,
            uint256 confidence
        ); // in bps
}
