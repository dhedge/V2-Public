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
import "../../utils/uniswap/UniswapV3PriceLibrary.sol";

/// @title Uniswap V3 asset guard
/// @dev Asset type = 7
contract UniswapV3AssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;
  using PositionValue for INonfungiblePositionManager;

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

    UniswapV3NonfungiblePositionGuard guard = UniswapV3NonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    for (uint256 i = 0; i < tokenIds.length; ++i) {
      uint256 tokenId = tokenIds[i];
      UniV3PoolParams memory poolParams;
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

      poolParams.sqrtPriceX96 = UniswapV3PriceLibrary.assertFairPrice(
        factory,
        nonfungiblePositionManager.factory(),
        poolParams.token0,
        poolParams.token1,
        poolParams.fee
      );

      (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.total(tokenId, poolParams.sqrtPriceX96);

      balance = balance.add(_assetValue(factory, poolParams.token0, amount0)).add(
        _assetValue(factory, poolParams.token1, amount1)
      );
    }
  }

  function _assetValue(address factory, address token, uint256 amount) internal view returns (uint256) {
    if (IHasAssetInfo(factory).isValidAsset(token)) {
      uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token);
      return tokenPriceInUsd.mul(amount).div(10 ** IERC20Extended(token).decimals());
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
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    // withdraw Processing
    // for each nft Position:
    // 1. decrease liuidity of a position based on the portion
    // 2. collect fees + decreased principals directly to user

    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(asset);

    address factory = IPoolLogic(pool).factory();
    UniswapV3NonfungiblePositionGuard guard = UniswapV3NonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    uint256 txCount;
    transactions = new MultiTransaction[](tokenIds.length.mul(2));
    for (uint256 i = 0; i < tokenIds.length; ++i) {
      DecreaseLiquidity memory decreaseLiquidity = _calcDecreaseLiquidity(
        nonfungiblePositionManager,
        tokenIds[i],
        portion
      );

      if (decreaseLiquidity.lpAmount != 0) {
        // decrease liquidity
        transactions[txCount].to = address(nonfungiblePositionManager);
        transactions[txCount].txData = abi.encodeWithSelector(
          INonfungiblePositionManager.decreaseLiquidity.selector,
          INonfungiblePositionManager.DecreaseLiquidityParams(
            tokenIds[i],
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
            tokenIds[i],
            to, // recipient
            uint128(decreaseLiquidity.amount0),
            uint128(decreaseLiquidity.amount1)
          )
        );
        txCount++;
      }
    }

    // Reduce length the empty items
    uint256 reduceLength = tokenIds.length.mul(2).sub(txCount);
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

    decreaseLiquidity.lpAmount = uint128(portion.mul(liquidity).div(10 ** 18));

    (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee)).slot0();

    (decreaseLiquidity.amount0, decreaseLiquidity.amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      decreaseLiquidity.lpAmount
    );

    (uint256 feeAmount0, uint256 feeAmount1) = nonfungiblePositionManager.fees(tokenId);
    decreaseLiquidity.amount0 = decreaseLiquidity.amount0.add(feeAmount0.mul(portion).div(10 ** 18));
    decreaseLiquidity.amount1 = decreaseLiquidity.amount1.add(feeAmount1.mul(portion).div(10 ** 18));
  }
}
