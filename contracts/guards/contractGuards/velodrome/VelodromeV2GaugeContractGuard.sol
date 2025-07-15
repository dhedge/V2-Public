// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/velodrome/IVelodromeV2Gauge.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/IHasSupportedAsset.sol";
import "../../../interfaces/ITransactionTypes.sol";

contract VelodromeV2GaugeContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Transaction guard for Velodrome V2 Gauge
  /// @dev It supports depositing, withdrawing and collecting rewards
  /// @param _poolManagerLogic the pool manager logic
  /// @param _to the gauge address
  /// @param _data the transaction data
  /// @return txType the transaction type of a given transaction data
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    bytes4 method = getMethod(_data);

    if (method == bytes4(keccak256("deposit(uint256)"))) {
      address stakeToken = IVelodromeV2Gauge(_to).stakingToken();
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      txType = uint16(TransactionType.Stake);
    } else if (method == IVelodromeV2Gauge.withdraw.selector) {
      address stakeToken = IVelodromeV2Gauge(_to).stakingToken();
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      txType = uint16(TransactionType.Unstake);
    } else if (method == IVelodromeV2Gauge.getReward.selector) {
      address account = abi.decode(getParams(_data), (address));
      require(account == poolLogic, "invalid claimer");

      address rewardToken = IVelodromeV2Gauge(_to).rewardToken();
      require(poolManagerLogicAssets.isSupportedAsset(rewardToken), "enable reward token");

      txType = uint16(TransactionType.Claim);
    }

    return (txType, false);
  }
}
