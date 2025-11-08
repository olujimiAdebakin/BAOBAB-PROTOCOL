// SPDX-License-Identifier: BUSL-1.1
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract TokenRescue {
    address public rescueAdmin;  // ← Only this address can rescue funds


    error OnlyRescueAdmin();


    /**
     * @notice Recover ERC-20 tokens sent to contract by mistake
     * @param token Token address (e.g. USDC, DAI)
     * @param amount Amount to rescue
     */
    function rescueERC20(address token, uint256 amount) external {
      
        if (msg.sender !== rescueAdmin){
            revert OnlyRescueAdmin();  // ← Access control
        }
        IERC20(token).transfer(rescueAdmin, amount);       // ← Send to admin
    }

    /**
     * @notice Recover ETH sent to contract
     */
    function rescueETH() external {
        if (msg.sender !== rescueAdmin){
            revert OnlyRescueAdmin();
        }
        payable(rescueAdmin).transfer(address(this).balance);  // ← Drain all ETH
    }
}