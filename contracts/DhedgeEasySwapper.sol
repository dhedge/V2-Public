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

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IPoolLogic.sol";
import "./interfaces/uniswapv2/IUniswapV2Router.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DhedgeEasySwapper is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  event Deposit(
    address pool,
    address depositor,
    address depositAsset,
    uint256 amount,
    address poolDepositAsset,
    uint256 liquidityMinted
  );
  event Withdraw(
    address pool,
    uint256 fundTokenAmount,
    address withdrawalAsset,
    uint256 amountWithdrawnInWithdrawalAsset
  );

  address payable public feeSink;
  uint256 public feeNumerator = 50;
  uint256 public feeDenominator = 1000;

  mapping(address => bool) public allowedPools;
  IERC20 public weth;
  IUniswapV2Router public swapRouter;

  // non erc20 assets -> aaveLendingPool etc
  mapping(address => bool) public assetsToSkip;

  constructor(
    address payable _feeSink,
    IUniswapV2Router _swapRouter,
    IERC20 _weth
  ) {
    feeSink = _feeSink;
    swapRouter = _swapRouter;
    weth = _weth;
  }

  function setPoolAllowed(address pool, bool allowed) external onlyOwner {
    allowedPools[pool] = allowed;
  }

  function setFee(uint256 numerator, uint256 denominator) external onlyOwner {
    require(feeDenominator > feeNumerator, "numerator must be < denominator");
    feeNumerator = numerator;
    feeDenominator = denominator;
  }

  function setFeeSink(address payable sink) external onlyOwner {
    feeSink = sink;
  }

  function setAssetToSkip(address asset, bool skip) external onlyOwner {
    assetsToSkip[asset] = skip;
  }

  function setSwapRouter(IUniswapV2Router _swapRouter) external onlyOwner {
    swapRouter = _swapRouter;
  }

  /// @notice deposit into underlying pool and receive tokens that aren't locked
  /// @param pool the pool to deposit into
  /// @param depositAsset the asset the user wants to deposit
  /// @param amount the amount of the deposit asset
  /// @param poolDepositAsset the asset that the pool accepts
  /// @param expectedLiquidityMinted the expected amount of pool tokens to receive (slippage protection)
  /// @return liquidityMinted the number of wrapper tokens allocated
  function deposit(
    address pool,
    IERC20 depositAsset,
    uint256 amount,
    IERC20 poolDepositAsset,
    uint256 expectedLiquidityMinted
  ) external returns (uint256 liquidityMinted) {
    require(allowedPools[address(pool)], "Pool is not allowed.");
    // Transfer the users funds to this contract
    depositAsset.safeTransferFrom(msg.sender, address(this), amount);

    if (depositAsset != poolDepositAsset) {
      swapThat(depositAsset, poolDepositAsset);
    }

    // Sweep fee to sink
    if (feeNumerator > 0 && feeDenominator > 0 && feeSink != address(0)) {
      poolDepositAsset.safeTransfer(
        feeSink,
        poolDepositAsset.balanceOf(address(this)).div(feeDenominator).mul(feeNumerator)
      );
    }

    // Approve the pool to take the funds
    poolDepositAsset.safeApprove(address(pool), poolDepositAsset.balanceOf(address(this)));
    // Deposit
    liquidityMinted = IPoolLogic(pool).deposit(address(poolDepositAsset), poolDepositAsset.balanceOf(address(this)));

    require(liquidityMinted >= expectedLiquidityMinted, "Deposit Slippage detected");
    // // Transfer the pool tokens to the depositer
    IERC20(pool).safeTransfer(msg.sender, liquidityMinted);
    emit Deposit(pool, msg.sender, address(depositAsset), amount, address(poolDepositAsset), liquidityMinted);
  }

  /// @notice withdraw underlying value of tokens in expectedWithdrawalAssetOfUser
  /// @dev Swaps the underlying pool withdrawal assets to expectedWithdrawalAssetOfUser
  /// @param fundTokenAmount the amount to withdraw
  /// @param withdrawalAsset must have direct pair to all pool.supportedAssets on swapRouter
  /// @param expectedAmountOut the amount of value in the withdrawalAsset expected (slippage protection)
  function withdraw(
    address pool,
    uint256 fundTokenAmount,
    IERC20 withdrawalAsset,
    uint256 expectedAmountOut
  ) external {
    require(allowedPools[pool], "Pool is not allowed.");
    IERC20(pool).safeTransferFrom(msg.sender, address(this), fundTokenAmount);
    IPoolLogic(pool).withdraw(fundTokenAmount);
    // Pools that have aave enabled withdraw weth to the user. This isnt in supportedAssets somestimes :(
    swapThat(weth, withdrawalAsset);

    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic())
      .getSupportedAssets();

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      IERC20 from = IERC20(supportedAssets[i].asset);
      if (assetsToSkip[address(from)]) {
        continue;
      }
      swapThat(from, withdrawalAsset);
    }

    uint256 balanceAfterSwaps = withdrawalAsset.balanceOf(address(this));
    require(balanceAfterSwaps >= expectedAmountOut, "Withdraw Slippage detected");
    withdrawalAsset.safeTransfer(msg.sender, balanceAfterSwaps);
    emit Withdraw(pool, fundTokenAmount, address(withdrawalAsset), balanceAfterSwaps);
  }

  /// @notice Swaps from an asset to the expectedWithdrawalAssetOfUser
  /// @dev get on the floor
  /// @param from asset to swap from
  function swapThat(IERC20 from, IERC20 to) internal {
    if (from == to) {
      return;
    }

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
