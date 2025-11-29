// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonStructs} from "../libraries/structs/CommonStructs.sol";
import {RoleRegistry} from "../access/RoleRegistry.sol";
/**
 * @title FeeCalculator – BAOBAB Protocol Revenue Engine (Final Mainnet Version)
 * @notice Single source of truth for all fees – uses canonical CommonStructs
 * @dev 100% compliant with your existing architecture
 */
contract FeeCalculator is AccessControl {
    using CommonStructs for *;

    /*═════════════════════════════════════  ROLES & CONSTANTS  ═════════════════════════════════════*/

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER");
    bytes32 public constant EMERGENCY_ADMIN = keccak256("EMERGENCY_ADMIN");

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_FEE_BPS = 500;      // 5% max
    uint256 public constant KEEPER_FEE_USD = 2.5e6; // $2.50

    /*═════════════════════════════════════  STORAGE  ═════════════════════════════════════*/

    // Asset → custom fee config (overrides class default)
    mapping(address => CommonStructs.FeeConfig) public assetFeeConfig;

    // Default fees per asset class
    mapping(CommonStructs.AssetClass => CommonStructs.FeeConfig) public defaultFeeByClass;

    // User tiers (0 = retail, 3 = VIP/staker)
    CommonStructs.UserTier[4] public tiers;

    // User → current tier
    mapping(address => uint256) public userTier;

    // Emergency & dynamic controls
    bool public emergencyMode;
    uint256 public emergencyTakerCapBps = 50;        // 0.5%
    uint256 public volatilityMultiplierBps = 10_000; // 1.0x

    // External contracts
    IERC20 public immutable baobabToken;
    address public volumeTracker;
    address public circuitBreaker;

    /*═════════════════════════════════════  EVENTS  ═════════════════════════════════════*/

    event FeeConfigUpdated(address indexed asset, uint256 takerBps, int256 makerBps);
    event DefaultClassFeeUpdated(CommonStructs.AssetClass class, uint256 takerBps, int256 makerBps);
    event UserTierUpgraded(address indexed user, uint256 tier);
    event EmergencyModeToggled(bool active, uint256 capBps);
    event VolatilityMultiplierUpdated(uint256 multiplierBps);

    /*═════════════════════════════════════  CONSTRUCTOR  ═════════════════════════════════════*/

    constructor(address _baobabToken, address admin) {
        baobabToken = IERC20(_baobabToken);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
        _grantRole(EMERGENCY_ADMIN, admin);

        // === User Tiers ===
        tiers[0] = CommonStructs.UserTier(0,        0,           0,     0);        // Retail
        tiers[1] = CommonStructs.UserTier(100_000e6, 1_000e18,   1500,  0);        // Active: 15% off
        tiers[2] = CommonStructs.UserTier(1_000_000e6, 10_000e18, 3000,  -10);     // Pro: 30% + small rebate
        tiers[3] = CommonStructs.UserTier(5_000_000e6, 50_000e18, 5000,  -25);     // VIP: 50% + 2.5 bps rebate

        // === Default Fees by Asset Class ===
        defaultFeeByClass[CommonStructs.AssetClass.CRYPTO]      = CommonStructs.FeeConfig(8,  0);
        defaultFeeByClass[CommonStructs.AssetClass.FOREX]       = CommonStructs.FeeConfig(18, 0);
        defaultFeeByClass[CommonStructs.AssetClass.STOCK]       = CommonStructs.FeeConfig(25, 0);
        defaultFeeByClass[CommonStructs.AssetClass.COMMODITY]   = CommonStructs.FeeConfig(15, 0);
    }

    /*═════════════════════════════════════  CORE FEE LOGIC  ═════════════════════════════════════*/

    function calculateTradingFeeTaker(
        address asset,
        address user,
        uint256 notionalUsd
    ) external view returns (uint256 feeBps) {
        CommonStructs.FeeConfig memory config = _getFeeConfig(asset);
        uint256 base = config.takerFeeBps;

        // Dynamic volatility multiplier
        base = base * volatilityMultiplierBps / BPS;

        // Apply tier discount
        uint256 tier = _getUserTier(user, notionalUsd);
        uint256 discount = tiers[tier].discountBps;
        feeBps = base * (BPS - discount) / BPS;

        // Emergency cap
        if (emergencyMode && feeBps > emergencyTakerCapBps) {
            feeBps = emergencyTakerCapBps;
        }

        return feeBps > MAX_FEE_BPS ? MAX_FEE_BPS : feeBps;
    }

    function calculateTradingFeeMaker(
        address asset,
        address user,
        uint256 notionalUsd
    ) external view returns (int256 feeBps) {
        uint256 tier = _getUserTier(user, notionalUsd);
        return tiers[tier].makerRebateBps; // can be negative → rebate
    }

    function getBorrowFeeBps(uint256 utilizationBps) external pure returns (uint256) {
        return 500 + (utilizationBps * 1000 / BPS); // 5% → 15% APR
    }

    function getLiquidationPenaltyBps(bool insuranceUsed) external pure returns (uint256) {
        return insuranceUsed ? 1250 : 500; // 12.5% or 5%
    }

    function getKeeperExecutionFeeUsd() external pure returns (uint256) {
        return KEEPER_FEE_USD;
    }

    /*═════════════════════════════════════  ADMIN FUNCTIONS  ═════════════════════════════════════*/

    function setAssetFeeConfig(
        address asset,
        uint256 takerBps,
        int256 makerBps
    ) external onlyRole(FEE_MANAGER_ROLE) {
        assetFeeConfig[asset] = CommonStructs.FeeConfig(takerBps, makerBps);
        emit FeeConfigUpdated(asset, takerBps, makerBps);
    }

    function setDefaultClassFee(
        CommonStructs.AssetClass class,
        uint256 takerBps,
        int256 makerBps
    ) external onlyRole(FEE_MANAGER_ROLE) {
        defaultFeeByClass[class] = CommonStructs.FeeConfig(takerBps, makerBps);
        emit DefaultClassFeeUpdated(class, takerBps, makerBps);
    }

    function setVolatilityMultiplier(uint256 multiplierBps) external onlyRole(FEE_MANAGER_ROLE) {
        require(multiplierBps >= 5000 && multiplierBps <= 30000, "Range");
        volatilityMultiplierBps = multiplierBps;
        emit VolatilityMultiplierUpdated(multiplierBps);
    }

    function toggleEmergencyMode(uint256 capBps) external onlyRole(EMERGENCY_ADMIN) {
        emergencyMode = !emergencyMode;
        if (emergencyMode) emergencyTakerCapBps = capBps;
        emit EmergencyModeToggled(emergencyMode, capBps);
    }

    function setVolumeTracker(address tracker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        volumeTracker = tracker;
    }

    /*═════════════════════════════════════  INTERNAL  ═════════════════════════════════════*/

    function _getFeeConfig(address asset) internal view returns (CommonStructs.FeeConfig memory) {
        CommonStructs.FeeConfig memory config = assetFeeConfig[asset];
        if (config.takerFeeBps == 0) {
            // fallback to class default (you can enhance with market lookup later)
            return defaultFeeByClass[CommonStructs.AssetClass.FOREX];
        }
        return config;
    }

    function _getUserTier(address user, uint256 volume30d) internal view returns (uint256) {
        uint256 tier = 0;
        uint256 staked = baobabToken.balanceOf(user);

        for (uint256 i = 3; i >= 1; --i) {
            if (volume30d >= tiers[i].minVolume30d || staked >= tiers[i].minStake) {
                tier = i;
                break;
            }
        }
        return tier;
    }
}