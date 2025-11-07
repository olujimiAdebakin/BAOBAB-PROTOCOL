// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {FixedPointMath} from "../math/FixedPointMath.sol";
import {CommonStructs} from "./CommonStructs.sol";

/**
 * @title TradingStructs
 * @author BAOBAB Protocol
 * @notice Enhanced order types with Scale & TWAP execution modes
 * @dev Integrates Hyperliquid-style order splitting for institutional UX
 */
library TradingStructs {
    using FixedPointMath for uint256;

    // ──────────────────────────────────────────────────────────────────────
    // Order Types & Execution Modes
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Core order type classification
    enum OrderType {
        MARKET,     // Instant fill
        LIMIT,      // Price-specific
        SCALE,      // Price-level splitting
        TWAP        // Time-based splitting
    }

    /// @dev Where the order should be routed
    enum ExecutionMode {
        AUTO, // Smart routing (default for 90% users)
        VAULT,      // Protocol fills instantly (AMM-style)
        ORDERBOOK   // Peer-to-peer matching (CLOB)
    }

    // Need to track order lifecycle
enum OrderStatus {
    PENDING,
    PARTIAL,
    FILLED,
    CANCELLED,
    EXPIRED
}

    // ──────────────────────────────────────────────────────────────────────
    // Enhanced Order Struct
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Unified order with full routing + splitting control
    struct Order {
        address trader;
        address baseToken;
        address quoteToken;
        uint96 size;                    // Total intended size
        uint96 price;                   // Target price (Q64.96)
        uint64 timestamp;
        uint64 expiry;
        OrderType orderType;
        ExecutionMode executionMode;
        bool isBuy;
        uint8 numSplits;                // For SCALE/TWAP (0 = no split)
        uint16 interval;                // Price steps (SCALE) or seconds (TWAP)
        uint16 slippageTolerance;       // Max deviation (bps)
    }

    // ──────────────────────────────────────────────────────────────────────
    // Scale Order Parameters
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Price ladder for SCALE orders
    struct ScaleConfig {
        uint256 startPrice;             // Q64.96
        uint256 endPrice;               // Q64.96
        uint256 stepSize;               // Price increment
        uint256[] fillAmounts;          // Size per level
        uint256 currentLevel;           // Progress tracker
        bool ascending;                 // true = buy ladder up, sell down
    }

    // ──────────────────────────────────────────────────────────────────────
    // TWAP Order Parameters
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Time-based execution schedule
    struct TWAPConfig {
        uint256 totalSize;
        uint256 sliceSize;              // size per interval
        uint256 startTime;
        uint256 endTime;
        uint256 lastExecution;
        uint256 executedSoFar;
        bool isActive;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Order NFT Metadata (Extended)
    // ──────────────────────────────────────────────────────────────────────

    struct OrderNFTMetadata {
        uint256 orderId;
        uint256 value;                  // size * price
        uint256 collateral;
        uint256 borrowAmount;
        uint64 stakeTimestamp;
        uint64 fillTimestamp;
        OrderType orderType;
        ExecutionMode executionMode;
        bool isActive;
        bytes32 configHash;             // Hash of Scale/TWAP config
    }

    // ──────────────────────────────────────────────────────────────────────
    // Position & Margin (unchanged)
    // ──────────────────────────────────────────────────────────────────────

    struct Position {
        address trader;
        address market;
        int128 size;
        uint128 entryPrice;
        uint128 collateral;
        uint64 lastFundingTime;
        uint64 openTimestamp;
    }

    struct MarginAccount {
        uint256 totalCollateral;
        uint256 totalDebt;
        uint256 maintenanceMargin;
        uint256 healthFactor;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Market Config (updated)
    // ──────────────────────────────────────────────────────────────────────

    struct MarketConfig {
        address baseToken;
        address quoteToken;
        uint256 maxLeverage;
        uint256 maintenanceMargin;
        uint256 fundingRateCap;
        bool isActive;
        bool allowScale;
        bool allowTWAP;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Risk & Vault (unchanged)
    // ──────────────────────────────────────────────────────────────────────

    struct RiskParams {
        uint256 ltvRatio;
        uint256 liquidationFee;
        uint256 interestRateBase;
        uint256 interestRateSlope;
    }

    struct Staker {
        uint256 blpBalance;
        uint256[] stakedNFTs;
        uint256 pendingBAOBAB;
        uint256 lastClaimTime;
    }

    struct VaultAccounting {
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 totalStakedValue;
        uint256 utilizationRate;
    }
}