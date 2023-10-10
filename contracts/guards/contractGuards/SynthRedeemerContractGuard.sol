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

import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/synthetix/ISynthRedeemer.sol";
import "../../utils/TxDataUtils.sol";

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

contract SynthRedeemerContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  address public immutable susdProxy;

  constructor(address _susdProxy) {
    susdProxy = _susdProxy;
  }

  /// @notice Transaction guard for Synthetix SynthRedeemer
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param _poolManagerLogic The pool manager logic address
  /// @param _data Transaction call data attempt
  /// @return txType Transaction type described in PoolLogic
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address,
    bytes calldata _data
  ) external override returns (uint16 txType, bool isPublic) {
    if (getMethod(_data) == ISynthRedeemer.redeemAll.selector) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(susdProxy), "susd must be enabled asset");

      IERC20[] memory synthProxies = abi.decode(getParams(_data), (IERC20[]));
      emit SynthRedeem(IPoolManagerLogic(_poolManagerLogic).poolLogic(), synthProxies);

      txType = uint16(TransactionType.RedeemSynth);
      isPublic = true;
    }
  }
}
