// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title IncentiveManager
 * @notice Manages all reward programs and user incentives for BAOBAB Protocol
 * @dev Tracks trading volume, distributes rewards, manages referral program
 */
contract IncentiveManager is ReentrancyGuard {

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                       STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct UserStats {
        uint256 totalVolumeTraded;       // Lifetime trading volume
        uint256 currentEpochVolume;      // Volume in current epoch
        uint256 lastTradeTimestamp;      // Last trade time
        uint256 totalRewardsEarned;      // Total rewards claimed
        uint256 pendingRewards;          // Unclaimed rewards
        address referrer;                // Who referred this user
        uint256 referralCount;           // How many users referred
        uint256 referralRewards;         // Rewards from referrals
        uint8 tier;                      // User tier (0-4)
    }

    struct RewardTier {
        uint256 minVolume;               // Min volume for this tier
        uint256 rewardMultiplier;        // Reward boost (basis points)
        uint256 tradingFeeDiscount;      // Fee discount (basis points)
        string name;                     // Tier name
    }

    struct Epoch {
        uint256 startTime;               // Epoch start
        uint256 endTime;                 // Epoch end
        uint256 totalRewardsPool;        // Total rewards for epoch
        uint256 totalVolumeTraded;       // Total volume in epoch
        bool finalized;                  // Epoch closed
    }

    struct ReferralReward {
        uint256 referrerShare;           // % to referrer (basis points)
        uint256 refereeBonus;            // % bonus to referee (basis points)
        uint256 minVolumeRequired;       // Min volume to qualify
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                    STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    IERC20 public immutable baobabToken;
    IERC20 public immutable collateralToken;

    address public admin;
    address public positionManager;
    address public revenueManager;

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant EPOCH_DURATION = 30 days;

    uint256 public currentEpochId;
    uint256 public totalRewardsDistributed;
    uint256 public rewardsPerVolumeUnit;        // Rewards per $1 traded (scaled by 1e18)

    mapping(address => UserStats) public userStats;
    mapping(uint256 => Epoch) public epochs;
    mapping(uint8 => RewardTier) public rewardTiers;
    
    ReferralReward public referralConfig;

    bool public tradingRewardsEnabled;
    bool public referralProgramEnabled;
    bool public liquidityMiningEnabled;

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                         EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event TradeRecorded(
        address indexed user,
        uint256 volume,
        uint256 rewardsEarned,
        uint256 timestamp
    );

    event RewardsClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event ReferralRegistered(
        address indexed referee,
        address indexed referrer,
        uint256 timestamp
    );

    event ReferralRewardPaid(
        address indexed referrer,
        address indexed referee,
        uint256 amount,
        uint256 timestamp
    );

    event TierUpgraded(
        address indexed user,
        uint8 oldTier,
        uint8 newTier,
        uint256 timestamp
    );

    event EpochStarted(
        uint256 indexed epochId,
        uint256 startTime,
        uint256 rewardsPool
    );

    event EpochFinalized(
        uint256 indexed epochId,
        uint256 totalVolume,
        uint256 totalRewards
    );

    event RewardsPoolFunded(
        uint256 indexed epochId,
        uint256 amount
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                         ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════

    error IncentiveManager__OnlyAdmin();
    error IncentiveManager__OnlyPositionManager();
    error IncentiveManager__NoRewardsToClaim();
    error IncentiveManager__InvalidReferrer();
    error IncentiveManager__AlreadyReferred();
    error IncentiveManager__InsufficientRewardsPool();
    error IncentiveManager__EpochNotFinalized();
    error IncentiveManager__ProgramDisabled();

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                       CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(
        address _baobabToken,
        address _collateralToken,
        address _admin
    ) {
        require(_baobabToken != address(0), "Invalid token");
        require(_collateralToken != address(0), "Invalid collateral");
        require(_admin != address(0), "Invalid admin");

        baobabToken = IERC20(_baobabToken);
        collateralToken = IERC20(_collateralToken);
        admin = _admin;

        _initializeRewardTiers();
        _initializeReferralConfig();
        _startNewEpoch();
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                        MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    modifier onlyAdmin() {
        if (msg.sender != admin) revert IncentiveManager__OnlyAdmin();
        _;
    }

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert IncentiveManager__OnlyPositionManager();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                   CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record a trade and calculate rewards
     * @param user Trader address
     * @param volumeTraded Trade volume in USD (18 decimals)
     */
    function recordTrade(address user, uint256 volumeTraded) 
        external 
        onlyPositionManager 
    {
        if (!tradingRewardsEnabled) return;

        UserStats storage stats = userStats[user];
        Epoch storage epoch = epochs[currentEpochId];

        // Update volumes
        stats.totalVolumeTraded += volumeTraded;
        stats.currentEpochVolume += volumeTraded;
        stats.lastTradeTimestamp = block.timestamp;

        epoch.totalVolumeTraded += volumeTraded;

        // Check for tier upgrade
        uint8 newTier = _calculateTier(stats.totalVolumeTraded);
        if (newTier > stats.tier) {
            emit TierUpgraded(user, stats.tier, newTier, block.timestamp);
            stats.tier = newTier;
        }

        // Calculate rewards
        uint256 baseRewards = (volumeTraded * rewardsPerVolumeUnit) / 1e18;
        uint256 multiplier = rewardTiers[stats.tier].rewardMultiplier;
        uint256 totalRewards = (baseRewards * multiplier) / BASIS_POINTS;

        // Add rewards to pending
        stats.pendingRewards += totalRewards;
        stats.totalRewardsEarned += totalRewards;

        // Handle referral rewards
        if (referralProgramEnabled && stats.referrer != address(0)) {
            _distributeReferralRewards(user, volumeTraded);
        }

        emit TradeRecorded(user, volumeTraded, totalRewards, block.timestamp);
    }

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external nonReentrant {
        UserStats storage stats = userStats[msg.sender];
        
        if (stats.pendingRewards == 0) revert IncentiveManager__NoRewardsToClaim();

        uint256 rewards = stats.pendingRewards;
        stats.pendingRewards = 0;

        // Transfer BAOBAB tokens
        require(
            baobabToken.transfer(msg.sender, rewards),
            "Transfer failed"
        );

        totalRewardsDistributed += rewards;

        emit RewardsClaimed(msg.sender, rewards, block.timestamp);
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

        // Set referrer
        refereeStats.referrer = referrer;
        
        // Update referrer stats
        UserStats storage referrerStats = userStats[referrer];
        referrerStats.referralCount++;

        emit ReferralRegistered(msg.sender, referrer, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                  INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _distributeReferralRewards(address referee, uint256 volume) internal {
        UserStats storage refereeStats = userStats[referee];
        address referrer = refereeStats.referrer;
        
        // Check minimum volume
        if (refereeStats.currentEpochVolume < referralConfig.minVolumeRequired) {
            return;
        }

        UserStats storage referrerStats = userStats[referrer];

        // Calculate referral rewards
        uint256 baseRewards = (volume * rewardsPerVolumeUnit) / 1e18;
        uint256 referrerReward = (baseRewards * referralConfig.referrerShare) / BASIS_POINTS;
        uint256 refereeBonus = (baseRewards * referralConfig.refereeBonus) / BASIS_POINTS;

        // Add to pending
        referrerStats.pendingRewards += referrerReward;
        referrerStats.referralRewards += referrerReward;
        refereeStats.pendingRewards += refereeBonus;

        emit ReferralRewardPaid(referrer, referee, referrerReward, block.timestamp);
    }

    function _calculateTier(uint256 totalVolume) internal view returns (uint8) {
        // Tier 4: $10M+
        if (totalVolume >= 10_000_000e18) return 4;
        // Tier 3: $1M+
        if (totalVolume >= 1_000_000e18) return 3;
        // Tier 2: $100k+
        if (totalVolume >= 100_000e18) return 2;
        // Tier 1: $10k+
        if (totalVolume >= 10_000e18) return 1;
        // Tier 0: Everyone else
        return 0;
    }

    function _initializeRewardTiers() internal {
        // Tier 0: Retail
        rewardTiers[0] = RewardTier({
            minVolume: 0,
            rewardMultiplier: 10000,      // 1x (100%)
            tradingFeeDiscount: 0,        // 0% discount
            name: "Retail"
        });

        // Tier 1: Active
        rewardTiers[1] = RewardTier({
            minVolume: 10_000e18,
            rewardMultiplier: 12000,      // 1.2x (120%)
            tradingFeeDiscount: 500,      // 5% discount
            name: "Active"
        });

        // Tier 2: Pro
        rewardTiers[2] = RewardTier({
            minVolume: 100_000e18,
            rewardMultiplier: 15000,      // 1.5x (150%)
            tradingFeeDiscount: 1000,     // 10% discount
            name: "Pro"
        });

        // Tier 3: Elite
        rewardTiers[3] = RewardTier({
            minVolume: 1_000_000e18,
            rewardMultiplier: 20000,      // 2x (200%)
            tradingFeeDiscount: 1500,     // 15% discount
            name: "Elite"
        });

        // Tier 4: VIP
        rewardTiers[4] = RewardTier({
            minVolume: 10_000_000e18,
            rewardMultiplier: 30000,      // 3x (300%)
            tradingFeeDiscount: 2000,     // 20% discount
            name: "VIP"
        });
    }

    function _initializeReferralConfig() internal {
        referralConfig = ReferralReward({
            referrerShare: 1000,          // 10% of rewards to referrer
            refereeBonus: 500,            // 5% bonus to referee
            minVolumeRequired: 1000e18    // $1000 min volume
        });
    }

    function _startNewEpoch() internal {
        currentEpochId++;
        
        epochs[currentEpochId] = Epoch({
            startTime: block.timestamp,
            endTime: block.timestamp + EPOCH_DURATION,
            totalRewardsPool: 0,
            totalVolumeTraded: 0,
            finalized: false
        });

        emit EpochStarted(currentEpochId, block.timestamp, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                    ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function setPositionManager(address _positionManager) external onlyAdmin {
        require(_positionManager != address(0), "Invalid address");
        positionManager = _positionManager;
    }

    function setRevenueManager(address _revenueManager) external onlyAdmin {
        require(_revenueManager != address(0), "Invalid address");
        revenueManager = _revenueManager;
    }

    function setRewardsPerVolumeUnit(uint256 _rewardsPerVolumeUnit) external onlyAdmin {
        rewardsPerVolumeUnit = _rewardsPerVolumeUnit;
    }

    function toggleTradingRewards(bool enabled) external onlyAdmin {
        tradingRewardsEnabled = enabled;
    }

    function toggleReferralProgram(bool enabled) external onlyAdmin {
        referralProgramEnabled = enabled;
    }

    function fundRewardsPool(uint256 amount) external onlyAdmin {
        require(
            baobabToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        epochs[currentEpochId].totalRewardsPool += amount;

        emit RewardsPoolFunded(currentEpochId, amount);
    }

    function finalizeEpoch() external onlyAdmin {
        Epoch storage epoch = epochs[currentEpochId];
        require(!epoch.finalized, "Already finalized");
        require(block.timestamp >= epoch.endTime, "Epoch not ended");

        epoch.finalized = true;

        emit EpochFinalized(
            currentEpochId,
            epoch.totalVolumeTraded,
            epoch.totalRewardsPool
        );

        _startNewEpoch();
    }

    function updateReferralConfig(
        uint256 _referrerShare,
        uint256 _refereeBonus,
        uint256 _minVolume
    ) external onlyAdmin {
        referralConfig.referrerShare = _referrerShare;
        referralConfig.refereeBonus = _refereeBonus;
        referralConfig.minVolumeRequired = _minVolume;
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyAdmin {
        IERC20(token).transfer(admin, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                     VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function getUserStats(address user) external view returns (UserStats memory) {
        return userStats[user];
    }

    function getCurrentEpoch() external view returns (Epoch memory) {
        return epochs[currentEpochId];
    }

    function getUserTier(address user) external view returns (uint8) {
        return userStats[user].tier;
    }

    function getPendingRewards(address user) external view returns (uint256) {
        return userStats[user].pendingRewards;
    }

    function getTierInfo(uint8 tier) external view returns (RewardTier memory) {
        return rewardTiers[tier];
    }

    function getReferralInfo(address user) external view returns (
        address referrer,
        uint256 referralCount,
        uint256 referralRewards
    ) {
        UserStats memory stats = userStats[user];
        return (stats.referrer, stats.referralCount, stats.referralRewards);
    }
}