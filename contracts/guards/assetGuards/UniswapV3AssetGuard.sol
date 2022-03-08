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
import "../../utils/DhedgeMath.sol";
import "../contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol";

/// @title Uniswap V3 asset guard
/// @dev Asset type = 6
contract UniswapV3AssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;
  using SafeMathUpgradeable for uint160;
  using PositionValue for INonfungiblePositionManager;

  // Number of seconds in the past from which to calculate the time-weighted means
  uint32 public priceUpdateInterval = 2 minutes;

  struct UniV3PoolParams {
    address token0;
    address token1;
    uint24 fee;
    uint160 sqrtPriceX96;
  }

  /// @notice Returns the pool position of Uniswap v3
  /// @dev Returns the balance priced in USD
  /// @param pool The pool logic address
  /// @return balance The total balance of the pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();
    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(asset);

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
      UniV3PoolParams memory poolParams;
      uint256 tokenId = nonfungiblePositionManager.tokenOfOwnerByIndex(pool, i);
      (, , poolParams.token0, poolParams.token1, poolParams.fee, , , , , , , ) = nonfungiblePositionManager.positions(
        tokenId
      );

      // If either of the underlying LP tokens are unsupported, then skip the NFT
      if (
        !IHasAssetInfo(factory).isValidAsset(poolParams.token0) ||
        !IHasAssetInfo(factory).isValidAsset(poolParams.token1)
      ) {
        continue;
      }

      // Get a fair sqrtPriceX96 from asset price oracles
      uint160 fairSqrtPriceX96 = _getFairSqrtPriceX96(factory, poolParams.token0, poolParams.token1);

      (poolParams.sqrtPriceX96, , , , , , ) = IUniswapV3Pool(
        IUniswapV3Factory(nonfungiblePositionManager.factory()).getPool(
          poolParams.token0,
          poolParams.token1,
          poolParams.fee
        )
      ).slot0();

      // Check that fair price is close to current pool price (0.25% threshold)
      require(
        poolParams.sqrtPriceX96 < fairSqrtPriceX96.add(fairSqrtPriceX96.div(400)) &&
          fairSqrtPriceX96 < poolParams.sqrtPriceX96.add(fairSqrtPriceX96.div(400)),
        "Uni v3 LP price mismatch"
      );

      (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.total(tokenId, fairSqrtPriceX96);

      balance = balance.add(_assetValue(factory, poolParams.token0, amount0)).add(
        _assetValue(factory, poolParams.token1, amount1)
      );
    }
  }

  /// @notice Returns the Uni pool square root price based on underlying oracle prices
  /// @param factory dHEDGE Factory address
  /// @param token0 Uni pool token0
  /// @param token1 Uni pool token1
  /// @return sqrtPriceX96 square root price as a Q64.96
  function _getFairSqrtPriceX96(
    address factory,
    address token0,
    address token1
  ) internal view returns (uint160 sqrtPriceX96) {
    uint256 token0Price = IHasAssetInfo(factory).getAssetPrice(token0);
    uint256 token1Price = IHasAssetInfo(factory).getAssetPrice(token1);
    uint8 token0Decimals = IERC20Extended(token0).decimals();
    uint8 token1Decimals = IERC20Extended(token1).decimals();
    uint256 priceRatio = token0Price.mul(10**token1Decimals).div(token1Price);

    // Overflow protection for the price ratio shift left
    bool overflowProtection;
    if (priceRatio > 10**18) {
      overflowProtection = true;
      priceRatio = priceRatio.div(10**10); // decrease 10 decimals
    }
    require(priceRatio <= 10**18 && priceRatio > 1000, "Uni v3 price ratio out of bounds");

    sqrtPriceX96 = uint160(DhedgeMath.sqrt((priceRatio << 192).div(10**token0Decimals)));

    if (overflowProtection) {
      sqrtPriceX96 = uint160(sqrtPriceX96.mul(10**5)); // increase 5 decimals (revert adjustment)
    }
  }

  function _assetValue(
    address factory,
    address token,
    uint256 amount
  ) internal view returns (uint256) {
    if (IHasAssetInfo(factory).isValidAsset(token)) {
      uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token);
      return tokenPriceInUsd.mul(amount).div(10**IERC20Extended(token).decimals());
    } else {
      return 0;
    }
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
    address asset,
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
    // 2. collect fees + decreased principals directly to user

    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(asset);
    uint256 length = nonfungiblePositionManager.balanceOf(pool);
    uint256 txCount;
    transactions = new MultiTransaction[](length.mul(2));
    for (uint256 i = 0; i < length; ++i) {
      uint256 tokenId = nonfungiblePositionManager.tokenOfOwnerByIndex(pool, i);
      DecreaseLiquidity memory decreaseLiquidity = _calcDecreaseLiquidity(nonfungiblePositionManager, tokenId, portion);

      if (decreaseLiquidity.lpAmount != 0) {
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
      }

      // collect fees
      if (decreaseLiquidity.amount0 != 0 || decreaseLiquidity.amount1 != 0) {
        transactions[txCount].to = address(nonfungiblePositionManager);
        transactions[txCount].txData = abi.encodeWithSelector(
          INonfungiblePositionManager.collect.selector,
          INonfungiblePositionManager.CollectParams(
            tokenId,
            to, // recipient
            uint128(decreaseLiquidity.amount0),
            uint128(decreaseLiquidity.amount1)
          )
        );
        txCount++;
      }
    }

    // Reduce length the empty items
    uint256 reduceLength = length.mul(2).sub(txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  // for stack too deep
  struct DecreaseLiquidity {
    uint128 lpAmount;
    uint256 amount0;
    uint256 amount1;
  }

  /// @notice Calculates liquidity withdraw balances
  /// @param tokenId nft position id
  /// @param portion withdraw portion
  /// @return decreaseLiquidity withdraw info
  function _calcDecreaseLiquidity(
    INonfungiblePositionManager nonfungiblePositionManager,
    uint256 tokenId,
    uint256 portion
  ) internal view returns (DecreaseLiquidity memory decreaseLiquidity) {
    IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(nonfungiblePositionManager.factory());
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

    decreaseLiquidity.lpAmount = uint128(portion.mul(liquidity).div(10**18));

    (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee)).slot0();

    (decreaseLiquidity.amount0, decreaseLiquidity.amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      decreaseLiquidity.lpAmount
    );

    (uint256 feeAmount0, uint256 feeAmount1) = nonfungiblePositionManager.fees(tokenId);
    decreaseLiquidity.amount0 = decreaseLiquidity.amount0.add(feeAmount0.mul(portion).div(10**18));
    decreaseLiquidity.amount1 = decreaseLiquidity.amount1.add(feeAmount1.mul(portion).div(10**18));
  }
}
