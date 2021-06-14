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
// MIT License
// ===========
//
// Copyright (c) 2020 dHEDGE DAO
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
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./IGuard.sol";
import "../utils/TxDataUtils.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";
import "../interfaces/synthetix/ISynth.sol";
import "../interfaces/synthetix/ISynthetix.sol";
import "../interfaces/synthetix/IAddressResolver.sol";
import "../interfaces/IHasSupportedAsset.sol";

/// @title Transaction guard for Synthetix's Exchanger contract
contract SynthetixGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  bytes32 private constant _SYNTHETIX_KEY = "Synthetix";

  IAddressResolver public addressResolver;

  constructor(IAddressResolver _addressResolver) public {
    addressResolver = _addressResolver;
  }

  /// @notice Transaction guard for Synthetix Exchanger
  /// @dev It supports exchangeWithTracking functionality
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type
  function txGuard(
    address _poolManagerLogic,
    address, // to
    bytes calldata data
  )
    external
    override
    returns (
      uint8 txType // transaction type
    )
  {
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("exchangeWithTracking(bytes32,uint256,bytes32,address,bytes32)"))) {
      bytes32 srcKey = getInput(data, 0);
      bytes32 srcAmount = getInput(data, 1);
      bytes32 dstKey = getInput(data, 2);

      address srcAsset = getAssetProxy(srcKey);
      address dstAsset = getAssetProxy(dstKey);

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
      IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
      require(poolManagerLogicAssets.isSupportedAsset(srcAsset), "unsupported source asset");
      require(poolManagerLogicAssets.isSupportedAsset(dstAsset), "unsupported destination asset");

      emit Exchange(poolManagerLogic.poolLogic(), srcAsset, uint256(srcAmount), dstAsset, block.timestamp);

      txType = 2; // 'Exchange' type
      return txType;
    }
  }

  function getAssetProxy(bytes32 key) public view returns (address) {
    address synth = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY)).synths(key);
    require(synth != address(0), "invalid key");
    address proxy = ISynth(synth).proxy();
    require(proxy != address(0), "invalid proxy");
    return proxy;
  }
}
