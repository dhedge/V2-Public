// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/velodrome/IVelodromeGauge.sol";
import "../../../interfaces/IHasSupportedAsset.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";

contract RamsesGaugeContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Transaction guard for Ramses Gauge
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
  ) external override returns (uint16 txType, bool isPublic) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    address stakeToken = IVelodromeGauge(_to).stake();

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == IVelodromeGauge.deposit.selector) {
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      uint256 amount = abi.decode(params, (uint256));

      emit Stake(poolLogic, stakeToken, _to, amount, block.timestamp);

      txType = uint16(TransactionType.Stake);
    } else if (method == IVelodromeGauge.depositAll.selector) {
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      emit Stake(poolLogic, stakeToken, _to, IERC20(stakeToken).balanceOf(poolLogic), block.timestamp);

      txType = uint16(TransactionType.Stake);
    } else if (method == IVelodromeGauge.withdraw.selector) {
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      uint256 amount = abi.decode(params, (uint256));

      emit Unstake(poolLogic, stakeToken, _to, amount, block.timestamp);

      txType = uint16(TransactionType.Unstake);
    } else if (method == IVelodromeGauge.withdrawAll.selector) {
      require(poolManagerLogicAssets.isSupportedAsset(stakeToken), "unsupported lp asset");

      emit Unstake(poolLogic, stakeToken, _to, IERC20(_to).balanceOf(poolLogic), block.timestamp);

      txType = uint16(TransactionType.Unstake);
    } else if (method == IVelodromeGauge.getReward.selector) {
      // it's allowed for everyone to claim anything on behalf of the pool
      address account = abi.decode(params, (address));

      require(account == poolLogic, "invalid claimer");

      emit Claim(poolLogic, _to, block.timestamp);

      txType = uint16(TransactionType.Claim);
      isPublic = true;
    }

    return (txType, isPublic);
  }
}
