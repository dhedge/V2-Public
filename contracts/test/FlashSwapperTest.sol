// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

// We import the contract so truffle compiles it, and we have the ABI
// available when working from truffle console.
import "../swappers/easySwapper/DhedgeEasySwapper.sol";
import "../interfaces/IPoolLogic.sol";
import "../interfaces/IPoolLogic.sol";
import "../interfaces/IERC20Extended.sol";

contract FlashSwapperTest {
  function flashSwap(DhedgeEasySwapper swapper, address pool, IERC20Extended depositToken, uint256 amount) public {
    depositToken.transferFrom(msg.sender, address(this), amount);
    depositToken.approve(address(swapper), amount);
    uint256 fundTokenAmount = swapper.depositWithCustomCooldown(pool, depositToken, amount, depositToken, 1);
    // Should revert, cannot deposit withdraw in same block
    IERC20(pool).approve(address(swapper), fundTokenAmount);
    swapper.withdraw(pool, fundTokenAmount, depositToken, 1);
  }

  // Only toros pools
  function flashSwapDirectWithdraw(
    DhedgeEasySwapper swapper,
    address pool,
    IERC20Extended depositToken,
    uint256 amount
  ) public {
    depositToken.transferFrom(msg.sender, address(this), amount);
    depositToken.approve(address(swapper), amount);
    uint256 fundTokenAmount = swapper.depositWithCustomCooldown(pool, depositToken, amount, depositToken, 1);
    // Should revert, cannot deposit withdraw in same bloc
    IPoolLogic(pool).withdraw(fundTokenAmount);
  }
}
