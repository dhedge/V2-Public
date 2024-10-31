// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/Path.sol";

import "../utils/TxDataUtils.sol";
import {AddressLib} from "../utils/oneInch/libraries/AddressLib.sol";
import {ProtocolLib} from "../utils/oneInch/libraries/ProtocolLib.sol";

import "../interfaces/uniswapV3/IV3SwapRouter.sol";
import "../interfaces/uniswapV3/IUniswapV3Pool.sol";
import "../interfaces/oneInch/IAggregationRouterV6.sol";

/// @title SwapRouterMock
/// @notice Mock contract for all swap routers.
/// @dev Supports: UniV3
contract SwapRouterMock is TxDataUtils {
  using Path for bytes;
  using AddressLib for uint256;
  using ProtocolLib for uint256;

  // UniV3 related selectors
  bytes4 internal constant UNIV3_EXACT_INPUT_SINGLE_SELECTOR = IV3SwapRouter.exactInputSingle.selector;
  bytes4 internal constant UNIV3_EXACT_INPUT_SELECTOR = IV3SwapRouter.exactInput.selector;
  bytes4 internal constant UNIV3_EXACT_OUTPUT_SINGLE_SELECTOR = IV3SwapRouter.exactOutputSingle.selector;
  bytes4 internal constant UNIV3_EXACT_OUTPUT_SELECTOR = IV3SwapRouter.exactOutput.selector;

  // UniV2 related selectors
  bytes4 internal constant UNIV2_SWAP_EXACT_TOKENS_FOR_TOKENS_SELECTOR =
    bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"));
  bytes4 internal constant UNIV2_SWAP_TOKENS_FOR_EXACT_TOKENS_SELECTOR =
    bytes4(keccak256("swapTokensForExactTokens(uint256,uint256,address[],address,uint256)"));

  // OneInchV6 related selectors
  bytes4 internal constant ONEINCH_V6_SWAP_SELECTOR = IAggregationRouterV6.swap.selector;
  bytes4 internal constant ONEINCH_V6_UNOSWAP_SELECTOR = IAggregationRouterV6.unoswap.selector;
  bytes4 internal constant ONEINCH_V6_UNOSWAP2_SELECTOR = IAggregationRouterV6.unoswap2.selector;
  bytes4 internal constant ONEINCH_V6_UNOSWAP3_SELECTOR = IAggregationRouterV6.unoswap3.selector;

  receive() external payable {}

  fallback() external payable {
    _fallbackImpl();
  }

  function _swapTokens(address srcToken, address destToken, uint256 srcAmount, uint256 destAmount) internal {
    IERC20(srcToken).transferFrom(msg.sender, address(this), srcAmount);
    IERC20(destToken).transfer(msg.sender, destAmount);
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

  function _fallbackImpl() private {
    bytes4 methodId = msg.sig;

    if (methodId == UNIV3_EXACT_INPUT_SELECTOR) {
      IV3SwapRouter.ExactInputParams memory params = abi.decode(getParams(msg.data), (IV3SwapRouter.ExactInputParams));
      (address srcAsset, address dstAsset) = _decodePath(params.path);

      _swapTokens(srcAsset, dstAsset, params.amountIn, params.amountOutMinimum);
    } else if (methodId == UNIV3_EXACT_INPUT_SINGLE_SELECTOR) {
      IV3SwapRouter.ExactInputSingleParams memory params = abi.decode(
        getParams(msg.data),
        (IV3SwapRouter.ExactInputSingleParams)
      );

      _swapTokens(params.tokenIn, params.tokenOut, params.amountIn, params.amountOutMinimum);
    } else if (methodId == UNIV3_EXACT_OUTPUT_SINGLE_SELECTOR) {
      IV3SwapRouter.ExactOutputSingleParams memory params = abi.decode(
        getParams(msg.data),
        (IV3SwapRouter.ExactOutputSingleParams)
      );

      _swapTokens(params.tokenIn, params.tokenOut, params.amountInMaximum, params.amountOut);
    } else if (methodId == UNIV3_EXACT_OUTPUT_SELECTOR) {
      IV3SwapRouter.ExactOutputParams memory params = abi.decode(
        getParams(msg.data),
        (IV3SwapRouter.ExactOutputParams)
      );
      (address srcAsset, address dstAsset) = _decodePath(params.path);

      _swapTokens(srcAsset, dstAsset, params.amountInMaximum, params.amountOut);
    } else if (
      methodId == UNIV2_SWAP_EXACT_TOKENS_FOR_TOKENS_SELECTOR || methodId == UNIV2_SWAP_TOKENS_FOR_EXACT_TOKENS_SELECTOR
    ) {
      _swapTokens(
        convert32toAddress(getArrayIndex(msg.data, 2, 0)),
        convert32toAddress(getArrayLast(msg.data, 2)),
        uint256(getInput(msg.data, 0)),
        uint256(getInput(msg.data, 1))
      );
    } else if (methodId == ONEINCH_V6_SWAP_SELECTOR) {
      (, IAggregationRouterV6.SwapDescription memory description) = abi.decode(
        getParams(msg.data),
        (address, IAggregationRouterV6.SwapDescription)
      );

      _swapTokens(description.srcToken, description.dstToken, description.amount, description.minReturnAmount);
    } else if (methodId == ONEINCH_V6_UNOSWAP_SELECTOR) {
      (uint256 srcToken, uint256 srcAmount, uint256 dstAmountMin, uint256 pool) = abi.decode(
        getParams(msg.data),
        (uint256, uint256, uint256, uint256)
      );

      uint256[] memory pools = new uint256[](1);
      pools[0] = pool;

      _swapTokens(srcToken.get(), _retreiveDstToken(srcToken.get(), pools), srcAmount, dstAmountMin);
    } else if (methodId == ONEINCH_V6_UNOSWAP2_SELECTOR) {
      (uint256 srcToken, uint256 srcAmount, uint256 dstAmountMin, uint256 pool1, uint256 pool2) = abi.decode(
        getParams(msg.data),
        (uint256, uint256, uint256, uint256, uint256)
      );

      uint256[] memory pools = new uint256[](2);
      pools[0] = pool1;
      pools[1] = pool2;

      _swapTokens(srcToken.get(), _retreiveDstToken(srcToken.get(), pools), srcAmount, dstAmountMin);
    } else if (methodId == ONEINCH_V6_UNOSWAP3_SELECTOR) {
      (uint256 srcToken, uint256 srcAmount, uint256 dstAmountMin, uint256 pool1, uint256 pool2, uint256 pool3) = abi
        .decode(getParams(msg.data), (uint256, uint256, uint256, uint256, uint256, uint256));

      uint256[] memory pools = new uint256[](3);
      pools[0] = pool1;
      pools[1] = pool2;
      pools[2] = pool3;

      _swapTokens(srcToken.get(), _retreiveDstToken(srcToken.get(), pools), srcAmount, dstAmountMin);
    } else {
      revert("SRM: unsupported method");
    }
  }
}
