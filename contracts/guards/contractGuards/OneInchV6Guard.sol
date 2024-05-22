// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {IAggregationRouterV6} from "../../interfaces/oneInch/IAggregationRouterV6.sol";
import {IUniswapV3Pool} from "../../interfaces/uniswapV3/IUniswapV3Pool.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {AddressLib} from "../../utils/oneInch/libraries/AddressLib.sol";
import {ProtocolLib} from "../../utils/oneInch/libraries/ProtocolLib.sol";
import {SlippageAccumulator} from "../../utils/SlippageAccumulator.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

/// @notice Contract guard contract for 1inch AggregationRouterV6
contract OneInchV6Guard is IGuard, TxDataUtils, ITransactionTypes {
  using AddressLib for uint256;
  using ProtocolLib for uint256;

  SlippageAccumulator private immutable slippageAccumulator;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "invalid address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  /// @dev Doesn't support methods `unoswapTo, `unoswapTo2`, `unoswapTo3`, `clipperSwapTo`,
  ///      not sure yet if having them is necessary.
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to 1inch AggregationRouterV6 address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    address poolLogic = poolManagerLogic.poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    SlippageAccumulator.SwapData memory swapData;
    swapData.to = _to;
    swapData.poolManagerLogic = _poolManagerLogic;

    if (method == IAggregationRouterV6.swap.selector) {
      (, IAggregationRouterV6.SwapDescription memory description) = abi.decode(
        params,
        (address, IAggregationRouterV6.SwapDescription)
      );

      require(description.dstReceiver == poolLogic, "recipient is not pool");

      swapData.srcAsset = description.srcToken;
      swapData.dstAsset = description.dstToken;
      swapData.srcAmount = description.amount;
      swapData.dstAmount = description.minReturnAmount;

      txType = _verifySwap(swapData);
    } else if (method == IAggregationRouterV6.unoswap.selector) {
      (uint256 srcToken, uint256 srcAmount, uint256 dstAmount, uint256 pool) = abi.decode(
        params,
        (uint256, uint256, uint256, uint256)
      );
      swapData.srcAsset = srcToken.get();

      uint256[] memory pools = new uint256[](1);
      pools[0] = pool;
      _checkProtocolsSupported(pools);

      swapData.dstAsset = _retreiveDstToken(swapData.srcAsset, pools);
      swapData.srcAmount = srcAmount;
      swapData.dstAmount = dstAmount;

      txType = _verifySwap(swapData);
    } else if (method == IAggregationRouterV6.unoswap2.selector) {
      (uint256 srcToken, uint256 srcAmount, uint256 dstAmount, uint256 pool1, uint256 pool2) = abi.decode(
        params,
        (uint256, uint256, uint256, uint256, uint256)
      );
      swapData.srcAsset = srcToken.get();

      uint256[] memory pools = new uint256[](2);
      pools[0] = pool1;
      pools[1] = pool2;
      _checkProtocolsSupported(pools);

      swapData.dstAsset = _retreiveDstToken(swapData.srcAsset, pools);
      swapData.srcAmount = srcAmount;
      swapData.dstAmount = dstAmount;

      txType = _verifySwap(swapData);
    } else if (method == IAggregationRouterV6.unoswap3.selector) {
      (uint256 srcToken, uint256 srcAmount, uint256 dstAmount, uint256 pool1, uint256 pool2, uint256 pool3) = abi
        .decode(params, (uint256, uint256, uint256, uint256, uint256, uint256));
      swapData.srcAsset = srcToken.get();

      uint256[] memory pools = new uint256[](3);
      pools[0] = pool1;
      pools[1] = pool2;
      pools[2] = pool3;
      _checkProtocolsSupported(pools);

      swapData.dstAsset = _retreiveDstToken(swapData.srcAsset, pools);
      swapData.srcAmount = srcAmount;
      swapData.dstAmount = dstAmount;

      txType = _verifySwap(swapData);
    } else if (method == IAggregationRouterV6.clipperSwap.selector) {
      (, uint256 srcToken, address dstToken, uint256 srcAmount, uint256 dstAmount) = abi.decode(
        params,
        (address, uint256, address, uint256, uint256)
      );

      swapData.srcAsset = srcToken.get();
      swapData.dstAsset = dstToken;
      swapData.srcAmount = srcAmount;
      swapData.dstAmount = dstAmount;

      txType = _verifySwap(swapData);
    }

    return (txType, false);
  }

  function _verifySwap(SlippageAccumulator.SwapData memory _swapData) internal returns (uint16 txType) {
    require(
      IHasSupportedAsset(_swapData.poolManagerLogic).isSupportedAsset(_swapData.dstAsset),
      "unsupported destination asset"
    );

    slippageAccumulator.updateSlippageImpact(_swapData);

    txType = uint16(TransactionType.Exchange);
  }

  function _retreiveDstToken(address _srcToken, uint256[] memory _pools) internal view returns (address dstToken) {
    dstToken = _srcToken;
    for (uint8 i = 0; i < _pools.length; i++) {
      IUniswapV3Pool pool = IUniswapV3Pool(_pools[i].get());
      address token0 = pool.token0();
      address token1 = pool.token1();
      if (dstToken == token0) {
        dstToken = token1;
      } else if (dstToken == token1) {
        dstToken = token0;
      } else {
        revert("invalid path");
      }
    }
  }

  function _checkProtocolsSupported(uint256[] memory _pools) internal pure {
    for (uint256 i = 0; i < _pools.length; i++) {
      ProtocolLib.Protocol protocol = _pools[i].protocol();
      require(
        protocol == ProtocolLib.Protocol.UniswapV2 || protocol == ProtocolLib.Protocol.UniswapV3,
        "exchange pool not supported"
      );
      require(!_pools[i].shouldUnwrapWeth(), "WETH unwrap not supported");
    }
  }
}
