// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Rebalancing Strategies in BAOBAB Baskets
 * @author BAOBAB Protocol
 * @notice Describes how Asset & Order Baskets maintain target allocations
 * @dev Critical for index funds, volatility strategies, and African market exposure
 */
library RebalancingGuide {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 1. MANUAL REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Manager manually triggers rebalance
     * @dev
     * Use Case: High-conviction strategies (e.g., "Dangote + MTNN Overweight")
     *
     * Flow:
     *  1. Manager calls BasketEngine.rebalance(basketId)
     *  2. System sells overweight assets, buys underweight
     *  3. Updates BasketComponent.currentWeightBps
     *
     * Advantages:
     *  - Full control over timing and execution
     *  - Avoids forced trades during volatility
     *
     * Risks:
     *  - Human error or delay
     *  - Potential front-running
     */
    function manual() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 2. SCHEDULED REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Automatic rebalance on a fixed calendar
     * @dev
     * Use Case: Passive indices (e.g., "NGX-30 Monthly Rebalance")
     *
     * Config (RebalanceSchedule):
     *  - intervalSeconds: 30 days = 2_592_000
     *  - nextRebalance: block.timestamp + interval
     *
     * Flow:
     *  - Keeper checks: block.timestamp >= nextRebalance
     *  - Executes rebalance
     *  - Sets nextRebalance += interval
     *
     * Advantages:
     *  - Predictable, transparent
     *  - Matches traditional ETFs
     *
     * Risks:
     *  - Rebalances during poor liquidity (e.g., weekend)
     */
    function scheduled() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 3. THRESHOLD REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Rebalance when any asset drifts beyond a defined threshold
     * @dev
     * Use Case: Volatility targeting (e.g., "Max 5% drift")
     *
     * Config (RebalanceConfig):
     *  - maxDeviationBps: 500 → 5%
     *  - minIntervalSeconds: 1 hour (prevent spam)
     *
     * Flow:
     *  1. Oracle updates prices → BasketEngine.updateNAV()
     *  2. For each component:
     *       drift = |currentWeight - targetWeight|
     *  3. If drift > maxDeviationBps → trigger rebalance
     *
     * Advantages:
     *  - Responsive to market moves
     *  - Minimizes tracking error
     *
     * Risks:
     *  - Frequent rebalancing → higher gas and slippage
     */
    function threshold() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 4. DYNAMIC REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Algorithmic rebalance based on custom logic or signals
     * @dev
     * Use Case: Smart beta, momentum, mean-reversion
     *
     * Examples:
     *  - Rebalance when RSI > 70 (sell winners)
     *  - Increase NGN/USD weight when CBN rate spikes
     *  - Auto-sell filled OrderNFTs, buy new pending ones
     *
     * Flow:
     *  1. Strategy contract implements IRebalanceLogic
     *  2. Keeper calls shouldRebalance(basketId) → bool
     *  3. If true → executes custom logic
     *
     * Advantages:
     *  - Adaptive to African market alpha
     *  - Highest potential returns
     *
     * Risks:
     *  - Complex → higher audit burden
     *  - Oracle dependency
     */
    function dynamic() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // HYBRID STRATEGIES (COMBINED)
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Combines multiple rebalance triggers for flexibility
     * @dev
     * Example 1: "Monthly + 10% Threshold"
     * → Rebalance monthly OR if drift > 10%
     *
     * Example 2: "Scheduled + Dynamic Override"
     * → Monthly rebalance, but manager can trigger early
     */
    function hybrid() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // REBALANCE EXECUTION (COMMON TO ALL)
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Steps performed in every rebalance
     * @dev
     * 1. Pause deposits/withdrawals
     * 2. Calculate current weights
     * 3. Determine buy/sell amounts
     * 4. Execute trades (via Router or Keeper)
     * 5. Update BasketComponent.amount & currentValue
     * 6. Log RebalanceLog
     * 7. Resume operations
     */
    function executionFlow() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // GAS & SLIPPAGE MITIGATION
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Best practices for efficient rebalancing
     * @dev
     *  - Batch trades in one tx
     *  - Use TWAP for large orders
     *  - Set maxSlippageBps in RebalanceConfig
     *  - Refund gas to executor via BAOBAB
     */
    function optimization() internal pure {}
}
