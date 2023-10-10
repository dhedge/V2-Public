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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import "@uniswap/v3-periphery/contracts/libraries/Path.sol";

import "../../../utils/SlippageAccumulator.sol";
import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/IHasGuardInfo.sol";
import "../../../interfaces/IManaged.sol";
import "../../../interfaces/IHasSupportedAsset.sol";
import "../../../interfaces/uniswapV3/IV3SwapRouter.sol";
import "../../../interfaces/uniswapV3/IMulticallExtended.sol";

contract UniswapV3RouterGuard is TxDataUtils, IGuard {
  using Path for bytes;
  using SafeMathUpgradeable for uint256;

  SlippageAccumulator private immutable slippageAccumulator;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "Null address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  /// @notice Transaction guard for UniswavpV3SwapGuard
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param _poolManagerLogic Pool address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in PoolLogic
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes memory data
  )
    public
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);

    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    address pool = poolManagerLogic.poolLogic();

    if (method == IV3SwapRouter.exactInput.selector) {
      IV3SwapRouter.ExactInputParams memory params = abi.decode(getParams(data), (IV3SwapRouter.ExactInputParams));
      (address srcAsset, address dstAsset) = _decodePath(params.path);
      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(pool == params.recipient, "recipient is not pool");

      slippageAccumulator.updateSlippageImpact(
        SlippageAccumulator.SwapData(
          srcAsset,
          dstAsset,
          params.amountIn,
          params.amountOutMinimum,
          to,
          address(poolManagerLogic)
        )
      );

      emit ExchangeFrom(pool, srcAsset, params.amountIn, dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == IV3SwapRouter.exactInputSingle.selector) {
      IV3SwapRouter.ExactInputSingleParams memory params = abi.decode(
        getParams(data),
        (IV3SwapRouter.ExactInputSingleParams)
      );

      address srcAsset = params.tokenIn;
      address dstAsset = params.tokenOut;

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(pool == params.recipient, "recipient is not pool");

      slippageAccumulator.updateSlippageImpact(
        SlippageAccumulator.SwapData(
          srcAsset,
          dstAsset,
          params.amountIn,
          params.amountOutMinimum,
          to,
          address(poolManagerLogic)
        )
      );

      emit ExchangeFrom(pool, srcAsset, params.amountIn, dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == IV3SwapRouter.exactOutput.selector) {
      IV3SwapRouter.ExactOutputParams memory params = abi.decode(getParams(data), (IV3SwapRouter.ExactOutputParams));

      (address dstAsset, address srcAsset) = _decodePath(params.path);
      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(pool == params.recipient, "recipient is not pool");

      slippageAccumulator.updateSlippageImpact(
        SlippageAccumulator.SwapData(
          srcAsset,
          dstAsset,
          params.amountInMaximum,
          params.amountOut,
          to,
          address(poolManagerLogic)
        )
      );

      emit ExchangeTo(pool, srcAsset, dstAsset, params.amountOut, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == IV3SwapRouter.exactOutputSingle.selector) {
      IV3SwapRouter.ExactOutputSingleParams memory params = abi.decode(
        getParams(data),
        (IV3SwapRouter.ExactOutputSingleParams)
      );

      address srcAsset = params.tokenIn;
      address dstAsset = params.tokenOut;

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(pool == params.recipient, "recipient is not pool");

      slippageAccumulator.updateSlippageImpact(
        SlippageAccumulator.SwapData(
          srcAsset,
          dstAsset,
          params.amountInMaximum,
          params.amountOut,
          to,
          address(poolManagerLogic)
        )
      );

      emit ExchangeTo(pool, srcAsset, dstAsset, params.amountOut, block.timestamp);

      txType = 2; // 'Exchange' type
    } else if (method == bytes4(keccak256("multicall(uint256,bytes[])"))) {
      // function selector doesn't work because of multiple 'multicall' functions
      (, bytes[] memory transactions) = abi.decode(getParams(data), (uint256, bytes[]));

      for (uint256 i = 0; i < transactions.length; i++) {
        (txType, ) = txGuard(_poolManagerLogic, to, transactions[i]);
        require(txType > 0, "invalid transaction");
      }

      txType = 25; // 'Multicall' type
    }

    // Given that there are no return statements above, this tx guard is not used for a public function (callable by anyone).
    // Make sure that it's the `poolLogic` contract of the `poolManagerLogic` which initiates the check on the tx.
    // Else, anyone can increase the slippage impact (updated by the call to SlippageAccumulator).
    // We can trust the poolLogic since it contains check to ensure the caller is authorised.
    require(IPoolManagerLogic(_poolManagerLogic).poolLogic() == msg.sender, "Caller not authorised");

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
