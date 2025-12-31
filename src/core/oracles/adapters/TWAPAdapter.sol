// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @author Consonant Labs, Inc.
 * @title TWAPAdapter
 * @notice Time-Weighted Average Price adapter implementing the IPriceFeed interface.
 *
 * @dev This contract calculates the TWAP over a configurable time window (`windowSize`)
 * using price observations pushed periodically. It is a vital **manipulation resistance**
 * layer. The resulting TWAP is generally used for sensitive actions like liquidations
 * and large-scale trades where instantaneous price spikes must be ignored.
 *
 * **Design Principles:**
 * 1. **Secure Input:** Price data is sourced exclusively from the central 
 * `ORACLE_SECURITY.getValidatedPrice()`, guaranteeing input prices are clean 
 * (non-zero, non-stale) before inclusion.
 * 2. **Public Pushing:** The `pushObservation()` function is external and permissionless,
 * allowing anyone to pay the gas to update the TWAP, thereby decentralizing the 
 * maintenance cost and increasing freshness.
 * 3. **Bounded Storage:** The internal `_pruneOldObservations()` function ensures 
 * that the storage array is periodically cleaned of old data, maintaining a fixed 
 * memory footprint related to the `windowSize`.
 * 4. **Standardized Output:** Implements the `IPriceFeed` standard, outputting 
 * a calculated price in 8 decimals, making it immediately usable by other protocol modules.
 */

import {IPriceFeed} from "../../../interfaces/IPriceFeed.sol";
import {IOracleSecurity} from "../../../interfaces/IOracleSecurity.sol";

/**
 * @title TWAPAdapter
 * @author BAOBAB Protocol
 * @notice Time-Weighted Average Price adapter
 *
 * PURPOSE:
 * - Smooth short-term price manipulation
 * - Used for liquidations, large trades, volatility protection
 *
 * IMPORTANT:
 * - TWAPAdapter does NOT enforce staleness
 * - TWAPAdapter does NOT enforce confidence rules
 * - Those are handled by OracleSecurity
 */
contract TWAPAdapter is IPriceFeed {
    // =============================================================
    // Structs
    // =============================================================

    struct Observation {
        int256 price;      // price with 8 decimals
        uint256 timestamp; // block timestamp
    }

    // =============================================================
    // Immutable config
    // =============================================================

    IOracleSecurity public immutable ORACLE_SECURITY;
    address public immutable asset;
    uint256 public immutable windowSize; // e.g. 30 minutes

    // =============================================================
    // Storage
    // =============================================================

    Observation[] internal observations;

    uint8 private constant DECIMALS = 8;

    // =============================================================
    // Errors
    // =============================================================

    error TWAP__NoObservations();
    error TWAP__WindowTooSmall();

    event TWAPObservationPushed(int256 price, uint256 timestamp);

    // =============================================================
    // Constructor
    // =============================================================

    /**
     * @param oracleSecurity OracleSecurity address
     * @param _asset Asset whose price is being TWAPed
     * @param _windowSize Time window for TWAP (seconds)
     */
    constructor(
        address oracleSecurity,
        address _asset,
        uint256 _windowSize
    ) {
        require(oracleSecurity != address(0), "INVALID_SECURITY");
        require(_asset != address(0), "INVALID_ASSET");
        if (_windowSize < 5 minutes) revert TWAP__WindowTooSmall();

        ORACLE_SECURITY = IOracleSecurity(oracleSecurity);
        asset = _asset;
        windowSize = _windowSize;
    }

    // =============================================================
    // External — Observation management
    // =============================================================

    /**
     * @notice Push a new observation
     * @dev Anyone can call — manipulation is averaged out
     */
    function pushObservation() external {
        int256 price = ORACLE_SECURITY.getValidatedPrice(asset, IOracleSecurity.PriceUse.PERP_TRADE);

        observations.push(
            Observation({
                price: price,
                timestamp: block.timestamp
            })
        );

        emit TWAPObservationPushed(price, block.timestamp);

        _pruneOldObservations();
        
    }

    // =============================================================
    // IPriceFeed — Fast Path
    // =============================================================

    function latestAnswer() external view override returns (int256) {
        return _computeTWAP();
    }

    function latestTimestamp() external view override returns (uint256) {
        if (observations.length == 0) return 0;
        return observations[observations.length - 1].timestamp;
    }

    // =============================================================
    // Metadata
    // =============================================================

    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    function description() external pure override returns (string memory) {
        return "BAOBAB TWAP Adapter";
    }

    // =============================================================
    // Extended data
    // =============================================================

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
        int256 twapPrice = _computeTWAP();

        // Confidence: tighter window + more samples = higher confidence
        uint256 obsCount = observations.length;
        confidence = obsCount == 0 ? 10_000 : (10_000 / obsCount); // bps

      //   updatedAt = latestTimestamp();
         updatedAt = obsCount == 0
        ? 0
        : observations[obsCount - 1].timestamp;

        return (0, twapPrice, 0, updatedAt, 0, confidence);
    }

    // =============================================================
    // Internal logic
    // =============================================================

