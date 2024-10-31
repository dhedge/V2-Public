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
// Copyright (c) 2023 dHEDGE DAO
//
// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITransformERC20Feature} from "../../interfaces/zeroEx/ITransformERC20Feature.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

contract ZeroExContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  /// @notice Transaction guard for ZeroEx protocol swaps
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param _poolManagerLogic The pool manager logic address
  /// @param _data Transaction call data attempt by manager
  /// @return txType Transaction type described in PoolLogic
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes calldata _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(poolLogic == msg.sender, "not pool logic");

    if (getMethod(_data) == ITransformERC20Feature.transformERC20.selector) {
      (IERC20 inputToken, IERC20 outputToken, uint256 inputTokenAmount) = abi.decode(
        getParams(_data),
        (IERC20, IERC20, uint256)
      );

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(outputToken)),
        "unsupported destination asset"
      );

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: address(inputToken),
        dstAsset: address(outputToken),
        srcAmount: _getBalance(address(inputToken), poolLogic),
        dstAmount: _getBalance(address(outputToken), poolLogic)
      });

      emit ExchangeFrom(poolLogic, address(inputToken), inputTokenAmount, address(outputToken), block.timestamp);

      txType = uint16(TransactionType.Exchange);
    }

    return (txType, false);
  }
}
