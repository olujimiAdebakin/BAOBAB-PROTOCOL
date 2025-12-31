// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceFeed} from "../../../interfaces/IPriceFeed.sol";

/**
 * @title TrustedOracle
 * @notice Oracle adapter with manual price feed set by trusted admin.
 * @dev Implements IPriceFeed interface for compatibility with OracleRegistry.
 */
contract TrustedOracle is IPriceFeed, Ownable {
    int256 private _price;
    uint256 private _updatedAt;
    uint8 private immutable _decimals;
    string private _description;

    event PriceUpdated(int256 newPrice, uint256 updatedAt);

    constructor(uint8 decimals_, string memory description_, address initialOwner) Ownable(initialOwner) {
        _decimals = decimals_;
        _description = description_;
    }

    /**
     * @notice Update the price manually
     * @param newPrice Price with `_decimals` decimals
     */
    function setPrice(int256 newPrice) external onlyOwner {
        require(newPrice > 0, "TrustedOracle: price must be positive");
        _price = newPrice;
        _updatedAt = block.timestamp;

        emit PriceUpdated(newPrice, _updatedAt);
    }

    // =====================
    // IPriceFeed interface
    // =====================

    function latestAnswer() external view override returns (int256) {
        return _price;
    }

    function latestTimestamp() external view override returns (uint256) {
        return _updatedAt;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
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
        return (
            0,
            _price,
            0,
            _updatedAt,
            0,
            0 
        );
    }
}
