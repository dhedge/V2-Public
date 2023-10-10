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
pragma experimental ABIEncoderV2;

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/velodrome/IVelodromeFactory.sol";
import "../../../interfaces/velodrome/IVelodromeRouter.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/IHasSupportedAsset.sol";

/// @notice Transaction guard for Velodrome Router
contract VelodromeRouterGuard is TxDataUtils, IGuard {
  event AddLiquidity(address fundAddress, address pair, bytes params, uint256 time);

  event RemoveLiquidity(address fundAddress, address pair, bytes params, uint256 time);

  /// @notice Transaction guard for Velodrome
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
    bytes memory params = getParams(data);
    if (method == IVelodromeRouter.addLiquidity.selector) {
      (address tokenA, address tokenB, bool stable, , , , , address recipient, ) = abi.decode(
        params,
        (address, address, bool, uint256, uint256, uint256, uint256, address, uint256)
      );

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IVelodromeFactory(IVelodromeRouter(to).factory()).getPair(tokenA, tokenB, stable);
      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      require(poolManagerLogic.poolLogic() == recipient, "recipient is not pool");

      emit AddLiquidity(poolManagerLogic.poolLogic(), pair, params, block.timestamp);

      txType = 3; // `Add Liquidity` type
    } else if (method == IVelodromeRouter.removeLiquidity.selector) {
      (address tokenA, address tokenB, bool stable, , , , address recipient, ) = abi.decode(
        params,
        (address, address, bool, uint256, uint256, uint256, address, uint256)
      );

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IVelodromeFactory(IVelodromeRouter(to).factory()).getPair(tokenA, tokenB, stable);
      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      require(poolManagerLogic.poolLogic() == recipient, "recipient is not pool");

      emit RemoveLiquidity(poolManagerLogic.poolLogic(), pair, params, block.timestamp);

      txType = 4; // `Remove Liquidity` type
    }

    return (txType, false);
  }
}
