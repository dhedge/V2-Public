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

// Ownable with a setter for the router?
contract DhedgeEasyWithdrawWrapper is ERC20 {
  using SignedSafeMath for int256;

  IPoolLogic public pool;
  // usdc
  ERC20 public expectDepositAssetOfPool;
  // usdc
  ERC20 public expectedWithdrawalAssetOfUser;
  ERC20 public weth;
  IUniswapV2Router public swapRouter;

  constructor(
    string memory name,
    string memory symbol,
    IPoolLogic _pool,
    ERC20 _expectDepositAssetOfPool,
    ERC20 _expectedWithdrawalAssetOfUser,
    IUniswapV2Router _swapRouter,
    ERC20 _weth
  ) ERC20(name, symbol) {
    pool = _pool;
    expectDepositAssetOfPool = _expectDepositAssetOfPool;
    expectedWithdrawalAssetOfUser = _expectedWithdrawalAssetOfUser;
    swapRouter = _swapRouter;
    weth = _weth;
  }

  /// @notice deposit into underlying pool and receive wrapper tokens
  /// @param amount the amount of the deposit asset to deposit
  /// @return liquidityMinted the number of wrapper tokens allocated
  function deposit(uint256 amount) external returns (uint256 liquidityMinted) {
    // Transfer the users funds to this contract
    expectDepositAssetOfPool.transferFrom(msg.sender, address(this), amount);
    // Approve the pool to take the funds
    expectDepositAssetOfPool.approve(address(pool), amount);
    // Deposit
    liquidityMinted = pool.deposit(address(expectDepositAssetOfPool), amount);
    // We issue matching wrapper tokens to the depositor
    _mint(msg.sender, liquidityMinted);
  }

  /// @notice withdraw underlying value of tokens in expectedWithdrawalAssetOfUser
  /// @dev Swaps the underlying pool withdrawal assets to expectedWithdrawalAssetOfUser
  /// @param fundTokenAmount the amount to withdraw
  /// @param expectedAmountOutInWithdrawalAsset the amount of value in the expectedAmountOutInWithdrawalAsset expected (slippage protection)
  function withdraw(uint256 fundTokenAmount, uint256 expectedAmountOutInWithdrawalAsset) external {
    // burn wrapper tokens
    _burn(msg.sender, fundTokenAmount);
    pool.withdraw(fundTokenAmount);
    // Pools that have aave enabled withdraw weth to the user. This isnt in supportedAssets :(
    swapThat(weth);
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(pool.poolManagerLogic())
      .getSupportedAssets();
    for (uint256 i = 0; i < supportedAssets.length; i++) {
      ERC20 from = ERC20(supportedAssets[i].asset);
      if (from == expectedWithdrawalAssetOfUser) {
        continue;
      }
      swapThat(from);
    }

    uint256 balanceAfterSwaps = expectedWithdrawalAssetOfUser.balanceOf(address(this));
    if (balanceAfterSwaps < expectedAmountOutInWithdrawalAsset) {
      revert("Slippage detected");
    }
    expectedWithdrawalAssetOfUser.transfer(msg.sender, balanceAfterSwaps);
  }

  /// @notice Swaps from an asset to the expectedWithdrawalAssetOfUser
  /// @dev get on the floor
  /// @param from asset to swap from
  function swapThat(ERC20 from) internal {
    uint256 balance = from.balanceOf(address(this));
    if (balance == 0) {
      return;
    }

    from.approve(address(swapRouter), balance);
    address to = address(expectedWithdrawalAssetOfUser);

    address[] memory path = new address[](2);
    path[0] = address(from);
    path[1] = to;

    swapRouter.swapExactTokensForTokens(balance, 0, path, address(this), uint256(-1));
  }

  /// @notice allows the token holder to withdraw assets directly from underlying pool incase to much slippage for single asset withdrawal or bad liquidity
  function emergencyWithdraw(uint256 fundTokenAmount) external {
    // burn wrapper tokens
    _burn(msg.sender, fundTokenAmount);
    pool.withdraw(fundTokenAmount);
    // Withdraw all the assets that have come from the pool
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(pool.poolManagerLogic())
      .getSupportedAssets();
    for (uint256 i = 0; i < supportedAssets.length; i++) {
      ERC20 asset = ERC20(supportedAssets[i].asset);
      uint256 balance = asset.balanceOf(address(this));
      if (balance > 0) {
        asset.transfer(msg.sender, balance);
      }
    }
  }
}
