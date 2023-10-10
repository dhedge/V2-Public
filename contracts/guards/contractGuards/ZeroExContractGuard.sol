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

import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/zeroEx/ITransformERC20Feature.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../utils/SlippageAccumulator.sol";
import "../../utils/TxDataUtils.sol";

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

contract ZeroExContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  SlippageAccumulator private immutable slippageAccumulator;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "Null address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  /// @notice Transaction guard for ZeroEx protocol swaps
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param _poolManagerLogic The pool manager logic address
  /// @param _to Transaction target address
  /// @param _data Transaction call data attempt by manager
  /// @return txType Transaction type described in PoolLogic
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes calldata _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(poolLogic == msg.sender, "Caller not authorised");

    if (getMethod(_data) == ITransformERC20Feature.transformERC20.selector) {
      (IERC20 inputToken, IERC20 outputToken, uint256 inputTokenAmount, uint256 minOutputTokenAmount) = abi.decode(
        getParams(_data),
        (IERC20, IERC20, uint256, uint256)
      );

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(outputToken)),
        "unsupported destination asset"
      );

      slippageAccumulator.updateSlippageImpact(
        SlippageAccumulator.SwapData(
          address(inputToken),
          address(outputToken),
          inputTokenAmount,
          minOutputTokenAmount,
          _to,
          _poolManagerLogic
        )
      );

      emit ExchangeFrom(poolLogic, address(inputToken), inputTokenAmount, address(outputToken), block.timestamp);

      txType = uint16(TransactionType.Exchange);
    }

    return (txType, false);
  }
}
