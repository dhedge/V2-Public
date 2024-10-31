// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IAggregationRouterV6} from "../../interfaces/oneInch/IAggregationRouterV6.sol";
import {IUniswapV2Factory} from "../../interfaces/uniswapV2/IUniswapV2Factory.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {AddressLib} from "../../utils/oneInch/libraries/AddressLib.sol";
import {ProtocolLib} from "../../utils/oneInch/libraries/ProtocolLib.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

/// @notice Contract guard contract for 1inch AggregationRouterV6
/// @dev As this contract inherits `SlippageAccumulatorUser`, it also inherits the `ITxTrackingGuard` interface.
contract OneInchV6Guard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  using AddressLib for uint256;
  using ProtocolLib for uint256;

  IUniswapV2Factory public immutable uniswapV2Factory;

  IUniswapV3Factory public immutable uniswapV3Factory;

  address public immutable quickswapV2Factory;

  mapping(address => mapping(address => bool)) internal _beforeSwapSrcAssetCheck; // poolLogic -> srcAsset -> bool

  constructor(
    address _slippageAccumulator,
    IUniswapV2Factory _uniswapV2Factory,
    IUniswapV3Factory _uniswapV3Factory,
    address _quickswapV2Factory
  ) SlippageAccumulatorUser(_slippageAccumulator) {
    require(address(_uniswapV2Factory) != address(0) && address(_uniswapV3Factory) != address(0), "invalid address");

    uniswapV2Factory = _uniswapV2Factory;
    uniswapV3Factory = _uniswapV3Factory;
    quickswapV2Factory = _quickswapV2Factory;
  }

  /// @dev Doesn't support methods `unoswapTo, `unoswapTo2`, `unoswapTo3`, `clipperSwapTo`,
  ///      not sure yet if having them is necessary.
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == IAggregationRouterV6.swap.selector) {
      (, IAggregationRouterV6.SwapDescription memory description) = abi.decode(
        params,
        (address, IAggregationRouterV6.SwapDescription)
      );

      require(description.dstReceiver == poolLogic, "recipient is not pool");

      txType = _verifySwap(
        SlippageAccumulator.SwapData({
          srcAsset: description.srcToken,
          dstAsset: description.dstToken,
          srcAmount: _getBalance(description.srcToken, poolLogic),
          dstAmount: _getBalance(description.dstToken, poolLogic)
        }),
        _poolManagerLogic
      );

      if (IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(description.srcToken)) {
        _beforeSwapSrcAssetCheck[poolLogic][description.srcToken] = true;
      }
    } else if (method == IAggregationRouterV6.unoswap.selector) {
      (address srcAsset, uint256[] memory pools) = _decodeUnoswap(params);

      txType = _unoswapHelper(srcAsset, pools, poolLogic, _poolManagerLogic);
    } else if (method == IAggregationRouterV6.unoswap2.selector) {
      (address srcAsset, uint256[] memory pools) = _decodeUnoswap2(params);

      txType = _unoswapHelper(srcAsset, pools, poolLogic, _poolManagerLogic);
    } else if (method == IAggregationRouterV6.unoswap3.selector) {
      (address srcAsset, uint256[] memory pools) = _decodeUnoswap3(params);

      txType = _unoswapHelper(srcAsset, pools, poolLogic, _poolManagerLogic);
    }

    return (txType, false);
  }

  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    address dstToken;

    if (method == IAggregationRouterV6.swap.selector) {
      (, IAggregationRouterV6.SwapDescription memory description) = abi.decode(
        params,
        (address, IAggregationRouterV6.SwapDescription)
      );
      dstToken = description.dstToken;

      if (_beforeSwapSrcAssetCheck[poolLogic][description.srcToken]) {
        require(
          IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(description.srcToken),
          "unsupported source asset"
        );

        _beforeSwapSrcAssetCheck[poolLogic][description.srcToken] = false;
      }
    } else if (method == IAggregationRouterV6.unoswap.selector) {
      (address srcAsset, uint256[] memory pools) = _decodeUnoswap(params);

      dstToken = _retreiveDstToken(srcAsset, pools);
    } else if (method == IAggregationRouterV6.unoswap2.selector) {
      (address srcAsset, uint256[] memory pools) = _decodeUnoswap2(params);

      dstToken = _retreiveDstToken(srcAsset, pools);
    } else if (method == IAggregationRouterV6.unoswap3.selector) {
      (address srcAsset, uint256[] memory pools) = _decodeUnoswap3(params);

      dstToken = _retreiveDstToken(srcAsset, pools);
    }

    if (dstToken != address(0))
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dstToken), "unsupported destination asset");

    SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
  }

  function _verifySwap(
    SlippageAccumulator.SwapData memory _swapData,
    address _poolManagerLogic
  ) internal returns (uint16 txType) {
    require(
      IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_swapData.dstAsset),
      "unsupported destination asset"
    );

    intermediateSwapData = _swapData;

    txType = uint16(TransactionType.Exchange);
  }

  function _retreiveDstToken(address _srcToken, uint256[] memory _pools) internal view returns (address dstToken) {
    dstToken = _srcToken;
    for (uint256 i; i < _pools.length; ++i) {
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

  function _checkProtocolsSupported(uint256[] memory _pools) internal view {
    for (uint256 i; i < _pools.length; ++i) {
      require(!_pools[i].shouldUnwrapWeth(), "WETH unwrap not supported");

      ProtocolLib.Protocol protocol = _pools[i].protocol();

      // On Polygon, UniswapV2 marked pools can be from Uniswap or Quickswap
      if (protocol == ProtocolLib.Protocol.UniswapV2) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pools[i].get()); // can use V3 interface for V2
        address token0 = pool.token0();
        address token1 = pool.token1();
        address uniswapPair = uniswapV2Factory.getPair(token0, token1);
        address quickswapPair;
        // If it's Polygon, Quickswap might have more liquidity
        if (quickswapV2Factory != address(0))
          quickswapPair = IUniswapV2Factory(quickswapV2Factory).getPair(token0, token1);

        require(uniswapPair == address(pool) || quickswapPair == address(pool), "uniV2 pool invalid");
      } else if (protocol == ProtocolLib.Protocol.UniswapV3) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pools[i].get());
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();
        address pair = uniswapV3Factory.getPool(token0, token1, fee);

        require(pair == address(pool), "uniV3 pool invalid");
      } else revert("exchange pool not supported");
    }
  }

  function _decodeUnoswap(bytes memory _params) internal pure returns (address srcAsset, uint256[] memory pools) {
    (uint256 srcToken, , , uint256 pool) = abi.decode(_params, (uint256, uint256, uint256, uint256));
    srcAsset = srcToken.get();

    pools = new uint256[](1);
    pools[0] = pool;
  }

  function _decodeUnoswap2(bytes memory _params) internal pure returns (address srcAsset, uint256[] memory pools) {
    (uint256 srcToken, , , uint256 pool1, uint256 pool2) = abi.decode(
      _params,
      (uint256, uint256, uint256, uint256, uint256)
    );
    srcAsset = srcToken.get();

    pools = new uint256[](2);
    pools[0] = pool1;
    pools[1] = pool2;
  }

  function _decodeUnoswap3(bytes memory _params) internal pure returns (address srcAsset, uint256[] memory pools) {
    (uint256 srcToken, , , uint256 pool1, uint256 pool2, uint256 pool3) = abi.decode(
      _params,
      (uint256, uint256, uint256, uint256, uint256, uint256)
    );
    srcAsset = srcToken.get();

    pools = new uint256[](3);
    pools[0] = pool1;
    pools[1] = pool2;
    pools[2] = pool3;
  }

  function _unoswapHelper(
    address _srcAsset,
    uint256[] memory _pools,
    address _poolLogic,
    address _poolManagerLogic
  ) internal returns (uint16 txType) {
    _checkProtocolsSupported(_pools);

    address dstAsset = _retreiveDstToken(_srcAsset, _pools);

    txType = _verifySwap(
      SlippageAccumulator.SwapData({
        srcAsset: _srcAsset,
        dstAsset: dstAsset,
        srcAmount: _getBalance(_srcAsset, _poolLogic),
        dstAmount: _getBalance(dstAsset, _poolLogic)
      }),
      _poolManagerLogic
    );
  }
}
