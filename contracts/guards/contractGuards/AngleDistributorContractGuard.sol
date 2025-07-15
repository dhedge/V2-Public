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
pragma abicoder v2;

import {IDistributor} from "../../interfaces/angle/IDistributor.sol";
import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

contract AngleDistributorContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  address public immutable aaveV3LendingPool;

  address public immutable rewardTokenSupported;

  constructor(address _aaveV3LendingPool, address _rewardTokenSupported) {
    require(_aaveV3LendingPool != address(0) && _rewardTokenSupported != address(0), "invalid address");

    aaveV3LendingPool = _aaveV3LendingPool;
    rewardTokenSupported = _rewardTokenSupported;
  }

  /// @notice Transaction guard for Angle Protocol's distributor contract
  /// @dev Straightforward design specifically for support of aave rewards on Base claiming
  /// @param _poolManagerLogic PoolManagerLogic address
  /// @param _data The transaction data
  /// @return txType The transaction type of a given transaction data
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == IDistributor.claim.selector) {
      (address[] memory users, address[] memory tokens) = abi.decode(getParams(_data), (address[], address[]));

      require(users.length == 1 && users[0] == poolLogic, "recipient is not pool");

      require(tokens.length == 1 && tokens[0] == rewardTokenSupported, "reward not supported");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(aaveV3LendingPool), "enable reward token");

      txType = uint16(TransactionType.Claim);
      isPublic = true;
    }
  }
}
