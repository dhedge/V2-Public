//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "./interfaces/IPoolLogic.sol";
import "./interfaces/uniswapv2/IUniswapV2Router.sol";
import "./interfaces/IHasSupportedAsset.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

// Ownable with a setter for the router?
contract DhedgeEasySwapper is Ownable {
  using SignedSafeMath for int256;

  mapping(address => bool) public allowedPools;
  ERC20 public weth;
  IUniswapV2Router public swapRouter;

  constructor(IUniswapV2Router _swapRouter, ERC20 _weth) {
    swapRouter = _swapRouter;
    weth = _weth;
  }

  function setPoolAllowed(address pool, bool allowed) external onlyOwner {
    allowedPools[pool] = allowed;
  }

  function setSwapRouter(IUniswapV2Router _swapRouter) external onlyOwner {
    swapRouter = _swapRouter;
  }

  /// @notice deposit into underlying pool and receive tokens that aren't locked
  /// @param depositAsset the deposit asset
  /// @param amount the amount of the deposit asset
  /// @return liquidityMinted the number of wrapper tokens allocated
  function deposit(
    IPoolLogic pool,
    ERC20 depositAsset,
    uint256 amount
  ) external returns (uint256 liquidityMinted) {
    require(allowedPools[pool], "Pool is not allowed.");
    // Transfer the users funds to this contract
    depositAsset.transferFrom(msg.sender, address(this), amount);
    // Approve the pool to take the funds
    depositAsset.approve(address(pool), amount);
    // Deposit
    liquidityMinted = pool.deposit(address(depositAsset), amount);
    pool.transfer(msg.sender, liquidityMinted);
  }

  /// @notice withdraw underlying value of tokens in expectedWithdrawalAssetOfUser
  /// @dev Swaps the underlying pool withdrawal assets to expectedWithdrawalAssetOfUser
  /// @param fundTokenAmount the amount to withdraw
  /// @param withdrawalAsset must have direct pair to all pool.supportedAssets on swapRouter
  /// @param expectedAmountOutInWithdrawalAsset the amount of value in the expectedAmountOutInWithdrawalAsset expected (slippage protection)
  function withdraw(
    IPoolLogic pool,
    uint256 fundTokenAmount,
    ERC20 withdrawalAsset,
    uint256 expectedAmountOutInWithdrawalAsset
  ) external {
    require(allowedPools[pool], "Pool is not allowed.");
    // burn wrapper tokens
    pool.transferFrom(msg.sender, address(this), fundTokenAmount);
    pool.withdraw(fundTokenAmount);
    // Pools that have aave enabled withdraw weth to the user. This isnt in supportedAssets somestimes :(
    swapThat(weth, withdrawalAsset);

    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(pool.poolManagerLogic())
      .getSupportedAssets();

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      ERC20 from = ERC20(supportedAssets[i].asset);
      if (from == withdrawalAsset) {
        continue;
      }
      swapThat(from, withdrawalAsset);
    }

    uint256 balanceAfterSwaps = withdrawalAsset.balanceOf(address(this));
    if (balanceAfterSwaps < expectedAmountOutInWithdrawalAsset) {
      revert("Slippage detected");
    }
    withdrawalAsset.transfer(msg.sender, balanceAfterSwaps);
  }

  /// @notice Swaps from an asset to the expectedWithdrawalAssetOfUser
  /// @dev get on the floor
  /// @param from asset to swap from
  function swapThat(ERC20 from, ERC20 to) internal {
    uint256 balance = from.balanceOf(address(this));
    if (balance == 0) {
      return;
    }

    from.approve(address(swapRouter), balance);

    address[] memory path = new address[](2);
    path[0] = address(from);
    path[1] = address(to);

    swapRouter.swapExactTokensForTokens(balance, 0, path, address(this), uint256(-1));
  }
}
