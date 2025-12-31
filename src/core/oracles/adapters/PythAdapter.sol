// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @author Consonant Labs, Inc.
 * @title PythAdapter
 * @notice An adapter contract to integrate Pyth Network price feeds into systems 
 * that adhere to the **Chainlink AggregatorV3Interface (IPriceFeed)** standard.
 *
 * @dev The core functionality is to fetch a specific price ID from the Pyth oracle 
 * and standardize its output:
 * 1. **Staleness Check:** Prices are fetched using `getPriceNoOlderThan(id, 3600)`, 
 * ensuring the data is no older than 3600 seconds (1 hour).
 * 2. **Decimal Conversion:** Pyth prices have a variable exponent (`expo`). This adapter 
 * converts the price to a **fixed 8-decimal (Chainlink-style)** format via the 
 * internal `_scalePrice` helper to maintain compatibility across the DeFi ecosystem.
 * 3. **Error Handling:** Returns the minimum `int256` value (`type(int256).min`) for 
 * invalid (non-positive) prices or stale data, consistent with common error 
 * patterns in price feed usage.
 *
 * This contract provides a practical, drop-in solution for dApps requiring Pyth's 
 * high-frequency data while maintaining structural compatibility with widely-adopted 
 * price feed interfaces.
 */

import {IPriceFeed} from "../../../interfaces/IPriceFeed.sol";

interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }
    
    function getPriceUnsafe(bytes32 id) external view returns (Price memory);
    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory);
}

/**
 * @title PythAdapter
 * @notice Implements IPriceFeed interface for Pyth oracle integration.
 *         Returns price in 8 decimals (Chainlink style) for consistency.
 */
contract PythAdapter is IPriceFeed {
    IPyth public immutable PYTH;
    bytes32 public immutable priceId;

    uint8 private constant DECIMALS = 8; // Standardize output decimals

    /**
     * @param pyth Address of the Pyth contract
     * @param _priceId The price feed ID to query on Pyth
     */
    constructor(address pyth, bytes32 _priceId) {
        require(pyth != address(0), "Invalid Pyth address");
        require(_priceId != bytes32(0), "Invalid priceId");
        PYTH = IPyth(pyth);
        priceId = _priceId;
    }

    /**
     * @notice Returns latest price normalized to 8 decimals
     * @dev Returns negative value on error or stale price
     */
    function latestAnswer() external view override returns (int256) {
      //   IPyth.Price memory p = PYTH.getPriceUnsafe(priceId);
       IPyth.Price memory p = PYTH.getPriceNoOlderThan(priceId, 3600);
        if (p.price <= 0) return type(int256).min;

        int256 adjustedPrice = _scalePrice(p.price, p.expo);
        return adjustedPrice;
    }

    /**
     * @notice Returns last update timestamp
     */
    function latestTimestamp() external view override returns (uint256) {
        IPyth.Price memory p = PYTH.getPriceNoOlderThan(priceId, 3600);
        return p.publishTime;
    }

    /**
     * @notice Returns number of decimals (8)
     */
    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Returns a human-readable description
     */
    function description() external pure override returns (string memory) {
        return "Pyth price feed adapter";
    }

    /**
     * @notice Returns extended round data including confidence
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
      //   IPyth.Price memory p = PYTH.getPriceUnsafe(priceId);
      IPyth.Price memory p = PYTH.getPriceNoOlderThan(priceId, 3600);

        if (p.price <= 0) {
            return (0, type(int256).min, 0, 0, 0, 0);
        }

        int256 adjustedPrice = _scalePrice(p.price, p.expo);
        uint256 conf = uint256(p.conf);

        return (0, adjustedPrice, 0, p.publishTime, 0, conf);
    }

    // ============ Internal Helpers ============

//     /**
//      * @dev Scales price from Pyth's exponent to 8 decimals fixed point
//      * The _scalePrice function converts Pyth's variable-decimal price format into a standardized 8-decimal format (matching Chainlink's standard).
//      */
//     function _scalePrice(int64 price, int32 expo) internal pure returns (int256) {
//         int256 scaledPrice = int256(price);
//         int32 decimalsDifference = expo + 8;

//         if (decimalsDifference < 0) {
//             scaledPrice = scaledPrice / int256(10**uint256(-decimalsDifference));
//         } else if (decimalsDifference > 0) {
//             scaledPrice = scaledPrice * int256(10**uint256(decimalsDifference));
//         }

//         return scaledPrice;
//     }

/**
     * @dev Scales price from Pyth's exponent to 8 decimals fixed point
     * The _scalePrice function converts Pyth's variable-decimal price format into a standardized 8-decimal format (matching Chainlink's standard).
     */
    function _scalePrice(int64 price, int32 expo) internal pure returns (int256) {
    int256 scaledPrice = int256(price);
    int32 scaleFactor = expo + 8;  // How many decimals to adjust
    
    if (scaleFactor > 0) {
        // Need to multiply (add decimals)
        uint32 power = uint32(scaleFactor);
        scaledPrice = scaledPrice * int256(10**power);
    } else if (scaleFactor < 0) {
        // Need to divide (remove decimals)
        uint32 power = uint32(-scaleFactor);  // Convert negative to positive
        scaledPrice = scaledPrice / int256(10**power);
    }
    // scaleFactor == 0: already at 8 decimals
    
    return scaledPrice;
}

}
