// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AddressUtils} from "./AddressUtils.sol";

/**
 * @title SafeTransfer — BAOBAB Ultra-Optimized Transfer Library
 * @notice Zero-dependency (except IERC20 + AddressUtils), USDT-safe, mainnet-proven
 * @dev Integrated with AddressUtils for bulletproof validation
 *      Used in: FeeDistributor, TradingEngine, LiquidationEngine, Vaults, Staking
 */
library SafeTransfer {
    using AddressUtils for address;

    error TransferFailed();
    error TransferFromFailed();
    error ETHTransferFailed();

    /*╔══════════════════════════════════════════════════════════════════════╗
      ║                          ERC20 TRANSFERS                             ║
      ╚══════════════════════════════════════════════════════════════════════╝*/

    /// @dev Standard transfer — validates recipient ≠ 0

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        to.validateNotZero();
        if (amount == 0) return;

        _rawTransfer(token, to, amount);
    }

    /// @dev Transfer + validate recipient is a contract (e.g. vault, staking)
    function safeTransferToContract(IERC20 token, address to, uint256 amount) internal {
        to.validateContract();
        if (amount == 0) return;

        _rawTransfer(token, to, amount);
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        from.validateNotZero();
        to.validateNotZero();
        if (amount == 0) return;

        bool success;
        assembly {
            let memPtr := mload(0x40)

            mstore(memPtr, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(memPtr, 0x04), and(from, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(memPtr, 0x24), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(memPtr, 0x44), amount)

            success := call(gas(), token, 0, memPtr, 0x64, memPtr, 0x20)
            if and(success, or(eq(returndatasize(), 0), and(eq(returndatasize(), 32), gt(mload(memPtr), 0)))) {
                success := true
            }
        }
        if (!success) revert TransferFromFailed();
    }

    /*╔══════════════════════════════════════════════════════════════════════╗
      ║                            NATIVE ETH                                ║
      ╚══════════════════════════════════════════════════════════════════════╝*/

    function safeSendETH(address to, uint256 amount) internal {
        to.validateNotZero();
        if (amount == 0) return;

        bool success;
        assembly {
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }
        if (!success) revert ETHTransferFailed();
    }

    /*╔══════════════════════════════════════════════════════════════════════╗
      ║                          INTERNAL RAW CALL                           ║
      ╚══════════════════════════════════════════════════════════════════════╝*/

    /// @dev Raw assembly transfer — shared core
    function _rawTransfer(IERC20 token, address to, uint256 amount) private {
        bool success;
        assembly {
            let memPtr := mload(0x40)

            mstore(memPtr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(memPtr, 0x04), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(memPtr, 0x24), amount)

            success := call(gas(), token, 0, memPtr, 0x44, memPtr, 0x20)
            if and(success, or(eq(returndatasize(), 0), and(eq(returndatasize(), 32), gt(mload(memPtr), 0)))) {
                success := true
            }
        }
        if (!success) revert TransferFailed();
    }
}
