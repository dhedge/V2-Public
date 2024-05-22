// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "../../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";
import "../../interfaces/IERC20Extended.sol";

library EasySwapperSwap {
  /// @notice Swaps from an asset to another asset
  /// @param swapRouter the swapRouter to use
  /// @param from asset to swap from
  /// @param to asset to swap to
  function swapThat(IUniswapV2RouterSwapOnly swapRouter, IERC20Extended from, IERC20Extended to) internal {
    if (from == to) {
      return;
    }

    uint256 balance = from.balanceOf(address(this));

    if (balance > 0) {
      from.approve(address(swapRouter), balance);
      address[] memory path = new address[](2);
      path[0] = address(from);
      path[1] = address(to);
      swapRouter.swapExactTokensForTokens(balance, 0, path, address(this), uint256(-1));
    }
  }
}
