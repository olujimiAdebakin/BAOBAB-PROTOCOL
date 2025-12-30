// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {CommonStructs} from "../libraries/structs/CommonStructs.sol";
import {VolumeStructs} from "../libraries/structs/VolumeStructs.sol";
import {RoleRegistry} from "../access/RoleRegistry.sol";
import {SecurityBase} from "../security/SecurityBase.sol";

/**
 * @title VolumeTracker
 * @author BAOBAB Protocol
 * @notice Single source of truth for ALL volume metrics (30-day rolling & lifetime)
 * @dev Uses circular buffer for efficient 30-day tracking with zero reorg issues
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                        VOLUME TRACKER
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *
 * KEY FEATURES:
 * - O(1) updates using circular buffer
 * - Automatic 30-day expiry without loops
 * - Per-market volume tracking for granular analytics
 * - Gas-optimized batch queries
 * - Role-based access control
 */
contract VolumeTracker is SecurityBase {
    using CommonStructs for *;
    using VolumeStructs for *;
    // ════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTURES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Single day's volume snapshot
     * @param amount Total volume for the day (18 decimals)
     * @param timestamp Day timestamp (normalized to midnight UTC)
     */
    struct DailyVolume {
        uint256 amount;
        uint256 timestamp;
    }

    /**
     * @notice User's complete volume profile
     * @param dailyVolumes Circular buffer of last 30 days
     * @param lifetimeVolume All-time cumulative volume (18 decimals)
     * @param currentIndex Current write position in circular buffer (0-29)
     * @param lastUpdateDay Last day volume was recorded
     */
    struct UserVolume {
        DailyVolume[30] dailyVolumes;
        uint256 lifetimeVolume;
        uint256 currentIndex;
        uint256 lastUpdateDay;
    }

    /**
     * @notice Per-market volume breakdown for analytics
     * @param marketId Market identifier
     * @param volume30d Rolling 30-day volume (18 decimals)
     * @param lifetimeVolume All-time volume in this market (18 decimals)
     */
    struct MarketVolume {
        bytes32 marketId;
        uint256 volume30d;
        uint256 lifetimeVolume;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STATE
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice User address => volume data
    mapping(address => UserVolume) private userVolumes;

    /// @notice User => Market => volume breakdown
    mapping(address => mapping(bytes32 => MarketVolume)) private marketVolumes;

    /// @notice Authorized recorders (TradingEngine, OrderRouter, etc.)
    mapping(address => bool) public authorizedRecorders;

    /// @notice Protocol admin
    address public admin;

    /// @notice Total protocol volume (lifetime)
    uint256 public protocolLifetimeVolume;

    // /// @notice Emergency pause flag
    // bool public paused;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event TradeRecorded(
        address indexed user, bytes32 indexed marketId, uint256 amount, uint256 timestamp, uint256 newLifetime
    );
    event RecorderUpdated(address indexed recorder, bool authorized);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event EmergencyPause(bool paused);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    // error Paused();
    error InvalidMarketId();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyAuthorized() {
        if (!authorizedRecorders[msg.sender] && msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    // modifier whenNotPaused() {
    //     if (paused) revert Paused();
    //     _;
    // }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor() {
        admin = msg.sender;
        authorizedRecorders[msg.sender] = true;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Record a trade - updates BOTH 30-day and lifetime volumes
     * @dev Called by TradingEngine on every fill
     * @param user Trader address
     * @param marketId Market where trade occurred
     * @param amount Trade size in quote asset (18 decimals)
     */
    function recordTrade(address user, bytes32 marketId, uint256 amount) external onlyAuthorized whenNotPaused {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (marketId == bytes32(0)) revert InvalidMarketId();

        uint256 today = block.timestamp / 1 days;
        UserVolume storage userVol = userVolumes[user];

        // ─────────────────────────────────────────────────────────────────────────────────────────
        // Update 30-day circular buffer
        // ─────────────────────────────────────────────────────────────────────────────────────────
        if (userVol.lastUpdateDay == 0) {
            // First trade ever - initialize buffer
            userVol.dailyVolumes[0] = DailyVolume(amount, today);
            userVol.currentIndex = 0;
        } else if (userVol.lastUpdateDay == today) {
            // Same day - accumulate to existing slot
            userVol.dailyVolumes[userVol.currentIndex].amount += amount;
        } else {
            // New day - advance circular buffer
            uint256 newIndex = (userVol.currentIndex + 1) % 30;

            // Overwrite old data (automatically expires >30d data)
            userVol.dailyVolumes[newIndex] = DailyVolume(amount, today);
            userVol.currentIndex = newIndex;
        }

        // ─────────────────────────────────────────────────────────────────────────────────────────
        // Update lifetime volume (monotonically increasing)
        // ─────────────────────────────────────────────────────────────────────────────────────────
        userVol.lifetimeVolume += amount;
        userVol.lastUpdateDay = today;

        // ─────────────────────────────────────────────────────────────────────────────────────────
        // Update per-market breakdown
        // ─────────────────────────────────────────────────────────────────────────────────────────
        MarketVolume storage marketVol = marketVolumes[user][marketId];
        marketVol.marketId = marketId;
        marketVol.lifetimeVolume += amount;
        // Note: volume30d computed on-demand to avoid storage bloat

        // ─────────────────────────────────────────────────────────────────────────────────────────
        // Update protocol-wide metrics
        // ─────────────────────────────────────────────────────────────────────────────────────────
        protocolLifetimeVolume += amount;

        emit TradeRecorded(user, marketId, amount, block.timestamp, userVol.lifetimeVolume);
    }

    /**
     * @notice Batch record multiple trades (gas optimization)
     * @param users Array of trader addresses
     * @param marketIds Array of market identifiers
     * @param amounts Array of trade sizes
     */
    function recordTradeBatch(address[] calldata users, bytes32[] calldata marketIds, uint256[] calldata amounts)
        external
        onlyAuthorized
        whenNotPaused
    {
        uint256 len = users.length;
        require(len == marketIds.length && len == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < len; i++) {
            // Inline to save external call overhead
            _recordTrade(users[i], marketIds[i], amounts[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get 30-day rolling volume for user
     * @param user Trader address
     * @return uint256 Volume in last 30 days (18 decimals)
     */
    function get30DayVolume(address user) public view returns (uint256) {
        uint256 total = 0;
        uint256 today = block.timestamp / 1 days;
        uint256 oldestAllowed = today - 30;

        UserVolume storage userVol = userVolumes[user];

        // Sum only entries within 30-day window
        for (uint256 i = 0; i < 30; i++) {
            if (userVol.dailyVolumes[i].timestamp > oldestAllowed) {
                total += userVol.dailyVolumes[i].amount;
            }
        }
        return total;
    }

    /**
     * @notice Get lifetime volume for user
     * @param user Trader address
     * @return uint256 All-time volume (18 decimals)
     */
    function getLifetimeVolume(address user) public view returns (uint256) {
        return userVolumes[user].lifetimeVolume;
    }

    /**
     * @notice Get both volumes at once (gas efficient for fee tier checks)
     * @param user Trader address
     * @return volume30d Rolling 30-day volume
     * @return lifetime All-time volume
     */
    function getVolumes(address user) external view returns (uint256 volume30d, uint256 lifetime) {
        return (get30DayVolume(user), getLifetimeVolume(user));
    }

    /**
     * @notice Get per-market volume breakdown for user
     * @param user Trader address
     * @param marketId Market identifier
     * @return MarketVolume Market-specific volume data
     */
    function getMarketVolume(address user, bytes32 marketId) external view returns (MarketVolume memory) {
        return marketVolumes[user][marketId];
    }

    /**
     * @notice Get user tier based on 30-day volume (for FeeManager integration)
     * @param user Trader address
     * @param tierThresholds Array of volume thresholds for tiers
     * @return uint8 Tier index (0 = lowest)
     */
    function getUserTier(address user, uint256[] calldata tierThresholds) external view returns (uint8) {
        uint256 volume = get30DayVolume(user);

        for (uint8 i = 0; i < tierThresholds.length; i++) {
            if (volume < tierThresholds[i]) {
                return i;
            }
        }
        return uint8(tierThresholds.length); // Highest tier
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Authorize contract to record trades (e.g., TradingEngine, OrderRouter)
     * @param recorder Contract address
     * @param authorized Authorization status
     */
    function setAuthorizedRecorder(address recorder, bool authorized) external onlyAdmin {
        if (recorder == address(0)) revert ZeroAddress();
        authorizedRecorders[recorder] = authorized;
        emit RecorderUpdated(recorder, authorized);
    }

    /**
     * @notice Transfer admin role
     * @param newAdmin New admin address
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminTransferred(oldAdmin, newAdmin);
    }

    // /**
    //  * @notice Emergency pause (stops all recording)
    //  * @param _paused Pause state
    //  */
    // function setPaused(bool _paused) external onlyAdmin {
    //     paused = _paused;
    //     emit EmergencyPause(_paused);
    // }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal trade recording logic (for batch optimization)
     */
    function _recordTrade(address user, bytes32 marketId, uint256 amount) private {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (marketId == bytes32(0)) revert InvalidMarketId();

        uint256 today = block.timestamp / 1 days;
        UserVolume storage userVol = userVolumes[user];

        if (userVol.lastUpdateDay == 0) {
            userVol.dailyVolumes[0] = DailyVolume(amount, today);
            userVol.currentIndex = 0;
        } else if (userVol.lastUpdateDay == today) {
            userVol.dailyVolumes[userVol.currentIndex].amount += amount;
        } else {
            uint256 newIndex = (userVol.currentIndex + 1) % 30;
            userVol.dailyVolumes[newIndex] = DailyVolume(amount, today);
            userVol.currentIndex = newIndex;
        }

        userVol.lifetimeVolume += amount;
        userVol.lastUpdateDay = today;

        MarketVolume storage marketVol = marketVolumes[user][marketId];
        marketVol.marketId = marketId;
        marketVol.lifetimeVolume += amount;

        protocolLifetimeVolume += amount;

        emit TradeRecorded(user, marketId, amount, block.timestamp, userVol.lifetimeVolume);
    }
}
