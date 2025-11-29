// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CommonStructs} from "../../libraries/CommonStructs.sol";

/**
 * @title FeeDistributor – BAOBAB Revenue Distribution Engine
 * @notice Distributes all collected fees instantly to:
 *         → Liquidity Providers (LPs)
 *         → Insurance Fund
 *         → Treasury
 *         → BAOBAB Stakers (via emissions)
 *         → Token Burn (optional)
 * @dev Called after every trade, liquidation, borrow repayment
 */
contract FeeDistributor is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using CommonStructs for CommonStructs.FeeDistribution;

    /*═════════════════════════════════════  ROLES  ═════════════════════════════════════*/
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY");

    /*═════════════════════════════════════  STATE  ═════════════════════════════════════*/
    IERC20 public immutable settlementToken; // USDC on Arbitrum

    // Current fee split configuration
    CommonStructs.FeeDistribution public feeSplit;

    // Recipients
    address public liquidityVault;     // Receives LP share
    address public insuranceFund;      // Insurance against bad debt
    address public treasury;           // Protocol revenue
    address public stakingRewards;     // BAOBAB staking contract
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    // Track accumulated fees (for UI/analytics)
    uint256 public totalFeesCollected;
    uint256 public totalLpFees;
    uint256 public totalInsuranceFees;
    uint256 public totalTreasuryFees;
    uint256 public totalStakerFees;
    uint256 public totalBurned;

    /*═════════════════════════════════════  EVENTS  ═════════════════════════════════════*/
    event FeesDistributed(
        uint256 total,
        uint256 lpShare,
        uint256 insuranceShare,
        uint256 treasuryShare,
        uint256 stakerShare,
        uint256 burnShare
    );
    event FeeSplitUpdated(
        uint16 treasuryBps,
        uint16 lpBps,
        uint16 insuranceBps,
        uint16 stakersBps,
        uint16 burnBps
    );
    event RecipientUpdated(string indexed role, address indexed newAddress);

    /*═════════════════════════════════════  CONSTRUCTOR  ═════════════════════════════════════*/
    constructor(
        address _settlementToken,
        address _liquidityVault,
        address _insuranceFund,
        address _treasury,
        address _stakingRewards,
        address admin
    ) {
        settlementToken = IERC20(_settlementToken);

        liquidityVault = _liquidityVault;
        insuranceFund = _insuranceFund;
        treasury = _treasury;
        stakingRewards = _stakingRewards;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);

        // Mainnet default split (as of Dec 2025)
        feeSplit = CommonStructs.FeeDistribution({
            treasuryBps: 3000,   // 30%
            lpBps: 4000,         // 40% ← rewards deep liquidity
            insuranceBps: 1500,  // 15%
            stakersBps: 1200,    // 12%
            burnBps: 300         // 3% → deflationary
        });

        require(feeSplit.isValidFeeDistribution(), "Invalid split");
    }

    /*═════════════════════════════════════  CORE FUNCTION  ═════════════════════════════════════*/
    /**
     * @notice Distribute collected fees according to current split
     * @param amount Total fee amount in settlement token (e.g., USDC)
     */
    function distributeFees(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        totalFeesCollected += amount;

        uint256 lpShare = (amount * feeSplit.lpBps) / 10_000;
        uint256 insuranceShare = (amount * feeSplit.insuranceBps) / 10_000;
        uint256 treasuryShare = (amount * feeSplit.treasuryBps) / 10_000;
        uint256 stakerShare = (amount * feeSplit.stakersBps) / 10_000;
        uint256 burnShare = (amount * feeSplit.burnBps) / 10_000;

        // Update trackers
        totalLpFees += lpShare;
        totalInsuranceFees += insuranceShare;
        totalTreasuryFees += treasuryShare;
        totalStakerFees += stakerShare;
        totalBurned += burnShare;

        // Distribute
        if (lpShare > 0) _safeTransfer(liquidityVault, lpShare);
        if (insuranceShare > 0) _safeTransfer(insuranceFund, insuranceShare);
        if (treasuryShare > 0) _safeTransfer(treasury, treasuryShare);
        if (stakerShare > 0) _safeTransfer(stakingRewards, stakerShare);
        if (burnShare > 0) _safeTransfer(burnAddress, burnShare);

        emit FeesDistributed(amount, lpShare, insuranceShare, treasuryShare, stakerShare, burnShare);
    }

    /*═════════════════════════════════════  ADMIN FUNCTIONS  ═════════════════════════════════════*/
    function setFeeSplit(CommonStructs.FeeDistribution calldata newSplit)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        require(newSplit.isValidFeeDistribution(), "Invalid distribution");
        feeSplit = newSplit;
        emit FeeSplitUpdated(
            newSplit.treasuryBps,
            newSplit.lpBps,
            newSplit.insuranceBps,
            newSplit.stakersBps,
            newSplit.burnBps
        );
    }

    function setLiquidityVault(address newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        liquidityVault = newVault;
        emit RecipientUpdated("LiquidityVault", newVault);
    }

    function setInsuranceFund(address newFund) external onlyRole(DEFAULT_ADMIN_ROLE) {
        insuranceFund = newFund;
        emit RecipientUpdated("InsuranceFund", newFund);
    }

    function setTreasury(address newTreasury) external onlyRole(TREASURY_ROLE) {
        treasury = newTreasury;
        emit RecipientUpdated("Treasury", newTreasury);
    }

    function setStakingRewards(address newContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakingRewards = newContract;
        emit RecipientUpdated("StakingRewards", newContract);
    }

    /*═════════════════════════════════════  INTERNAL  ═════════════════════════════════════*/
    function _safeTransfer(address to, uint256 amount) internal {
        if (to == address(0) || amount == 0) return;
        settlementToken.safeTransfer(to, amount);
    }

    /*═════════════════════════════════════  VIEW HELPERS  ═════════════════════════════════════*/
    function getCurrentSplit() external view returns (CommonStructs.FeeDistribution memory) {
        return feeSplit;
    }

    function pendingMakerRebates() external view returns (uint256) {
        // Future feature: track unpaid rebates from negative maker fees
        return 0;
    }
}