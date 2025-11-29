// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SecurityBase} from "../security/SecurityBase.sol";
import {CommonStructs} from "../libraries/structs/CommonStructs.sol";
import {BaobabMath} from "../libraries/utils/BaobabMath.sol";
import {SafeTransfer} from "../libraries/utils/SafeTransfer.sol";
import {EmergencyPauser} from "../security/EmergencyPauser.sol";
import {RoleRegistry} from "../access/RoleRegistry.sol";
import {AccessManager} from "../access/AccessManager.sol";
import {AddressUtils} from "../libraries/utils/AddressUtils.sol";


/**
 * @title FeeDistributor – BAOBAB Protocol Revenue Distribution Engine
 * @notice Production-grade fee distribution with instant settlements, emergency controls,
 *         and comprehensive analytics for protocol sustainability
 * @dev Features:
 *      • Instant fee distribution on every transaction
 *      • Multi-tier emergency controls and circuit breakers
 *      • Comprehensive fee tracking and analytics
 *      • Gas-optimized batch operations
 *      • Maker rebate tracking and settlements
 */
contract FeeDistributor is AccessControl, SecurityBase, EmergencyPauser {
    using SafeERC20 for IERC20;
    using BaobabMath for uint256;
    using AddressUtils for address;
    using CommonStructs for CommonStructs.FeeDistribution;

    AccessManager public accessManager;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       ROLES & CONSTANTS                                        */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY");
    bytes32 public constant EMERGENCY_ADMIN = keccak256("EMERGENCY_ADMIN");

    uint256 public constant MIN_DISTRIBUTION_AMOUNT = 1e6; // $1.00 minimum to prevent dust
    uint256 public constant MAX_FEE_BPS = BaobabMath.BPS; // 100% maximum

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                          STORAGE                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    // Core protocol token
    IERC20 public immutable settlementToken;

    // Current fee distribution configuration
    CommonStructs.FeeDistribution public feeSplit;

    // Recipient addresses
    address public liquidityVault;
    address public insuranceFund;
    address public treasury;
    address public stakingRewards;
    address public burnAddress;

    // Emergency controls
    bool public distributionsPaused;
    address public emergencyTreasury; // Fallback treasury during emergencies

    // Fee tracking and analytics
    uint256 public totalFeesCollected;
    uint256 public totalDistributions;
    uint256 public lastDistributionTime;


    CommonStructs.FeeStats public feeStats;

    // Maker rebate tracking (for negative maker fees)
    mapping(address => uint256) public pendingMakerRebates;
    uint256 public totalPendingRebates;

    // Distribution whitelist (authorized callers)
    mapping(address => bool) public authorizedDistributors;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                           EVENTS                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    event FeesDistributed(
        uint256 indexed distributionId,
        address indexed distributor,
        uint256 totalAmount,
        uint256 lpShare,
        uint256 insuranceShare,
        uint256 treasuryShare,
        uint256 stakerShare,
        uint256 burnShare
    );
    event FeeSplitUpdated(CommonStructs.FeeDistribution newSplit);
    event feeStatsUpdated(CommonStructs.FeeStats newStats);
    event RecipientUpdated(string indexed role, address indexed oldAddress, address indexed newAddress);
    event DistributionPaused(bool paused, address indexed by);
    event EmergencyTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event MakerRebateClaimed(address indexed trader, uint256 amount);
    event AuthorizedDistributorUpdated(address indexed distributor, bool authorized);
    event DistributionFailed(address indexed recipient, uint256 amount, string reason);

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                           ERRORS                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    error InvalidFeeDistribution();
    error DistributionPaused();
    error UnauthorizedDistributor();
    error InsufficientAmount();
    error InvalidRecipientAddress();
    error EmergencyTreasuryNotSet();
    error InvalidEmergencyAddress();
    error DistributionFailedError(address recipient, uint256 amount);

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                         MODIFIERS                                              */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    modifier onlyAuthorizedDistributor() {
        if (!authorizedDistributors[msg.sender] && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert UnauthorizedDistributor();
        }
        _;
    }

    modifier whenDistributionsActive() {
        if (distributionsPaused) revert DistributionPaused();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount < MIN_DISTRIBUTION_AMOUNT) revert InsufficientAmount();
        _;
    }

    modifier validRecipient(address recipient) {
        recipient.validateNotZero();
        // if (recipient == address(0)) revert InvalidRecipientAddress();
        // _;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                        CONSTRUCTOR                                             */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Initialize FeeDistributor with protocol dependencies and default configuration
     * @param _settlementToken Settlement token address (USDC)
     * @param _liquidityVault Liquidity vault for LP rewards
     * @param _insuranceFund Insurance fund for protocol risk coverage
     * @param _treasury Protocol treasury for revenue
     * @param _stakingRewards Staking rewards contract for BAOBAB emissions
     * @param admin Administrator address with default privileges
     */
    constructor(
        address _settlementToken,
        address _liquidityVault,
        address _insuranceFund,
        address _treasury,
        address _stakingRewards,
        address _accessManager,
        address admin
    ) {
        // if (
        //     _settlementToken == address(0) ||
        //     _liquidityVault == address(0) ||
        //     _insuranceFund == address(0) ||
        //     _treasury == address(0) ||
        //     _stakingRewards == address(0) ||
        //     _accessManager == address(0) ||
        //     admin == address(0)
        // ) {
        //     revert InvalidRecipientAddress();
        // }

        _settlementToken.validateNotZero();
        _liquidityVault.validateNotZero();
        _insuranceFund.validateNotZero();
        _treasury.validateNotZero();
        _stakingRewards.validateNotZero();
        _accessManager.validateNotZero();
        admin.validateNotZero();

        settlementToken = IERC20(_settlementToken);
        liquidityVault = _liquidityVault;
        insuranceFund = _insuranceFund;
        treasury = _treasury;
        stakingRewards = _stakingRewards;
        accessmanager = _accessManager(AccessManager);
        burnAddress = 0x000000000000000000000000000000000000dEaD;

        // Initialize role hierarchy
        grantRole(DEFAULT_ADMIN_ROLE, admin);
        grantRole(FEE_MANAGER_ROLE, admin);
        grantRole(TREASURY_ROLE, admin);
        grantRole(EMERGENCY_ADMIN, admin);

        // Authorize core protocol contracts as distributors
        authorizedDistributors[admin] = true;

        // Set default fee distribution (optimized for protocol sustainability)
        feeSplit = CommonStructs.FeeDistribution({
            treasuryBps: 3000,   // 30% - Protocol development & operations
            lpBps: 4000,         // 40% - Liquidity provider incentives
            insuranceBps: 1500,  // 15% - Risk coverage & insurance
            stakersBps: 1200,    // 12% - BAOBAB staking rewards
            burnBps: 300         // 3%  - Deflationary tokenomics
        });

        if (!feeSplit.isValidFeeDistribution()) {
            revert InvalidFeeDistribution();
        }
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                    CORE DISTRIBUTION LOGIC                                     */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Distribute collected fees according to current allocation split
     * @dev Gas-optimized with minimal storage operations and safe transfers
     * @param amount Total fee amount in settlement token decimals
     */
    function distributeFees(uint256 amount)
        external
        nonReentrant
        whenNotEmergencyPaused
        whenDistributionsActive
        onlyAuthorizedDistributor
        validAmount(amount)
    {
        totalFeesCollected += amount;
        totalDistributions++;
        lastDistributionTime = block.timestamp;

        // Calculate distribution amounts with safe math
        uint256 lpShare = amount.applyBps(feeSplit.lpBps);
        uint256 insuranceShare = amount.applyBps(feeSplit.insuranceBps);
        uint256 treasuryShare = amount.applyBps(feeSplit.treasuryBps);
        uint256 stakerShare = amount.applyBps(feeSplit.stakersBps);
        uint256 burnShare = amount.applyBps(feeSplit.burnBps);

        // Validate distribution sum equals original amount (safety check)
        uint256 distributedTotal = lpShare + insuranceShare + treasuryShare + stakerShare + burnShare;
        require(distributedTotal <= amount, "Distribution overflow");

        // Update fee statistics
        feeStats.totalLpFees += lpShare;
        feeStats.totalInsuranceFees += insuranceShare;
        feeStats.totalTreasuryFees += treasuryShare;
        feeStats.totalStakerFees += stakerShare;
        feeStats.totalBurned += burnShare;

        // Execute distributions with error handling
        _distributeToRecipient(liquidityVault, lpShare, "Liquidity Vault");
        _distributeToRecipient(insuranceFund, insuranceShare, "Insurance Fund");
        _distributeToRecipient(treasury, treasuryShare, "Treasury");
        _distributeToRecipient(stakingRewards, stakerShare, "Staking Rewards");
        _distributeToRecipient(burnAddress, burnShare, "Burn Address");

        emit FeesDistributed(
            totalDistributions,
            msg.sender,
            amount,
            lpShare,
            insuranceShare,
            treasuryShare,
            stakerShare,
            burnShare
        );
    }

    /**
     * @notice Batch distribute fees for multiple transactions (gas optimization)
     * @param amounts Array of fee amounts to distribute
     */
    function distributeFeesBatch(uint256[] calldata amounts)
        external
        nonReentrant
        whenNotEmergencyPaused
        whenDistributionsActive
        onlyAuthorizedDistributor
    {
        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] >= MIN_DISTRIBUTION_AMOUNT) {
                totalAmount += amounts[i];
            }
        }

        require(totalAmount > 0, "No valid amounts");
        distributeFees(totalAmount);
    }

    /**
     * @notice Claim pending maker rebates (negative fees)
     * @dev Traders can claim rebates accumulated from maker orders
     */
    function claimMakerRebates() external nonReentrant whenNotEmergencyPaused {
        uint256 rebateAmount = pendingMakerRebates[msg.sender];
        require(rebateAmount > 0, "No rebates available");

        pendingMakerRebates[msg.sender] = 0;
        totalPendingRebates -= rebateAmount;

        _safeTransfer(msg.sender, rebateAmount);
        emit MakerRebateClaimed(msg.sender, rebateAmount);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      ADMIN FUNCTIONS                                           */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Update fee distribution split configuration
     * @param newSplit New fee distribution configuration
     */
    function setFeeSplit(CommonStructs.FeeDistribution calldata newSplit)
        external
        onlyRole(RoleRegistry.FEE_MANAGER_ROLE)
    {
        if (!newSplit.isValidFeeDistribution()) {
            revert InvalidFeeDistribution();
        }
        feeSplit = newSplit;
        emit FeeSplitUpdated(newSplit);
    }

    /**
     * @notice Update liquidity vault recipient address
     * @param newVault New liquidity vault address
     */
    function setLiquidityVault(address newVault)
        external
        onlyRole(RoleRegistry.FEE_MANAGER_ROLE)
        validRecipient(newVault)
    {
        address oldVault = liquidityVault;
        liquidityVault = newVault;
        emit RecipientUpdated("LiquidityVault", oldVault, newVault);
    }

    /**
     * @notice Update insurance fund recipient address
     * @param newFund New insurance fund address
     */
    function setInsuranceFund(address newFund)
        external
        onlyRole(RoleRegistry.FEE_MANAGER_ROLE)
        validRecipient(newFund)
    {
        address oldFund = insuranceFund;
        insuranceFund = newFund;
        emit RecipientUpdated("InsuranceFund", oldFund, newFund);
    }

    /**
     * @notice Update treasury recipient address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury)
        external
        onlyRole(RoleRegistry.TREASURY_ROLE)
        validRecipient(newTreasury)
    {
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit RecipientUpdated("Treasury", oldTreasury, newTreasury);
    }

    /**
     * @notice Update staking rewards contract address
     * @param newContract New staking rewards contract address
     */
    function setStakingRewards(address newContract)
        external
        onlyRole(RoleRegistry.FEE_MANAGER_ROLE)
        validRecipient(newContract)
    {
        address oldContract = stakingRewards;
        stakingRewards = newContract;
        emit RecipientUpdated("StakingRewards", oldContract, newContract);
    }

    /**
     * @notice Set emergency treasury for failover scenarios
     * @param newEmergencyTreasury Emergency treasury address
     */
    function setEmergencyTreasury(address newEmergencyTreasury)
        external
        onlyRole(RoleRegistry.EMERGENCY_ADMIN)
        validRecipient(newEmergencyTreasury)
    {
        address oldEmergencyTreasury = emergencyTreasury;
        emergencyTreasury = newEmergencyTreasury;
        emit EmergencyTreasuryUpdated(oldEmergencyTreasury, newEmergencyTreasury);
    }

    /**
     * @notice Pause/unpause all fee distributions (emergency only)
     * @param paused Whether to pause distributions
     */
    function setDistributionsPaused(bool paused) external onlyRole(RoleRegistry.EMERGENCY_ADMIN || RoleRegistry.PAUSER_ROLE) {
        distributionsPaused = paused;
        emit DistributionPaused(paused, msg.sender);
    }

    /**
     * @notice Authorize/unauthorize fee distributors
     * @param distributor Address to update
     * @param authorized Whether address is authorized
     */
    function setAuthorizedDistributor(address distributor, bool authorized)
        external
        onlyRole(RoleRegistry.FEE_MANAGER_ROLE)
    {
        authorizedDistributors[distributor] = authorized;
        emit AuthorizedDistributorUpdated(distributor, authorized);
    }

    /**
     * @notice Emergency withdrawal to treasury (circuit breaker scenario)
     * @dev Only usable when distributions are paused
     */
    function emergencyWithdraw() external onlyRole(RoleRegistry.EMERGENCY_ADMIN) {
        require(distributionsPaused, "Not in emergency");
        emergencyTreasury.validateNotZero();
        if (emergencyTreasury != address(0)) revert InvalidEmergencyAddress();

        uint256 balance = settlementToken.balanceOf(address(this));
        require(balance > 0, "No funds to withdraw");

        _safeTransfer(emergencyTreasury, balance);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                    INTERNAL FUNCTIONS                                          */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Internal function to distribute funds with comprehensive error handling
     * @param to Recipient address
     * @param amount Distribution amount
     * @param recipientName Human-readable recipient name for error reporting
     */
    function _distributeToRecipient(address to, uint256 amount, string memory recipientName) internal {
        
        if (amount == 0 || to == address(0)) return;

        try settlementToken.safeTransfer(to, amount) {
            // Transfer successful
        } catch {
            // Transfer failed - update statistics and emit event
            feeStats.failedDistributions++;
            emit DistributionFailed(to, amount, "Transfer failed");
            
            // In emergency scenarios, redirect to emergency treasury
            if (distributionsPaused && emergencyTreasury != address(0)) {
                _safeTransfer(emergencyTreasury, amount);
            }
        }
    }

    /**
     * @notice Safe token transfer with zero-address and zero-amount checks
     * @param to Recipient address
     * @param amount Transfer amount
     */
    function _safeTransfer(address to, uint256 amount) internal {
        if (to == address(0) || amount == 0) return;
        settlementToken.safeTransfer(to, amount);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      VIEW FUNCTIONS                                            */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Get current fee distribution configuration
     * @return Current fee split configuration
     */
    function getCurrentSplit() external view returns (CommonStructs.FeeDistribution memory) {
        return feeSplit;
    }

    /**
     * @notice Get comprehensive fee statistics
     * @return All fee distribution statistics
     */
    function getFeeStatistics() external view returns (CommonStructs.FeeStats memory) {
        return feeStats;
    }

    /**
     * @notice Get contract token balance
     * @return Current settlement token balance
     */
    function getContractBalance() external view returns (uint256) {
        return settlementToken.balanceOf(address(this));
    }

    /**
     * @notice Check if address is authorized to distribute fees
     * @param distributor Address to check
     * @return Whether address is authorized
     */
    function isAuthorizedDistributor(address distributor) external view returns (bool) {
        return authorizedDistributors[distributor] || hasRole(RoleRegistry.FEE_MANAGER_ROLE, distributor);
    }

    /**
     * @notice Get pending maker rebates for a trader
     * @param trader Trader address
     * @return Pending rebate amount
     */
    function getPendingMakerRebates(address trader) external view returns (uint256) {
        return pendingMakerRebates[trader];
    }
}