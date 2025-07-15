// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IFToken} from "../../../interfaces/fluid/IFToken.sol";

contract FluidTokenContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    bytes4 method = getMethod(_data);

    if (method == IFToken.deposit.selector) {
      (, address receiver) = abi.decode(getParams(_data), (uint256, address));

      require(poolLogic == receiver, "recipient is not pool");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "unsupported destination asset");

      txType = uint16(TransactionType.FluidLendingDeposit);
    } else if (method == IFToken.withdraw.selector || method == IFToken.redeem.selector) {
      (, address receiver, address owner) = abi.decode(getParams(_data), (uint256, address, address));

      require(poolLogic == receiver && poolLogic == owner, "recipient is not pool");

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(IFToken(_to).asset()),
        "unsupported destination asset"
      );

      txType = uint16(TransactionType.FluidLendingWithdraw);
    }

    return (txType, isPublic);
  }
}