//     function _computeTWAP() internal view returns (int256) {
//         uint256 len = observations.length;
//         if (len == 0) revert TWAP__NoObservations();

//         uint256 weightedSum = 0;
//         uint256 totalTime = 0;

//         uint256 cutoff = block.timestamp - windowSize;

//         for (uint256 i = len - 1; i > 0; i--) {
//             Observation memory curr = observations[i];
//             Observation memory prev = observations[i - 1];

//             if (curr.timestamp <= cutoff) break;

//             uint256 dt = curr.timestamp - prev.timestamp;
//             weightedSum += uint256(curr.price) * dt;
//             totalTime += dt;
//         }

//             //  Handle latest observation to current time
//     Observation memory latest = observations[len - 1];
//     uint256 timeSinceLatest = block.timestamp - latest.timestamp;
    
//     if (timeSinceLatest > 0) {
//         weightedSum += uint256(latest.price) * timeSinceLatest;
//         totalTime += timeSinceLatest;
//     }


//         if (totalTime == 0) revert TWAP__NoObservations();

//         return int256(weightedSum / totalTime);
//     }

    function _computeTWAP() internal view returns (int256) {
    uint256 len = observations.length;
    if (len == 0) revert TWAP__NoObservations();
    
    uint256 weightedSum = 0;
    uint256 totalTime = 0;
    uint256 cutoff = block.timestamp - windowSize;
    
    // Add price from latest observation to NOW
    Observation memory latest = observations[len - 1];
    uint256 timeToNow = block.timestamp - latest.timestamp;
    
    if (timeToNow > 0 && latest.timestamp > cutoff) {
        weightedSum += uint256(latest.price) * timeToNow;
        totalTime += timeToNow;
    }
    
    // Process intervals between observations
    for (uint256 i = len - 1; i > 0; i--) {
        Observation memory curr = observations[i];
        Observation memory prev = observations[i - 1];
        
        // Stop if prev observation is outside window
        if (prev.timestamp <= cutoff) break;
        
        // Price from prev.timestamp to curr.timestamp = prev.price
        uint256 dt = curr.timestamp - prev.timestamp;
        weightedSum += uint256(prev.price) * dt;
        totalTime += dt;
    }
    
    if (totalTime == 0) revert TWAP__NoObservations();
    
    return int256(weightedSum / totalTime);
}

// NB: this impl is too GAS intensive and not realistic for prod grade architecture
    // function _pruneOldObservations() internal {
    //     uint256 cutoff = block.timestamp - windowSize;

    //     while (observations.length > 0 && observations[0].timestamp < cutoff) {
    //         _shiftLeft();
    //     }
    // }

    // Gas-Efficient Pruning (Still involves storage writes, but cleans the array once)
function _pruneOldObservations() internal {
    uint256 cutoff = block.timestamp - windowSize;
    uint256 shiftAmount = 0;
    
    // Find how many observations are outside the window
    for (uint256 i = 0; i < observations.length; i++) {
        if (observations[i].timestamp < cutoff) {
            shiftAmount++;
        } else {
            break; // Since array is time-sorted, we can stop here
        }
    }

    if (shiftAmount == 0) return;

    // Shift the valid observations down
    for (uint256 i = 0; i < observations.length - shiftAmount; i++) {
        observations[i] = observations[i + shiftAmount];
    }
    
    // Resize the array in a single operation
    observations.pop(); 
    // Need to loop pop() 'shiftAmount' times.
    for (uint256 i = 0; i < shiftAmount; i++) {
        observations.pop(); 
    }
}
// Delete _shiftLeft()

    function _shiftLeft() internal {
        uint256 len = observations.length;
        for (uint256 i = 0; i < len - 1; i++) {
            observations[i] = observations[i + 1];
        }
        observations.pop();
    }
}
