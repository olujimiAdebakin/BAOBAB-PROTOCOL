// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title RateLimiter – Advanced Multi-Layer Rate Limiter
 * @author BAOBAB Protocol
 * @notice Production-grade protection against spam, DoS, and economic attacks for the BAOBAB Protocol
 * @dev Implements three-layer rate limiting:
 *      • Token bucket algorithm (request counting)
 *      • Tier-based limits (user segmentation)
 *      • Gas consumption tracking (economic attack prevention)
 * @dev Features per-operation controls, emergency bypass, keeper-specific limits, and African market optimizations
 */
contract RateLimiter {
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       CONSTANTS & IMMUTABLES                                     */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /// @notice Unlimited requests constant for whitelisted users and disabled operations
    uint256 private constant UNLIMITED = type(uint256).max;

    /// @notice Standard time window constants for rate limiting
    uint256 private constant ONE_HOUR = 1 hours;
    uint256 private constant FIVE_MINUTES = 5 minutes;
    uint256 private constant GAS_WINDOW = 5 minutes; // Gas limit reset window

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                            ENUMS & STRUCTS                                       */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice User tier determines which rate limit bucket applies
     * @dev Tiers are assigned based on user activity, volume, or staking status
     */
    enum UserTier {
        Basic, // Retail users - default tier with basic protection
        Premium, // Active traders (>$50k TVL or volume) - elevated limits
        VIP, // High-volume traders or staked BAOBAB holders - generous limits
        MarketMaker // Registered DAO-approved market makers - highest limits

    }

    /**
     * @notice Tiered request limits configuration per operation type
     * @dev Different user tiers get different request allowances
     */
    struct TieredRateLimit {
        uint256 basic; // Retail users - conservative limits
        uint256 premium; // Active traders - balanced limits
        uint256 vip; // High-volume users - generous limits
        uint256 marketMaker; // Market makers - maximum limits for liquidity provision
    }

    /**
     * @notice Gas-based rate limiting configuration
     * @dev Prevents economic attacks by limiting total gas consumption per window
     */
    struct GasRateLimit {
        uint256 maxGasPerWindow; // Maximum gas units allowed per time window
        uint256 gasUsed; // Accumulated gas consumption in current window
        uint256 windowStart; // Start timestamp of current gas tracking window
    }

    /**
     * @notice Standard token-bucket rate limit configuration
     * @dev Controls request frequency using time-based windows
     */
    struct RateLimitConfig {
        uint256 timeWindow; // Duration in seconds for request counting window
        bool enabled; // Whether this operation type has rate limiting enabled
    }

    /**
     * @notice Per-user per-operation rate limiting state
     * @dev Tracks individual user activity for each operation type
     */
    struct RateLimitState {
        uint256 requestCount; // Number of requests in current window
        uint256 windowStart; // Start timestamp of current counting window
        uint256 lastRequestTime; // Timestamp of last request for cooldown tracking
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                             STORAGE                                              */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /// @notice Administrator address with configuration privileges
    address public admin;

    /// @notice Global enable/disable switch for all rate limiting
    bool public globalEnabled = true;

    /// @notice Operation ID to rate limit configuration mapping
    mapping(bytes32 => RateLimitConfig) public configs;

    /// @notice Operation ID to tiered limits configuration mapping
    mapping(bytes32 => TieredRateLimit) public tieredLimits;

    /// @notice Operation ID to global gas limit configuration mapping
    mapping(bytes32 => GasRateLimit) public gasLimits;

    /// @notice User to operation ID to request counting state mapping
    mapping(address => mapping(bytes32 => RateLimitState)) public userStates;

    /// @notice User to operation ID to gas consumption state mapping
    mapping(address => mapping(bytes32 => GasRateLimit)) public userGasStates;

    /// @notice User to tier assignment mapping
    mapping(address => UserTier) public userTier;

    /// @notice Addresses that bypass all rate limiting (protocol contracts, admins)
    mapping(address => bool) public whitelist;

    /// @notice Addresses with emergency bypass during protocol emergencies
    mapping(address => bool) public emergencyBypass;

    /// @notice Keeper bot addresses with specialized rate limits
    mapping(address => bool) public isKeeper;

    /// @notice Keeper-specific rate limits per operation
    mapping(bytes32 => TieredRateLimit) public keeperLimits;

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                             EVENTS                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /// @notice Emitted when rate limit configuration is updated
    event RateLimitConfigured(bytes32 indexed opId, uint256 timeWindow);

    /// @notice Emitted when tiered limits are configured for an operation
    event TieredLimitsSet(bytes32 indexed opId, uint256 basic, uint256 premium, uint256 vip, uint256 mm);

    /// @notice Emitted when gas limits are configured for an operation
    event GasLimitSet(bytes32 indexed opId, uint256 maxGasPerWindow);

    /// @notice Emitted when a user's tier is upgraded or changed
    event UserTierUpgraded(address indexed user, UserTier tier);

    /// @notice Emitted when rate limit is exceeded by a user
    event RateLimitExceeded(address indexed user, bytes32 indexed operationId, string reason);

    /// @notice Emitted when whitelist status is updated
    event WhitelistUpdated(address indexed account, bool status);

    /// @notice Emitted when emergency bypass status is updated
    event EmergencyBypassUpdated(address indexed account, bool status);

    /// @notice Emitted when keeper status is updated
    event KeeperStatusUpdated(address indexed account, bool status);

    /// @notice Emitted when global rate limiting is toggled
    event GlobalToggled(bool enabled);

    /// @notice Emitted when admin is transferred
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                             ERRORS                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /// @notice Thrown when caller is not the admin
    error NotAdmin();

    /// @notice Thrown when configuration parameters are invalid
    error InvalidConfig();

    /// @notice Thrown when rate limit is exceeded
    error RateLimitCount(uint256 retryAfter, string reason);

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                       CORE RATE LIMIT CHECK                                      */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Main entry point for rate limit checking - validates all three protection layers
     * @dev Must be called at the beginning of sensitive external functions
     * @dev Checks: request counting, tier-based limits, and gas consumption
     * @param user The address of the user to check limits for
     * @param operationId The operation identifier being performed
     */
    function checkRateLimit(address user, bytes32 operationId) public whenEnabled {
        // Skip rate limiting for whitelisted addresses
        if (whitelist[user]) return;

        uint256 startGas = gasleft();

        _checkCountLimit(user, operationId);
        _checkGasLimit(user, operationId, startGas);

        // Record successful request timestamp for cooldown tracking
        RateLimitState storage state = userStates[user][operationId];
        state.lastRequestTime = block.timestamp;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                          MODIFIERS                                               */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Restricts function to admin only
     * @dev Reverts with NotAdmin if caller is not the admin
     */
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /**
     * @notice Skips rate limiting when globally disabled
     * @dev Allows temporary disabling of all rate limits during maintenance
     */
    modifier whenEnabled() {
        if (!globalEnabled) return;
        _;
    }

    /**
     * @notice Applies rate limiting unless emergency bypass is granted
     * @dev Used by critical protocol functions that need emergency override capability
     * @param operationId The operation identifier to check limits for
     */
    modifier rateLimitedOrEmergency(bytes32 operationId) {
        if (!emergencyBypass[msg.sender]) {
            checkRateLimit(msg.sender, operationId);
        }
        _;
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                          CONSTRUCTOR                                             */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Initializes the RateLimiter with admin and default configurations
     * @dev Sets up default rate limits for common BAOBAB protocol operations
     * @param initialAdmin The initial admin address with configuration privileges
     */
    constructor(address initialAdmin) {
        if (initialAdmin == address(0)) revert ZeroAddress();
        admin = initialAdmin;

        // Default configurations for BAOBAB protocol operations
        // Tier progression: Basic -> Premium -> VIP -> MarketMaker

        // Trading operations
        _setTieredLimit("PLACE_ORDER", 10, 30, 100, 500, 1 minutes);
        _setGasLimit("PLACE_ORDER", 10_000_000); // ~100 orders at 100k gas each

        _setTieredLimit("CANCEL_ORDER", 20, 60, 200, 1000, 1 minutes);
        _setTieredLimit("EXECUTE_MARKET_ORDER", 5, 15, 50, 200, 1 minutes);

        // Liquidity operations
        _setTieredLimit("ADD_LIQUIDITY", 5, 15, 50, 200, 1 minutes);
        _setTieredLimit("REMOVE_LIQUIDITY", 5, 15, 50, 200, 1 minutes);

        // Order NFT operations
        _setTieredLimit("BORROW_AGAINST_ORDER", 3, 10, 30, 100, 1 hours);
        _setTieredLimit("STAKE_ORDER_NFT", 10, 30, 100, 500, 1 minutes);

        // Basket operations
        _setTieredLimit("CREATE_BASKET", 2, 5, 20, 100, 1 hours);
        _setTieredLimit("REBALANCE_BASKET", 1, 3, 10, 50, 1 hours);

        // Event derivatives
        _setTieredLimit("PLACE_EVENT_BET", 5, 15, 50, 200, 1 minutes);

        // Advanced order types with strict gas limits
        _setTieredLimit("EXECUTE_TWAP", 2, 5, 20, 100, 5 minutes);
        _setGasLimit("EXECUTE_TWAP", 5_000_000); // Gas-intensive operation

        _setTieredLimit("CREATE_SCALE_ORDER", 3, 8, 25, 100, 1 minutes);

        // Risk management operations
        _setTieredLimit("LIQUIDATE_POSITION", 10, 25, 80, 300, 1 minutes);
        _setTieredLimit("EXECUTE_ADL", 5, 10, 30, 100, 1 minutes);

        // Settlement operations
        _setTieredLimit("SETTLE_EVENT", 1, 3, 10, 50, 10 minutes);
        _setGasLimit("SETTLE_EVENT", 8_000_000); // Complex settlement logic
    }

    /**
     * @notice Internal function to check request counting limits
     * @dev Implements token bucket algorithm with tier-based allowances
     * @param user The user address to check
     * @param operationId The operation identifier
     */
    function _checkCountLimit(address user, bytes32 operationId) internal {
        RateLimitConfig memory cfg = configs[operationId];
        // Skip if operation has no count-based limiting
        if (!cfg.enabled) return;

        TieredRateLimit memory limits = tieredLimits[operationId];
        uint256 userLimit = _getLimitForUser(user, limits, operationId);

        RateLimitState storage state = userStates[user][operationId];
        uint256 currentTime = block.timestamp;

        // Reset window if we've moved to a new time window
        if (currentTime >= state.windowStart + cfg.timeWindow) {
            state.windowStart = currentTime;
            state.requestCount = 1;
            return;
        }

        // Increment request count (unchecked for gas optimization)
        unchecked {
            state.requestCount += 1;
        }

        // Check if limit exceeded
        if (state.requestCount > userLimit) {
            uint256 retryAfter = (state.windowStart + cfg.timeWindow) - currentTime;
            emit RateLimitExceeded(user, operationId, "Request count exceeded");
            revert RateLimitCount(retryAfter, "Too many requests");
        }
    }

    /**
     * @notice Internal function to check gas consumption limits
     * @dev Prevents economic attacks by limiting total gas usage per window
     * @param user The user address to check
     * @param operaId The operation identifier
     * @param startGas The gas left at the start of the operation (for gas tracking)
     */
    function _checkGasLimit(address user, bytes32 operaId, uint256 startGas) internal {
        GasRateLimit storage gl = userGasStates[user][operaId];
        // Skip if no gas limit configured for this operation
        if (gl.maxGasPerWindow == 0) return;

        // Calculate gas used in this call (include 50k overhead for function calls)
        uint256 gasUsedThisCall = startGas - gasleft() + 50_000;
        uint256 currentTime = block.timestamp;

        // Reset gas tracking window if expired
        if (currentTime >= gl.windowStart + GAS_WINDOW) {
            gl.windowStart = currentTime;
            gl.gasUsed = gasUsedThisCall;
            return;
        }

        // Accumulate gas usage (unchecked for gas optimization)
        unchecked {
            gl.gasUsed += gasUsedThisCall;
        }

        // Check if gas limit exceeded
        if (gl.gasUsed > gl.maxGasPerWindow) {
            uint256 retryAfter = GAS_WINDOW - (currentTime - gl.windowStart);
            emit RateLimitExceeded(user, operaId, "Gas limit exceeded");
            revert RateLimitCount(retryAfter, "Gas budget exhausted");
        }
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                         ADMIN FUNCTIONS                                          */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Configure tiered rate limits for an operation
     * @dev Sets both the tiered request limits and the time window
     * @param opName The operation name (e.g., "PLACE_ORDER")
     * @param basic Limit for Basic tier users
     * @param premium Limit for Premium tier users
     * @param vip Limit for VIP tier users
     * @param marketMaker Limit for Market Maker tier users
     * @param timeWindow Time window in seconds for request counting
     */
    function setTieredLimit(
        string calldata opName,
        uint256 basic,
        uint256 premium,
        uint256 vip,
        uint256 marketMaker,
        uint256 timeWindow
    ) external onlyAdmin {
        if (timeWindow == 0) revert InvalidConfig();

        bytes32 operationId = _opId(opName);
        tieredLimits[operationId] = TieredRateLimit(basic, premium, vip, marketMaker);
        configs[operationId] = RateLimitConfig(timeWindow, true);

        emit TieredLimitsSet(operationId, basic, premium, vip, marketMaker);
        emit RateLimitConfigured(operationId, timeWindow);
    }

    /**
     * @notice Configure gas limits for an operation
     * @dev Sets the maximum gas consumption allowed per time window
     * @param opName The operation name
     * @param maxGasPerWindow Maximum gas units allowed per 5-minute window
     */
    function setGasLimit(string calldata opName, uint256 maxGasPerWindow) external onlyAdmin {
        bytes32 operationId = _opId(opName);
        gasLimits[operationId] = GasRateLimit(maxGasPerWindow, 0, block.timestamp);
        emit GasLimitSet(operationId, maxGasPerWindow);
    }

    /**
     * @notice Upgrade or change a user's tier
     * @dev Used to assign appropriate rate limits based on user status
     * @param user The user address to upgrade
     * @param newTier The new tier to assign
     */
    function upgradeUserTier(address user, UserTier newTier) external onlyAdmin {
        if (user == address(0)) revert ZeroAddress();
        userTier[user] = newTier;
        emit UserTierUpgraded(user, newTier);
    }

    /**
     * @notice Set whitelist status for an address
     * @dev Whitelisted addresses bypass all rate limiting
     * @param account The address to modify
     * @param status True to whitelist, false to remove
     */
    function setWhitelist(address account, bool status) external onlyAdmin {
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    /**
     * @notice Set emergency bypass status for an address
     * @dev Emergency bypass allows critical functions during protocol emergencies
     * @param account The address to modify
     * @param status True to grant emergency bypass, false to revoke
     */
    function setEmergencyBypass(address account, bool status) external onlyAdmin {
        emergencyBypass[account] = status;
        emit EmergencyBypassUpdated(account, status);
    }

    /**
     * @notice Set keeper status for an address
     * @dev Keepers use specialized rate limits different from regular users
     * @param account The address to modify
     * @param status True to mark as keeper, false to remove
     */
    function setKeeperStatus(address account, bool status) external onlyAdmin {
        isKeeper[account] = status;
        emit KeeperStatusUpdated(account, status);
    }

    /**
     * @notice Configure keeper-specific rate limits
     * @dev Keepers have different operational patterns than regular users
     * @param opName The operation name
     * @param basic Basic keeper limit
     * @param premium Premium keeper limit
     * @param vip VIP keeper limit
     * @param marketMaker Market maker keeper limit
     */
    function setKeeperLimits(string calldata opName, uint256 basic, uint256 premium, uint256 vip, uint256 marketMaker)
        external
        onlyAdmin
    {
        bytes32 operationId = _opId(opName);
        keeperLimits[operationId] = TieredRateLimit(basic, premium, vip, marketMaker);
        emit TieredLimitsSet(operationId, basic, premium, vip, marketMaker);
    }

    /**
     * @notice Toggle global rate limiting on/off
     * @dev Emergency function to disable all rate limits temporarily
     */
    function toggleGlobal() external onlyAdmin {
        globalEnabled = !globalEnabled;
        emit GlobalToggled(globalEnabled);
    }

    /**
     * @notice Transfer admin privileges to a new address
     * @dev Important security function - should be used with care
     * @param newAdmin The new admin address
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    /**
     * @notice Reset rate limit state for a user and operation
     * @dev Emergency function to clear stuck rate limit states
     * @param user The user address
     * @param opName The operation name
     */
    function resetRateLimitState(address user, string calldata opName) external onlyAdmin {
        bytes32 operationId = _opId(opName);
        delete userStates[user][operationId];
        delete userGasStates[user][operationId];
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                      INTERNAL HELPERS                                           */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Internal function to set tiered limits with configuration
     * @dev Used in constructor for initial setup
     */
    function _setTieredLimit(
        string memory opName,
        uint256 basic,
        uint256 premium,
        uint256 vip,
        uint256 marketMaker,
        uint256 timeWindow
    ) internal {
        bytes32 operationId = _opId(opName);
        tieredLimits[operationId] = TieredRateLimit(basic, premium, vip, marketMaker);
        configs[operationId] = RateLimitConfig(timeWindow, true);
    }

    /**
     * @notice Internal function to set gas limit
     * @dev Used in constructor for initial setup
     */
    function _setGasLimit(string memory opName, uint256 maxGasPerWindow) internal {
        bytes32 operationId = _opId(opName);
        gasLimits[operationId] = GasRateLimit(maxGasPerWindow, 0, block.timestamp);
    }

    /**
     * @notice Internal function to set configuration
     * @dev Used in constructor for initial setup
     */
    function _setConfig(string memory opName, uint256 timeWindow) internal {
        bytes32 operationId = _opId(opName);
        configs[operationId] = RateLimitConfig(timeWindow, true);
    }

    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/
    /*                                         VIEW FUNCTIONS                                           */
    /*══════════════════════════════════════════════════════════════════════════════════════════════════*/

    /**
     * @notice Get the current tier for a user
     * @param user The user address to query
     * @return The user's current tier
     */
    function getUserTier(address user) external view returns (UserTier) {
        return userTier[user];
    }

    /**
     * @notice Get remaining requests for a user and operation
     * @dev Returns UNLIMITED for whitelisted users or disabled operations
     * @param user The user address to query
     * @param opName The operation name to check
     * @return Number of remaining requests in current window
     */
    function remainingRequests(address user, string calldata opName) external view returns (uint256) {
        // Unlimited for whitelisted or globally disabled
        if (!globalEnabled || whitelist[user]) return UNLIMITED;

        bytes32 operationId = _opId(opName);
        RateLimitConfig memory cfg = configs[operationId];
        // Unlimited if operation not enabled
        if (!cfg.enabled) return UNLIMITED;

        TieredRateLimit memory limits = tieredLimits[operationId];
        uint256 allowed = _getLimitForUser(user, limits, operationId);

        RateLimitState memory state = userStates[user][operationId];

        // Full allowance in new window
        if (block.timestamp >= state.windowStart + cfg.timeWindow) return allowed;

        // Calculate remaining in current window
        return state.requestCount >= allowed ? 0 : allowed - state.requestCount;
    }

    /**
     * @notice Get remaining gas allowance for a user and operation
     * @param user The user address to query
     * @param opName The operation name to check
     * @return Remaining gas units available in current window
     */
    function remainingGas(address user, string calldata opName) external view returns (uint256) {
        bytes32 operationId = _opId(opName);
        GasRateLimit memory gl = userGasStates[user][operationId];

        if (gl.maxGasPerWindow == 0) return UNLIMITED;
        if (block.timestamp >= gl.windowStart + GAS_WINDOW) return gl.maxGasPerWindow;

        return gl.gasUsed >= gl.maxGasPerWindow ? 0 : gl.maxGasPerWindow - gl.gasUsed;
    }

    /**
     * @notice Check if an operation would be allowed for a user
     * @param user The user address to check
     * @param opName The operation name to check
     * @return allowed True if the operation would be allowed
     * @return retryAfter Seconds until rate limit resets (0 if allowed)
     */
    function checkRateLimitView(address user, string calldata opName)
        external
        view
        returns (bool allowed, uint256 retryAfter)
    {
        if (!globalEnabled || whitelist[user]) return (true, 0);

        bytes32 operationId = _opId(opName);
        RateLimitConfig memory cfg = configs[operationId];
        if (!cfg.enabled) return (true, 0);

        TieredRateLimit memory limits = tieredLimits[operationId];
        uint256 userLimit = _getLimitForUser(user, limits, operationId);

        RateLimitState memory state = userStates[user][operationId];
        uint256 currentTime = block.timestamp;

        if (currentTime >= state.windowStart + cfg.timeWindow) {
            return (true, 0);
        }

        if (state.requestCount >= userLimit) {
            retryAfter = (state.windowStart + cfg.timeWindow) - currentTime;
            return (false, retryAfter);
        }

        return (true, 0);
    }

    /**
     * @notice Internal function to get rate limit for a user based on tier and keeper status
     * @param user The user address
     * @param limits The tiered limits configuration
     * @param operationId The operation identifier
     * @return The applicable rate limit for the user
     */
    function _getLimitForUser(address user, TieredRateLimit memory limits, bytes32 operationId)
        internal
        view
        returns (uint256)
    {
        // Keepers use specialized limits
        if (isKeeper[user]) {
            TieredRateLimit memory keeperLimit = keeperLimits[operationId];
            UserTier currentTier = userTier[user];

            if (currentTier == UserTier.MarketMaker) return keeperLimit.marketMaker;
            if (currentTier == UserTier.VIP) return keeperLimit.vip;
            if (currentTier == UserTier.Premium) return keeperLimit.premium;
            return keeperLimit.basic;
        }

        // Regular users use standard tiered limits
        UserTier currentTier = userTier[user];
        if (currentTier == UserTier.MarketMaker) return limits.marketMaker;
        if (currentTier == UserTier.VIP) return limits.vip;
        if (currentTier == UserTier.Premium) return limits.premium;
        return limits.basic;
    }

    /**
     * @notice Generate operation ID from operation name
     * @param name The operation name
     * @return The keccak256 hash of the operation name
     */
    function _opId(string memory name) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    /**
     * @notice Get operation ID for an operation name
     * @param name The operation name
     * @return The operation ID used in storage mappings
     */
    function opId(string calldata name) external pure returns (bytes32) {
        return _opId(name);
    }
}
