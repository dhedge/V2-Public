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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/stargate/IStargateLpStaking.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IHasSupportedAsset.sol";

/// @title Transaction guard for the Stargate router
contract StargateLpStakingContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  using SafeMathUpgradeable for uint256;

  /// @notice Transaction guard for the Stargate router
  /// @dev It supports ***
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    view
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    if (method == IStargateLpStaking.deposit.selector) {
      uint256 poolId = abi.decode(getParams(data), (uint256));

      address stargatePool = IStargateLpStaking(to).poolInfo(poolId).lpToken;

      require(poolManagerLogicAssets.isSupportedAsset(stargatePool), "unsupported staking asset");
      _assertRewardToken(to, poolLogic, poolManagerLogicAssets);

      txType = uint16(TransactionType.Stake);
    } else if (method == IStargateLpStaking.withdraw.selector) {
      uint256 stargatePoolId = abi.decode(getParams(data), (uint256));

      address stargatePool = IStargateLpStaking(to).poolInfo(stargatePoolId).lpToken;

      require(poolManagerLogicAssets.isSupportedAsset(stargatePool), "unsupported staking asset");
      _assertRewardToken(to, poolLogic, poolManagerLogicAssets);

      txType = uint16(TransactionType.Unstake);
    } else if (method == IStargateLpStaking.emergencyWithdraw.selector) {
      // in case the rewards end
      uint256 stargatePoolId = abi.decode(getParams(data), (uint256));

      address stargatePool = IStargateLpStaking(to).poolInfo(stargatePoolId).lpToken;

      require(poolManagerLogicAssets.isSupportedAsset(stargatePool), "unsupported staking asset");
      _assertRewardToken(to, poolLogic, poolManagerLogicAssets);

      txType = uint16(TransactionType.Unstake);
    }

    return (txType, false);
  }

  function _assertRewardToken(
    address lpStakingAddress,
    address poolLogic,
    IHasSupportedAsset poolManagerLogicAssets
  ) private view returns (address rewardToken) {
    address factory = IPoolLogic(poolLogic).factory();
    try IStargateLpStaking(lpStakingAddress).stargate() returns (address _rewardToken) {
      rewardToken = _rewardToken;
    } catch {
      // Optimism version uses `eToken` instead of `stargate` to get the reward token
      rewardToken = IStargateLpStaking(lpStakingAddress).eToken();
    }

    if (IHasAssetInfo(factory).isValidAsset(rewardToken)) {
      require(poolManagerLogicAssets.isSupportedAsset(rewardToken), "unsupported reward token");
    }
  }
}
