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
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "../../utils/TxDataUtils.sol";
import "../../utils/SlippageAccumulator.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/uniswapV2/IUniswapV2Factory.sol";
import "../../interfaces/uniswapV2/IUniswapV2Router.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";

/// @notice Transaction guard for UniswapV2Router
/// @dev This will be used for sushiswap as well since Sushi uses the same interface.
contract UniswapV2RouterGuard is TxDataUtils, IGuard {
  struct SwapData {
    address recipient;
    address srcAsset;
    address dstAsset;
    uint256 srcAmount;
    uint256 dstAmount;
    address to;
  }

  event AddLiquidity(
    address fundAddress,
    address tokenA,
    address tokenB,
    address pair,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    uint256 time
  );

  event RemoveLiquidity(
    address fundAddress,
    address tokenA,
    address tokenB,
    address pair,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    uint256 time
  );

  SlippageAccumulator private immutable slippageAccumulator;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "Null address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  /// @notice Transaction guard for Uniswap V2
  /// @dev It supports exchange, addLiquidity and removeLiquidity functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param to the router address
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type, 3 for `Add Liquidity`, 4 for `Remove Liquidity`
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"))) {
      _verifyExchange(
        SwapData(
          convert32toAddress(getInput(data, 3)),
          convert32toAddress(getArrayIndex(data, 2, 0)),
          convert32toAddress(getArrayLast(data, 2)),
          uint256(getInput(data, 0)),
          uint256(getInput(data, 1)),
          to
        ),
        poolManagerLogicAssets,
        poolManagerLogic,
        2
      );

      txType = 2; // 'Exchange' type
    } else if (method == bytes4(keccak256("swapTokensForExactTokens(uint256,uint256,address[],address,uint256)"))) {
      _verifyExchange(
        SwapData(
          convert32toAddress(getInput(data, 3)),
          convert32toAddress(getArrayIndex(data, 2, 0)),
          convert32toAddress(getArrayLast(data, 2)),
          uint256(getInput(data, 0)),
          uint256(getInput(data, 1)),
          to
        ),
        poolManagerLogicAssets,
        poolManagerLogic,
        1
      );

      txType = 2; // 'Exchange' type
    } else if (
      method == bytes4(keccak256("addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"))
    ) {
      address tokenA = convert32toAddress(getInput(data, 0));
      address tokenB = convert32toAddress(getInput(data, 1));

      uint256 amountADesired = uint256(getInput(data, 2));
      uint256 amountBDesired = uint256(getInput(data, 3));
      uint256 amountAMin = uint256(getInput(data, 4));
      uint256 amountBMin = uint256(getInput(data, 5));

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IUniswapV2Factory(IUniswapV2Router(to).factory()).getPair(tokenA, tokenB);
      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      require(poolManagerLogic.poolLogic() == convert32toAddress(getInput(data, 6)), "recipient is not pool");

      emit AddLiquidity(
        poolManagerLogic.poolLogic(),
        tokenA,
        tokenB,
        pair,
        amountADesired,
        amountBDesired,
        amountAMin,
        amountBMin,
        block.timestamp
      );

      txType = 3; // `Add Liquidity` type
    } else if (
      method == bytes4(keccak256("removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)"))
    ) {
      address tokenA = convert32toAddress(getInput(data, 0));
      address tokenB = convert32toAddress(getInput(data, 1));

      uint256 liquidity = uint256(getInput(data, 2));

      uint256 amountAMin = uint256(getInput(data, 3));
      uint256 amountBMin = uint256(getInput(data, 4));

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IUniswapV2Factory(IUniswapV2Router(to).factory()).getPair(tokenA, tokenB);
      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      require(poolManagerLogic.poolLogic() == convert32toAddress(getInput(data, 5)), "recipient is not pool");

      emit RemoveLiquidity(
        poolManagerLogic.poolLogic(),
        tokenA,
        tokenB,
        pair,
        liquidity,
        amountAMin,
        amountBMin,
        block.timestamp
      );

      txType = 4; // `Remove Liquidity` type
    }

    // Given that there are no return statements above, this tx guard is not used for a public function (callable by anyone).
    // Make sure that it's the `poolLogic` contract of the `poolManagerLogic` which initiates the check on the tx.
    // Else, anyone can increase the slippage impact (updated by the call to SlippageAccumulator).
    // We can trust the poolLogic since it contains check to ensure the caller is authorised.
    require(IPoolManagerLogic(_poolManagerLogic).poolLogic() == msg.sender, "Caller not authorised");

    return (txType, false);
  }

  /// @dev Internal function to update cumulative slippage. This is required to avoid stack-too-deep errors.
  /// @param swapData The data used in a swap.
  /// @param poolManagerLogicAssets Contains supported assets mapping.
  /// @param poolManagerLogic The poolManager address.
  /// @param exchangeType Type of exchange (from/to); useful for emitting the correct event.
  function _verifyExchange(
    SwapData memory swapData,
    IHasSupportedAsset poolManagerLogicAssets,
    IPoolManagerLogic poolManagerLogic,
    uint8 exchangeType
  ) internal {
    address poolLogic = poolManagerLogic.poolLogic();
    require(poolManagerLogicAssets.isSupportedAsset(swapData.dstAsset), "unsupported destination asset");

    require(poolLogic == swapData.recipient, "recipient is not pool");

    slippageAccumulator.updateSlippageImpact(
      SlippageAccumulator.SwapData(
        swapData.srcAsset,
        swapData.dstAsset,
        swapData.srcAmount,
        swapData.dstAmount,
        swapData.to,
        address(poolManagerLogic)
      )
    );

    if (exchangeType == 1) {
      emit ExchangeTo(poolLogic, swapData.srcAsset, swapData.dstAsset, swapData.dstAmount, block.timestamp);
    } else if (exchangeType == 2) {
      emit ExchangeFrom(poolLogic, swapData.srcAsset, swapData.srcAmount, swapData.dstAsset, block.timestamp);
    }
  }
}
