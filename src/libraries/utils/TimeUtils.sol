// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title BaobabTimeUtils
 * @author BAOBAB Protocol
 * @notice Comprehensive time utilities for DeFi operations with African market optimization
 * @dev Provides time calculations, market hours, funding rate schedules, and time-based validations
 * @dev Features both universal time functions and African market-specific utilities
 */
library BaobabTimeUtils {
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Seconds in a day for time calculations
    uint256 internal constant SECONDS_PER_DAY = 24 * 60 * 60;
    
    /// @dev Seconds in an hour for market session calculations
    uint256 internal constant SECONDS_PER_HOUR = 60 * 60;
    
    /// @dev Seconds in a week for weekly settlements
    uint256 internal constant SECONDS_PER_WEEK = 7 * SECONDS_PER_DAY;

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // AFRICAN MARKET HOURS (UTC OFFSETS)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Nigerian Stock Exchange trading hours (UTC+1)
    uint256 internal constant NSE_OPEN_UTC = 8 * SECONDS_PER_HOUR;   // 8:00 AM UTC = 9:00 AM WAT
    uint256 internal constant NSE_CLOSE_UTC = 15 * SECONDS_PER_HOUR;  // 3:00 PM UTC = 4:00 PM WAT
    
    /// @dev Johannesburg Stock Exchange trading hours (UTC+2)
    uint256 internal constant JSE_OPEN_UTC = 7 * SECONDS_PER_HOUR;    // 7:00 AM UTC = 9:00 AM SAST
    uint256 internal constant JSE_CLOSE_UTC = 15 * SECONDS_PER_HOUR;  // 3:00 PM UTC = 5:00 PM SAST
    
    /// @dev Nairobi Securities Exchange trading hours (UTC+3)
    uint256 internal constant NAIROBI_OPEN_UTC = 6 * SECONDS_PER_HOUR;   // 6:00 AM UTC = 9:00 AM EAT
    uint256 internal constant NAIROBI_CLOSE_UTC = 13 * SECONDS_PER_HOUR; // 1:00 PM UTC = 4:00 PM EAT

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // FUNDING RATE SCHEDULES
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Funding rate intervals for perpetual contracts (8 hours standard)
    uint256 internal constant FUNDING_INTERVAL = 8 * SECONDS_PER_HOUR;
    
    /// @dev Daily settlement time for mark-to-market (4:00 PM UTC)
    uint256 internal constant DAILY_SETTLEMENT_UTC = 16 * SECONDS_PER_HOUR;

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Reverts when time calculation would overflow uint256
    error BaobabTimeCalculationOverflow();
    
    /// @dev Reverts when trading is attempted outside market hours
    error BaobabMarketClosed();
    
    /// @dev Reverts when invalid time parameters are provided
    error BaobabInvalidTimeParameters();

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // BASIC TIME OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current block timestamp with BAOBAB naming convention
     * @return currentTimestamp Current block timestamp in seconds
     */
    function baobabNow() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Add specified number of days to a timestamp
     * @param timestamp Base timestamp to add days to
     * @param daysToAdd Number of days to add
     * @return newTimestamp Resulting timestamp after adding days
     * @dev Reverts on overflow for large values
     */
    function baobabAddDays(uint256 timestamp, uint256 daysToAdd) internal pure returns (uint256) {
        if (timestamp > type(uint256).max - daysToAdd * SECONDS_PER_DAY) {
            revert BaobabTimeCalculationOverflow();
        }
        return timestamp + daysToAdd * SECONDS_PER_DAY;
    }

    /**
     * @notice Add specified number of hours to a timestamp
     * @param timestamp Base timestamp to add hours to
     * @param hoursToAdd Number of hours to add
     * @return newTimestamp Resulting timestamp after adding hours
     * @dev Reverts on overflow for large values
     */
    function baobabAddHours(uint256 timestamp, uint256 hoursToAdd) internal pure returns (uint256) {
        if (timestamp > type(uint256).max - hoursToAdd * SECONDS_PER_HOUR) {
            revert BaobabTimeCalculationOverflow();
        }
        return timestamp + hoursToAdd * SECONDS_PER_HOUR;
    }

    /**
     * @notice Add specified number of minutes to a timestamp
     * @param timestamp Base timestamp to add minutes to
     * @param minutesToAdd Number of minutes to add
     * @return newTimestamp Resulting timestamp after adding minutes
     * @dev Reverts on overflow for large values
     */
    function baobabAddMinutes(uint256 timestamp, uint256 minutesToAdd) internal pure returns (uint256) {
        if (timestamp > type(uint256).max - minutesToAdd * 60) {
            revert BaobabTimeCalculationOverflow();
        }
        return timestamp + minutesToAdd * 60;
    }

    /**
     * @notice Calculate difference between two timestamps in days
     * @param from Starting timestamp
     * @param to Ending timestamp
     * @return daysDifference Number of days between timestamps
     * @dev Reverts if 'to' is before 'from'
     */
    function baobabDiffDays(uint256 from, uint256 to) internal pure returns (uint256) {
        if (to < from) revert BaobabInvalidTimeParameters();
        return (to - from) / SECONDS_PER_DAY;
    }

    /**
     * @notice Calculate difference between two timestamps in hours
     * @param from Starting timestamp
     * @param to Ending timestamp
     * @return hoursDifference Number of hours between timestamps
     * @dev Reverts if 'to' is before 'from'
     */
    function baobabDiffHours(uint256 from, uint256 to) internal pure returns (uint256) {
        if (to < from) revert BaobabInvalidTimeParameters();
        return (to - from) / SECONDS_PER_HOUR;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // AFRICAN MARKET HOURS VALIDATION (HARDCODED - LEGACY)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if Nigerian stock market is currently open
     * @param timestamp UTC timestamp to check market hours for
     * @return isOpen True if Nigerian market is within trading hours
     */
    function baobabIsNigerianMarketOpen(uint256 timestamp) internal pure returns (bool) {
        uint256 timeOfDay = timestamp % SECONDS_PER_DAY;
        return timeOfDay >= NSE_OPEN_UTC && timeOfDay < NSE_CLOSE_UTC;
    }

    /**
     * @notice Check if South African stock market is currently open
     * @param timestamp UTC timestamp to check market hours for
     * @return isOpen True if South African market is within trading hours
     */
    function baobabIsSouthAfricanMarketOpen(uint256 timestamp) internal pure returns (bool) {
        uint256 timeOfDay = timestamp % SECONDS_PER_DAY;
        return timeOfDay >= JSE_OPEN_UTC && timeOfDay < JSE_CLOSE_UTC;
    }

    /**
     * @notice Check if Kenyan stock market is currently open
     * @param timestamp UTC timestamp to check market hours for
     * @return isOpen True if Kenyan market is within trading hours
     */
    function baobabIsKenyanMarketOpen(uint256 timestamp) internal pure returns (bool) {
        uint256 timeOfDay = timestamp % SECONDS_PER_DAY;
        return timeOfDay >= NAIROBI_OPEN_UTC && timeOfDay < NAIROBI_CLOSE_UTC;
    }

    /**
     * @notice Check if any major African equity market is currently open
     * @param timestamp UTC timestamp to check market hours for
     * @return isOpen True if any Nigerian, South African, or Kenyan market is open
     */
    function baobabIsAnyAfricanMarketOpen(uint256 timestamp) internal pure returns (bool) {
        return baobabIsNigerianMarketOpen(timestamp) ||
               baobabIsSouthAfricanMarketOpen(timestamp) ||
               baobabIsKenyanMarketOpen(timestamp);
    }

    /**
     * @notice Validate trading hours for African assets based on region
     * @param timestamp UTC timestamp to validate
     * @param marketRegion Region identifier for market hours validation
     * @dev Reverts with BaobabMarketClosed if outside permitted trading hours
     */
    function baobabValidateAfricanMarketHours(uint256 timestamp, bytes32 marketRegion) internal pure {
        bool isOpen;
        
        if (marketRegion == "NIGERIA") {
            isOpen = baobabIsNigerianMarketOpen(timestamp);
        } else if (marketRegion == "SOUTH_AFRICA") {
            isOpen = baobabIsSouthAfricanMarketOpen(timestamp);
        } else if (marketRegion == "KENYA") {
            isOpen = baobabIsKenyanMarketOpen(timestamp);
        } else {
            isOpen = baobabIsAnyAfricanMarketOpen(timestamp);
        }
        
        if (!isOpen) revert BaobabMarketClosed();
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // DYNAMIC MARKET HOURS VALIDATION (MARKET REGISTRY INTEGRATION)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    // NOTE: These functions require MarketRegistry integration
    // Uncomment and implement when MarketRegistry is available
    
    /*
    /**
     * @notice Check if market is open using dynamic MarketRegistry data
     * @param market Address of the market contract to check
     * @return isOpen True if market is currently within trading hours
     * @dev Uses MarketRegistry for dynamic market hours management
     *//*
    function baobabIsMarketOpen(address market) internal view returns (bool) {
        MarketRegistry.MarketHours memory hours = MarketRegistry(marketRegistryAddress).getMarketHours(market);
        
        // 24/7 markets (crypto) are always open
        if (hours.is24h) return true;
        
        // Check if current time is within trading hours
        uint256 currentTimeUTC = block.timestamp % SECONDS_PER_DAY;
        return currentTimeUTC >= hours.openTimeUTC && currentTimeUTC < hours.closeTimeUTC;
    }

    /**
     * @notice Validate trading hours for specific market using MarketRegistry
     * @param market Address of the market contract to validate
     * @dev Reverts with BaobabMarketClosed if outside trading hours
     *//*
    function baobabValidateMarketHours(address market) internal view {
        if (!baobabIsMarketOpen(market)) {
            revert BaobabMarketClosed();
        }
    }
    */

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // FUNDING RATE & SETTLEMENT SCHEDULES
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate next funding rate timestamp based on 8-hour intervals
     * @param timestamp Current timestamp for funding calculation
     * @return nextFunding Timestamp of next funding rate application
     */
    function baobabNextFundingTimestamp(uint256 timestamp) internal pure returns (uint256) {
        uint256 fundingEpoch = (timestamp / FUNDING_INTERVAL) * FUNDING_INTERVAL;
        return fundingEpoch + FUNDING_INTERVAL;
    }

    /**
     * @notice Calculate time remaining until next funding rate application
     * @param timestamp Current timestamp for calculation
     * @return timeUntilFunding Seconds remaining until next funding rate
     */
    function baobabTimeUntilNextFunding(uint256 timestamp) internal pure returns (uint256) {
        uint256 nextFunding = baobabNextFundingTimestamp(timestamp);
        return nextFunding - timestamp;
    }

    /**
     * @notice Check if funding rate should be applied at current timestamp
     * @param timestamp Timestamp to check for funding application
     * @return shouldApply True if funding rate should be applied now
     */
    function baobabShouldApplyFunding(uint256 timestamp) internal pure returns (bool) {
        return timestamp % FUNDING_INTERVAL == 0;
    }

    /**
     * @notice Calculate next daily settlement timestamp
     * @param timestamp Current timestamp for settlement calculation
     * @return nextSettlement Timestamp of next daily settlement
     */
    function baobabNextSettlementTimestamp(uint256 timestamp) internal pure returns (uint256) {
        uint256 daysSinceEpoch = timestamp / SECONDS_PER_DAY;
        return (daysSinceEpoch * SECONDS_PER_DAY) + DAILY_SETTLEMENT_UTC;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ORDER EXPIRY & TIME-BASED VALIDATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if timestamp is in the future relative to current block
     * @param timestamp Timestamp to check
     * @return isFuture True if timestamp is after current block time
     */
    function baobabIsFuture(uint256 timestamp) internal view returns (bool) {
        return timestamp > block.timestamp;
    }

    /**
     * @notice Check if timestamp is in the past relative to current block
     * @param timestamp Timestamp to check
     * @return isPast True if timestamp is before current block time
     */
    function baobabIsPast(uint256 timestamp) internal view returns (bool) {
        return timestamp < block.timestamp;
    }

    /**
     * @notice Check if order has expired based on TTL (Time To Live)
     * @param orderTimestamp When the order was created
     * @param ttl Time To Live in seconds for order validity
     * @return isExpired True if order has exceeded its TTL
     */
    function baobabIsOrderExpired(uint256 orderTimestamp, uint256 ttl) internal view returns (bool) {
        return block.timestamp > orderTimestamp + ttl;
    }

    /**
     * @notice Validate that order has not expired based on TTL
     * @param orderTimestamp When the order was created
     * @param ttl Time To Live in seconds for order validity
     * @dev Reverts with error message if order has expired
     */
    function baobabValidateOrderNotExpired(uint256 orderTimestamp, uint256 ttl) internal view {
        if (baobabIsOrderExpired(orderTimestamp, ttl)) {
            revert("Order expired");
        }
    }

    /**
     * @notice Calculate order expiry timestamp based on TTL
     * @param orderTimestamp When the order was created
     * @param ttl Time To Live in seconds for order validity
     * @return expiryTimestamp Timestamp when order will expire
     * @dev Reverts on overflow for large TTL values
     */
    function baobabCalculateExpiry(uint256 orderTimestamp, uint256 ttl) internal pure returns (uint256) {
        if (orderTimestamp > type(uint256).max - ttl) {
            revert BaobabTimeCalculationOverflow();
        }
        return orderTimestamp + ttl;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // EVENT DERIVATIVES SCHEDULING
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate time remaining until event settlement
     * @param settlementTime Scheduled settlement timestamp for event
     * @return timeUntilSettlement Seconds remaining until settlement (0 if past due)
     */
    function baobabTimeUntilSettlement(uint256 settlementTime) internal view returns (uint256) {
        if (settlementTime <= block.timestamp) return 0;
        return settlementTime - block.timestamp;
    }

    /**
     * @notice Check if event should be settled based on current time
     * @param settlementTime Scheduled settlement timestamp for event
     * @return shouldSettle True if current time is at or past settlement time
     */
    function baobabShouldSettleEvent(uint256 settlementTime) internal view returns (bool) {
        return block.timestamp >= settlementTime;
    }

    /**
     * @notice Validate that settlement time is in the future
     * @param settlementTime Scheduled settlement timestamp to validate
     * @dev Reverts if settlement time is in the past
     */
    function baobabValidateFutureSettlement(uint256 settlementTime) internal view {
        if (settlementTime <= block.timestamp) {
            revert BaobabInvalidTimeParameters();
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // KEEPER BOT SCHEDULING & AUTOMATION
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Calculate next keeper execution time based on interval
     * @param lastExecution Timestamp of last keeper execution
     * @param interval Execution interval in seconds
     * @return nextExecution Timestamp for next keeper execution
     */
    function baobabNextKeeperExecution(uint256 lastExecution, uint256 interval) internal view returns (uint256) {
        if (lastExecution == 0) return block.timestamp;
        return lastExecution + interval;
    }

    /**
     * @notice Check if keeper should execute based on schedule
     * @param lastExecution Timestamp of last keeper execution
     * @param interval Execution interval in seconds
     * @return shouldExecute True if keeper should execute now
     */
    function baobabShouldKeeperExecute(uint256 lastExecution, uint256 interval) internal view returns (bool) {
        return block.timestamp >= baobabNextKeeperExecution(lastExecution, interval);
    }

    /**
     * @notice Calculate random delay for anti-MEV protection
     * @param baseDelay Base delay in seconds
     * @param randomRange Random range in seconds for additional delay
     * @return randomDelay Total delay including random component
     */
    function baobabCalculateRandomDelay(uint256 baseDelay, uint256 randomRange) internal view returns (uint256) {
        uint256 random = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp)));
        return baseDelay + (random % randomRange);
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TIME-BASED ACCESS CONTROL & VALIDATION
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if current time is within specified time window
     * @param startTime Window start timestamp
     * @param endTime Window end timestamp
     * @return inWindow True if current time is within the window
     */
    function baobabIsInTimeWindow(uint256 startTime, uint256 endTime) internal view returns (bool) {
        return block.timestamp >= startTime && block.timestamp <= endTime;
    }

    /**
     * @notice Validate current time is within specified time window
     * @param startTime Window start timestamp
     * @param endTime Window end timestamp
     * @dev Reverts with error message if outside allowed time window
     */
    function baobabValidateInTimeWindow(uint256 startTime, uint256 endTime) internal view {
        if (!baobabIsInTimeWindow(startTime, endTime)) {
            revert("Outside allowed time window");
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // GAS-OPTIMIZED TIME CALCULATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get start of day timestamp (00:00:00 UTC)
     * @param timestamp Any timestamp within the day
     * @return startOfDay Timestamp representing start of the day
     */
    function baobabStartOfDay(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / SECONDS_PER_DAY) * SECONDS_PER_DAY;
    }

    /**
     * @notice Get start of hour timestamp (HH:00:00)
     * @param timestamp Any timestamp within the hour
     * @return startOfHour Timestamp representing start of the hour
     */
    function baobabStartOfHour(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / SECONDS_PER_HOUR) * SECONDS_PER_HOUR;
    }

    /**
     * @notice Get start of week timestamp (Monday 00:00:00 UTC)
     * @param timestamp Any timestamp within the week
     * @return startOfWeek Timestamp representing start of the week
     * @dev Adjusts for January 1, 1970 being a Thursday
     */
    function baobabStartOfWeek(uint256 timestamp) internal pure returns (uint256) {
        uint256 dayOfWeek = (timestamp / SECONDS_PER_DAY + 3) % 7;
        return baobabStartOfDay(timestamp) - dayOfWeek * SECONDS_PER_DAY;
    }
}