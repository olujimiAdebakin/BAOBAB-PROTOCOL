// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title AddressUtils
 * @author BAOBAB Protocol
 * @notice Comprehensive address validation and utility functions for secure DeFi operations
 * @dev Provides gas-optimized address checks, contract verification, and safety validations
 * @dev Essential for preventing common vulnerabilities and ensuring protocol security
 */
library AddressUtils {
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Reverts when address is zero
    error ZeroAddress();
    
    /// @dev Reverts when address is not a contract
    error NotAContract();
    
    /// @dev Reverts when contract call fails
    error CallFailed();
    
    /// @dev Reverts when delegate call is not allowed to target
    error DelegateCallNotAllowed();

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ADDRESS VALIDATION
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate that address is not zero
     * @param addr Address to validate
     * @dev Reverts with ZeroAddress if address is zero
     */
    function validateNotZero(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Validate that address is a contract
     * @param addr Address to validate
     * @dev Reverts with NotAContract if address is not a contract
     * @dev Uses extcodesize > 0 check (note: may return false during constructor execution)
     */
    function validateContract(address addr) internal view {
        if (addr == address(0)) revert ZeroAddress();
        if (addr.code.length == 0) revert NotAContract();
    }

    /**
     * @notice Check if address is a contract
     * @param addr Address to check
     * @return isContract True if address is a contract
     * @dev Returns false during contract construction
     */
    function isContract(address addr) internal view returns (bool) {
        return addr.code.length > 0;
    }

    /**
     * @notice Check if address is zero
     * @param addr Address to check
     * @return isZero True if address is zero
     */
    function isZero(address addr) internal pure returns (bool) {
        return addr == address(0);
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CONTRACT INTERACTION SAFETY
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Perform a safe call to a contract with value
     * @param target Target contract address
     * @param value ETH value to send
     * @param data Call data
     * @return success Whether the call succeeded
     * @return returnData Return data from the call
     */
    function functionCallWithValue(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool success, bytes memory returnData) {
        validateContract(target);
        
        (success, returnData) = target.call{value: value}(data);
        if (!success) revert CallFailed();
    }

    /**
     * @notice Perform a static call to a contract
     * @param target Target contract address
     * @param data Call data
     * @return success Whether the call succeeded
     * @return returnData Return data from the call
     */
    function functionStaticCall(
        address target,
        bytes memory data
    ) internal view returns (bool success, bytes memory returnData) {
        validateContract(target);
        
        (success, returnData) = target.staticcall(data);
        if (!success) revert CallFailed();
    }

    /**
     * @notice Perform a delegate call to a contract with safety checks
     * @param target Target contract address
     * @param data Call data
     * @param allowedTargets Mapping of allowed delegate call targets
     * @return success Whether the call succeeded
     * @return returnData Return data from the call
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        mapping(address => bool) storage allowedTargets
    ) internal returns (bool success, bytes memory returnData) {
        validateContract(target);
        
        if (!allowedTargets[target]) revert DelegateCallNotAllowed();
        
        (success, returnData) = target.delegatecall(data);
        if (!success) revert CallFailed();
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ADDRESS CONVERSIONS & UTILITIES
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert address to payable
     * @param addr Address to convert
     * @return payableAddr Payable address
     */
    function toPayable(address addr) internal pure returns (address payable) {
        return payable(addr);
    }

    /**
     * @notice Convert address to bytes32
     * @param addr Address to convert
     * @return bytes32 representation of address
     */
    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /**
     * @notice Convert bytes32 to address
     * @param b Bytes32 to convert
     * @return addr Address representation
     */
    function toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    /**
     * @notice Get contract creation code hash
     * @param addr Contract address
     * @return codeHash Hash of contract creation code
     */
    function getCodeHash(address addr) internal view returns (bytes32) {
        return addr.codehash;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ARRAY OPERATIONS FOR ADDRESSES
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if address array contains specific address
     * @param arr Array of addresses
     * @param target Address to find
     * @return contains True if array contains target
     */
    function contains(address[] memory arr, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == target) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Find index of address in array
     * @param arr Array of addresses
     * @param target Address to find
     * @return index Index of address, or -1 if not found
     */
    function indexOf(address[] memory arr, address target) internal pure returns (int256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == target) {
                return int256(i);
            }
        }
        return -1;
    }

    /**
     * @notice Remove address from array
     * @param arr Array of addresses
     * @param target Address to remove
     * @return newArray New array without the target address
     * @dev Reverts if address not found
     */
    function remove(address[] memory arr, address target) internal pure returns (address[] memory) {
        int256 index = indexOf(arr, target);
        if (index == -1) revert("Address not found in array");
        
        address[] memory newArray = new address[](arr.length - 1);
        uint256 newIndex = 0;
        
        for (uint256 i = 0; i < arr.length; i++) {
            if (i != uint256(index)) {
                newArray[newIndex] = arr[i];
                newIndex++;
            }
        }
        
        return newArray;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // SECURITY CHECKS & VALIDATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if address is a contract and implements specific interface
     * @param addr Address to check
     * @param interfaceId Interface identifier to check
     * @return implementsInterface True if contract implements the interface
     */
    function supportsInterface(address addr, bytes4 interfaceId) internal view returns (bool) {
        if (!isContract(addr)) return false;
        
        try IERC165(addr).supportsInterface(interfaceId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    /**
     * @notice Validate multiple addresses are not zero
     * @param addresses Array of addresses to validate
     */
    function validateMultipleNotZero(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            validateNotZero(addresses[i]);
        }
    }

    /**
     * @notice Validate multiple addresses are contracts
     * @param addresses Array of addresses to validate
     */
    function validateMultipleContracts(address[] memory addresses) internal view {
        for (uint256 i = 0; i < addresses.length; i++) {
            validateContract(addresses[i]);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // GAS-OPTIMIZED ASSEMBLY OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Gas-optimized zero address check using assembly
     * @param addr Address to check
     * @return isZeroAddr True if address is zero
     */
    function isZeroAssembly(address addr) internal pure returns (bool) {
        assembly {
            isZeroAddr := iszero(addr)
        }
    }

    /**
     * @notice Gas-optimized contract existence check using assembly
     * @param addr Address to check
     * @return isContractAddr True if address is a contract
     */
    function isContractAssembly(address addr) internal view returns (bool) {
        assembly {
            isContractAddr := gt(extcodesize(addr), 0)
        }
    }

    /**
     * @notice Get contract code size using assembly
     * @param addr Address to check
     * @return codeSize Size of contract code
     */
    function getCodeSize(address addr) internal view returns (uint256) {
        assembly {
            codeSize := extcodesize(addr)
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // EIP-165 INTERFACE FOR ERC165 SUPPORT
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev Interface for EIP-165 support check
    interface IERC165 {
        function supportsInterface(bytes4 interfaceId) external view returns (bool);
    }
}