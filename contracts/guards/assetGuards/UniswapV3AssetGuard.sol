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
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {PositionValue} from "@uniswap/v3-periphery/contracts/libraries/PositionValue.sol";

import {ClosedAssetGuard} from "./ClosedAssetGuard.sol";
import {UniswapV3NonfungiblePositionGuard} from "../contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {UniswapV3PriceLibrary} from "../../utils/uniswap/UniswapV3PriceLibrary.sol";

/// @title Uniswap V3 asset guard
/// @dev Asset type = 7
/// @dev The managed asset is the NonfungiblePositionManager, so the pool's position is a set of ERC721
///      token IDs tracked by the contract guard rather than a fungible balance.
contract UniswapV3AssetGuard is ClosedAssetGuard {
  using SafeMath for uint256;
  using PositionValue for INonfungiblePositionManager;

  /// @dev Grouped to avoid stack too deep in `getBalance`
  struct UniV3PoolParams {
    address token0;
    address token1;
    uint24 fee;
    uint160 sqrtPriceX96;
  }

  /// @dev Grouped to avoid stack too deep in `withdrawProcessing`
  struct DecreaseLiquidity {
    uint128 lpAmount;
    uint256 amount0;
    uint256 amount1;
  }

  /// @notice Returns the value of the pool's Uniswap V3 positions
  /// @dev Returns the balance priced in USD, 18 decimals
  /// @param pool The pool logic address
  /// @param asset Address of the NonfungiblePositionManager
  /// @return balance The total balance of the pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();
    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(asset);

    UniswapV3NonfungiblePositionGuard guard = UniswapV3NonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    for (uint256 i; i < tokenIds.length; ++i) {
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

  /// @notice Returns the decimals of the Uniswap V3 position asset
  /// @dev Positions are valued in USD, which is always 18 decimals in this codebase
  /// @return decimals The decimals of the given asset
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates the transactions that unroll a portion of the pool's Uniswap V3 positions
  /// @dev For each tracked NFT position: decrease its liquidity by the portion, then collect the freed
  ///      principal along with the proportional share of accrued fees directly to the withdrawer.
  /// @dev `withdrawAsset` and `withdrawBalance` are intentionally left unset - nothing is paid out by
  ///      PoolLogic itself, the whole withdrawal happens through the returned transactions.
  /// @param pool Address of the pool
  /// @param asset Address of the NonfungiblePositionManager
  /// @param portion Portion of the pool's positions to withdraw, in 10^18 scale
  /// @param to Address receiving the withdrawn tokens
  /// @return withdrawAsset Unused by this guard, always the zero address
  /// @return withdrawBalance Unused by this guard, always zero
  /// @return transactions are used to execute the withdrawal transactions in PoolLogic
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
    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(asset);

    address factory = IPoolLogic(pool).factory();
    UniswapV3NonfungiblePositionGuard guard = UniswapV3NonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    uint256 txCount;
    transactions = new MultiTransaction[](tokenIds.length.mul(2));
    for (uint256 i; i < tokenIds.length; ++i) {
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

    // Shrink the array by the number of unused slots
    uint256 reduceLength = tokenIds.length.mul(2).sub(txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  function _assetValue(address factory, address token, uint256 amount) internal view returns (uint256) {
    if (IHasAssetInfo(factory).isValidAsset(token)) {
      uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token);
      return tokenPriceInUsd.mul(amount).div(10 ** IERC20Extended(token).decimals());
    } else {
      return 0;
    }
  }

  /// @param nonfungiblePositionManager Uniswap V3 NonfungiblePositionManager
  /// @param tokenId NFT position id
  /// @param portion Withdraw portion, in 10^18 scale
  /// @return decreaseLiquidity Liquidity to remove plus the token amounts it frees, fees included
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
