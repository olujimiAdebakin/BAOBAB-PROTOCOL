// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title SecurityBase
 * @author BAOBAB Protocol
 * @notice Base security contract providing reentrancy protection and common security patterns
 * @dev All protocol contracts should inherit from this for baseline security
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                        SECURITY BASE
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
abstract contract SecurityBase {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev Reentrancy guard states
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev Reentrancy guard status
    uint256 private _status;

    /// @dev Global pause state
    bool private _paused;

    /// @dev Contract initialization state
    bool private _initialized;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when contract is paused
     * @param account Address that triggered pause
     */
    event Paused(address account);

    /**
     * @notice Emitted when contract is unpaused
     * @param account Address that triggered unpause
     */
    event Unpaused(address account);

    /**
     * @notice Emitted when contract is initialized
     * @param account Address that initialized contract
     */
    event Initialized(address account);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when reentrancy is detected
    error ReentrancyGuard__ReentrantCall();

    /// @notice Thrown when operation attempted while paused
    error SecurityBase__ContractPaused();

    /// @notice Thrown when operation requires contract to be paused
    error SecurityBase__ContractNotPaused();

    /// @notice Thrown when contract is already initialized
    error SecurityBase__AlreadyInitialized();

    /// @notice Thrown when operation attempted before initialization
    error SecurityBase__NotInitialized();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor() {
        _status = _NOT_ENTERED;
        _paused = false;
        _initialized = false;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Prevents reentrancy attacks
     * @dev Uses OpenZeppelin's reentrancy guard pattern
     */
    modifier nonReentrant() {
        if (_status == _ENTERED) {
            revert ReentrancyGuard__ReentrantCall();
        }

        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /**
     * @notice Ensures function can only be called when not paused
     */
    modifier whenNotPaused() {
        if (_paused) {
            revert SecurityBase__ContractPaused();
        }
        _;
    }

    /**
     * @notice Ensures function can only be called when paused
     */
    modifier whenPaused() {
        if (!_paused) {
            revert SecurityBase__ContractNotPaused();
        }
        _;
    }

    /**
     * @notice Ensures contract is initialized before execution
     */
    modifier onlyInitialized() {
        if (!_initialized) {
            revert SecurityBase__NotInitialized();
        }
        _;
    }

    /**
     * @notice Ensures contract can only be initialized once
     */
    modifier initializer() {
        if (_initialized) {
            revert SecurityBase__AlreadyInitialized();
        }
        _initialized = true;
        emit Initialized(msg.sender);
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Pauses the contract
     * @dev Only callable by inheriting contracts
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by inheriting contracts
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @notice Checks if contract is paused
     * @return bool True if paused
     */
    function _isPaused() internal view returns (bool) {
        return _paused;
    }

    /**
     * @notice Checks if contract is initialized
     * @return bool True if initialized
     */
    function _isInitialized() internal view returns (bool) {
        return _initialized;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns whether the contract is paused
     * @return bool True if paused
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @notice Returns whether the contract is initialized
     * @return bool True if initialized
     */
    function initialized() public view virtual returns (bool) {
        return _initialized;
    }
}