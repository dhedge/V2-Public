// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ERC20Guard} from "../ERC20Guard.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {RamsesNonfungiblePositionGuard} from "../../contractGuards/ramsesCL/RamsesNonfungiblePositionGuard.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {UniswapV3PriceLibrary} from "../../../utils/uniswap/UniswapV3PriceLibrary.sol";
import {IRamsesVoter} from "../../../interfaces/ramses/IRamsesVoter.sol";

import {IRamsesGaugeV2} from "../../../interfaces/ramses/IRamsesGaugeV2.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IRamsesNonfungiblePositionManager} from "../../../interfaces/ramses/IRamsesNonfungiblePositionManager.sol";
import {RamsesCLPositionValue} from "../../../utils/ramses/RamsesCLPositionValue.sol";
import {AddressArrayLib} from "../../../utils/ramses/AddressArrayLib.sol";

/// @title Ramses CL asset guard
/// @dev Asset type = 29
contract RamsesCLAssetGuard is ERC20Guard {
  using SafeCast for uint256;
  using SafeMath for uint256;
  using AddressArrayLib for address[];

  using RamsesCLPositionValue for IRamsesNonfungiblePositionManager;

  IRamsesVoter public voter;

  uint256 public constant MAX_NUMBER_OF_REWARD_TOKEN = 5;

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
    address to;
    uint256 portion;
    IRamsesNonfungiblePositionManager nonfungiblePositionManager;
    IUniswapV3Pool ramsesPool;
    IRamsesGaugeV2 gauge;
    uint256 validAssetCount;
    address[] validAssets;
    uint256[] validAssetAmounts;
    IHasSupportedAsset poolManagerLogic;
    IHasAssetInfo dHedgeFactory;
  }

  /// @dev We need Voter contract to get the gauge address
  /// @param voterAddress Ramses voter contract address
  constructor(address voterAddress) {
    voter = IRamsesVoter(voterAddress);
  }

  /// @notice Returns the pool position of Ramses CL
  /// @dev Returns the balance priced in USD
  /// @param pool The pool logic address
  /// @param asset Ramses CL asset
  /// @return balance The total balance of the pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();
    IRamsesNonfungiblePositionManager nonfungiblePositionManager = IRamsesNonfungiblePositionManager(asset);
    RamsesNonfungiblePositionGuard guard = RamsesNonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(IPoolLogic(pool).poolManagerLogic());
    address ramsesFactory = nonfungiblePositionManager.factory();

    for (uint256 i = 0; i < tokenIds.length; ++i) {
      balance = balance.add(
        _tokenBalance(factory, poolManagerLogic, nonfungiblePositionManager, tokenIds[i], ramsesFactory)
      );
    }
  }

  function _tokenBalance(
    address factory,
    IPoolManagerLogic poolManagerLogic,
    IRamsesNonfungiblePositionManager nonfungiblePositionManager,
    uint256 tokenId,
    address ramsesFactory
  ) internal view returns (uint256 tokenBalance) {
    UniV3PoolParams memory poolParams;
    (, , poolParams.token0, poolParams.token1, poolParams.fee, , , , , , , ) = nonfungiblePositionManager.positions(
      tokenId
    );

    // If either of the underlying LP tokens are unsupported, then skip the NFT
    if (
      !IHasAssetInfo(factory).isValidAsset(poolParams.token0) || !IHasAssetInfo(factory).isValidAsset(poolParams.token1)
    ) {
      return 0;
    }

    poolParams.sqrtPriceX96 = UniswapV3PriceLibrary.assertFairPrice(
      factory,
      ramsesFactory,
      poolParams.token0,
      poolParams.token1,
      poolParams.fee
    );

    IRamsesGaugeV2 gauge = IRamsesGaugeV2(
      voter.gauges(IUniswapV3Factory(ramsesFactory).getPool(poolParams.token0, poolParams.token1, poolParams.fee))
    );

    (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.total(tokenId, poolParams.sqrtPriceX96);

    tokenBalance = poolManagerLogic.assetValue(poolParams.token0, amount0).add(
      poolManagerLogic.assetValue(poolParams.token1, amount1)
    );

    address[] memory rewardTokens = gauge.getRewardTokens();

    for (uint256 i = 0; i < rewardTokens.length; ++i) {
      uint256 rewardAmount = gauge.earned(rewardTokens[i], tokenId);
      tokenBalance = tokenBalance.add(_assetValue(factory, poolManagerLogic, rewardTokens[i], rewardAmount));
    }

    return tokenBalance;
  }

  function _assetValue(
    address dHedgeFactory,
    IPoolManagerLogic poolManagerLogic,
    address token,
    uint256 amount
  ) internal view returns (uint256 assetValue) {
    if (IHasAssetInfo(dHedgeFactory).isValidAsset(token)) {
      assetValue = poolManagerLogic.assetValue(token, amount);
    } else {
      assetValue = 0;
    }
  }

  /// @notice Returns decimal of the VelodromeCL asset
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing RamsesCL LP tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset RamsesNonfungiblePositionManager
  /// @param portion Portion of the RamsesCL asset to withdraw
  /// @param to The investor address to withdraw to
  /// @return withdrawAsset Asset address to withdraw (Basically zero address)
  /// @return withdrawBalance Amount to withdraw (Basically zero amount)
  /// @return transactions Transactions to be executed (These is where actual token transfer happens)
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
    IRamsesNonfungiblePositionManager nonfungiblePositionManager = IRamsesNonfungiblePositionManager(asset);
    uint256 txCount;
    address factory = IPoolLogic(pool).factory();

    RamsesNonfungiblePositionGuard guard = RamsesNonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    // 3 transactions(decLp, collect, getReward) + reward tranfers, per token
    transactions = new MultiTransaction[](tokenIds.length.mul(3 + MAX_NUMBER_OF_REWARD_TOKEN));

    for (uint256 i = 0; i < tokenIds.length; ++i) {
      DecreaseLiquidity memory decreaseLiquidity;
      {
        decreaseLiquidity.to = to;
        decreaseLiquidity.nonfungiblePositionManager = nonfungiblePositionManager;
        decreaseLiquidity.portion = portion;
        decreaseLiquidity.poolManagerLogic = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic());
        decreaseLiquidity.dHedgeFactory = IHasAssetInfo(factory);
        decreaseLiquidity = _calcDecreaseLiquidity(decreaseLiquidity, nonfungiblePositionManager, tokenIds[i]);
        decreaseLiquidity = _calcFeesAndRewardForDecreaseLiquidity(
          decreaseLiquidity,
          nonfungiblePositionManager,
          tokenIds[i]
        );
      }

      (transactions, txCount) = _addDecreaseLiquidityTransactions(
        transactions,
        txCount,
        decreaseLiquidity,
        tokenIds[i]
      );

      (transactions, txCount) = _addRewardTransactions(transactions, txCount, decreaseLiquidity, tokenIds[i]);
    }
    // Reduce length the empty items
    uint256 reduceLength = transactions.length.sub(txCount);

    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }
    return (withdrawAsset, withdrawBalance, transactions);
  }

  function _calcDecreaseLiquidity(
    DecreaseLiquidity memory decreaseLiquidity,
    IRamsesNonfungiblePositionManager nonfungiblePositionManager,
    uint256 tokenId
  ) internal view returns (DecreaseLiquidity memory) {
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

    decreaseLiquidity.lpAmount = decreaseLiquidity.portion.mul(liquidity).div(10 ** 18).toUint128();
    decreaseLiquidity.ramsesPool = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee));

    (uint160 sqrtPriceX96, , , , , , ) = decreaseLiquidity.ramsesPool.slot0();
    (decreaseLiquidity.amount0, decreaseLiquidity.amount1) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      decreaseLiquidity.lpAmount
    );

    return decreaseLiquidity;
  }

  function _isDeferredTransferReward(
    DecreaseLiquidity memory decreaseLiquidity,
    address rewardToken
  ) internal view returns (bool) {
    if (decreaseLiquidity.poolManagerLogic.isSupportedAsset(rewardToken)) {
      uint16 rewardAssetType = decreaseLiquidity.dHedgeFactory.getAssetType(rewardToken);
      uint16 clAssetType = decreaseLiquidity.dHedgeFactory.getAssetType(
        address(decreaseLiquidity.nonfungiblePositionManager)
      );
      return rewardAssetType < clAssetType;
    }
    return false;
  }

  function _calcFeesAndRewardForDecreaseLiquidity(
    DecreaseLiquidity memory decreaseLiquidity,
    IRamsesNonfungiblePositionManager nonfungiblePositionManager,
    uint256 tokenId
  ) internal view returns (DecreaseLiquidity memory) {
    (uint256 feeAmount0, uint256 feeAmount1) = nonfungiblePositionManager.fees(tokenId);
    decreaseLiquidity.amount0 = decreaseLiquidity.amount0.add(feeAmount0.mul(decreaseLiquidity.portion).div(10 ** 18));
    decreaseLiquidity.amount1 = decreaseLiquidity.amount1.add(feeAmount1.mul(decreaseLiquidity.portion).div(10 ** 18));

    decreaseLiquidity.gauge = IRamsesGaugeV2(voter.gauges(address(decreaseLiquidity.ramsesPool)));
    address[] memory rewardTokens = decreaseLiquidity.gauge.getRewardTokens();

    address[] memory validAssets = new address[](rewardTokens.length);
    uint256[] memory validAssetAmounts = new uint256[](rewardTokens.length);

    for (uint256 j = 0; j < rewardTokens.length; ++j) {
      uint256 rewardTokenAmount = decreaseLiquidity.gauge.earned(rewardTokens[j], tokenId);
      if (!validAssets.contains(rewardTokens[j]) && rewardTokenAmount > 0) {
        validAssets[decreaseLiquidity.validAssetCount] = rewardTokens[j];
        // if it's a deferred transfer supported asset, validAssetAmounts of it is 0
        // so it will only be claimed but no transfer here
        if (!_isDeferredTransferReward(decreaseLiquidity, rewardTokens[j])) {
          validAssetAmounts[decreaseLiquidity.validAssetCount] = rewardTokenAmount.mul(decreaseLiquidity.portion).div(
            10 ** 18
          );
        }
        decreaseLiquidity.validAssetCount = decreaseLiquidity.validAssetCount.add(1);
      }
      if (decreaseLiquidity.validAssetCount >= MAX_NUMBER_OF_REWARD_TOKEN) {
        break;
      }
    }
    uint256 reduceLength = validAssets.length.sub(decreaseLiquidity.validAssetCount);
    assembly {
      mstore(validAssets, sub(mload(validAssets), reduceLength))
      mstore(validAssetAmounts, sub(mload(validAssetAmounts), reduceLength))
    }
    decreaseLiquidity.validAssets = validAssets;
    decreaseLiquidity.validAssetAmounts = validAssetAmounts;

    return decreaseLiquidity;
  }

  function _addDecreaseLiquidityTransactions(
    MultiTransaction[] memory transactions,
    uint256 txCount,
    DecreaseLiquidity memory decreaseLiquidity,
    uint256 tokenId
  ) internal pure returns (MultiTransaction[] memory, uint256) {
    if (decreaseLiquidity.lpAmount != 0) {
      // decrease liquidity; only get accounted in the position
      transactions[txCount].to = address(decreaseLiquidity.nonfungiblePositionManager);
      transactions[txCount].txData = abi.encodeWithSelector(
        IRamsesNonfungiblePositionManager.decreaseLiquidity.selector,
        IRamsesNonfungiblePositionManager.DecreaseLiquidityParams(
          tokenId,
          decreaseLiquidity.lpAmount,
          0,
          0,
          type(uint256).max
        )
      );
      txCount++;
    }

    // collect fees and principals
    if (decreaseLiquidity.amount0 != 0 || decreaseLiquidity.amount1 != 0) {
      transactions[txCount].to = address(decreaseLiquidity.nonfungiblePositionManager);
      transactions[txCount].txData = abi.encodeWithSelector(
        IRamsesNonfungiblePositionManager.collect.selector,
        IRamsesNonfungiblePositionManager.CollectParams(
          tokenId,
          decreaseLiquidity.to, // recipient
          (decreaseLiquidity.amount0).toUint128(),
          (decreaseLiquidity.amount1).toUint128()
        )
      );
      txCount++;
    }
    return (transactions, txCount);
  }

  function _addRewardTransactions(
    MultiTransaction[] memory transactions,
    uint256 txCount,
    DecreaseLiquidity memory decreaseLiquidity,
    uint256 tokenId
  ) internal pure returns (MultiTransaction[] memory, uint256) {
    if (decreaseLiquidity.validAssets.length != 0) {
      // reward withdrawing
      transactions[txCount].to = address(decreaseLiquidity.nonfungiblePositionManager);
      transactions[txCount].txData = abi.encodeWithSelector(
        IRamsesGaugeV2.getReward.selector,
        tokenId,
        decreaseLiquidity.validAssets
      );
      txCount++;

      // reward transfers to the investor
      for (uint256 j = 0; j < decreaseLiquidity.validAssetCount; ++j) {
        if (decreaseLiquidity.validAssetAmounts[j] != 0) {
          transactions[txCount].to = decreaseLiquidity.validAssets[j];
          transactions[txCount].txData = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")),
            decreaseLiquidity.to,
            decreaseLiquidity.validAssetAmounts[j]
          );
          txCount++;
        }
      }
    }
    return (transactions, txCount);
  }
}
