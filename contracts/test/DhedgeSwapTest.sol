// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

// We import the contract so truffle compiles it, and we have the ABI
// available when working from truffle console.
import "../utils/DhedgeSwap.sol";
import "../interfaces/uniswapv2/IUniswapV2Router.sol";

contract DhedgeSwapTest {
  using DhedgeSwap for IUniswapV2Router;

  IUniswapV2Router public swapRouter;
  // solhint-disable-next-line state-visibility
  address weth;

  constructor(address _swapRouter, address _weth) {
    swapRouter = IUniswapV2Router(_swapRouter);
    weth = _weth;
  }

  function swapTokensIn(
    address from,
    address to,
    uint256 amountIn
  ) public {
    swapRouter.swapTokensIn(weth, from, to, amountIn);
  }

  function swapTokensOut(
    address from,
    address to,
    uint256 amountOut
  ) public {
    swapRouter.swapTokensOut(weth, from, to, amountOut);
  }
}
