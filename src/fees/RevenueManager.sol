// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RevenueManager
 * @notice Tracks and reports all protocol revenue streams for BAOBAB Protocol
 * @dev Records fees, provides analytics, manages revenue allocation
 */
contract RevenueManager {

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                       STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    struct RevenueSource {
        uint256 tradingFees;            // Opening + closing fees
        uint256 liquidationFees;        // Liquidation penalties
        uint256 executionFees;          // TWAP/Scale order fees
        uint256 vaultDepositFees;       // LP deposit fees
        uint256 vaultWithdrawFees;      // LP withdrawal fees
        uint256 vaultPerformanceFees;   // Performance fees
        uint256 spreadRevenue;          // AMM spread captured
        uint256 otherRevenue;           // Misc revenue
    }

    struct MarketRevenue {
        bytes32 marketId;
        uint256 totalVolume;            // Trading volume
        uint256 totalFees;              // All fees from market
        uint256 openInterest;           // Current OI
        uint256 numberOfTrades;         // Trade count
    }

    struct DailySnapshot {
        uint256 date;                   // Timestamp (start of day)
        RevenueSource revenue;
        uint256 totalRevenue;           // Sum of all sources
        uint256 totalVolume;            // Total trading volume
        uint256 uniqueTraders;          // Unique users
        uint256 totalTrades;            // Total trades
    }

    struct Allocation {
        uint256 stakersShare;           // % to stakers (basis points)
        uint256 lpShare;                // % to LPs
        uint256 treasuryShare;          // % to treasury
        uint256 insuranceShare;         // % to insurance
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                    STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════

    address public admin;
    address public feeDistributor;
    address public positionManager;

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant SECONDS_PER_DAY = 86400;

    // Cumulative revenue tracking
    RevenueSource public lifetimeRevenue;
    uint256 public totalRevenueAllTime;
    uint256 public totalVolumeAllTime;

    // Daily snapshots
    mapping(uint256 => DailySnapshot) public dailySnapshots;
    uint256 public currentDay;

    // Market-specific tracking
    mapping(bytes32 => MarketRevenue) public marketRevenue;
    bytes32[] public activeMarkets;

    // Revenue allocation
    Allocation public revenueAllocation;

    // Per-source tracking
    mapping(uint256 => mapping(uint256 => uint256)) public revenueBySource; // day => sourceType => amount

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                         EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════

    event RevenueRecorded(
        uint256 indexed day,
        uint8 indexed sourceType,
        uint256 amount,
        bytes32 marketId
    );

    event DailySnapshotCreated(
        uint256 indexed day,
        uint256 totalRevenue,
        uint256 totalVolume
    );

    event AllocationUpdated(
        uint256 stakersShare,
        uint256 lpShare,
        uint256 treasuryShare,
        uint256 insuranceShare
    );

    event MarketRevenueUpdated(
        bytes32 indexed marketId,
        uint256 volume,
        uint256 fees
    );

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                         ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════

    error RevenueManager__OnlyAdmin();
    error RevenueManager__OnlyAuthorized();
    error RevenueManager__InvalidAllocation();

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                       CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════

    constructor(address _admin) {
        require(_admin != address(0), "Invalid admin");
        admin = _admin;

        // Initialize default allocation: 40/30/20/10
        revenueAllocation = Allocation({
            stakersShare: 4000,     // 40%
            lpShare: 3000,          // 30%
            treasuryShare: 2000,    // 20%
            insuranceShare: 1000    // 10%
        });

        currentDay = block.timestamp / SECONDS_PER_DAY;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                        MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════

    modifier onlyAdmin() {
        if (msg.sender != admin) revert RevenueManager__OnlyAdmin();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != feeDistributor && 
            msg.sender != positionManager && 
            msg.sender != admin) {
            revert RevenueManager__OnlyAuthorized();
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                   CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record trading fee revenue
     * @param amount Fee amount
     * @param marketId Market where fee was generated
     */
    function recordTradingFee(uint256 amount, bytes32 marketId) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        lifetimeRevenue.tradingFees += amount;
        totalRevenueAllTime += amount;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.revenue.tradingFees += amount;
        snapshot.totalRevenue += amount;

        _updateMarketRevenue(marketId, 0, amount);

        emit RevenueRecorded(currentDay, 0, amount, marketId);
    }

    /**
     * @notice Record liquidation fee revenue
     * @param amount Fee amount
     * @param marketId Market where liquidation occurred
     */
    function recordLiquidationFee(uint256 amount, bytes32 marketId) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        lifetimeRevenue.liquidationFees += amount;
        totalRevenueAllTime += amount;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.revenue.liquidationFees += amount;
        snapshot.totalRevenue += amount;

        _updateMarketRevenue(marketId, 0, amount);

        emit RevenueRecorded(currentDay, 1, amount, marketId);
    }

    /**
     * @notice Record execution fee revenue
     * @param amount Fee amount
     */
    function recordExecutionFee(uint256 amount) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        lifetimeRevenue.executionFees += amount;
        totalRevenueAllTime += amount;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.revenue.executionFees += amount;
        snapshot.totalRevenue += amount;

        emit RevenueRecorded(currentDay, 2, amount, bytes32(0));
    }

    /**
     * @notice Record vault deposit fee
     * @param amount Fee amount
     */
    function recordVaultDepositFee(uint256 amount) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        lifetimeRevenue.vaultDepositFees += amount;
        totalRevenueAllTime += amount;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.revenue.vaultDepositFees += amount;
        snapshot.totalRevenue += amount;

        emit RevenueRecorded(currentDay, 3, amount, bytes32(0));
    }

    /**
     * @notice Record vault withdrawal fee
     * @param amount Fee amount
     */
    function recordVaultWithdrawFee(uint256 amount) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        lifetimeRevenue.vaultWithdrawFees += amount;
        totalRevenueAllTime += amount;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.revenue.vaultWithdrawFees += amount;
        snapshot.totalRevenue += amount;

        emit RevenueRecorded(currentDay, 4, amount, bytes32(0));
    }

    /**
     * @notice Record vault performance fee
     * @param amount Fee amount
     */
    function recordVaultPerformanceFee(uint256 amount) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        lifetimeRevenue.vaultPerformanceFees += amount;
        totalRevenueAllTime += amount;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.revenue.vaultPerformanceFees += amount;
        snapshot.totalRevenue += amount;

        emit RevenueRecorded(currentDay, 5, amount, bytes32(0));
    }

    /**
     * @notice Record AMM spread revenue
     * @param amount Spread captured
     * @param marketId Market where spread occurred
     */
    function recordSpreadRevenue(uint256 amount, bytes32 marketId) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        lifetimeRevenue.spreadRevenue += amount;
        totalRevenueAllTime += amount;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.revenue.spreadRevenue += amount;
        snapshot.totalRevenue += amount;

        _updateMarketRevenue(marketId, 0, amount);

        emit RevenueRecorded(currentDay, 6, amount, marketId);
    }

    /**
     * @notice Record trading volume
     * @param volume Trade volume
     * @param marketId Market where trade occurred
     */
    function recordVolume(uint256 volume, bytes32 marketId) 
        external 
        onlyAuthorized 
    {
        _checkAndUpdateDay();

        totalVolumeAllTime += volume;

        DailySnapshot storage snapshot = dailySnapshots[currentDay];
        snapshot.totalVolume += volume;
        snapshot.totalTrades++;

        _updateMarketRevenue(marketId, volume, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                  INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function _checkAndUpdateDay() internal {
        uint256 today = block.timestamp / SECONDS_PER_DAY;
        
        if (today > currentDay) {
            // Finalize previous day
            emit DailySnapshotCreated(
                currentDay,
                dailySnapshots[currentDay].totalRevenue,
                dailySnapshots[currentDay].totalVolume
            );
            
            // Start new day
            currentDay = today;
            dailySnapshots[currentDay].date = block.timestamp;
        }
    }

    function _updateMarketRevenue(
        bytes32 marketId,
        uint256 volume,
        uint256 fees
    ) internal {
        if (marketId == bytes32(0)) return;

        MarketRevenue storage market = marketRevenue[marketId];
        
        // Initialize if new market
        if (market.marketId == bytes32(0)) {
            market.marketId = marketId;
            activeMarkets.push(marketId);
        }

        market.totalVolume += volume;
        market.totalFees += fees;
        if (volume > 0) market.numberOfTrades++;

        emit MarketRevenueUpdated(marketId, volume, fees);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                    ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function setFeeDistributor(address _feeDistributor) external onlyAdmin {
        require(_feeDistributor != address(0), "Invalid address");
        feeDistributor = _feeDistributor;
    }

    function setPositionManager(address _positionManager) external onlyAdmin {
        require(_positionManager != address(0), "Invalid address");
        positionManager = _positionManager;
    }

    function updateRevenueAllocation(
        uint256 _stakersShare,
        uint256 _lpShare,
        uint256 _treasuryShare,
        uint256 _insuranceShare
    ) external onlyAdmin {
        // Must sum to 100%
        if (_stakersShare + _lpShare + _treasuryShare + _insuranceShare != BASIS_POINTS) {
            revert RevenueManager__InvalidAllocation();
        }

        revenueAllocation.stakersShare = _stakersShare;
        revenueAllocation.lpShare = _lpShare;
        revenueAllocation.treasuryShare = _treasuryShare;
        revenueAllocation.insuranceShare = _insuranceShare;

        emit AllocationUpdated(
            _stakersShare,
            _lpShare,
            _treasuryShare,
            _insuranceShare
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════════
    //                                     VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════

    function getLifetimeRevenue() external view returns (RevenueSource memory) {
        return lifetimeRevenue;
    }

    function getTodaySnapshot() external view returns (DailySnapshot memory) {
        return dailySnapshots[currentDay];
    }

    function getDailySnapshot(uint256 day) external view returns (DailySnapshot memory) {
        return dailySnapshots[day];
    }

    function getMarketRevenue(bytes32 marketId) external view returns (MarketRevenue memory) {
        return marketRevenue[marketId];
    }

    function getActiveMarkets() external view returns (bytes32[] memory) {
        return activeMarkets;
    }

    function getRevenueAllocation() external view returns (Allocation memory) {
        return revenueAllocation;
    }

    function getTotalRevenue() external view returns (uint256) {
        return totalRevenueAllTime;
    }

    function getTotalVolume() external view returns (uint256) {
        return totalVolumeAllTime;
    }

    function getRevenueBySource(uint256 day, uint8 sourceType) 
        external 
        view 
        returns (uint256) 
    {
        return revenueBySource[day][sourceType];
    }

    /**
     * @notice Calculate revenue share for a specific stakeholder
     * @param totalRevenue Total revenue to split
     * @param shareType 0=stakers, 1=LPs, 2=treasury, 3=insurance
     */
    function calculateShare(uint256 totalRevenue, uint8 shareType) 
        external 
        view 
        returns (uint256) 
    {
        if (shareType == 0) {
            return (totalRevenue * revenueAllocation.stakersShare) / BASIS_POINTS;
        } else if (shareType == 1) {
            return (totalRevenue * revenueAllocation.lpShare) / BASIS_POINTS;
        } else if (shareType == 2) {
            return (totalRevenue * revenueAllocation.treasuryShare) / BASIS_POINTS;
        } else if (shareType == 3) {
            return (totalRevenue * revenueAllocation.insuranceShare) / BASIS_POINTS;
        }
        return 0;
    }

    /**
     * @notice Get revenue breakdown for last N days
     */
    function getRevenueBreakdown(uint256 numDays) 
        external 
        view 
        returns (
            uint256 totalRevenue,
            uint256 totalVolume,
            uint256 avgDailyRevenue
        ) 
    {
        uint256 startDay = currentDay > numDays ? currentDay - numDays : 0;
        
        for (uint256 i = startDay; i <= currentDay; i++) {
            totalRevenue += dailySnapshots[i].totalRevenue;
            totalVolume += dailySnapshots[i].totalVolume;
        }
        
        avgDailyRevenue = numDays > 0 ? totalRevenue / numDays : 0;
    }

    /**
     * @notice Get top revenue markets
     */
    function getTopMarkets(uint256 limit) 
        external 
        view 
        returns (bytes32[] memory markets, uint256[] memory revenues) 
    {
        uint256 count = activeMarkets.length < limit ? activeMarkets.length : limit;
        markets = new bytes32[](count);
        revenues = new uint256[](count);
        
        // Simple selection (in production, sort by revenue)
        for (uint256 i = 0; i < count; i++) {
            markets[i] = activeMarkets[i];
            revenues[i] = marketRevenue[activeMarkets[i]].totalFees;
        }
    }
}