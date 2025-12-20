// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SecurityBase} from "../security/SecurityBase.sol";
import {RoleRegistry} from "../access/RoleRegistry.sol";
import {AccessManager} from "../access/AccessManager.sol";
import {AddressUtils} from "../libraries/utils/AddressUtils.sol";
import {BaobabMath} from "../libraries/utils/BaobabMath.sol";
import {SafeTransfer} from "../libraries/utils/SafeTransfer.sol";
import {CommonStructs} from "../libraries/structs/CommonStructs.sol";
import {EmergencyPauser} from "../security/EmergencyPauser.sol";

/**
 * @title StakingRewards – BAOBAB Protocol Staking & Rewards Distribution
 * @notice Production-grade staking contract with proportional reward distribution,
 *         emergency controls, and comprehensive staker analytics
 * @dev Features:
 *      • Flexible staking/unstaking with cooldown periods
 *      • Proportional USDC reward distribution
 *      • Epoch-based reward finalization
 *      • Emergency withdrawal mechanism
 *      • Comprehensive event tracking and analytics
 */
contract StakingRewards is EmergencyPauser {
    using SafeERC20 for IERC20;
    using BaobabMath for uint256;
    using AddressUtils for *;
    using SafeTransfer for *;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       CORE TOKENS & DEPENDENCIES                                */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    // BAOBAB staking token (what users stake)
    IERC20 public immutable baobabToken;

    // USDC reward token (what FeeDistributor sends)
    IERC20 public immutable rewardToken;

    // Access control
    AccessManager public accessManager;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                          STAKING STORAGE                                        */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    // User staking information
    mapping(address => uint256) public stakedBalance;           // Amount of BAOBAB staked by user
    mapping(address => uint256) public rewardDebt;              // Rewards already claimed by user
    mapping(address => uint256) public lastStakeTime;           // Last time user staked
    mapping(address => uint256) public lastUnstakeTime;         // Last time user unstaked
    mapping(address => uint256) public unstakingAmount;         // Amount pending unstaking (cooldown)
    mapping(address => uint256) public unstakingReleaseTime;    // When unstaking becomes available

    // Total protocol staking
    uint256 public totalStaked;                                 // Total BAOBAB staked by all users
    uint256 public totalRewardsClaimed;                         // Total USDC rewards claimed
    uint256 public totalRewardsAccumulated;                     // Total USDC rewards ever received

    // Reward tracking
    uint256 public accumulatedRewardsPerShare;                  // Cumulative rewards per staked token
    uint256 public constant REWARD_PRECISION = 1e12;            // Precision for reward calculations

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      CONFIGURATION & CONTROL                                    */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    // Staking configuration
    uint256 public unstakingCooldown = 7 days;                  // Cooldown period before unstaking completes
    uint256 public minStakingAmount = 1e18;                     // Minimum 1 BAOBAB to stake
    bool public stakingEnabled = true;

    // Epoch tracking
    uint256 public currentEpoch;
    uint256 public epochStartTime;
    uint256 public epochDuration = 7 days;                      // Weekly reward epochs

    // Emergency controls
    address public emergencyTreasury;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                              EVENTS                                             */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    event Staked(address indexed staker, uint256 amount, uint256 newBalance, uint256 timestamp);
    event UnstakingInitiated(address indexed staker, uint256 amount, uint256 releaseTime);
    event UnstakingCompleted(address indexed staker, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed staker, uint256 rewardAmount, uint256 newRewardDebt);
    event RewardsDistributed(uint256 epoch, uint256 totalRewards, uint256 rewardPerShare);
    event EpochFinalized(uint256 epoch, uint256 totalRewards, uint256 newAccumulatedRewards);
    event StakingConfigUpdated(string indexed param, uint256 oldValue, uint256 newValue);
    event StakingEnabled(bool enabled);
    event EmergencyWithdrawal(address indexed user, uint256 stakedAmount, uint256 unstakedAmount);
    event EmergencyTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                              ERRORS                                             */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    error StakingDisabled();
    error InsufficientStakeAmount();
    error NoStakedBalance();
    error UnstakingNotReady();
    error NoUnstakingInitiated();
    error InsufficientRewards();
    error InvalidCooldownPeriod();
    error InvalidEpochDuration();
    error EmergencyTreasuryNotSet();
    error InvalidEmergencyAddress();
    error TransferFailed();
    error NoRewardsAccumulated();

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                            MODIFIERS                                            */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    modifier onlyRole(bytes32 role) {
        require(accessManager.hasRole(role, msg.sender), "Unauthorized");
        _;
    }

    modifier whenStakingActive() {
        if (!stakingEnabled) revert StakingDisabled();
        _;
    }

    modifier validStakeAmount(uint256 amount) {
        if (amount < minStakingAmount) revert InsufficientStakeAmount();
        _;
    }

    modifier hasStake(address user) {
        if (stakedBalance[user] == 0) revert NoStakedBalance();
        _;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                          CONSTRUCTOR                                            */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Initialize StakingRewards contract with token dependencies
     * @param _baobabToken BAOBAB token address (what users stake)
     * @param _rewardToken USDC reward token address
     * @param _accessManager AccessManager for role-based control
     * @param admin Admin address with initial privileges
     * @param multisig Multisig for emergency controls
     */
    constructor(
        address _baobabToken,
        address _rewardToken,
        address _accessManager,
        address admin,
        address multisig
    ) EmergencyPauser(admin, multisig) {
        _baobabToken.validateContract();
        _rewardToken.validateContract();
        _accessManager.validateContract();
        admin.validateNotZero();
        multisig.validateNotZero();

        baobabToken = IERC20(_baobabToken);
        rewardToken = IERC20(_rewardToken);
        accessManager = AccessManager(_accessManager);

        epochStartTime = block.timestamp;
        currentEpoch = 1;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      CORE STAKING FUNCTIONS                                     */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Stake BAOBAB tokens to earn proportional USDC rewards
     * @param amount Amount of BAOBAB to stake
     * @dev User must approve StakingRewards contract to spend BAOBAB first
     */
    function stake(uint256 amount)
        external
        nonReentrant
        whenProtocolNotPaused
        whenStakingActive
        validStakeAmount(amount)
    {
        // Calculate and claim any pending rewards first
        uint256 pendingReward = _calculatePendingReward(msg.sender);
        if (pendingReward > 0) {
            rewardDebt[msg.sender] += pendingReward;
        }

        // Transfer BAOBAB from user to this contract
        SafeTransfer.safeTransferFrom(baobabToken, msg.sender, address(this), amount);

        // Update staking state
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
        lastStakeTime[msg.sender] = block.timestamp;

        emit Staked(msg.sender, amount, stakedBalance[msg.sender], block.timestamp);
    }

    /**
     * @notice Initiate unstaking process (enters cooldown period)
     * @param amount Amount of BAOBAB to unstake
     * @dev Must wait `unstakingCooldown` period before completing unstaking
     */
    function initiateUnstaking(uint256 amount)
        external
        nonReentrant
        whenProtocolNotPaused
        hasStake(msg.sender)
    {
        require(amount > 0, "Amount must be > 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked balance");

        // Claim any pending rewards before unstaking
        uint256 pendingReward = _calculatePendingReward(msg.sender);
        if (pendingReward > 0) {
            rewardDebt[msg.sender] += pendingReward;
        }

        // Set up unstaking (cooldown period)
        unstakingAmount[msg.sender] = amount;
        unstakingReleaseTime[msg.sender] = block.timestamp + unstakingCooldown;
        lastUnstakeTime[msg.sender] = block.timestamp;

        // Reduce staked balance immediately
        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        emit UnstakingInitiated(msg.sender, amount, unstakingReleaseTime[msg.sender]);
    }

    /**
     * @notice Complete unstaking and withdraw BAOBAB after cooldown
     * @dev Can only be called after `unstakingCooldown` period has passed
     */
    function completeUnstaking()
        external
        nonReentrant
        whenProtocolNotPaused
    {
        uint256 amount = unstakingAmount[msg.sender];
        if (amount == 0) revert NoUnstakingInitiated();
        if (block.timestamp < unstakingReleaseTime[msg.sender]) revert UnstakingNotReady();

        // Clear unstaking state
        unstakingAmount[msg.sender] = 0;
        unstakingReleaseTime[msg.sender] = 0;

        // Transfer BAOBAB back to user
        SafeTransfer.safeTransfer(baobabToken, msg.sender, amount);

        emit UnstakingCompleted(msg.sender, amount, block.timestamp);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                    REWARD CLAIM & DISTRIBUTION                                  */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Claim accumulated USDC rewards
     * @dev Rewards distributed proportionally based on staked amount and time
     */
    function claimRewards()
        external
        nonReentrant
        whenProtocolNotPaused
    {
        uint256 pendingReward = _calculatePendingReward(msg.sender);
        if (pendingReward == 0) revert NoRewardsAccumulated();

        // Update reward debt
        rewardDebt[msg.sender] += pendingReward;
        totalRewardsClaimed += pendingReward;

        // Transfer USDC rewards to user
        SafeTransfer.safeTransfer(rewardToken, msg.sender, pendingReward);

        emit RewardsClaimed(msg.sender, pendingReward, rewardDebt[msg.sender]);
    }

    /**
     * @notice FeeDistributor calls this to distribute USDC rewards to all stakers
     * @dev Updates accumulated rewards per share for proportional distribution
     */
    function distributeRewards()
        external
        nonReentrant
        whenProtocolNotPaused
        onlyRole(RoleRegistry.FEE_DISTRIBTOR_ROLE)
    {
        uint256 rewardAmount = rewardToken.balanceOf(address(this)) - (totalRewardsAccumulated - totalRewardsClaimed);
        if (rewardAmount == 0) revert NoRewardsAccumulated();
        if (totalStaked == 0) {
            // No stakers - send rewards to treasury or emergency address
            SafeTransfer.safeTransfer(rewardToken, emergencyTreasury, rewardAmount);
            return;
        }

        // Calculate new rewards per share
        uint256 newRewardsPerShare = (rewardAmount * REWARD_PRECISION) / totalStaked;
        accumulatedRewardsPerShare += newRewardsPerShare;

        totalRewardsAccumulated += rewardAmount;

        emit RewardsDistributed(currentEpoch, rewardAmount, accumulatedRewardsPerShare);
    }

    /**
     * @notice Finalize current epoch and prepare for next epoch
     * @dev Moves to next weekly epoch for better reward tracking
     */
    function finalizeEpoch()
        external
        onlyRole(RoleRegistry.FEE_MANAGER_ROLE)
    {
        emit EpochFinalized(currentEpoch, totalRewardsAccumulated - totalRewardsClaimed, accumulatedRewardsPerShare);

        // Move to next epoch
        currentEpoch++;
        epochStartTime = block.timestamp;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      ADMIN CONFIGURATION                                        */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Set unstaking cooldown period
     * @param _cooldownPeriod New cooldown period in seconds (min 1 day, max 30 days)
     */
    function setUnstakingCooldown(uint256 _cooldownPeriod)
        external
        onlyRole(RoleRegistry.ADMIN_ROLE)
    {
        require(_cooldownPeriod >= 1 days && _cooldownPeriod <= 30 days, "Invalid cooldown");
        uint256 oldValue = unstakingCooldown;
        unstakingCooldown = _cooldownPeriod;
        emit StakingConfigUpdated("UnstakingCooldown", oldValue, _cooldownPeriod);
    }

    /**
     * @notice Set minimum staking amount
     * @param _minAmount Minimum BAOBAB amount to stake
     */
    function setMinStakingAmount(uint256 _minAmount)
        external
        onlyRole(RoleRegistry.ADMIN_ROLE)
    {
        require(_minAmount > 0, "Min amount must be > 0");
        uint256 oldValue = minStakingAmount;
        minStakingAmount = _minAmount;
        emit StakingConfigUpdated("MinStakingAmount", oldValue, _minAmount);
    }

    /**
     * @notice Enable or disable staking
     * @param enabled Whether staking is enabled
     */
    function setStakingEnabled(bool enabled)
        external
        onlyRole(RoleRegistry.ADMIN_ROLE)
    {
        stakingEnabled = enabled;
        emit StakingEnabled(enabled);
    }

    /**
     * @notice Set epoch duration
     * @param _duration New epoch duration in seconds (min 1 day, max 30 days)
     */
    function setEpochDuration(uint256 _duration)
        external
        onlyRole(RoleRegistry.ADMIN_ROLE)
    {
        require(_duration >= 1 days && _duration <= 30 days, "Invalid duration");
        uint256 oldValue = epochDuration;
        epochDuration = _duration;
        emit StakingConfigUpdated("EpochDuration", oldValue, _duration);
    }

    /**
     * @notice Set emergency treasury for reward distribution fallback
     * @param _emergencyTreasury Emergency treasury address
     */
    function setEmergencyTreasury(address _emergencyTreasury)
        external
        onlyRole(RoleRegistry.EMERGENCY_ADMIN)
    {
        _emergencyTreasury.validateNotZero();
        address oldTreasury = emergencyTreasury;
        emergencyTreasury = _emergencyTreasury;
        emit EmergencyTreasuryUpdated(oldTreasury, _emergencyTreasury);
    }

    /**
     * @notice Emergency withdrawal (only when protocol is paused)
     * @dev Allows users to withdraw staked tokens during emergencies
     */
    function emergencyWithdraw()
        external
        nonReentrant
         whenProtocolNotPaused
    {
        uint256 stakedAmount = stakedBalance[msg.sender];
        uint256 unstakedAmount = unstakingAmount[msg.sender];

        require(stakedAmount > 0 || unstakedAmount > 0, "Nothing to withdraw");

        // Clear balances
        if (stakedAmount > 0) {
            totalStaked -= stakedAmount;
            stakedBalance[msg.sender] = 0;
        }
        if (unstakedAmount > 0) {
            unstakingAmount[msg.sender] = 0;
            unstakingReleaseTime[msg.sender] = 0;
        }

        // Transfer both staked and unstaking amounts
        uint256 totalWithdraw = stakedAmount + unstakedAmount;
        SafeTransfer.safeTransfer(baobabToken, msg.sender, totalWithdraw);

        emit EmergencyWithdrawal(msg.sender, stakedAmount, unstakedAmount);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                        INTERNAL FUNCTIONS                                       */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Calculate pending USDC rewards for a staker
     * @param staker Staker address
     * @return Pending reward amount in USDC
     */
    function _calculatePendingReward(address staker) internal view returns (uint256) {
        uint256 userShare = (stakedBalance[staker] * accumulatedRewardsPerShare) / REWARD_PRECISION;
        uint256 pending = userShare - rewardDebt[staker];
        return pending;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                         VIEW FUNCTIONS                                          */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Get pending rewards for a staker
     * @param staker Staker address
     * @return Pending USDC reward amount
     */
    function getPendingRewards(address staker) external view returns (uint256) {
        return _calculatePendingReward(staker);
    }

/**
 * @notice Get staking information for a specific user
 * @param staker Address of the staker to query
 * @return staked Amount of BAOBAB tokens currently staked by the user
 * @return pending Amount of USDC rewards pending claim by the user
 * @return unstaking Amount of BAOBAB tokens currently in the unstaking process
 * @return releaseTime Timestamp when unstaked tokens become available for withdrawal
 */
function getStakerInfo(address staker)
    external
    view
    returns (uint256 staked, uint256 pending, uint256 unstaking, uint256 releaseTime)
{
    staked = stakedBalance[staker];
    pending = _calculatePendingReward(staker);
    unstaking = unstakingAmount[staker];
    releaseTime = unstakingReleaseTime[staker];
}

/**
 * @notice Get protocol-wide staking statistics
 * @return total Total amount of BAOBAB tokens staked across all users
 * @return claimed Total amount of USDC rewards claimed by all users
 * @return accumulated Total amount of USDC rewards accumulated for distribution
 * @return apy Current Annual Percentage Yield (APY) for stakers, scaled by 100 (e.g., 500 = 5% APY)
 */
function getProtocolStats()
    external
    view
    returns (uint256 total, uint256 claimed, uint256 accumulated, uint256 apy)
{
    total = totalStaked;
    claimed = totalRewardsClaimed;
    accumulated = totalRewardsAccumulated;
    
    // Calculate APY: (annual rewards / total staked) * 100
    // APY returned as percentage scaled by 100 (e.g., 500 = 5%)
    if (totalStaked > 0) {
        uint256 weeklyRewards = totalRewardsAccumulated / 52;
        apy = (weeklyRewards * 52 * 100) / totalStaked;
    }
}

    /**
     * @notice Check if user is currently unstaking
     * @param user User address
     * @return isUnstaking True if user has pending unstaking
     * @return timeRemaining Seconds until unstaking completes
     */
    function getUnstakingStatus(address user)
        external
        view
        returns (bool isUnstaking, uint256 timeRemaining)
    {
        isUnstaking = unstakingAmount[user] > 0;
        if (isUnstaking && block.timestamp < unstakingReleaseTime[user]) {
            timeRemaining = unstakingReleaseTime[user] - block.timestamp;
        }
    }

    /**
     * @notice Get contract USDC balance (rewards available to distribute)
     * @return USDC balance in contract
     */
    function getRewardBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
}
