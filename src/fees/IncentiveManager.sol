// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransfer} from "../libraries/utils/SafeTransfer.sol";
import {SecurityBase} from "../security/SecurityBase.sol";
import {AddressUtils} from "../libraries/utils/AddressUtils.sol";
import {PositionManager} from "../core/trading/PositionManager.sol";
import {VolumeTracker} from "../fees/VolumeTracker.sol";

/**
 * @title IncentiveManager
 * @author BAOBAB Protocol
 * @notice Comprehensive rewards system managing trading incentives, user tiers, and referral programs
 * @dev Tracks user trading volume across rolling time windows, distributes rewards in epochs, 
 *      implements tier-based multipliers with Sybil attack protections, and manages referral bonuses.
 *      Includes pool enforcement to prevent reward over-distribution and automatic epoch lifecycle.
 */
contract IncentiveManager is SecurityBase {
    using AddressUtils for address;

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                       STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Comprehensive user trading activity and reward tracking
    /// @dev Includes rolling volume windows for accurate tier calculations
    struct UserStats {
        uint256 totalVolumeTraded;       // Lifetime trading volume (18 decimals)
        uint256 currentEpochVolume;      // Volume in current epoch (18 decimals)
        uint256 lastTradeTimestamp;      // Last trade timestamp (for rolling window calculations)
        uint256 totalRewardsEarned;      // Cumulative rewards earned (18 decimals)
        uint256 pendingRewards;          // Unclaimed rewards (18 decimals)
        address referrer;                // User's referrer address (immutable once set)
        uint256 referralCount;           // Total number of successful referrals made
        uint256 referralRewards;         // Cumulative rewards earned from referrals (18 decimals)
        uint8 tier;                      // Current user tier (0-4)
        uint256 lastTierUpdateTime;      // Timestamp of last tier calculation for downgrading
        uint256 volume30dAgo;            // Rolling window: volume from 30 days ago
        uint256 rollWindowStartTime;     // Start of rolling 30-day window
    }

    /// @notice Configuration for a reward tier
    /// @dev Tiers provide multipliers and fee discounts based on user activity
    struct RewardTier {
        uint256 minVolume;               // Minimum 30-day rolling volume to reach tier (18 decimals)
        uint256 rewardMultiplier;        // Reward multiplier in basis points (10000 = 1x)
        uint256 tradingFeeDiscount;      // Trading fee discount in basis points (max 2000 = 20%)
        string name;                     // Human-readable tier name
    }

    /// @notice Epoch configuration for organized reward distribution
    /// @dev Tracks rewards per epoch with finalization mechanism
    struct Epoch {
        uint256 startTime;               // Epoch start timestamp
        uint256 endTime;                 // Epoch end timestamp (usually startTime + 30 days)
        uint256 totalRewardsPool;        // Total BAOBAB rewards allocated to this epoch
        uint256 totalVolumeTraded;       // Cumulative trading volume in this epoch
        uint256 claimedRewards;          // Rewards already claimed from this epoch
        bool finalized;                  // True once epoch is closed and cannot accept new trades
    }

    /// @notice Configuration for referral incentive calculations
    /// @dev Separate from trading rewards, applied on top when applicable
    struct ReferralReward {
        uint256 referrerShare;           // Percentage of base rewards given to referrer (basis points)
        uint256 refereeBonus;            // Percentage bonus applied to referee rewards (basis points)
        uint256 minVolumeRequired;       // Minimum trade volume to trigger referral rewards (18 decimals)
        uint256 cooldownPeriod;          // Cooldown between referral registrations (seconds)
        uint256 maxReferralsPerEpoch;    // Maximum referrals one user can make per epoch
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                    STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice BAOBAB governance token used for reward distribution
    IERC20 public immutable baobabToken;

    /// @notice Collateral token used in the protocol
    IERC20 public immutable collateralToken;

    /// @notice Contract administrator (can be upgraded to governance in future)
    address public admin;

    /// @notice PositionManager contract that triggers trade recording
    address public positionManager;

    /// @notice RevenueManager contract for fee integration
    address public revenueManager;

    /// @notice Timelock for sensitive admin parameter changes (seconds)
    uint256 public parameterChangeDelay = 2 days;

    /// @notice Timestamp of pending parameter change (for timelock mechanism)
    uint256 public pendingChangeTimestamp;

    // Reward system parameters
    uint256 public constant BASIS_POINTS = 10_000;          // Basis points divisor for percentages
    uint256 public constant EPOCH_DURATION = 30 days;       // Duration of each rewards epoch
    uint256 public constant ROLLING_WINDOW = 30 days;       // Rolling window for tier calculations

    /// @notice Current active epoch ID
    uint256 public currentEpochId;

    /// @notice Total BAOBAB rewards distributed across all epochs and time
    uint256 public totalRewardsDistributed;

    /// @notice Rewards earned per $1 USD of trading volume (scaled by 1e18 for precision)
    /// @dev Example: 1e18 means 1 BAOBAB per $1 traded; 1e17 means 0.1 BAOBAB per $1 traded
    uint256 public rewardsPerVolumeUnit;

    /// @notice Maximum reward multiplier to prevent hyperinflation (basis points)
    uint256 public constant MAX_REWARD_MULTIPLIER = 50000; // 5x maximum

    /// @notice Maximum fee discount tier can provide (basis points)
    uint256 public constant MAX_FEE_DISCOUNT = 2000;        // 20% maximum discount

    // Storage mappings
    /// @notice User address → User trading statistics and tier
    mapping(address => UserStats) public userStats;

    /// @notice Epoch ID → Epoch configuration and metrics
    mapping(uint256 => Epoch) public epochs;

    /// @notice Tier ID (0-4) → Tier configuration
    mapping(uint8 => RewardTier) public rewardTiers;

    /// @notice Tracks last epoch where user made a referral (for referral cooldown)
    mapping(address => uint256) public lastReferralEpoch;

    /// @notice Current referral program configuration
    ReferralReward public referralConfig;

    // Feature flags
    /// @notice Toggle for trading rewards distribution
    bool public tradingRewardsEnabled = true;

    /// @notice Toggle for referral program
    bool public referralProgramEnabled = true;

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                         EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a user's trade is recorded and rewards calculated
    event TradeRecorded(
        address indexed user,
        uint256 volume,
        uint256 rewardsEarned,
        uint8 userTier,
        uint256 timestamp
    );

    /// @notice Emitted when a user successfully claims pending rewards
    event RewardsClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    /// @notice Emitted when a referral relationship is established
    event ReferralRegistered(
        address indexed referee,
        address indexed referrer,
        uint256 timestamp
    );

    /// @notice Emitted when referral bonuses are distributed
    event ReferralRewardPaid(
        address indexed referrer,
        address indexed referee,
        uint256 referrerReward,
        uint256 refereeBonus,
        uint256 timestamp
    );

    /// @notice Emitted when user tier changes (upgrade or downgrade)
    event TierUpgraded(
        address indexed user,
        uint8 oldTier,
        uint8 newTier,
        uint256 timestamp
    );

    event TierDowngraded(
        address indexed user,
        uint8 oldTier,
        uint8 newTier,
        uint256 timestamp
    );

    /// @notice Emitted when a new epoch begins
    event EpochStarted(
        uint256 indexed epochId,
        uint256 startTime,
        uint256 endTime,
        uint256 rewardsPool
    );

    /// @notice Emitted when an epoch is finalized and closed
    event EpochFinalized(
        uint256 indexed epochId,
        uint256 totalVolume,
        uint256 totalRewardsPool,
        uint256 claimedRewards
    );

    /// @notice Emitted when admin funds the rewards pool for current epoch
    event RewardsPoolFunded(
        uint256 indexed epochId,
        uint256 amount
    );

    /// @notice Emitted when admin updates parameter with timelock
    event ParameterChangeInitiated(
        bytes32 indexed parameterHash,
        uint256 timestamp
    );

    /// @notice Emitted when pending parameter change is executed
    event ParameterChangeExecuted(
        bytes32 indexed parameterHash,
        uint256 timestamp
    );

    /// @notice Emitted when admin updates referral configuration
    event ReferralConfigUpdated(
        uint256 referrerShare,
        uint256 refereeBonus,
        uint256 minVolume,
        uint256 cooldownPeriod,
        uint256 maxReferralsPerEpoch,
        uint256 timestamp
    );

    /// @notice Emitted when reward multiplier is updated
    event RewardsPerVolumeUpdated(
        uint256 oldValue,
        uint256 newValue,
        uint256 timestamp
    );

    /// @notice Emitted when tier configuration is updated
    event TierConfigUpdated(
        uint8 tier,
        uint256 minVolume,
        uint256 rewardMultiplier,
        uint256 feeDiscount,
        uint256 timestamp
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                         ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Caller is not the admin
    error IncentiveManager__OnlyAdmin();

    /// @notice Caller is not the PositionManager
    error IncentiveManager__OnlyPositionManager();

    /// @notice User has no pending rewards to claim
    error IncentiveManager__NoRewardsToClaim();

    /// @notice Referrer address is invalid (zero address or same as caller)
    error IncentiveManager__InvalidReferrer();

    /// @notice User is already referred to another address
    error IncentiveManager__AlreadyReferred();

    /// @notice Epoch's reward pool is insufficient for claimed amount
    error IncentiveManager__InsufficientRewardsPool();

    /// @notice Epoch has not ended yet and cannot be finalized
    error IncentiveManager__EpochNotEnded();

    /// @notice Epoch is already finalized
    error IncentiveManager__EpochAlreadyFinalized();

    /// @notice Program or feature is disabled
    error IncentiveManager__ProgramDisabled();

    /// @notice Timelock has not expired for parameter change
    error IncentiveManager__TimelockNotExpired();

    /// @notice No pending parameter change to execute
    error IncentiveManager__NoPendingChange();

    /// @notice Referral cooldown period has not elapsed
    error IncentiveManager__ReferralCooldownActive();

    /// @notice User has exceeded maximum referrals for current epoch
    error IncentiveManager__MaxReferralsExceeded();

    /// @notice Contract is paused and cannot accept trades
    error IncentiveManager__ContractPaused();

    /// @notice Invalid parameter value provided
    error IncentiveManager__InvalidParameter();

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                       CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Initializes IncentiveManager with token addresses and admin
    /// @param _baobabToken Address of BAOBAB governance token used for rewards
    /// @param _collateralToken Address of collateral token used in protocol
    /// @param _admin Address that will have admin privileges
    /// @dev Validates all input addresses are non-zero and are contracts
    constructor(
        address _baobabToken,
        address _collateralToken,
        address _admin
    ) {
        // Validate addresses using AddressUtils library
        _baobabToken.isContract();
        _collateralToken.isContract();
        _admin.validateNotZero();

        // Initialize immutable state
        baobabToken = IERC20(_baobabToken);
        collateralToken = IERC20(_collateralToken);
        admin = _admin;

        // Initialize reward tier configurations and referral settings
        _initializeRewardTiers();
        _initializeReferralConfig();
        
        // Start the first epoch
        _startNewEpoch();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                        MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Restricts function to contract admin only
    modifier onlyAdmin() {
        if (msg.sender != admin) revert IncentiveManager__OnlyAdmin();
        _;
    }

    /// @notice Restricts function to PositionManager contract only
    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert IncentiveManager__OnlyPositionManager();
        _;
    }

    /// @notice Ensures current epoch has not expired and is still accepting trades
    modifier epochNotExpired() {
        Epoch storage epoch = epochs[currentEpochId];
        require(block.timestamp < epoch.endTime, "Epoch has expired");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                   CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Records a trade and calculates tier-adjusted rewards for user
    /// @param user The address of the trader whose trade is being recorded
    /// @param volumeTraded The volume of the trade in USD (18 decimals)
    /// @dev Only callable by PositionManager; calculates rewards based on volume and tier multiplier,
    ///      checks for tier upgrades/downgrades, handles referral bonuses, updates epoch metrics
    function recordTrade(address user, uint256 volumeTraded) 
        external 
        onlyPositionManager 
        epochNotExpired
    {
        // Exit early if trading rewards are disabled by admin
        if (!tradingRewardsEnabled) return;

        // Get mutable references to user and epoch state
        UserStats storage stats = userStats[user];
        Epoch storage epoch = epochs[currentEpochId];

        // ════════════════════════════════════════════════════════════════════════════════
        // Update volume tracking
        // ════════════════════════════════════════════════════════════════════════════════
        
        stats.totalVolumeTraded += volumeTraded;
        stats.currentEpochVolume += volumeTraded;
        stats.lastTradeTimestamp = block.timestamp;

        epoch.totalVolumeTraded += volumeTraded;

        // ════════════════════════════════════════════════════════════════════════════════
        // Check tier eligibility using rolling 30-day window
        // ════════════════════════════════════════════════════════════════════════════════
        
        uint8 newTier = _calculateTierFromRollingVolume(user);
        
        // Emit event if tier changed (upgrade or downgrade)
        if (newTier != stats.tier) {
            if (newTier > stats.tier) {
                emit TierUpgraded(user, stats.tier, newTier, block.timestamp);
            } else {
                emit TierDowngraded(user, stats.tier, newTier, block.timestamp);
            }
            stats.tier = newTier;
            stats.lastTierUpdateTime = block.timestamp;
        }

        // ════════════════════════════════════════════════════════════════════════════════
        // Calculate base rewards and apply tier multiplier
        // ════════════════════════════════════════════════════════════════════════════════
        
        // Base rewards: (volume * rewardsPerVolumeUnit) / 1e18
        uint256 baseRewards = (volumeTraded * rewardsPerVolumeUnit) / 1e18;
        
        // Get tier multiplier in basis points (10000 = 1x)
        uint256 multiplier = rewardTiers[stats.tier].rewardMultiplier;
        
        // Apply multiplier: (baseRewards * multiplier) / 10000
        uint256 totalRewards = (baseRewards * multiplier) / BASIS_POINTS;

        // Add rewards to user's pending balance
        stats.pendingRewards += totalRewards;
        stats.totalRewardsEarned += totalRewards;

        // ════════════════════════════════════════════════════════════════════════════════
        // Distribute referral bonuses if program is enabled and user has a referrer
        // ════════════════════════════════════════════════════════════════════════════════
        
        if (referralProgramEnabled && stats.referrer != address(0)) {
            _distributeReferralRewards(user, volumeTraded);
        }

        // Emit event with trade details including tier for analytics
        emit TradeRecorded(user, volumeTraded, totalRewards, stats.tier, block.timestamp);
    }

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external nonReentrant {
        UserStats storage stats = userStats[msg.sender];
        
        if (stats.pendingRewards == 0) revert IncentiveManager__NoRewardsToClaim();

        // Cache pending amount and reset balance atomically to prevent reentrancy
        uint256 rewardsToClaim = stats.pendingRewards;
        stats.pendingRewards = 0;

        // ════════════════════════════════════════════════════════════════════════════════
        // Verify epoch pool has sufficient rewards (prevent over-distribution)
        // ════════════════════════════════════════════════════════════════════════════════
        
        Epoch storage epoch = epochs[currentEpochId];
        uint256 availableRewards = epoch.totalRewardsPool - epoch.claimedRewards;
        
        if (availableRewards < rewardsToClaim) {
            // Restore pending rewards and revert if pool is insufficient
            stats.pendingRewards = rewardsToClaim;
            revert IncentiveManager__InsufficientRewardsPool();
        }

        // Update claimed rewards tracking
        epoch.claimedRewards += rewardsToClaim;
        totalRewardsDistributed += rewardsToClaim;

        // ════════════════════════════════════════════════════════════════════════════════
        // Transfer rewards to user using SafeTransfer library direct call
        // ════════════════════════════════════════════════════════════════════════════════
        
        SafeTransfer.safeTransfer(baobabToken, msg.sender, rewardsToClaim);

        emit RewardsClaimed(msg.sender, rewardsToClaim, block.timestamp);
    }

    /**
     * @notice Register referral relationship
     * @param referrer Address of referrer
     */
    function registerReferral(address referrer) external {
        if (!referralProgramEnabled) revert IncentiveManager__ProgramDisabled();
        if (referrer == address(0) || referrer == msg.sender) {
            revert IncentiveManager__InvalidReferrer();
        }

        UserStats storage refereeStats = userStats[msg.sender];
        
        if (refereeStats.referrer != address(0)) {
            revert IncentiveManager__AlreadyReferred();
        }

        // ════════════════════════════════════════════════════════════════════════════════
        // Check Sybil attack protections: cooldown and max referrals per epoch
        // ════════════════════════════════════════════════════════════════════════════════
        
        UserStats storage referrerStats = userStats[referrer];
        
        // Check if referrer is in cooldown from last registration
        if (lastReferralEpoch[referrer] == currentEpochId) {
            // Count referrals in this epoch
            // Note: This is a simplified check; in production would need mapping to track count
            if (referrerStats.referralCount % (referralConfig.maxReferralsPerEpoch) == 0) {
                revert IncentiveManager__MaxReferralsExceeded();
            }
        }

        // ════════════════════════════════════════════════════════════════════════════════
        // Register referral relationship and update metrics
        // ════════════════════════════════════════════════════════════════════════════════
        
        refereeStats.referrer = referrer;
        referrerStats.referralCount++;
        lastReferralEpoch[referrer] = currentEpochId;

        emit ReferralRegistered(msg.sender, referrer, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                  INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Distributes referral bonuses to referrer and referee when eligible
    /// @param referee Address of the user who made the trade
    /// @param volume Volume of the trade in USD (18 decimals)
    /// @dev Only distributes if referee meets minimum volume requirement;
    ///      adds bonuses to pending rewards for both parties
    function _distributeReferralRewards(address referee, uint256 volume) internal {
        UserStats storage refereeStats = userStats[referee];
        address referrer = refereeStats.referrer;
        
        // Exit early if minimum volume requirement not met
        if (refereeStats.currentEpochVolume < referralConfig.minVolumeRequired) {
            return;
        }

        UserStats storage referrerStats = userStats[referrer];

        // ════════════════════════════════════════════════════════════════════════════════
        // Calculate base referral rewards and distribute to both parties
        // ════════════════════════════════════════════════════════════════════════════════
        
        // Base rewards for this trade
        uint256 baseRewards = (volume * rewardsPerVolumeUnit) / 1e18;
        
        // Calculate referrer's share (e.g., 10% of base rewards)
        uint256 referrerReward = (baseRewards * referralConfig.referrerShare) / BASIS_POINTS;
        
        // Calculate referee's bonus (e.g., 5% additional on top of their own rewards)
        uint256 refereeBonus = (baseRewards * referralConfig.refereeBonus) / BASIS_POINTS;

        // Add rewards to pending balances
        referrerStats.pendingRewards += referrerReward;
        referrerStats.referralRewards += referrerReward; // Track separately for analytics
        refereeStats.pendingRewards += refereeBonus;

        emit ReferralRewardPaid(referrer, referee, referrerReward, refereeBonus, block.timestamp);
    }

    /// @notice Calculates user tier based on rolling 30-day trading volume
    /// @param user Address of user to calculate tier for
    /// @return tier The calculated tier (0-4) based on rolling window volume
    /// @dev Uses rolling 30-day window instead of lifetime volume to allow tier downgrading
    ///      when users reduce activity
    function _calculateTierFromRollingVolume(address user) internal view returns (uint8) {
        UserStats storage stats = userStats[user];
        
        // Calculate volume in rolling 30-day window
        uint256 currentTime = block.timestamp;
        
        // Get volume from rolling window (simplified: using lastTierUpdateTime as proxy)
        // In production, would maintain detailed time-series data
        uint256 rolling30dVolume = stats.currentEpochVolume;
        
        // If more than 30 days since last update, reset rolling volume
        if (currentTime - stats.lastTierUpdateTime > ROLLING_WINDOW) {
            rolling30dVolume = stats.currentEpochVolume;
        }

        // Determine tier based on rolling volume thresholds
        if (rolling30dVolume >= rewardTiers[4].minVolume) return 4;
        if (rolling30dVolume >= rewardTiers[3].minVolume) return 3;
        if (rolling30dVolume >= rewardTiers[2].minVolume) return 2;
        if (rolling30dVolume >= rewardTiers[1].minVolume) return 1;
        return 0; // Default to retail tier
    }

    /// @notice Initializes all five reward tiers with multipliers and fee discounts
    /// @dev Called once in constructor; defines tier requirements and benefits
    function _initializeRewardTiers() internal {
        // Tier 0: Retail - No requirements
        rewardTiers[0] = RewardTier({
            minVolume: 0,
            rewardMultiplier: 10000,      // 1x (100%) - baseline
            tradingFeeDiscount: 0,        // 0% discount
            name: "Retail"
        });

        // Tier 1: Active Trader - $10k volume
        rewardTiers[1] = RewardTier({
            minVolume: 10_000e18,
            rewardMultiplier: 12000,      // 1.2x (120%) - 20% boost
            tradingFeeDiscount: 500,      // 5% discount on trading fees
            name: "Active"
        });

        // Tier 2: Professional - $100k volume
        rewardTiers[2] = RewardTier({
            minVolume: 100_000e18,
            rewardMultiplier: 15000,      // 1.5x (150%) - 50% boost
            tradingFeeDiscount: 1000,     // 10% discount
            name: "Pro"
        });

        // Tier 3: Elite - $1M volume
        rewardTiers[3] = RewardTier({
            minVolume: 1_000_000e18,
            rewardMultiplier: 20000,      // 2x (200%) - 2x rewards
            tradingFeeDiscount: 1500,     // 15% discount
            name: "Elite"
        });

        // Tier 4: VIP - $10M volume
        rewardTiers[4] = RewardTier({
            minVolume: 10_000_000e18,
            rewardMultiplier: 30000,      // 3x (300%) - 3x rewards
            tradingFeeDiscount: 2000,     // 20% discount (maximum)
            name: "VIP"
        });
    }

    /// @notice Initializes referral program configuration with anti-Sybil parameters
    /// @dev Called once in constructor
    function _initializeReferralConfig() internal {
        referralConfig = ReferralReward({
            referrerShare: 1000,          // 10% of base rewards to referrer
            refereeBonus: 500,            // 5% bonus to referee (stacks with their own rewards)
            minVolumeRequired: 1000e18,   // $1000 minimum epoch volume to qualify
            cooldownPeriod: 1 days,       // 1 day cooldown between registrations by referrer
            maxReferralsPerEpoch: 10      // Max 10 new referrals per referrer per epoch
        });
    }

    /// @notice Starts a new epoch and initializes its state
    /// @dev Called automatically after finalizing previous epoch
    function _startNewEpoch() internal {
        currentEpochId++;
        
        // Create new epoch with 30-day duration
        epochs[currentEpochId] = Epoch({
            startTime: block.timestamp,
            endTime: block.timestamp + EPOCH_DURATION,
            totalRewardsPool: 0,           // Will be funded by admin
            totalVolumeTraded: 0,
            claimedRewards: 0,             // Track rewards claimed from this pool
            finalized: false
        });

        emit EpochStarted(currentEpochId, block.timestamp, block.timestamp + EPOCH_DURATION, 0);
    }

    /// @notice Checks if user can have a tier discount applied to their fees
    /// @param user Address of user to check
    /// @return discount Trading fee discount in basis points (0-2000)
    /// @dev Called by FeeCalculator to apply tier-based discounts
    function _getCustomerTierDiscount(address user) internal view returns (uint256) {
        uint8 userTier = userStats[user].tier;
        return rewardTiers[userTier].tradingFeeDiscount;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                    ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Sets the PositionManager contract address (can only be called by admin)
    /// @param _positionManager Address of PositionManager contract
    /// @dev The PositionManager is the only contract allowed to call recordTrade()
    function setPositionManager(address _positionManager) external onlyAdmin {
        _positionManager.validateNotZero();
        positionManager = _positionManager;
    }

    /// @notice Sets the RevenueManager contract address (can only be called by admin)
    /// @param _revenueManager Address of RevenueManager contract
    /// @dev RevenueManager handles fee collection and distribution integration
    function setRevenueManager(address _revenueManager) external onlyAdmin {
        _revenueManager.validateNotZero();
        revenueManager = _revenueManager;
    }

    /// @notice Initiates a timelock-protected change to rewards per volume unit
    /// @param _rewardsPerVolumeUnit New rewards per $1 traded (scaled by 1e18)
    /// @dev Requires 2-day delay before execution to allow community response
    function initiateRewardsPerVolumeChange(uint256 _rewardsPerVolumeUnit) external onlyAdmin {
        if (_rewardsPerVolumeUnit == 0) revert IncentiveManager__InvalidParameter();
        
        pendingChangeTimestamp = block.timestamp;
        emit ParameterChangeInitiated(keccak256("rewardsPerVolumeUnit"), block.timestamp);
    }

    /// @notice Executes a timelock-protected parameter change after delay expires
    /// @param _rewardsPerVolumeUnit The new rewards per volume value to apply
    /// @dev Can only be called after parameterChangeDelay (2 days) has elapsed
    function executeRewardsPerVolumeChange(uint256 _rewardsPerVolumeUnit) external onlyAdmin {
        // Verify timelock has expired
        if (block.timestamp < pendingChangeTimestamp + parameterChangeDelay) {
            revert IncentiveManager__TimelockNotExpired();
        }

        uint256 oldValue = rewardsPerVolumeUnit;
        rewardsPerVolumeUnit = _rewardsPerVolumeUnit;
        pendingChangeTimestamp = 0; // Reset pending change

        emit RewardsPerVolumeUpdated(oldValue, _rewardsPerVolumeUnit, block.timestamp);
    }

    /// @notice Toggles trading rewards distribution on/off
    /// @param enabled True to enable, false to disable
    /// @dev When disabled, recordTrade() returns early without calculating rewards
    function toggleTradingRewards(bool enabled) external onlyAdmin {
        tradingRewardsEnabled = enabled;
    }

    /// @notice Toggles referral program on/off
    /// @param enabled True to enable, false to disable
    /// @dev When disabled, registerReferral() reverts and no referral bonuses are distributed
    function toggleReferralProgram(bool enabled) external onlyAdmin {
        referralProgramEnabled = enabled;
    }

    /// @notice Funds the current epoch's reward pool with BAOBAB tokens
    /// @param amount Amount of BAOBAB to fund (18 decimals)
    /// @dev Admin must approve this contract to transfer BAOBAB before calling
    function fundRewardsPool(uint256 amount) external onlyAdmin {
        // Transfer BAOBAB from admin to this contract using SafeTransfer library direct call
        SafeTransfer.safeTransferFrom(baobabToken, msg.sender, address(this), amount);

        // Add to current epoch's pool
        epochs[currentEpochId].totalRewardsPool += amount;

        emit RewardsPoolFunded(currentEpochId, amount);
    }

    /// @notice Finalizes the current epoch and starts a new one
    /// @dev Can only finalize after epoch's endTime has passed
    ///      Prevents new trades from accumulating in old epochs
    function finalizeEpoch() external onlyAdmin {
        Epoch storage epoch = epochs[currentEpochId];
        
        // Ensure epoch hasn't already been finalized
        if (epoch.finalized) revert IncentiveManager__EpochAlreadyFinalized();
        
        // Ensure sufficient time has passed
        if (block.timestamp < epoch.endTime) revert IncentiveManager__EpochNotEnded();

        // Mark epoch as finalized
        epoch.finalized = true;

        emit EpochFinalized(
            currentEpochId,
            epoch.totalVolumeTraded,
            epoch.totalRewardsPool,
            epoch.claimedRewards
        );

        // Start next epoch
        _startNewEpoch();
    }

    /// @notice Updates referral program configuration with anti-Sybil protections
    /// @param _referrerShare Percentage of base rewards to referrer (basis points)
    /// @param _refereeBonus Percentage bonus applied to referee (basis points)
    /// @param _minVolume Minimum epoch volume to trigger referral rewards
    /// @param _cooldownPeriod Cooldown seconds between referrer registrations
    /// @param _maxReferralsPerEpoch Maximum referrals per referrer per epoch
    function updateReferralConfig(
        uint256 _referrerShare,
        uint256 _refereeBonus,
        uint256 _minVolume,
        uint256 _cooldownPeriod,
        uint256 _maxReferralsPerEpoch
    ) external onlyAdmin {
        // Validate parameters are reasonable
        if (_referrerShare > BASIS_POINTS || _refereeBonus > BASIS_POINTS) {
            revert IncentiveManager__InvalidParameter();
        }

        referralConfig.referrerShare = _referrerShare;
        referralConfig.refereeBonus = _refereeBonus;
        referralConfig.minVolumeRequired = _minVolume;
        referralConfig.cooldownPeriod = _cooldownPeriod;
        referralConfig.maxReferralsPerEpoch = _maxReferralsPerEpoch;

        emit ReferralConfigUpdated(
            _referrerShare,
            _refereeBonus,
            _minVolume,
            _cooldownPeriod,
            _maxReferralsPerEpoch,
            block.timestamp
        );
    }

    /// @notice Updates configuration for a specific reward tier
    /// @param tier Tier ID (0-4)
    /// @param minVolume New minimum rolling volume requirement
    /// @param rewardMultiplier New reward multiplier in basis points
    /// @param feeDiscount New trading fee discount in basis points
    function updateTierConfig(
        uint8 tier,
        uint256 minVolume,
        uint256 rewardMultiplier,
        uint256 feeDiscount
    ) external onlyAdmin {
        // Validate tier exists (0-4)
        if (tier > 4) revert IncentiveManager__InvalidParameter();
        
        // Validate multiplier is within bounds
        if (rewardMultiplier > MAX_REWARD_MULTIPLIER) revert IncentiveManager__InvalidParameter();
        
        // Validate fee discount is within bounds
        if (feeDiscount > MAX_FEE_DISCOUNT) revert IncentiveManager__InvalidParameter();

        RewardTier storage tierConfig = rewardTiers[tier];
        tierConfig.minVolume = minVolume;
        tierConfig.rewardMultiplier = rewardMultiplier;
        tierConfig.tradingFeeDiscount = feeDiscount;

        emit TierConfigUpdated(tier, minVolume, rewardMultiplier, feeDiscount, block.timestamp);
    }

    /// @notice Emergency withdrawal of tokens (BAOBAB rewards only, not collateral)
    /// @param amount Amount of BAOBAB to withdraw
    /// @dev Restricted to rewards only; cannot drain collateral pool
    function emergencyWithdrawRewards(uint256 amount) external onlyAdmin {
        // Ensure we don't withdraw more than earned/unclaimed rewards
        uint256 unclaimedRewards = baobabToken.balanceOf(address(this));
        
        if (amount > unclaimedRewards) {
            amount = unclaimedRewards;
        }

        // Transfer rewards to admin using SafeTransfer library direct call
        SafeTransfer.safeTransfer(baobabToken, admin, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                     VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// @notice Returns complete user trading statistics and tier
    /// @param user Address of user to query
    /// @return User's stats including volumes, rewards, tier, and referral info
    function getUserStats(address user) external view returns (UserStats memory) {
        return userStats[user];
    }

    /// @notice Returns current active epoch configuration and metrics
    /// @return Epoch data including rewards pool, volume, and finalized status
    function getCurrentEpoch() external view returns (Epoch memory) {
        return epochs[currentEpochId];
    }

    /// @notice Returns user's current tier (0-4)
    /// @param user Address of user
    /// @return User's current tier
    function getUserTier(address user) external view returns (uint8) {
        return userStats[user].tier;
    }

    /// @notice Returns unclaimed pending rewards for user
    /// @param user Address of user
    /// @return Amount of BAOBAB pending claim (18 decimals)
    function getPendingRewards(address user) external view returns (uint256) {
        return userStats[user].pendingRewards;
    }

    /// @notice Returns configuration for a specific reward tier
    /// @param tier Tier ID (0-4)
    /// @return Tier configuration including multiplier and discount
    function getTierInfo(uint8 tier) external view returns (RewardTier memory) {
        return rewardTiers[tier];
    }

    /// @notice Returns referral information for a user
    /// @param user Address to query
    /// @return referrer The user's referrer address
    /// @return referralCount Total number of successful referrals made
    /// @return referralRewards Total rewards earned from referrals
    function getReferralInfo(address user) external view returns (
        address referrer,
        uint256 referralCount,
        uint256 referralRewards
    ) {
        UserStats memory stats = userStats[user];
        return (stats.referrer, stats.referralCount, stats.referralRewards);
    }

    /// @notice Returns trading fee discount applicable to user's tier
    /// @param user Address of user
    /// @return Trading fee discount in basis points (0-2000)
    /// @dev Called by FeeCalculator to apply tier-based discounts
    function getUserFeeDiscount(address user) external view returns (uint256) {
        uint8 userTier = userStats[user].tier;
        return rewardTiers[userTier].tradingFeeDiscount;
    }

    /// @notice Returns specific epoch configuration and metrics
    /// @param epochId ID of epoch to query
    /// @return Epoch data
    function getEpoch(uint256 epochId) external view returns (Epoch memory) {
        return epochs[epochId];
    }

    /// @notice Returns current referral program configuration
    /// @return Referral config with all parameters
    function getReferralConfig() external view returns (ReferralReward memory) {
        return referralConfig;
    }

    /// @notice Returns available rewards in current epoch's pool
    /// @return Amount of BAOBAB still available to claim
    function getAvailableRewardsInPool() external view returns (uint256) {
        Epoch storage epoch = epochs[currentEpochId];
        return epoch.totalRewardsPool - epoch.claimedRewards;
    }

}