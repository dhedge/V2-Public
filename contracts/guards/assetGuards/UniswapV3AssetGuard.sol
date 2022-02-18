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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionValue.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./ERC20Guard.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IERC20Extended.sol";
import "../contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol";

/// @title Uniswap V3 asset guard
/// @dev Asset type = 6
contract UniswapV3AssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;
  using PositionValue for INonfungiblePositionManager;

  IUniswapV3Factory public uniswapV3Factory;
  INonfungiblePositionManager public nonfungiblePositionManager;

  // Number of seconds in the past from which to calculate the time-weighted means
  uint32 public priceUpdateInterval = 2 minutes;

  constructor(address _nonfungiblePositionManager) {
    // solhint-disable-next-line reason-string
    require(_nonfungiblePositionManager != address(0), "_nonfungiblePositionManager address cannot be 0");

    uniswapV3Factory = IUniswapV3Factory(INonfungiblePositionManager(_nonfungiblePositionManager).factory());
    nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
  }

  /// @notice Returns the pool position of Uniswap v3
  /// @dev Returns the balance priced in ETH
  /// @param pool The pool logic address
  /// @return balance The total balance of the pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();

    uint256 length;
    {
      UniswapV3NonfungiblePositionGuard guard = UniswapV3NonfungiblePositionGuard(
        IHasGuardInfo(factory).getGuard(asset)
      );
      uint256 nftCount = nonfungiblePositionManager.balanceOf(pool);
      uint256 limit = guard.uniV3PositionsLimit();
      length = limit < nftCount ? limit : nftCount;
    }
    for (uint256 i = 0; i < length; ++i) {
      uint256 tokenId = nonfungiblePositionManager.tokenOfOwnerByIndex(pool, i);
      (, , address token0, address token1, uint24 fee, , , , , , , ) = nonfungiblePositionManager.positions(tokenId);
      // (
      //   uint96 nonce,
      //   address operator,
      //   address token0,
      //   address token1,
      //   uint24 fee,
      //   int24 tickLower,
      //   int24 tickUpper,
      //   uint128 liquidity,
      //   uint256 feeGrowthInside0LastX128,
      //   uint256 feeGrowthInside1LastX128,
      //   uint128 tokensOwed0,
      //   uint128 tokensOwed1
      // ) = nonfungiblePositionManager.positions(tokenId);

      (int24 tick, ) = OracleLibrary.consult(uniswapV3Factory.getPool(token0, token1, fee), priceUpdateInterval);
      uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
      (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.total(tokenId, sqrtRatioX96);

      balance = balance.add(_assetValue(factory, token0, amount0)).add(_assetValue(factory, token1, amount1));
    }
  }

  function _assetValue(
    address factory,
    address token,
    uint256 amount
  ) internal view returns (uint256) {
    uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token);
    return tokenPriceInUsd.mul(amount).div(10**IERC20Extended(token).decimals());
  }

  /// @notice Returns decimal of the Aave lending pool asset
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @dev Withdrawal processing is not applicable for this guard
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool,
    address, // asset
    uint256 portion,
    address to
  )
    external
    view
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      MultiTransaction[] memory transactions
    )
  {
    // withdraw Processing
    // for each nft Position:
    // 1. decrease liuidity of a position based on the portion
    // 2. collect fees from the position
    // 3. transfer token0, token1 direcly to user. (token amount which was decreased from liquidity position)

    uint256 length = nonfungiblePositionManager.balanceOf(pool);
    uint256 txCount;
    transactions = new MultiTransaction[](length * 4);
    for (uint256 i = 0; i < length; ++i) {
      uint256 tokenId = nonfungiblePositionManager.tokenOfOwnerByIndex(pool, i);
      DecreaseLiquidity memory decreaseLiquidity = _calcDecreaseLiquidity(tokenId, portion);

      // decrease liquidity
      transactions[txCount].to = address(nonfungiblePositionManager);
      transactions[txCount].txData = abi.encodeWithSelector(
        INonfungiblePositionManager.decreaseLiquidity.selector,
        INonfungiblePositionManager.DecreaseLiquidityParams(
          tokenId,
          decreaseLiquidity.lpAmount,
          0,
          0,
          type(uint256).max
        )
      );
      txCount++;

      // collect fees
      transactions[txCount].to = address(nonfungiblePositionManager);
      if (decreaseLiquidity.feeAmount0 == 0 && decreaseLiquidity.feeAmount1 == 0) {
        transactions[txCount].txData = abi.encodeWithSelector(
          INonfungiblePositionManager.collect.selector,
          INonfungiblePositionManager.CollectParams(tokenId, pool, type(uint128).max, type(uint128).max)
        );
      } else {
        transactions[txCount].txData = abi.encodeWithSelector(
          INonfungiblePositionManager.collect.selector,
          INonfungiblePositionManager.CollectParams(
            tokenId,
            pool,
            uint128(decreaseLiquidity.feeAmount0),
            uint128(decreaseLiquidity.feeAmount1)
          )
        );
      }
      txCount++;

      // We directly transfer the amount of tokens we receive from decreasing by the withdrawers portion.
      // transfer token0 to user
      transactions[txCount].to = decreaseLiquidity.token0;
      transactions[txCount].txData = abi.encodeWithSelector(
        bytes4(keccak256("transfer(address,uint256)")),
        to, // recipient
        decreaseLiquidity.amount0.add(decreaseLiquidity.feeAmount0)
      );
      txCount++;

      // transfer token1 to user
      transactions[txCount].to = decreaseLiquidity.token1;
      transactions[txCount].txData = abi.encodeWithSelector(
        bytes4(keccak256("transfer(address,uint256)")),
        to, // recipient
        decreaseLiquidity.amount1.add(decreaseLiquidity.feeAmount1)
      );
      txCount++;
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  // for stack too deep
  struct DecreaseLiquidity {
    uint128 lpAmount;
    address token0;
    address token1;
    uint256 amount0;
    uint256 amount1;
    uint256 feeAmount0;
    uint256 feeAmount1;
  }

  /// @notice Calculates liquidity withdraw balances
  /// @param tokenId nft position id
  /// @param portion withdraw portion
  /// @return decreaseLiquidity withdraw info
  function _calcDecreaseLiquidity(uint256 tokenId, uint256 portion)
    internal
    view
    returns (DecreaseLiquidity memory decreaseLiquidity)
  {
    (
      ,
      ,
      address token0,
      address token1,
      uint24 fee,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      ,
      ,
      ,

    ) = nonfungiblePositionManager.positions(tokenId);

    decreaseLiquidity.token0 = token0;
    decreaseLiquidity.token1 = token1;
    decreaseLiquidity.lpAmount = uint128(portion.mul(liquidity).div(10**18));

    (int24 tick, ) = OracleLibrary.consult(uniswapV3Factory.getPool(token0, token1, fee), priceUpdateInterval);

    (decreaseLiquidity.amount0, decreaseLiquidity.amount1) = LiquidityAmounts.getAmountsForLiquidity(
      TickMath.getSqrtRatioAtTick(tick),
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      decreaseLiquidity.lpAmount
    );

    (uint256 feeAmount0, uint256 feeAmount1) = nonfungiblePositionManager.fees(tokenId);
    decreaseLiquidity.feeAmount0 = feeAmount0.mul(portion).div(10**18);
    decreaseLiquidity.feeAmount1 = feeAmount1.mul(portion).div(10**18);
  }
}
