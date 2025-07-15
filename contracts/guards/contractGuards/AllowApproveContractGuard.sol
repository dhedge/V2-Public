//
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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

contract AllowApproveContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  address public immutable allowedSpender;

  constructor(address _spender) {
    allowedSpender = _spender;
  }

  function txGuard(
    address /* _poolManagerLogic */,
    address /* _to */,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool isPublic) {
    bytes4 method = getMethod(_data);

    if (method == bytes4(keccak256("approve(address,uint256)"))) {
      address spender = abi.decode(getParams(_data), (address));

      require(spender == allowedSpender, "unsupported spender approval");

      txType = uint16(TransactionType.Approve);
      isPublic = true;
    }

    return (txType, isPublic);
  }
}
