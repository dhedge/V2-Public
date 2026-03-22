// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";

interface IUnverifiedLiquifiClaimer {
  function batchClaimTokens(
    address[] calldata _beneficiaries,
    uint256[] calldata _awardAmounts,
    uint256[] calldata _claimAmounts,
    uint32[] calldata _releaseTimes,
    uint32[] calldata _unlockTimes,
    bytes32[][] calldata _proofs
  ) external;
}

contract LiquifiRewardsContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    bytes4 method = getMethod(_data);

    if (method == IUnverifiedLiquifiClaimer.batchClaimTokens.selector) {
      address[] memory beneficiaries = abi.decode(getParams(_data), (address[]));

      for (uint256 i; i < beneficiaries.length; ++i) {
        require(beneficiaries[i] == poolLogic, "recipient is not pool");
      }

      txType = uint16(TransactionType.Claim);
    }

    return (txType, false);
  }
}
