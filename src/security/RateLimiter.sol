// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title RateLimiter
 * @author BAOBAB Protocol
 * @notice Protects against DoS attacks and spam by limiting operation frequency
 * @dev Implements token bucket algorithm with configurable limits per operation type
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                        RATE LIMITER
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
contract RateLimiter {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Rate limit configuration
     * @param maxRequests Maximum requests allowed in time window
     * @param timeWindow Time window in seconds
     * @param enabled Whether rate limit is active
     */
    struct RateLimitConfig {
        uint256 maxRequests;
        uint256 timeWindow;
        bool enabled;
    }

    /**
     * @notice User rate limit state
     * @param requestCount Number of requests in current window
     * @param windowStart Start of current time window
     * @param lastRequestTime Last request timestamp
     */
    struct RateLimitState {
        uint256 requestCount;
        uint256 windowStart;
        uint256 lastRequestTime;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Per-operation rate limit configurations
    mapping(bytes32 => RateLimitConfig) public rateLimitConfigs;

    /// @notice Per-user, per-operation rate limit states
    mapping(address => mapping(bytes32 => RateLimitState)) public rateLimitStates;

    /// @notice Whitelist addresses (bypass rate limits)
    mapping(address => bool) public whitelist;

    /// @notice Admin address
    address public admin;

    /// @notice Global rate limiter enabled/disabled
    bool public globalEnabled;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event RateLimitConfigured(
        bytes32 indexed operationId,
        uint256 maxRequests,
        uint256 timeWindow
    );

    event RateLimitExceeded(
        address indexed user,
        bytes32 indexed operationId,
        uint256 timestamp
    );

    event WhitelistUpdated(address indexed account, bool whitelisted);
    event GlobalStateToggled(bool enabled);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error RateLimiter__RateLimitExceeded(uint256 retryAfter);
    error RateLimiter__OnlyAdmin();
    error RateLimiter__InvalidConfig();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor(address _admin) {
        if (_admin == address(0)) revert RateLimiter__InvalidConfig();
        admin = _admin;
        globalEnabled = true;

        // Default configurations
        _setRateLimit("PLACE_ORDER", 10, 1 minutes);
        _setRateLimit("CANCEL_ORDER", 20, 1 minutes);
        _setRateLimit("ADD_LIQUIDITY", 5, 1 minutes);
        _setRateLimit("REMOVE_LIQUIDITY", 5, 1 minutes);
        _setRateLimit("CLAIM_REWARDS", 1, 1 hours);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyAdmin() {
        if (msg.sender != admin) revert RateLimiter__OnlyAdmin();
        _;
    }

    modifier rateLimited(bytes32 operationId) {
        checkRateLimit(msg.sender, operationId);
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                   RATE LIMIT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check and update rate limit for user operation
     * @param user User address
     * @param operationId Operation identifier
     * @dev Reverts if rate limit exceeded
     */
    function checkRateLimit(address user, bytes32 operationId) public {
        // Skip if globally disabled or user is whitelisted
        if (!globalEnabled || whitelist[user]) return;

        RateLimitConfig memory config = rateLimitConfigs[operationId];
        
        // Skip if operation has no rate limit
        if (!config.enabled || config.maxRequests == 0) return;

        RateLimitState storage state = rateLimitStates[user][operationId];

        // Check if we're in a new time window
        if (block.timestamp >= state.windowStart + config.timeWindow) {
            // Reset window
            state.windowStart = block.timestamp;
            state.requestCount = 1;
            state.lastRequestTime = block.timestamp;
            return;
        }

        // Increment request count in current window
        state.requestCount++;
        state.lastRequestTime = block.timestamp;

        // Check if limit exceeded
        if (state.requestCount > config.maxRequests) {
            uint256 retryAfter = (state.windowStart + config.timeWindow) - block.timestamp;
            
            emit RateLimitExceeded(user, operationId, block.timestamp);
            revert RateLimiter__RateLimitExceeded(retryAfter);
        }
    }

    /**
     * @notice Check if operation would exceed rate limit
     * @param user User address
     * @param operationId Operation identifier
     * @return allowed True if operation is allowed
     * @return retryAfter Seconds until rate limit resets (0 if allowed)
     */
    function checkRateLimitView(
        address user,
        bytes32 operationId
    ) public view returns (bool allowed, uint256 retryAfter) {
        // Allow if globally disabled or user is whitelisted
        if (!globalEnabled || whitelist[user]) return (true, 0);

        RateLimitConfig memory config = rateLimitConfigs[operationId];
        
        // Allow if operation has no rate limit
        if (!config.enabled || config.maxRequests == 0) return (true, 0);

        RateLimitState memory state = rateLimitStates[user][operationId];

        // Allow if in new time window
        if (block.timestamp >= state.windowStart + config.timeWindow) {
            return (true, 0);
        }

        // Check if adding one more request would exceed limit
        if (state.requestCount >= config.maxRequests) {
            retryAfter = (state.windowStart + config.timeWindow) - block.timestamp;
            return (false, retryAfter);
        }

        return (true, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Configure rate limit for an operation
     * @param operationName Operation name (e.g., "PLACE_ORDER")
     * @param maxRequests Maximum requests allowed
     * @param timeWindow Time window in seconds
     */
    function configureRateLimit(
        string calldata operationName,
        uint256 maxRequests,
        uint256 timeWindow
    ) external onlyAdmin {
        bytes32 operationId = keccak256(abi.encodePacked(operationName));
        _setRateLimit(operationName, maxRequests, timeWindow);
    }

    /**
     * @notice Enable/disable rate limit for an operation
     * @param operationName Operation name
     * @param enabled Whether rate limit is enabled
     */
    function toggleRateLimit(
        string calldata operationName,
        bool enabled
    ) external onlyAdmin {
        bytes32 operationId = keccak256(abi.encodePacked(operationName));
        rateLimitConfigs[operationId].enabled = enabled;
    }

    /**
     * @notice Add address to whitelist
     * @param account Address to whitelist
     */
    function addToWhitelist(address account) external onlyAdmin {
        whitelist[account] = true;
        emit WhitelistUpdated(account, true);
    }

    /**
     * @notice Remove address from whitelist
     * @param account Address to remove
     */
    function removeFromWhitelist(address account) external onlyAdmin {
        whitelist[account] = false;
        emit WhitelistUpdated(account, false);
    }

    /**
     * @notice Toggle global rate limiter
     */
    function toggleGlobalRateLimiter() external onlyAdmin {
        globalEnabled = !globalEnabled;
        emit GlobalStateToggled(globalEnabled);
    }

    /**
     * @notice Reset rate limit state for a user
     * @param user User address
     * @param operationName Operation name
     * @dev Emergency function to clear stuck rate limits
     */
    function resetRateLimitState(
        address user,
        string calldata operationName
    ) external onlyAdmin {
        bytes32 operationId = keccak256(abi.encodePacked(operationName));
        delete rateLimitStates[user][operationId];
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal function to set rate limit
     * @param operationName Operation name
     * @param maxRequests Maximum requests
     * @param timeWindow Time window in seconds
     */
    function _setRateLimit(
        string memory operationName,
        uint256 maxRequests,
        uint256 timeWindow
    ) internal {
        if (timeWindow == 0) revert RateLimiter__InvalidConfig();
        
        bytes32 operationId = keccak256(abi.encodePacked(operationName));
        
        rateLimitConfigs[operationId] = RateLimitConfig({
            maxRequests: maxRequests,
            timeWindow: timeWindow,
            enabled: true
        });

        emit RateLimitConfigured(operationId, maxRequests, timeWindow);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get rate limit configuration for operation
     * @param operationName Operation name
     * @return config Rate limit configuration
     */
    function getRateLimitConfig(
        string calldata operationName
    ) external view returns (RateLimitConfig memory config) {
        bytes32 operationId = keccak256(abi.encodePacked(operationName));
        return rateLimitConfigs[operationId];
    }

    /**
     * @notice Get rate limit state for user and operation
     * @param user User address
     * @param operationName Operation name
     * @return state Rate limit state
     */
    function getRateLimitState(
        address user,
        string calldata operationName
    ) external view returns (RateLimitState memory state) {
        bytes32 operationId = keccak256(abi.encodePacked(operationName));
        return rateLimitStates[user][operationId];
    }

    /**
     * @notice Get remaining requests for user
     * @param user User address
     * @param operationName Operation name
     * @return remaining Number of requests remaining in current window
     */
    function getRemainingRequests(
        address user,
        string calldata operationName
    ) external view returns (uint256 remaining) {
        if (whitelist[user] || !globalEnabled) return type(uint256).max;

        bytes32 operationId = keccak256(abi.encodePacked(operationName));
        RateLimitConfig memory config = rateLimitConfigs[operationId];
        
        if (!config.enabled) return type(uint256).max;

        RateLimitState memory state = rateLimitStates[user][operationId];

        // If in new window, return full allowance
        if (block.timestamp >= state.windowStart + config.timeWindow) {
            return config.maxRequests;
        }

        // Return remaining in current window
        if (state.requestCount >= config.maxRequests) {
            return 0;
        }
        
        return config.maxRequests - state.requestCount;
    }

    /**
     * @notice Generate operation ID from name
     * @param operationName Operation name
     * @return bytes32 Operation ID
     */
    function getOperationId(string calldata operationName) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(operationName));
    }
}