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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./Path.sol";
import "../IGuard.sol";
import "../../utils/TxDataUtils.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IManaged.sol";
import "../../interfaces/IHasSupportedAsset.sol";

contract UniswapV3SwapGuard is TxDataUtils, IGuard {
  using Path for bytes;
  using SafeMathUpgradeable for uint256;

  // transaction guard for Uniswap Swap Router
  function txGuard(address _poolManagerLogic, bytes calldata data)
    external
    override
    returns (
      uint8 txType // transaction type
    )
  {
    bytes4 method = getMethod(data);

    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    address pool = poolManagerLogic.poolLogic();

    if (method == bytes4(keccak256("exactInput((bytes,address,uint256,uint256,uint256))"))) {
      address toAddress = convert32toAddress(getInput(data, 2)); // receiving address of the trade
      uint256 offset = uint256(getInput(data, 0)).div(32); // dynamic Struct/tuple (abiencoder V2)
      bytes memory path = getBytes(data, 0, offset); // requires an offset due to dynamic Struct/tuple in calldata (abiencoder V2)
      bytes memory firstPool = path.getFirstPool();
      address srcAsset = firstPool.getPoolAddress();
      uint256 srcAmount = uint256(getInput(data, 4));
      address dstAsset;
      bool hasMultiplePools = path.hasMultiplePools();
      require(hasMultiplePools, "trade invalid");

      // check that all swap path assets are supported
      // srcAsset -> while loop(path assets) -> dstAsset
      // TODO: consider a better way of doing this

      // check that source asset is supported
      require(poolManagerLogicAssets.isSupportedAsset(srcAsset), "unsupported source asset");

      address asset;

      // loop through path assets
      while (hasMultiplePools) {
        path = path.skipToken();
        bytes memory firstPool = path.getFirstPool();
        asset = firstPool.getPoolAddress(); // gets asset from swap path
        hasMultiplePools = path.hasMultiplePools();

        // // TODO: consider enabling a validation of path assets once the total dHedge valid asset universe is big enough
        // require(
        //     poolManagerLogic.validateAsset(asset),
        //     "invalid path asset"
        // );
      }

      // check that destination asset is supported (if it's a valid address)
      (, dstAsset, ) = path.decodeFirstPool(); // gets the destination asset
      if (dstAsset == address(0)) {
        // if the remaining path is just trailing zeros, use the last path asset instead
        dstAsset = asset;
      } else {
        require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");
      }

      require(pool == toAddress, "recipient is not pool");

      emit Exchange(pool, srcAsset, srcAmount, dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
      return txType;
    }

    if (
      method == bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"))
    ) {
      address srcAsset = convert32toAddress(getInput(data, 0));
      address dstAsset = convert32toAddress(getInput(data, 1));
      address toAddress = convert32toAddress(getInput(data, 3)); // receiving address of the trade
      uint256 srcAmount = uint256(getInput(data, 5));

      require(poolManagerLogicAssets.isSupportedAsset(srcAsset), "unsupported source asset");

      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      require(pool == toAddress, "recipient is not pool");

      emit Exchange(pool, srcAsset, srcAmount, dstAsset, block.timestamp);

      txType = 2;
      return txType; // 'Exchange' type
    }
  }
}
