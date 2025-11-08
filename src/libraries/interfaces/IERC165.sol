// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC165
 * @dev https://eips.ethereum.org/EIPS/eip-165
 * @notice Standard interface detection
 */
interface IERC165 {

        // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // EIP-165 INTERFACE FOR ERC165 SUPPORT
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /**
     * @notice Query if a contract implements an interface
     * @param interfaceId The interface identifier, as specified in ERC-165
     * @dev Interface identification is decentralized — no registration needed
     * @return `true` if the contract implements `interfaceId`, `false` otherwise
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}