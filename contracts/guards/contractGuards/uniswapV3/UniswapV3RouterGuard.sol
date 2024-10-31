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
// Copyright (c) 2022 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Path} from "@uniswap/v3-periphery/contracts/libraries/Path.sol";

import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {IV3SwapRouter} from "../../../interfaces/uniswapV3/IV3SwapRouter.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

contract UniswapV3RouterGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  using Path for bytes;

  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  /// @notice Transaction guard for UniswapV3 Swap Router
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param poolManagerLogic Pool manager logic address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in PoolLogic
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes memory data
  ) public override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(data);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);

    if (method == IV3SwapRouter.exactInput.selector) {
      IV3SwapRouter.ExactInputParams memory params = abi.decode(getParams(data), (IV3SwapRouter.ExactInputParams));
      (address srcAsset, address dstAsset) = _decodePath(params.path);

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(poolLogic == params.recipient, "recipient is not pool");

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: srcAsset,
        dstAsset: dstAsset,
        srcAmount: _getBalance(srcAsset, poolLogic),
        dstAmount: _getBalance(dstAsset, poolLogic)
      });

      emit ExchangeFrom(poolLogic, srcAsset, params.amountIn, dstAsset, block.timestamp);

      txType = uint16(TransactionType.Exchange);
    } else if (method == IV3SwapRouter.exactInputSingle.selector) {
      IV3SwapRouter.ExactInputSingleParams memory params = abi.decode(
        getParams(data),
        (IV3SwapRouter.ExactInputSingleParams)
      );

      require(poolManagerLogicAssets.isSupportedAsset(params.tokenOut), "unsupported destination asset");

      require(poolLogic == params.recipient, "recipient is not pool");

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: params.tokenIn,
        dstAsset: params.tokenOut,
        srcAmount: _getBalance(params.tokenIn, poolLogic),
        dstAmount: _getBalance(params.tokenOut, poolLogic)
      });

      emit ExchangeFrom(poolLogic, params.tokenIn, params.amountIn, params.tokenOut, block.timestamp);

      txType = uint16(TransactionType.Exchange);
    } else if (method == IV3SwapRouter.exactOutput.selector) {
      IV3SwapRouter.ExactOutputParams memory params = abi.decode(getParams(data), (IV3SwapRouter.ExactOutputParams));
      (address dstAsset, address srcAsset) = _decodePath(params.path);

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(poolLogic == params.recipient, "recipient is not pool");

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: srcAsset,
        dstAsset: dstAsset,
        srcAmount: _getBalance(srcAsset, poolLogic),
        dstAmount: _getBalance(dstAsset, poolLogic)
      });

      emit ExchangeTo(poolLogic, srcAsset, dstAsset, params.amountOut, block.timestamp);

      txType = uint16(TransactionType.Exchange);
    } else if (method == IV3SwapRouter.exactOutputSingle.selector) {
      IV3SwapRouter.ExactOutputSingleParams memory params = abi.decode(
        getParams(data),
        (IV3SwapRouter.ExactOutputSingleParams)
      );

      require(poolManagerLogicAssets.isSupportedAsset(params.tokenOut), "unsupported destination asset");

      require(poolLogic == params.recipient, "recipient is not pool");

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: params.tokenIn,
        dstAsset: params.tokenOut,
        srcAmount: _getBalance(params.tokenIn, poolLogic),
        dstAmount: _getBalance(params.tokenOut, poolLogic)
      });

      emit ExchangeTo(poolLogic, params.tokenIn, params.tokenOut, params.amountOut, block.timestamp);

      txType = uint16(TransactionType.Exchange);
    } else if (method == bytes4(keccak256("multicall(uint256,bytes[])"))) {
      // function selector doesn't work because of multiple 'multicall' functions
      (, bytes[] memory transactions) = abi.decode(getParams(data), (uint256, bytes[]));

      // allow only one swap tx in multicall so that slippage can be calculated correctly
      require(transactions.length == 1, "invalid multicall");

      for (uint256 i; i < transactions.length; ++i) {
        (txType, ) = txGuard(poolManagerLogic, to, transactions[i]);
        require(txType > 0, "invalid transaction");
      }

      txType = uint16(TransactionType.UniswapV3Multicall);
    }

    return (txType, false);
  }

  function _decodePath(bytes memory path) internal pure returns (address srcAsset, address dstAsset) {
    (srcAsset, , ) = path.decodeFirstPool();

    address asset;
    // loop through path assets
    while (path.hasMultiplePools()) {
      path = path.skipToken();
      (asset, , ) = path.decodeFirstPool();
    }
    // check that destination asset is supported (if it's a valid address)
    (, dstAsset, ) = path.decodeFirstPool(); // gets the destination asset
    if (dstAsset == address(0)) {
      // if the remaining path is just trailing zeros, use the last path asset instead
      dstAsset = asset;
    }
  }
}
