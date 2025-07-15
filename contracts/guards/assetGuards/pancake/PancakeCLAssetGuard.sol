// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IPancakeCLPool} from "../../../interfaces/pancake/IPancakeCLPool.sol";
import {IPancakeNonfungiblePositionManager} from "../../../interfaces/pancake/IPancakeNonfungiblePositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {ClosedAssetGuard} from "../ClosedAssetGuard.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IERC20Extended} from "../../../interfaces/IERC20Extended.sol";
import {PancakeNonfungiblePositionGuard} from "../../contractGuards/pancake/PancakeNonfungiblePositionGuard.sol";
import {UniswapV3PriceLibrary} from "../../../utils/uniswap/UniswapV3PriceLibrary.sol";
import {PancakeCLPositionValue} from "../../../utils/pancake/PancakeCLPositionValue.sol";

/// @title Pancake CL asset guard
/// @dev Asset type = 31
contract PancakeCLAssetGuard is ClosedAssetGuard {
  using SafeMath for uint256;
  using PancakeCLPositionValue for IPancakeNonfungiblePositionManager;

  address public stakingAddress;

  struct UniV3PoolParams {
    address token0;
    address token1;
    uint24 fee;
    uint160 sqrtPriceX96;
  }

  // for stack too deep
  struct DecreaseLiquidity {
    uint128 lpAmount;
    uint256 amount0;
    uint256 amount1;
  }

  /// @param _stakingAddress Pancake MasterchefV3 contract address
  constructor(address _stakingAddress) {
    stakingAddress = _stakingAddress;
  }

  /// @notice Returns the pool position of Uniswap v3
  /// @dev Returns the balance priced in USD
  /// @param pool The pool logic address
  /// @return balance The total balance of the pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();
    IPancakeNonfungiblePositionManager nonfungiblePositionManager = IPancakeNonfungiblePositionManager(asset);

    PancakeNonfungiblePositionGuard guard = PancakeNonfungiblePositionGuard(
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
    uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token);
    return tokenPriceInUsd.mul(amount).div(10 ** IERC20Extended(token).decimals());
  }

  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

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

    IPancakeNonfungiblePositionManager nonfungiblePositionManager = IPancakeNonfungiblePositionManager(asset);

    address factory = IPoolLogic(pool).factory();
    PancakeNonfungiblePositionGuard guard = PancakeNonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    uint256 txCount;
    transactions = new MultiTransaction[](tokenIds.length.mul(2));
    for (uint256 i = 0; i < tokenIds.length; ++i) {
      address txToAddress = nonfungiblePositionManager.ownerOf(tokenIds[i]) == stakingAddress
        ? stakingAddress
        : address(nonfungiblePositionManager);

      DecreaseLiquidity memory decreaseLiquidity = _calcDecreaseLiquidity(
        nonfungiblePositionManager,
        tokenIds[i],
        portion
      );

      if (decreaseLiquidity.lpAmount != 0) {
        // decrease liquidity
        transactions[txCount].to = txToAddress;
        transactions[txCount].txData = abi.encodeWithSelector(
          IPancakeNonfungiblePositionManager.decreaseLiquidity.selector,
          IPancakeNonfungiblePositionManager.DecreaseLiquidityParams(
            tokenIds[i],
            decreaseLiquidity.lpAmount,
            0,
            0,
            type(uint256).max
          )
        );
        txCount++;
      }

      // collect tokens
      if (decreaseLiquidity.amount0 != 0 || decreaseLiquidity.amount1 != 0) {
        transactions[txCount].to = txToAddress;
        transactions[txCount].txData = abi.encodeWithSelector(
          IPancakeNonfungiblePositionManager.collect.selector,
          IPancakeNonfungiblePositionManager.CollectParams(
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
    uint256 reduceLength = transactions.length.sub(txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Calculates liquidity withdraw balances
  /// @param tokenId nft position id
  /// @param portion withdraw portion
  /// @return decreaseLiquidity withdraw info
  function _calcDecreaseLiquidity(
    IPancakeNonfungiblePositionManager nonfungiblePositionManager,
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

    (uint160 sqrtPriceX96, , , , , , ) = IPancakeCLPool(uniswapV3Factory.getPool(token0, token1, fee)).slot0();

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
