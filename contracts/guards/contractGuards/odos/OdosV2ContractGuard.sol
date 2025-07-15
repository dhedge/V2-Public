// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {IOdosRouterV2} from "../../../interfaces/odos/IOdosRouterV2.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";

/// @notice Contract guard contract for OdosRouterV2
/// @dev As this contract inherits `SlippageAccumulatorUser`, it also inherits the `ITxTrackingGuard` interface.
contract OdosV2ContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  mapping(address => mapping(address => bool)) internal _beforeSwapSrcAssetCheck; // poolLogic -> srcAsset -> bool
  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  /// @dev  Support methods `swapCompact, `swap`
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == IOdosRouterV2.swap.selector) {
      bytes memory params = getParams(_data);
      IOdosRouterV2.SwapTokenInfo memory swapTokenInfo = abi.decode(params, (IOdosRouterV2.SwapTokenInfo));
      txType = _verifySwap(swapTokenInfo, _poolManagerLogic, poolLogic);
    } else if (method == IOdosRouterV2.swapCompact.selector) {
      (bool success, bytes memory swapData) = address(this).staticcall(
        abi.encodePacked(this._decodeCompactCalldata.selector, _to, _data)
      );
      require(success, "decodeCompactCalldata failed");
      IOdosRouterV2.SwapTokenInfo memory swapTokenInfo = abi.decode(swapData, (IOdosRouterV2.SwapTokenInfo));
      txType = _verifySwap(swapTokenInfo, _poolManagerLogic, poolLogic);
    }

    return (txType, false);
  }

  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    bytes4 method = getMethod(_data);

    if (method == IOdosRouterV2.swap.selector) {
      bytes memory params = getParams(_data);
      IOdosRouterV2.SwapTokenInfo memory swapTokenInfo = abi.decode(params, (IOdosRouterV2.SwapTokenInfo));
      _verifySwapAfterTxGuard(swapTokenInfo, _poolManagerLogic, poolLogic);
      SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
    } else if (method == IOdosRouterV2.swapCompact.selector) {
      (bool success, bytes memory swapData) = address(this).staticcall(
        abi.encodePacked(this._decodeCompactCalldata.selector, _to, _data)
      );
      require(success, "decodeCompactCalldata failed");
      IOdosRouterV2.SwapTokenInfo memory swapTokenInfo = abi.decode(swapData, (IOdosRouterV2.SwapTokenInfo));
      _verifySwapAfterTxGuard(swapTokenInfo, _poolManagerLogic, poolLogic);
      SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
    }
  }

  function _verifySwap(
    IOdosRouterV2.SwapTokenInfo memory _swapTokenInfo,
    address _poolManagerLogic,
    address _poolLogic
  ) internal returns (uint16 txType) {
    require(_swapTokenInfo.outputReceiver == _poolLogic, "recipient is not pool");
    require(_swapTokenInfo.inputToken != address(0), "invalid input token"); // do not support native ETH
    require(_swapTokenInfo.inputAmount != 0, "invalid input amount"); // do not support entire balance trade
    require(
      IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_swapTokenInfo.outputToken),
      "unsupported destination asset"
    );

    intermediateSwapData = SlippageAccumulator.SwapData({
      srcAsset: _swapTokenInfo.inputToken,
      dstAsset: _swapTokenInfo.outputToken,
      srcAmount: _getBalance(_swapTokenInfo.inputToken, _poolLogic),
      dstAmount: _getBalance(_swapTokenInfo.outputToken, _poolLogic)
    });
    if (IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_swapTokenInfo.inputToken)) {
      _beforeSwapSrcAssetCheck[_poolLogic][_swapTokenInfo.inputToken] = true;
    }

    txType = uint16(TransactionType.Exchange);
  }

  function _verifySwapAfterTxGuard(
    IOdosRouterV2.SwapTokenInfo memory _swapTokenInfo,
    address _poolManagerLogic,
    address _poolLogic
  ) internal {
    require(
      IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_swapTokenInfo.outputToken),
      "unsupported destination asset"
    );

    if (_beforeSwapSrcAssetCheck[_poolLogic][_swapTokenInfo.inputToken]) {
      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_swapTokenInfo.inputToken),
        "unsupported source asset"
      );

      _beforeSwapSrcAssetCheck[_poolLogic][_swapTokenInfo.inputToken] = false;
    }
  }

  /// @notice Decode the compact calldata for a swap
  /// modified from https://github.com/odos-xyz/odos-router-v2/blob/main/contracts/OdosRouterV2.sol#L103
  /// and use assembly to call storage variable `address[] public addressList` in the OdosRouterV2 contract
  function _decodeCompactCalldata() public view returns (IOdosRouterV2.SwapTokenInfo memory tokenInfo) {
    address executor;

    {
      address msgSender = msg.sender;

      assembly {
        // Define function to load in token address, either from calldata or from storage
        function getAddress(currPos, routerAddress) -> result, newPos {
          let inputPos := shr(240, calldataload(currPos))

          switch inputPos
          // Reserve the null address as a special case that can be specified with 2 null bytes
          case 0x0000 {
            newPos := add(currPos, 2)
          }
          // This case means that the address is encoded in the calldata directly following the code
          case 0x0001 {
            result := and(shr(80, calldataload(currPos)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            newPos := add(currPos, 22)
          }
          // Otherwise we use the case to load in from the cached address list
          default {
            let ptr := mload(0x40) //  the free memory pointer
            let selector := 0xb810fb43 // for function addressList(uint256)
            mstore(ptr, shl(224, selector)) // selector is only 4 bytes, so shift left by (32 - 4) * 8 = 224 bits
            mstore(add(ptr, 4), sub(inputPos, 2)) //  store the uint256 argument after the selector
            let success := staticcall(gas(), routerAddress, ptr, 36, ptr, 32)
            if iszero(success) {
              revert(0, 0)
            }
            result := mload(ptr) // load the address from memory
            newPos := add(currPos, 2) // update the position in calldata
          }
        }
        let result := 0
        let pos := 28 // 4 + 20 + 4   Skip the first 4 bytes of the _decodeCompactCalldata.selector and 20 bytes of _to address and 4 bytes of the swapCompact.selector
        let routerAddress := shr(96, calldataload(4)) // shift to remove upper 12 bytes (96 bits)

        // Load in the input and output token addresses
        result, pos := getAddress(pos, routerAddress)
        mstore(tokenInfo, result)

        result, pos := getAddress(pos, routerAddress)
        mstore(add(tokenInfo, 0x60), result)

        // Load in the input amount - a 0 byte means the full balance is to be used
        let inputAmountLength := shr(248, calldataload(pos))
        pos := add(pos, 1)

        if inputAmountLength {
          mstore(add(tokenInfo, 0x20), shr(mul(sub(32, inputAmountLength), 8), calldataload(pos)))
          pos := add(pos, inputAmountLength)
        }

        // Load in the quoted output amount
        let quoteAmountLength := shr(248, calldataload(pos))
        pos := add(pos, 1)

        let outputQuote := shr(mul(sub(32, quoteAmountLength), 8), calldataload(pos))
        mstore(add(tokenInfo, 0x80), outputQuote)
        pos := add(pos, quoteAmountLength)

        // Load the slippage tolerance and use to get the minimum output amount
        {
          let slippageTolerance := shr(232, calldataload(pos))
          mstore(add(tokenInfo, 0xA0), div(mul(outputQuote, sub(0xFFFFFF, slippageTolerance)), 0xFFFFFF))
        }
        pos := add(pos, 3)

        // Load in the executor address
        executor, pos := getAddress(pos, routerAddress)

        // Load in the destination to send the input to - Zero denotes the executor
        result, pos := getAddress(pos, routerAddress)
        if eq(result, 0) {
          result := executor
        }
        mstore(add(tokenInfo, 0x40), result)

        // Load in the destination to send the output to - Zero denotes msg.sender
        result, pos := getAddress(pos, routerAddress)
        if eq(result, 0) {
          result := msgSender
        }
        mstore(add(tokenInfo, 0xC0), result)
        //
        // we don't need to load the referral code and the pathDefinition
      }
    }
  }
}
