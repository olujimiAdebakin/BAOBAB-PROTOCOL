// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonStructs} from "../libraries/structs/CommonStructs.sol";
import {BaobabMath} from "../libraries/utils/BaobabMath.sol";
import {SafeTransfer} from "../libraries/utils/SafeTransfer.sol";
import {RoleRegistry} from "../access/RoleRegistry.sol";

/**
 * @title FeeCalculator – BAOBAB Protocol Revenue Engine
 * @notice Centralized fee calculation engine with tier-based discounts and dynamic pricing
 * @dev Uses BaobabMath for safe arithmetic operations and standardized calculations
 */
contract FeeCalculator is AccessControl {
    using BaobabMath for uint256;
    using BaobabMath for int256;
    using CommonStructs for *;
    using SafeTransfer for IERC20;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       ROLES & CONSTANTS                                        */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    // Role constants imported from RoleRegistry
    bytes32 public constant FEE_MANAGER_ROLE = RoleRegistry.FEE_MANAGER_ROLE;
    bytes32 public constant EMERGENCY_ADMIN = RoleRegistry.EMERGENCY_ADMIN;

    uint256 public constant KEEPER_FEE_USD = 2.5e6; // $2.50

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                          STORAGE                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    // Asset → custom fee configuration (overrides class default)
    mapping(address => CommonStructs.FeeConfig) public assetFeeConfig;

    // Asset → asset class mapping for fee fallbacks
    mapping(address => CommonStructs.AssetClass) public assetToClass;

    // Default fees per asset class
    mapping(CommonStructs.AssetClass => CommonStructs.FeeConfig) public defaultFeeByClass;

    // User tiers configuration (0 = retail, 3 = VIP)
    CommonStructs.UserTier[4] public tiers;

    // Emergency fee caps per asset
    mapping(address => uint256) public emergencyFeeCaps;

    // Emergency controls
    bool public emergencyMode;
    uint256 public emergencyTakerCapBps = 50; // 0.5% default cap
    uint256 public volatilityMultiplierBps = BaobabMath.BPS; // 1.0x default

    // External contract dependencies
    IERC20 public immutable baobabToken;
    address public volumeTracker;
    address public circuitBreaker;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                           EVENTS                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    event FeeConfigUpdated(address indexed asset, uint256 takerBps, int256 makerBps);
    event AssetClassUpdated(address indexed asset, CommonStructs.AssetClass class);
    event DefaultClassFeeUpdated(CommonStructs.AssetClass class, uint256 takerBps, int256 makerBps);
    event EmergencyFeeCapUpdated(address indexed asset, uint256 capBps);
    event EmergencyModeToggled(bool active, uint256 capBps);
    event VolatilityMultiplierUpdated(uint256 multiplierBps);
    event VolumeTrackerUpdated(address indexed tracker);
    event CircuitBreakerUpdated(address indexed breaker);

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                          ERRORS                                                */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    error InvalidFeeConfiguration();
    error InvalidAssetClass();
    error VolatilityMultiplierOutOfRange();

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                         MODIFIERS                                              */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    modifier validFeeBps(uint256 bps) {
        if (!BaobabMath.isValidFeeBps(bps)) revert InvalidFeeConfiguration();
        _;
    }

    modifier validRebateBps(int256 bps) {
        if (bps < -100 || bps > 100) revert InvalidFeeConfiguration(); // -1% to +1% rebate range
        _;
    }

    modifier validAssetClass(CommonStructs.AssetClass class) {
        if (uint8(class) > uint8(CommonStructs.AssetClass.COMMODITY)) revert InvalidAssetClass();
        _;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                        CONSTRUCTOR                                             */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Initialize FeeCalculator with protocol dependencies and default configurations
     * @param _baobabToken Address of BAOBAB token for staking-based tier calculations
     * @param admin Administrator address with default role privileges
     */
    constructor(address _baobabToken, address admin) {
        if (_baobabToken == address(0) || admin == address(0)) {
            revert InvalidFeeConfiguration();
        }

        baobabToken = IERC20(_baobabToken);
        
        // Setup role hierarchy
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
        _grantRole(EMERGENCY_ADMIN, admin);

        _initializeTiers();
        _initializeDefaultFees();
    }

    /**
     * @notice Initialize user tier configurations
     * 
     */
    function _initializeTiers() internal {
        // Tier 0: Retail (default)
        tiers[0] = CommonStructs.UserTier({
            minVolume30d: 0,
            minStake: 0,
            discountBps: 0,
            makerRebateBps: 0
        });

        // Tier 1: Active Trader
        tiers[1] = CommonStructs.UserTier({
            minVolume30d: 100_000e6,  // $100k volume
            minStake: 1_000e18,       // 1,000 BAOBAB
            discountBps: 1500,        // 15% discount
            makerRebateBps: 0         // No rebate
        });

        // Tier 2: Professional Trader
        tiers[2] = CommonStructs.UserTier({
            minVolume30d: 1_000_000e6, // $1M volume
            minStake: 10_000e18,       // 10,000 BAOBAB
            discountBps: 3000,         // 30% discount
            makerRebateBps: -10        // 0.1% rebate
        });

        // Tier 3: VIP/Institutional
        tiers[3] = CommonStructs.UserTier({
            minVolume30d: 5_000_000e6, // $5M volume
            minStake: 50_000e18,       // 50,000 BAOBAB
            discountBps: 5000,         // 50% discount
            makerRebateBps: -25        // 0.25% rebate
        });
    }

    /**
     * @notice Initialize default fee configurations by asset class
     */
    function _initializeDefaultFees() internal {
        // Crypto: Low volatility, high liquidity
        defaultFeeByClass[CommonStructs.AssetClass.CRYPTO] = CommonStructs.FeeConfig({
            takerFeeBps: 8,   // 0.08%
            makerRebateBps: 0    // 0% (can be negative for rebates)
        });

        // Forex: Medium volatility
        defaultFeeByClass[CommonStructs.AssetClass.FOREX] = CommonStructs.FeeConfig({
            takerFeeBps: 18,  // 0.18%
            makerRebateBps: 0
        });

        // Stocks: Higher volatility, regulatory costs
        defaultFeeByClass[CommonStructs.AssetClass.STOCK] = CommonStructs.FeeConfig({
            takerFeeBps: 25,  // 0.25%
            makerRebateBps: 0
        });

        // Commodities: Medium volatility
        defaultFeeByClass[CommonStructs.AssetClass.COMMODITY] = CommonStructs.FeeConfig({
            takerFeeBps: 15,  // 0.15%
            makerRebateBps: 0
        });
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                    CORE FEE CALCULATIONS                                       */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Calculate taker trading fee with tier discounts and volatility adjustments
     * @param asset Trading asset address
     * @param user User address for tier determination
     * @param notionalUsd Notional value in USD for volume calculation
     * @return feeBps Final taker fee in basis points
     */
    function calculateTradingFeeTaker(
        address asset,
        address user,
        uint256 notionalUsd
    ) external view returns (uint256 feeBps) {
        CommonStructs.FeeConfig memory config = _getFeeConfig(asset);
        
        // Apply volatility multiplier to base fee
        uint256 baseFee = config.takerFeeBps.applyMultiplier(volatilityMultiplierBps);
        
        // Apply tier-based discount
        CommonStructs.UserTier memory userTier = _getUserTierStruct(user, notionalUsd);
        uint256 discount = userTier.discountBps;
        feeBps = baseFee.calculateFeeWithDiscount(discount);
        
        // Apply emergency fee caps if active
        if (emergencyMode) {
            uint256 emergencyCap = emergencyFeeCaps[asset] != 0 
                ? emergencyFeeCaps[asset] 
                : emergencyTakerCapBps;
            feeBps = feeBps > emergencyCap ? emergencyCap : feeBps;
        }
        
        // Final safety check
        return feeBps > BaobabMath.MAX_FEE_BPS ? BaobabMath.MAX_FEE_BPS : feeBps;
    }

    /**
     * @notice Calculate maker trading fee/rebate
     * @param user User address for tier determination
     * @param notionalUsd Notional value in USD for volume calculation
     * @return feeBps Maker fee in basis points (negative = rebate)
     */
    function calculateTradingFeeMaker(
        address, // asset (unused - maker fee is same across assets)
        address user,
        uint256 notionalUsd
    ) external view returns (int256 feeBps) {
        CommonStructs.UserTier memory userTier = _getUserTierStruct(user, notionalUsd);
        return userTier.makerRebateBps; // Negative values indicate rebates
    }

    /**
     * @notice Calculate position-specific fees (for PositionManager integration)
     * @param user User address for tier determination
     * @param notionalUsd Position notional value
     * @param isOpening Whether this is an opening fee (true) or closing fee (false)
     * @return feeBps Position fee in basis points
     */
    function calculatePositionFee(
        address user,
        uint256 notionalUsd,
        bool isOpening
    ) external view returns (uint256 feeBps) {
        // Position fees are typically lower than trading fees
        uint256 baseFee = isOpening ? 5 : 3; // 0.05% open, 0.03% close
        
        // Apply tier discount
        CommonStructs.UserTier memory userTier = _getUserTierStruct(user, notionalUsd);
        uint256 discount = userTier.discountBps;
        feeBps = baseFee.calculateFeeWithDiscount(discount);
        
        // Cap position fees at 0.5%
        return feeBps > 50 ? 50 : feeBps;
    }

    /**
     * @notice Calculate borrow fee based on pool utilization
     * @param utilizationBps Utilization rate in basis points (0-10000)
     * @return feeBps Borrow fee in basis points (5-15% APR range)
     */
    function getBorrowFeeBps(uint256 utilizationBps) external pure returns (uint256) {
        return BaobabMath.calculateBorrowFee(utilizationBps);
    }

    /**
     * @notice Get liquidation penalty based on insurance fund usage
     * @param insuranceUsed Whether insurance fund was used for liquidation
     * @return penaltyBps Liquidation penalty in basis points
     */
    function getLiquidationPenaltyBps(bool insuranceUsed) external pure returns (uint256) {
        return insuranceUsed ? 1250 : 500; // 12.5% or 5%
    }

    /**
     * @notice Get standardized keeper execution fee
     * @return feeUsd Keeper fee in USD (6 decimals)
     */
    function getKeeperExecutionFeeUsd() external pure returns (uint256) {
        return KEEPER_FEE_USD;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      ADMIN FUNCTIONS                                           */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Set custom fee configuration for specific asset
     * @param asset Asset address
     * @param takerBps Taker fee in basis points
     * @param makerBps Maker fee in basis points (negative for rebates)
     */
    function setAssetFeeConfig(
        address asset,
        uint256 takerBps,
        int256 makerBps
    ) external onlyRole(FEE_MANAGER_ROLE) validFeeBps(takerBps) validRebateBps(makerBps) {
        assetFeeConfig[asset] = CommonStructs.FeeConfig(takerBps, makerBps);
        emit FeeConfigUpdated(asset, takerBps, makerBps);
    }

    /**
     * @notice Set asset class for fee fallback determination
     * @param asset Asset address
     * @param class Asset class
     */
    function setAssetClass(
        address asset, 
        CommonStructs.AssetClass class
    ) external onlyRole(FEE_MANAGER_ROLE) validAssetClass(class) {
        assetToClass[asset] = class;
        emit AssetClassUpdated(asset, class);
    }

    /**
     * @notice Set default fee configuration for asset class
     * @param class Asset class
     * @param takerBps Taker fee in basis points
     * @param makerBps Maker fee in basis points
     */
    function setDefaultClassFee(
        CommonStructs.AssetClass class,
        uint256 takerBps,
        int256 makerBps
    ) external onlyRole(FEE_MANAGER_ROLE) validFeeBps(takerBps) validRebateBps(makerBps) validAssetClass(class) {
        defaultFeeByClass[class] = CommonStructs.FeeConfig(takerBps, makerBps);
        emit DefaultClassFeeUpdated(class, takerBps, makerBps);
    }

    /**
     * @notice Set emergency fee cap for specific asset
     * @param asset Asset address
     * @param capBps Emergency fee cap in basis points
     */
    function setEmergencyFeeCap(
        address asset, 
        uint256 capBps
    ) external onlyRole(EMERGENCY_ADMIN) validFeeBps(capBps) {
        emergencyFeeCaps[asset] = capBps;
        emit EmergencyFeeCapUpdated(asset, capBps);
    }

    /**
     * @notice Set volatility multiplier for dynamic fee adjustments
     * @param multiplierBps Multiplier in basis points (5000 = 0.5x, 20000 = 2.0x)
     */
    function setVolatilityMultiplier(uint256 multiplierBps) external onlyRole(FEE_MANAGER_ROLE) {
        if (multiplierBps < 5000 || multiplierBps > 30000) {
            revert VolatilityMultiplierOutOfRange();
        }
        volatilityMultiplierBps = multiplierBps.toUint128();
        emit VolatilityMultiplierUpdated(multiplierBps);
    }

    /**
     * @notice Toggle emergency mode with optional fee cap
     * @param capBps Global emergency fee cap in basis points
     */
    function toggleEmergencyMode(uint256 capBps) external onlyRole(EMERGENCY_ADMIN) validFeeBps(capBps) {
        emergencyMode = !emergencyMode;
        if (emergencyMode) {
            emergencyTakerCapBps = capBps;
        }
        emit EmergencyModeToggled(emergencyMode, capBps);
    }

    /**
     * @notice Set volume tracker contract address
     * @param tracker Volume tracker contract address
     */
    function setVolumeTracker(address tracker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        volumeTracker = tracker;
        emit VolumeTrackerUpdated(tracker);
    }

    /**
     * @notice Set circuit breaker contract address
     * @param breaker Circuit breaker contract address
     */
    function setCircuitBreaker(address breaker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        circuitBreaker = breaker;
        emit CircuitBreakerUpdated(breaker);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                    INTERNAL FUNCTIONS                                          */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Get fee configuration for asset with fallback to class defaults
     * @param asset Asset address
     * @return Fee configuration
     */
    function _getFeeConfig(address asset) internal view returns (CommonStructs.FeeConfig memory) {
        CommonStructs.FeeConfig memory customConfig = assetFeeConfig[asset];
        
        // Return custom configuration if set
        if (customConfig.takerFeeBps != 0) {
            return customConfig;
        }
        
        // Fallback to asset class default
        CommonStructs.AssetClass assetClass = assetToClass[asset];
        return defaultFeeByClass[assetClass];
    }

    // /**
    //  * @notice Determine user tier based on volume and staking
    //  * @param user User address
    //  * @param volume30d 30-day trading volume
    //  * @return tier User tier (0-3)
    //  */
 function _getUserTier(address user, uint256 volume30d) internal view returns (uint256 tier) {
    uint256 staked = baobabToken.balanceOf(user);
    
    // Tier 3: VIP (requires BOTH $5M volume AND 50k BAOBAB stake)
    if (volume30d >= tiers[3].minVolume30d && staked >= tiers[3].minStake) {
        return 3;
    }
    
    // Tier 2: Professional (requires BOTH $1M volume AND 10k BAOBAB stake)
    if (volume30d >= tiers[2].minVolume30d && staked >= tiers[2].minStake) {
        return 2;
    }
    
    // Tier 1: Active Trader (requires BOTH $100k volume AND 1k BAOBAB stake)
    if (volume30d >= tiers[1].minVolume30d && staked >= tiers[1].minStake) {
        return 1;
    }
    
    // Tier 0: Retail (default, no requirements)
    return 0;
}


function _getUserTierStruct(address user, uint256 volume30d) 
    internal view returns (CommonStructs.UserTier memory) 
{
    uint256 staked = baobabToken.balanceOf(user);
    
    for (uint256 i = tiers.length - 1; i >= 1; i--) {
        if (volume30d >= tiers[i].minVolume30d && staked >= tiers[i].minStake) {
            return tiers[i];
        }
    }
    return tiers[0];
}
}