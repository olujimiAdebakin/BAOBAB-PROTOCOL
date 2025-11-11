// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AccessManager} from "./AccessManager.sol";
import {RoleRegistry} from "./RoleRegistry.sol";

/**
 * @title ProtocolOwner
 * @author BAOBAB Protocol
 * @notice Owner-specific administrative functions and protocol governance
 * @dev Inherits from AccessManager for role-based control
 *
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 *                                       PROTOCOL OWNER
 * ═══════════════════════════════════════════════════════════════════════════════════════════════════
 */
contract ProtocolOwner {
    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                       STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /// @notice Access control manager
    AccessManager public immutable accessManager;

    /// @notice Protocol treasury address
    address public treasury;

    /// @notice Insurance vault address
    address public insuranceVault;

    /// @notice Fee recipient address
    address public feeRecipient;

    /// @notice Protocol pause state
    bool public protocolPaused;

    /// @notice Emergency withdrawal enabled
    bool public emergencyWithdrawalEnabled;

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event InsuranceVaultUpdated(address indexed oldVault, address indexed newVault);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event ProtocolPauseToggled(bool paused);
    event EmergencyWithdrawalToggled(bool enabled);
    event EmergencyFundsRecovered(address indexed token, address indexed to, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                           ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    error ProtocolOwner__OnlyOwner();
    error ProtocolOwner__InvalidAddress();
    error ProtocolOwner__ProtocolPaused();
    error ProtocolOwner__EmergencyWithdrawalNotEnabled();

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                         CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    constructor(address _accessManager, address _treasury, address _insuranceVault, address _feeRecipient) {
        if (
            _accessManager == address(0) || _treasury == address(0) || _insuranceVault == address(0)
                || _feeRecipient == address(0)
        ) {
            revert ProtocolOwner__InvalidAddress();
        }

        accessManager = AccessManager(_accessManager);
        treasury = _treasury;
        insuranceVault = _insuranceVault;
        feeRecipient = _feeRecipient;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                          MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (!accessManager.hasRole(RoleRegistry.OWNER_ROLE, msg.sender)) {
            revert ProtocolOwner__OnlyOwner();
        }
        _;
    }

    modifier whenNotPaused() {
        if (protocolPaused) revert ProtocolOwner__ProtocolPaused();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    ADDRESS MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ProtocolOwner__InvalidAddress();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Update insurance vault address
     * @param newVault New insurance vault address
     */
    function setInsuranceVault(address newVault) external onlyOwner {
        if (newVault == address(0)) revert ProtocolOwner__InvalidAddress();

        address oldVault = insuranceVault;
        insuranceVault = newVault;

        emit InsuranceVaultUpdated(oldVault, newVault);
    }

    /**
     * @notice Update fee recipient address
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ProtocolOwner__InvalidAddress();

        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;

        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                     PROTOCOL CONTROL
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Toggle protocol pause state
     * @dev Affects all trading operations
     */
    function toggleProtocolPause() external onlyOwner {
        protocolPaused = !protocolPaused;
        emit ProtocolPauseToggled(protocolPaused);
    }

    /**
     * @notice Enable emergency withdrawal mode
     * @dev Allows users to withdraw funds during critical issues
     */
    function enableEmergencyWithdrawal() external onlyOwner {
        emergencyWithdrawalEnabled = true;
        emit EmergencyWithdrawalToggled(true);
    }

    /**
     * @notice Disable emergency withdrawal mode
     */
    function disableEmergencyWithdrawal() external onlyOwner {
        emergencyWithdrawalEnabled = false;
        emit EmergencyWithdrawalToggled(false);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                    EMERGENCY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Recover stuck tokens (emergency use only)
     * @param token Token address
     * @param to Recipient address
     * @param amount Amount to recover
     * @dev Only owner, requires emergency withdrawal enabled
     */
    function recoverFunds(address token, address to, uint256 amount) external onlyOwner {
        if (!emergencyWithdrawalEnabled) {
            revert ProtocolOwner__EmergencyWithdrawalNotEnabled();
        }
        if (to == address(0)) revert ProtocolOwner__InvalidAddress();

        // Transfer tokens
        (bool success,) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(success, "Transfer failed");

        emit EmergencyFundsRecovered(token, to, amount);
    }

    /**
     * @notice Recover stuck ETH (emergency use only)
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverETH(address payable to, uint256 amount) external onlyOwner {
        if (!emergencyWithdrawalEnabled) {
            revert ProtocolOwner__EmergencyWithdrawalNotEnabled();
        }
        if (to == address(0)) revert ProtocolOwner__InvalidAddress();

        (bool success,) = to.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit EmergencyFundsRecovered(address(0), to, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════════════════════
    //                                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if protocol is paused
     * @return bool True if paused
     */
    function isPaused() external view returns (bool) {
        return protocolPaused;
    }

    /**
     * @notice Check if emergency withdrawal is enabled
     * @return bool True if enabled
     */
    function isEmergencyWithdrawalEnabled() external view returns (bool) {
        return emergencyWithdrawalEnabled;
    }

    /**
     * @notice Get protocol configuration
     * @return _treasury Treasury address
     * @return _insuranceVault Insurance vault address
     * @return _feeRecipient Fee recipient address
     * @return _paused Protocol pause state
     * @return _emergencyEnabled Emergency withdrawal state
     */
    function getProtocolConfig()
        external
        view
        returns (
            address _treasury,
            address _insuranceVault,
            address _feeRecipient,
            bool _paused,
            bool _emergencyEnabled
        )
    {
        return (treasury, insuranceVault, feeRecipient, protocolPaused, emergencyWithdrawalEnabled);
    }
}
