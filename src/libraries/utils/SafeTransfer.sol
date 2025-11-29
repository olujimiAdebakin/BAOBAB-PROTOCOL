// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title SafeTransfer
 * @notice Gas-optimized, battle-tested ERC20/ETH transfer library
 * @dev Used across ALL BAOBAB contracts (FeeDistributor, LiquidationEngine, Vaults, etc.)
 *      → Handles missing return value (USDT issue)
 *      → Reverts on failure with clear message
 *      → Optimized assembly for ETH
 */
library SafeTransfer {
    using Address for address;

    /*╔══════════════════════════════════════════════════════════════════════╗
      ║                               ERC20                                  ║
      ╚══════════════════════════════════════════════════════════════════════╝*/

    /// @dev Transfers ERC20 tokens with proper return value checking
    function safeTransfer ERC20(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;
        require(to != address(0), "SafeTransfer: to 0");

        bool success;
        /// @solidity memory-safe-assembly
        assembly {
            // Get free memory pointer
            let memPtr := mload(0x40)

            // selector for transfer(address,uint256)
            mstore(memPtr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(memPtr, 0x04), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(memPtr, 0x24), amount)

            // 36 bytes total: 4 selector + 32 addr + 32 amount
            success := call(gas(), token, 0, memPtr, 0x44, memPtr, 0x20)

            // Check return data size + value
            if and(success, eq(returndatasize(), 0x20)) {
                success := and(success, gt(mload(memPtr), 0))
            }
        }
        require(success, "SafeTransfer: ERC20 transfer failed");
    }

    /// @dev Transfers ERC20 from msg.sender → to
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;
        require(from != address(0) && to != address(0), "SafeTransfer: 0 addr");

        bool success;
        assembly {
            let memPtr := mload(0x40)

            // selector for transferFrom(address,address,uint256)
            mstore(memPtr, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(memPtr, 0x04), and(from, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(memPtr, 0x24), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(memPtr, 0x44), amount)

            success := call(gas(), token, 0, memPtr, 0x64, memPtr, 0x20)

            if and(success, eq(returndatasize(), 0x20)) {
                success := and(success, gt(mload(memPtr), 0))
            }
        }
        require(success, "SafeTransfer: transferFrom failed");
    }

    /*╔══════════════════════════════════════════════════════════════════════╗
      ║                               NATIVE ETH                             ║
      ╚══════════════════════════════════════════════════════════════════════╝*/

    /// @dev Sends ETH with safety checks
    function safeSendETH(address to, uint256 amount) internal {
        if (amount == 0) return;
        require(to != address(0), "SafeTransfer: ETH to 0");

        bool success;
        assembly {
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }
        require(success, "SafeTransfer: ETH send failed");
    }
}