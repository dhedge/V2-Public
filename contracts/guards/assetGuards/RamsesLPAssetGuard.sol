// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/velodrome/IVelodromeGauge.sol";
import "../../interfaces/ramses/IRamsesVoter.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IPoolManagerLogic.sol";

import "./ERC20Guard.sol";

/// @title Ramses LP/Gauge token asset guard
/// @dev Asset type = 20
contract RamsesLPAssetGuard is ERC20Guard {
  using SafeMath for uint256;

  struct WithdrawTxsParams {
    uint256 rewardsListLength;
    uint256 txCount;
    uint256 tokensCount;
  }

  IRamsesVoter public voter;

  /// @dev We need Voter contract to get the gauge address
  /// @param _voter Ramses voter contract address
  constructor(address _voter) {
    voter = IRamsesVoter(_voter);
  }

  /// @notice Returns the balance of Ramses LP asset
  /// @dev Includes claimable gauge rewards if reward tokens are supported in AssetHandler
  /// @param _pool Pool address
  /// @param _asset Ramses LP asset
  /// @return balance Ramses LP asset balance of given pool
  function getBalance(address _pool, address _asset) public view override returns (uint256 balance) {
    // Add balance of pair token itself
    balance = IERC20(_asset).balanceOf(_pool);

    IVelodromeGauge gauge = IVelodromeGauge(voter.gauges(_asset));

    uint256 rewardsValue;

    if (address(gauge) != address(0)) {
      // Add balance staked in gauge
      balance = balance.add(gauge.balanceOf(_pool));

      address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();

      uint256 rewardsListLength = gauge.rewardsListLength();
      // Add to balance all claimable rewards
      for (uint256 i; i < rewardsListLength; ++i) {
        address rewardToken = gauge.rewards(i);
        uint256 rewardAmount = gauge.earned(rewardToken, _pool);
        // will add 0 if reward token is not supported
        rewardsValue = rewardsValue.add(_assetValue(poolManagerLogic, rewardToken, rewardAmount));
      }
    }

    // Convert rewards value in LP price
    balance = balance.add(
      rewardsValue.mul(10 ** 18).div(IHasAssetInfo(IPoolLogic(_pool).factory()).getAssetPrice(_asset))
    );
  }

  /// @notice Creates transaction data for withdrawing from Ramses LP asset
  /// @dev Doesn't transfer portion of reward tokens if they are not supported in AssetHandler
  /// @param _pool Pool address
  /// @param _asset Ramses LP asset
  /// @param _portion The fraction of total Ramses LP asset to withdraw
  /// @param _to The investor address to withdraw to
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of LP asset balance to investor
  /// @return transactions are used to execute the Ramses LP withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _portion,
    address _to
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    withdrawAsset = _asset;
    withdrawBalance = IERC20(_asset).balanceOf(_pool).mul(_portion).div(10 ** 18);

    IVelodromeGauge gauge = IVelodromeGauge(voter.gauges(_asset));
    // If there is no gauge, no transactions required, only portion of LP Pair token is returned to investor
    if (address(gauge) != address(0)) {
      transactions = _prepareTransactions(gauge, _pool, _portion, _to);
    }
  }

  function _prepareTransactions(
    IVelodromeGauge gauge,
    address _pool,
    uint256 _portion,
    address _to
  ) internal view returns (MultiTransaction[] memory transactions) {
    WithdrawTxsParams memory params;
    params.rewardsListLength = gauge.rewardsListLength();
    // Maximum possible transactions are:
    // 1. Withdraw from gauge
    // 2. Claim rewards
    // plus rewards list length for each reward token transfer
    transactions = new MultiTransaction[](2 + params.rewardsListLength);

    {
      uint256 gaugeLPBalance = gauge.balanceOf(_pool);
      // Withdraw a portion of LP tokens from gauge
      if (gaugeLPBalance > 0) {
        transactions[params.txCount].to = address(gauge);
        transactions[params.txCount].txData = abi.encodeWithSelector(
          IVelodromeGauge.withdraw.selector,
          gaugeLPBalance.mul(_portion).div(10 ** 18)
        );
        params.txCount = params.txCount.add(1);
      }
    }

    address[] memory rewardTokens = new address[](params.rewardsListLength);

    {
      for (uint256 i; i < params.rewardsListLength; ++i) {
        address rewardToken = gauge.rewards(i);
        // We do not transfer investor's portion of reward token if it's not supported in AssetHandler
        // This also prevents from transfering of xRAM token (which is non-transferable), no plans to support illiquid token
        if (!IHasAssetInfo(IPoolLogic(_pool).factory()).isValidAsset(rewardToken)) continue;
        // We do not tranfer investor's portion of reward token if it's nothing to claim
        if (gauge.earned(rewardToken, _pool) <= 0) continue;
        rewardTokens[params.tokensCount] = rewardToken;
        params.tokensCount = params.tokensCount.add(1);
      }

      uint256 reduceTokensLength = (rewardTokens.length).sub(params.tokensCount);
      assembly {
        mstore(rewardTokens, sub(mload(rewardTokens), reduceTokensLength))
      }
    }

    // If reward tokens list doesn't have any supported token, do nothing
    // Otherwise, claim and transfer user's portion of reward token
    if (rewardTokens.length > 0) {
      // First, claim available rewards from gauge
      transactions[params.txCount].to = address(gauge);
      transactions[params.txCount].txData = abi.encodeWithSelector(
        IVelodromeGauge.getReward.selector,
        _pool,
        rewardTokens
      );
      params.txCount = params.txCount.add(1);

      // Second, transfer a portion of claimed rewards to the investor
      for (uint256 i; i < rewardTokens.length; ++i) {
        // Amount will be > 0, because we skipped tokens with 0 balance earlier
        uint256 rewardAmount = gauge.earned(rewardTokens[i], _pool);
        transactions[params.txCount].to = rewardTokens[i];
        transactions[params.txCount].txData = abi.encodeWithSelector(
          IERC20.transfer.selector,
          _to,
          rewardAmount.mul(_portion).div(10 ** 18)
        );
        params.txCount = params.txCount.add(1);
      }
    }

    uint256 reduceLength = (transactions.length).sub(params.txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }
  }

  function _assetValue(
    address _poolManagerLogic,
    address _token,
    uint256 _amount
  ) internal view returns (uint256 assetValue) {
    if (IPoolManagerLogic(_poolManagerLogic).validateAsset(_token) && _amount > 0) {
      assetValue = IPoolManagerLogic(_poolManagerLogic).assetValue(_token, _amount);
    }
  }
}
