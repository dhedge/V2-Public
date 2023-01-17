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

import "./ERC20Guard.sol";
import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/quick/IStakingRewardsFactory.sol";
import "../../interfaces/quick/IStakingRewards.sol";
import "../../interfaces/arrakis/IArrakisV1RouterStaking.sol";
import "../../interfaces/arrakis/ILiquidityGaugeV4.sol";
import "../../interfaces/arrakis/IArrakisVaultV1.sol";
import "../../utils/uniswap/UniswapV3PriceLibrary.sol";

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

/// @title Arrakis Liquidity Gauge V4 asset guard
/// @dev Asset type = 9
contract ArrakisLiquidityGaugeV4AssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;

  address public arrakisV1RouterStaking;

  struct UniV3PoolParams {
    address token0;
    address token1;
    uint160 sqrtPriceX96;
  }

  /// @notice Initialise for the contract
  constructor(address _arrakisV1RouterStaking) {
    arrakisV1RouterStaking = _arrakisV1RouterStaking;
  }

  /// @notice Creates transaction data for withdrawing staked tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset Staked asset
  /// @param portion The fraction of total staked asset to withdraw
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the staked withdrawal transaction in PoolLogic
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
    uint256 totalAssetBalance = IERC20Extended(asset).balanceOf(pool);
    uint256 burnAmount = totalAssetBalance.mul(portion).div(10**18);

    if (burnAmount > 0) {
      // should approve gauge asset to unstake
      transactions = new MultiTransaction[](2);
      transactions[0].to = asset;
      transactions[0].txData = abi.encodeWithSelector(
        IERC20Extended.approve.selector,
        arrakisV1RouterStaking, // gauge
        burnAmount
      );
      // removeLiquidityAndUnstake claims an unclaimed rewards to the msg.sender (in this case the pool)
      // The removed liquidity is sent directly the withdrawer.
      transactions[1].to = arrakisV1RouterStaking;
      transactions[1].txData = abi.encodeWithSelector(
        IArrakisV1RouterStaking.removeLiquidityAndUnstake.selector,
        asset, // gauge
        burnAmount,
        0, // amount0Min
        0, // amount1Min
        to // receiver
      );
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include any external balance in staking contracts
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();

    ILiquidityGaugeV4 gauge = ILiquidityGaugeV4(asset);
    IArrakisVaultV1 vault = IArrakisVaultV1(gauge.staking_token());
    (uint256 amount0Current, uint256 amount1Current) = vault.getUnderlyingBalances();

    balance = (
      _assetValue(factory, vault.token0(), amount0Current).add(_assetValue(factory, vault.token1(), amount1Current))
    ).mul(IERC20Extended(asset).balanceOf(pool)).div(vault.totalSupply());

    uint256 length = gauge.reward_count();
    for (uint256 i = 0; i < length; i++) {
      address rewardToken = gauge.reward_tokens(i);
      uint256 rewardBalance = gauge.claimable_reward(pool, rewardToken);
      balance = balance.add(_assetValue(factory, rewardToken, rewardBalance));
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
}
