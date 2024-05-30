// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IVelodromeNonfungiblePositionManager} from "../../../interfaces/velodrome/IVelodromeNonfungiblePositionManager.sol";
import {IVelodromeCLPool} from "../../../interfaces/velodrome/IVelodromeCLPool.sol";
import {IVelodromeCLGauge} from "../../../interfaces/velodrome/IVelodromeCLGauge.sol";
import {IVelodromeCLFactory} from "../../../interfaces/velodrome/IVelodromeCLFactory.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";

import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";

import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";

import {ERC20Guard} from "../ERC20Guard.sol";
import {VelodromeNonfungiblePositionGuard} from "../../contractGuards/velodrome/VelodromeNonfungiblePositionGuard.sol";
import {VelodromeCLPriceLibrary} from "../../../utils/velodrome/VelodromeCLPriceLibrary.sol";
import {VelodromeCLPositionValue} from "../../../utils/velodrome/VelodromeCLPositionValue.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

/// @title Velodrome CL asset guard
/// @dev Asset type = 26
contract VelodromeCLAssetGuard is ERC20Guard {
  using SafeCast for uint256;
  using SafeMath for uint256;
  using VelodromeCLPositionValue for IVelodromeNonfungiblePositionManager;

  struct VelodromeCLPoolParams {
    address token0;
    address token1;
    int24 tickSpacing;
    uint160 sqrtPriceX96;
  }

  struct WithdrawParams {
    address pool;
    address asset;
    uint256 portion;
    address to;
  }

  // for stack too deep
  struct DecreaseLiquidityData {
    address token0;
    address token1;
    uint128 lpAmount;
    uint256 amount0PrincipalToCollect;
    uint256 amount1PrincipalToCollect;
    uint128 amount0FeesToCollect;
    uint128 amount1FeesToCollect;
    address gauge;
    bool isStaked;
    uint256 tokenId;
    bool isToUnstakeForWithdrawal;
    bool isToWithdrawAllLP; // bool to check if stakeBack needed
    uint256 rewardAmount;
    address rewardToken;
  }

  /// @notice Returns the pool position of Velodrome CL
  /// @dev Returns the balance priced in USD
  /// @param pool The pool logic address
  /// @param asset Velodrome CL asset
  /// @return balance The total balance of the pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager = IVelodromeNonfungiblePositionManager(asset);

    VelodromeNonfungiblePositionGuard guard = VelodromeNonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);

    for (uint256 i = 0; i < tokenIds.length; ++i) {
      balance = balance.add(_tokenBalance(factory, pool, nonfungiblePositionManager, tokenIds[i]));
    }
  }

  function _tokenBalance(
    address factory,
    address pool,
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager,
    uint256 tokenId
  ) internal view returns (uint256 tokenBalance) {
    VelodromeCLPoolParams memory poolParams;
    (, , poolParams.token0, poolParams.token1, poolParams.tickSpacing, , , , , , , ) = nonfungiblePositionManager
      .positions(tokenId);

    // If either of the underlying LP tokens are unsupported, then skip the NFT
    if (
      !IHasAssetInfo(factory).isValidAsset(poolParams.token0) || !IHasAssetInfo(factory).isValidAsset(poolParams.token1)
    ) {
      return 0;
    }
    poolParams.sqrtPriceX96 = VelodromeCLPriceLibrary.assertFairPrice(
      factory,
      nonfungiblePositionManager.factory(),
      poolParams.token0,
      poolParams.token1,
      poolParams.tickSpacing
    );

    (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.total(tokenId, poolParams.sqrtPriceX96);

    tokenBalance = tokenBalance.add(_assetValue(pool, poolParams.token0, amount0)).add(
      _assetValue(pool, poolParams.token1, amount1)
    );

    IVelodromeCLGauge clGauge = IVelodromeCLGauge(
      IVelodromeCLPool(
        IVelodromeCLFactory(nonfungiblePositionManager.factory()).getPool(
          poolParams.token0,
          poolParams.token1,
          poolParams.tickSpacing
        )
      ).gauge()
    );

    bool isStaked = nonfungiblePositionManager.ownerOf(tokenId) == address(clGauge);

    if (isStaked) {
      //during increasing/decreasing staked liquidity the rewards move from earned to rewards
      address rewardToken = clGauge.rewardToken();
      tokenBalance = tokenBalance.add(_assetValue(pool, rewardToken, clGauge.earned(pool, tokenId)));
      tokenBalance = tokenBalance.add(_assetValue(pool, rewardToken, clGauge.rewards(tokenId)));
    }
    return tokenBalance;
  }

  function _assetValue(address pool, address token, uint256 amount) internal view returns (uint256 assetValue) {
    if (IHasAssetInfo(IPoolLogic(pool).factory()).isValidAsset(token)) {
      address poolManagerLogic = IPoolLogic(pool).poolManagerLogic();
      assetValue = IPoolManagerLogic(poolManagerLogic).assetValue(token, amount);
    } else {
      assetValue = 0;
    }
  }

  /// @notice Returns decimal of the VelodromeCL asset
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing VelodromeCL LP tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset VelodromeNonfungiblePositionManager
  /// @param portion Portion of the VelodromeCL asset to withdraw
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
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager = IVelodromeNonfungiblePositionManager(asset);

    address factory = IPoolLogic(pool).factory();
    VelodromeNonfungiblePositionGuard guard = VelodromeNonfungiblePositionGuard(
      IHasGuardInfo(factory).getContractGuard(asset)
    );
    uint256[] memory tokenIds = guard.getOwnedTokenIds(pool);
    uint256 txCount;
    // Allows up to 7 transactions per owned tokenId.
    // For the staked case in _addDecreaseLiquidityTransactions, a maximum of 5 txs is expected.
    // Similarly, in _addRewardTransactions, a maximum of 2 txs is expected.
    transactions = new MultiTransaction[](tokenIds.length.mul(7));
    WithdrawParams memory withdrawParams = WithdrawParams({pool: pool, asset: asset, portion: portion, to: to});
    for (uint256 i = 0; i < tokenIds.length; ++i) {
      DecreaseLiquidityData memory decreaseLiquidityData = _calcPrincipalsForDecreaseLiquidity(
        nonfungiblePositionManager,
        tokenIds[i],
        portion
      );
      decreaseLiquidityData = _calcFeesAndRewardForDecreaseLiquidity(
        nonfungiblePositionManager,
        tokenIds[i],
        portion,
        withdrawParams,
        decreaseLiquidityData
      );
      (transactions, txCount) = _addDecreaseLiquidityTransactions(
        transactions,
        txCount,
        decreaseLiquidityData,
        withdrawParams
      );
      (transactions, txCount) = _addRewardTransactions(transactions, txCount, decreaseLiquidityData, withdrawParams);
    }
    // Reduce length the empty items
    uint256 reduceLength = transactions.length.sub(txCount);

    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }
    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Calculates liquidity withdraw fees, and reward if it's staked;
  /// @dev Also to avoid stack too deep error
  ///
  /// @param nonfungiblePositionManager VelodromeNonfungiblePositionManager
  /// @param tokenId nft position id
  /// @param portion withdraw portion
  /// @param withdrawParams info includes the pool address
  /// @param decreaseLiquidityData withdraw info
  /// @return decreaseLiquidity withdraw info with added data
  function _calcFeesAndRewardForDecreaseLiquidity(
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager,
    uint256 tokenId,
    uint256 portion,
    WithdrawParams memory withdrawParams,
    DecreaseLiquidityData memory decreaseLiquidityData
  ) internal view returns (DecreaseLiquidityData memory) {
    (uint256 feeAmount0, uint256 feeAmount1) = nonfungiblePositionManager.fees(tokenId);
    decreaseLiquidityData.amount0FeesToCollect = (feeAmount0.mul(portion).div(10 ** 18)).toUint128();
    decreaseLiquidityData.amount1FeesToCollect = (feeAmount1.mul(portion).div(10 ** 18)).toUint128();
    // gauge rewards
    if (decreaseLiquidityData.isStaked) {
      IVelodromeCLGauge clGauge = IVelodromeCLGauge(decreaseLiquidityData.gauge);
      decreaseLiquidityData.rewardAmount = clGauge.earned(withdrawParams.pool, decreaseLiquidityData.tokenId).add(
        clGauge.rewards(decreaseLiquidityData.tokenId)
      );
      decreaseLiquidityData.rewardToken = clGauge.rewardToken();
    }

    return decreaseLiquidityData;
  }

  /// @notice Calculates liquidity withdraw principals
  ///
  /// @param nonfungiblePositionManager VelodromeNonfungiblePositionManager
  /// @param tokenId nft position id
  /// @param portion withdraw portion
  /// @return decreaseLiquidity withdraw info
  function _calcPrincipalsForDecreaseLiquidity(
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager,
    uint256 tokenId,
    uint256 portion
  ) internal view returns (DecreaseLiquidityData memory decreaseLiquidity) {
    IVelodromeCLFactory velodromeCLFactory = IVelodromeCLFactory(nonfungiblePositionManager.factory());
    (
      ,
      ,
      address token0,
      address token1,
      int24 tickSpacing,
      int24 tickLower,
      int24 tickUpper,
      uint128 liquidity,
      ,
      ,
      ,

    ) = nonfungiblePositionManager.positions(tokenId);

    decreaseLiquidity.token0 = token0;
    decreaseLiquidity.token1 = token1;
    decreaseLiquidity.lpAmount = (portion.mul(liquidity).div(10 ** 18)).toUint128();
    IVelodromeCLPool clPool = IVelodromeCLPool(velodromeCLFactory.getPool(token0, token1, tickSpacing));
    decreaseLiquidity.gauge = clPool.gauge();
    decreaseLiquidity.isStaked = nonfungiblePositionManager.ownerOf(tokenId) == decreaseLiquidity.gauge;
    decreaseLiquidity.isToWithdrawAllLP = portion == uint256(10 ** 18);
    decreaseLiquidity.tokenId = tokenId;
    decreaseLiquidity.isToUnstakeForWithdrawal = decreaseLiquidity.isStaked && decreaseLiquidity.lpAmount != 0;

    (uint160 sqrtPriceX96, , , , , ) = clPool.slot0();

    (decreaseLiquidity.amount0PrincipalToCollect, decreaseLiquidity.amount1PrincipalToCollect) = LiquidityAmounts
      .getAmountsForLiquidity(
        sqrtPriceX96,
        TickMath.getSqrtRatioAtTick(tickLower),
        TickMath.getSqrtRatioAtTick(tickUpper),
        decreaseLiquidity.lpAmount
      );
  }

  /// @notice Add transactions related to claiming gauge rewards
  function _addRewardTransactions(
    MultiTransaction[] memory transactions,
    uint256 txCount,
    DecreaseLiquidityData memory decreaseLiquidityData,
    WithdrawParams memory withdrawParams
  ) internal view returns (MultiTransaction[] memory, uint256) {
    if (!decreaseLiquidityData.isStaked || decreaseLiquidityData.rewardAmount == 0) {
      return (transactions, txCount);
    }

    // unstaking will claim reward internally, so only call getReward if isToUnstakeForWithdrawal is not true
    if (!decreaseLiquidityData.isToUnstakeForWithdrawal) {
      // include gauge reward claim transaction
      transactions[txCount++] = MultiTransaction({
        to: decreaseLiquidityData.gauge,
        txData: abi.encodeWithSelector(bytes4(keccak256("getReward(uint256)")), decreaseLiquidityData.tokenId)
      });
    }

    if (
      IHasSupportedAsset(IPoolLogic(withdrawParams.pool).poolManagerLogic()).isSupportedAsset(
        decreaseLiquidityData.rewardToken
      )
    ) {
      // to avoid double transferring;
      //  rewardToken as supportedAsset would have its own AssetGuard to handle the transfer
      return (transactions, txCount);
    }

    transactions[txCount++] = MultiTransaction({
      to: decreaseLiquidityData.rewardToken,
      txData: abi.encodeWithSelector(
        bytes4(keccak256("transfer(address,uint256)")),
        withdrawParams.to,
        decreaseLiquidityData.rewardAmount.mul(withdrawParams.portion).div(10 ** 18)
      )
    });

    return (transactions, txCount);
  }

  /// @notice Records transactions related to decreased liquidity, including principals and fees
  /// @dev Fees will only be accumulated and accounted for if the position is not staked in the gauge
  function _addDecreaseLiquidityTransactions(
    MultiTransaction[] memory transactions,
    uint256 txCount,
    DecreaseLiquidityData memory decreaseLiquidityData,
    WithdrawParams memory withdrawParams
  ) internal pure returns (MultiTransaction[] memory, uint256) {
    // to decrease liquidity, staked nft position needs to be unstaked first. after withdrawing, we stake it back.
    if (decreaseLiquidityData.isToUnstakeForWithdrawal) {
      transactions[txCount++] = MultiTransaction({
        to: decreaseLiquidityData.gauge,
        txData: abi.encodeWithSelector(IVelodromeCLGauge.withdraw.selector, decreaseLiquidityData.tokenId)
      });
    }

    // decreaseLiquidity
    if (decreaseLiquidityData.lpAmount != 0) {
      transactions[txCount++] = MultiTransaction({
        to: address(withdrawParams.asset), // nonfungiblePositionManager
        txData: abi.encodeWithSelector(
          IVelodromeNonfungiblePositionManager.decreaseLiquidity.selector,
          IVelodromeNonfungiblePositionManager.DecreaseLiquidityParams(
            decreaseLiquidityData.tokenId,
            decreaseLiquidityData.lpAmount,
            0,
            0,
            type(uint256).max
          )
        )
      });
    }

    // Collect principals and fees
    if (
      decreaseLiquidityData.amount0PrincipalToCollect != 0 ||
      decreaseLiquidityData.amount1PrincipalToCollect != 0 ||
      decreaseLiquidityData.amount0FeesToCollect != 0 ||
      decreaseLiquidityData.amount1FeesToCollect != 0
    ) {
      transactions[txCount++] = MultiTransaction({
        to: withdrawParams.asset, // nonfungiblePositionManager
        txData: abi.encodeWithSelector(
          IVelodromeNonfungiblePositionManager.collect.selector,
          IVelodromeNonfungiblePositionManager.CollectParams(
            decreaseLiquidityData.tokenId,
            withdrawParams.to, // recipient
            (decreaseLiquidityData.amount0PrincipalToCollect.add(decreaseLiquidityData.amount0FeesToCollect))
              .toUint128(),
            (decreaseLiquidityData.amount1PrincipalToCollect.add(decreaseLiquidityData.amount1FeesToCollect))
              .toUint128()
          )
        )
      });
    }

    // stake it back
    if (decreaseLiquidityData.isToUnstakeForWithdrawal && !decreaseLiquidityData.isToWithdrawAllLP) {
      transactions[txCount++] = MultiTransaction({
        to: withdrawParams.asset, // nonfungiblePositionManager
        txData: abi.encodeWithSelector(
          bytes4(keccak256("approve(address,uint256)")),
          decreaseLiquidityData.gauge,
          decreaseLiquidityData.tokenId
        )
      });
      transactions[txCount++] = MultiTransaction({
        to: decreaseLiquidityData.gauge,
        txData: abi.encodeWithSelector(IVelodromeCLGauge.deposit.selector, decreaseLiquidityData.tokenId)
      });
    }

    return (transactions, txCount);
  }
}
