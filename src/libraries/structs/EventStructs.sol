// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title EventStructs
 * @author BAOBAB Protocol
 * @notice Prediction markets — clean, gas-optimized, no external math
 * @dev All price/volume math uses inline operations or uint128
 *      Designed for scalability across African event markets (AFCON, elections, commodities)
 */
library EventStructs {

    // ──────────────────────────────────────────────────────────────────────
    // Event Market Core
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @dev Core event market metadata
     * @param eventId Unique identifier (incremental)
     * @param creationTime Block timestamp of market creation
     * @param resolutionTime Expected resolution deadline
     * @param creator Address that deployed the market
     * @param oracle Trusted resolver (EOA or contract)
     * @param ipfsHash CID pointing to off-chain metadata (title, description, image)
     * @param outcomeCount Number of possible outcomes (2–255)
     * @param isResolved True when oracle has submitted result
     * @param isCancelled True if market voided (e.g. event postponed)
     */
    struct EventMarket {
        uint128 eventId;
        uint64 creationTime;
        uint64 resolutionTime;
        address creator;
        address oracle;
        bytes32 ipfsHash;
        uint8 outcomeCount;
        bool isResolved;
        bool isCancelled;
    }

    /**
     * @dev Tracks volume and final price per outcome
     * @param totalYes Total wagered on "Yes" (or outcome index)
     * @param totalNo Total wagered on "No" (or other)
     * @param finalPrice Q64.96 price at resolution (e.g. 0.7 * 1e18)
     * @param isWinning True if this outcome won
     */
    struct Outcome {
        uint128 totalYes;
        uint128 totalNo;
        uint128 finalPrice; // Q64.96 — but never scaled here
        bool isWinning;
    }

    // ──────────────────────────────────────────────────────────────────────
    // User & LP
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @dev User's bet in a prediction market
     * @param user Bettor address
     * @param eventId Market ID
     * @param outcomeIndex 0 = Yes, 1 = No, etc.
     * @param claimed 0 = not claimed, 1 = claimed win, 2 = refunded
     * @param amount Wager size (in base token)
     * @param payout Total payout if winning (calculated at resolution)
     */
    struct EventPosition {
        address user;
        uint128 eventId;
        uint8 outcomeIndex;
        uint8 claimed; // 0=no, 1=yes, 2=refunded
        uint128 amount;
        uint128 payout;
    }

    /**
     * @dev Liquidity provider in event market pool
     * @param shares LP share amount
     * @param depositTime When LP entered
     * @param lastClaim Last fee claim timestamp
     * @param pendingFees Accumulated unclaimed fees
     */
    struct EventLP {
        uint128 shares;
        uint64 depositTime;
        uint64 lastClaim;
        uint128 pendingFees;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Resolution
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @dev Oracle result submission
     * @param eventId Target market
     * @param winningOutcome Index of winning outcome
     * @param timestamp Submission time
     * @param signature EIP-712 or ECDSA proof
     * @param executed True if payout processed
     */
    struct OracleSubmission {
        uint128 eventId;
        uint8 winningOutcome;
        uint64 timestamp;
        bytes signature;
        bool executed;
    }

    /**
     * @dev Dispute mechanism (optional governance layer)
     * @param windowEnd Deadline for disputes
     * @param bond Amount locked by challenger
     * @param challenger Address raising dispute
     * @param resolved True when dispute settled
     * @param upheld True if oracle overturned
     */
    struct Dispute {
        uint64 windowEnd;
        uint128 bond;
        address challenger;
        bool resolved;
        bool upheld;
    }

    // ──────────────────────────────────────────────────────────────────────
    // Config
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @dev Fee configuration per market (base 10000 = 100.00%)
     * @param entryFee Charged on bet placement
     * @param creatorFee % to market creator
     * @param protocolFee % to BAOBAB treasury
     * @param lpFee % to liquidity providers
     * @param disputeBond % of pool required to challenge
     */
    struct EventFeeConfig {
        uint16 entryFee;     // e.g. 50 = 0.50%
        uint16 creatorFee;
        uint16 protocolFee;
        uint16 lpFee;
        uint16 disputeBond;
    }

    /**
     * @dev Payout calculation inputs
     * @param totalPool Sum of all wagers
     * @param winningPool Sum of winning bets
     * @param protocolCut Treasury share
     * @param lpCut LP reward
     */
    struct PayoutFormula {
        uint256 totalPool;
        uint256 winningPool;
        uint256 protocolCut;
        uint256 lpCut;
    }

    /**
     * @dev For markets with >2 outcomes
     * @param labels Outcome names (off-chain reference)
     * @param volumes Wager volume per outcome
     * @param winningIndex Index of resolved winner
     * @param active True if still accepting bets
     */
    struct MultiOutcome {
        string[] labels;
        uint128[] volumes;
        uint8 winningIndex;
        bool active;
    }

    /**
     * @dev Event timing and categorization
     * @param startTime When betting opens
     * @param endTime When betting closes
     * @param categoryHash keccak256("Sports"), "Politics", etc.
     * @param isLive True if currently active
     */
    struct EventSchedule {
        uint64 startTime;
        uint64 endTime;
        bytes32 categoryHash;
        bool isLive;
    }
}