// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

// We import the contract so truffle compiles it, and we have the ABI
// available when working from truffle console.
import "../DhedgeEasySwapper.sol";
import "../interfaces/IPoolLogic.sol";
import "../interfaces/IPoolLogic.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FlashSwapperTest {
  function flashSwap(
    DhedgeEasySwapper swapper,
    address pool,
    IERC20 depositToken,
    uint256 amount
  ) public {
    depositToken.transferFrom(msg.sender, address(this), amount);
    depositToken.approve(address(swapper), amount);
    uint256 fundTokenAmount = swapper.deposit(pool, depositToken, amount, depositToken, 1);
    // Should revert, cannot deposit withdraw in same block
    IERC20(pool).approve(address(swapper), fundTokenAmount);
    swapper.withdraw(pool, fundTokenAmount, depositToken, 1);
  }

  // Only toros pools
  function flashSwapHakorMod3(
    DhedgeEasySwapper swapper,
    address pool,
    IERC20 depositToken,
    uint256 amount
  ) public {
    depositToken.transferFrom(msg.sender, address(this), amount);
    depositToken.approve(address(swapper), amount);
    uint256 fundTokenAmount = swapper.deposit(pool, depositToken, amount, depositToken, 1);
    // Should revert, cannot deposit withdraw in same block
    IERC20(pool).approve(pool, fundTokenAmount);
    IPoolLogic(pool).withdraw(fundTokenAmount);
  }
}

// Mint with swapper
// Transfer to different address
// With different address withdraw

// only one person
