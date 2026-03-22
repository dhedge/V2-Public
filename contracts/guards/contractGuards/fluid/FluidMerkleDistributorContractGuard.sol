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

import {IFluidMerkleDistributor} from "../../../interfaces/fluid/IFluidMerkleDistributor.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

contract FluidMerkleDistributorContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool isPublic) {
    bytes4 method = getMethod(_data);

    if (method == IFluidMerkleDistributor.claim.selector) {
      (address recipient, , uint8 positionType, , , , ) = abi.decode(
        getParams(_data),
        (address, uint256, uint8, bytes32, uint256, bytes32[], bytes)
      );

      // Change once other types are supported in dHEDGE
      require(positionType == 1, "only lending");

      address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

      require(recipient == poolLogic, "recipient is not pool");

      txType = uint16(TransactionType.Claim);
    }

    return (txType, isPublic);
  }
}
