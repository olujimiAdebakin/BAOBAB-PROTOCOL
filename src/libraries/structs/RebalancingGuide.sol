// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Rebalancing Strategies in BAOBAB Baskets
 * @author BAOBAB Protocol
 * @notice How Asset & Order Baskets maintain target allocations
 * @dev Critical for index funds, volatility strategies, and African market exposure
 */
library RebalancingGuide {

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 1. MANUAL REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Manager manually triggers rebalance
     * @notice Use Case: High-conviction strategies (e.g., "Dangote + MTNN Overweight")
     * @dev Flow:
     *      1. Manager calls BasketEngine.rebalance(basketId)
     *      2. System sells overweight assets, buys underweight
     *      3. Updates BasketComponent.currentWeightBps
     * @advantages
     *      - Full control over timing and execution
     *      - Avoids forced trades during volatility
     * @risks
     *      - Human error or delay
     *      - Potential front-running
     */
    function manual() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 2. SCHEDULED REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Automatic rebalance on fixed calendar
     * @notice Use Case: Passive indices (e.g., "NGX-30 Monthly Rebalance")
     * @dev Config (RebalanceSchedule):
     *      intervalSeconds: 30 days = 2_592_000
     *      nextRebalance: block.timestamp + interval
     * @flow
     *      Keeper checks: block.timestamp >= nextRebalance
     *      → executes rebalance
     *      → sets nextRebalance += interval
     * @advantages
     *      - Predictable, transparent
     *      - Matches traditional ETFs
     * @risks
     *      - Rebalances during bad liquidity (e.g., weekend)
     */
    function scheduled() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 3. THRESHOLD REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Rebalance when any asset drifts > X%
     * @notice Use Case: Volatility targeting (e.g., "Max 5% drift")
     * @dev Config (RebalanceConfig):
     *      maxDeviationBps: 500 → 5%
     *      minIntervalSeconds: 1 hour (prevent spam)
     * @flow
     *      1. Oracle updates prices → BasketEngine.updateNAV()
     *      2. For each component:
     *           drift = |currentWeight - targetWeight|
     *      3. If drift > maxDeviationBps → trigger rebalance
     * @advantages
     *      - Responsive to market moves
     *      - Minimizes tracking error
     * @risks
     *      - Frequent rebalancing → high gas + slippage
     */
    function threshold() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // 4. DYNAMIC REBALANCING
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Algorithmic rebalance based on signals
     * @notice Use Case: Smart beta, momentum, mean-reversion
     * @dev Examples:
     *      - Rebalance when RSI > 70 (sell winners)
     *      - Increase NGN/USD weight when CBN rate spikes
     *      - Auto-sell filled OrderNFTs, buy new pending ones
     * @flow
     *      1. Strategy contract implements IRebalanceLogic
     *      2. Keeper calls: shouldRebalance(basketId) → bool
     *      3. If true → execute custom logic
     * @advantages
     *      - Adaptive to African market alpha
     *      - Highest potential returns
     * @risks
     *      - Complex → audit burden
     *      - Oracle dependency
     */
    function dynamic() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // HYBRID STRATEGIES (COMBINED)
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Example: "Monthly + 10% Threshold"
     *      → Rebalance monthly OR if drift > 10%
     * @dev Example: "Scheduled + Dynamic Override"
     *      → Monthly rebalance, but manager can trigger early
     */
    function hybrid() internal pure {}

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    // REBALANCE EXECUTION (COMMON TO ALL)
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Steps in every rebalance:
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
     * @dev Best Practices:
     *      - Batch trades in one tx
     *      - Use TWAP for large orders
     *      - Set maxSlippageBps in RebalanceConfig
     *      - Refund gas to executor via BAOBAB
     */
    function optimization() internal pure {}
}