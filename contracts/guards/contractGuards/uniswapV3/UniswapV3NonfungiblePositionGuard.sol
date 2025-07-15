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

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {UniswapV3PriceLibrary} from "../../../utils/uniswap/UniswapV3PriceLibrary.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {NftTrackerConsumerGuard} from "../shared/NftTrackerConsumerGuard.sol";

contract UniswapV3NonfungiblePositionGuard is NftTrackerConsumerGuard, ITxTrackingGuard {
  using SafeMath for uint256;

  bool public override isTxTrackingGuard = true;

  constructor(
    uint256 _uniV3PositionsLimit,
    address _nftTracker
  ) NftTrackerConsumerGuard(_nftTracker, keccak256("UNISWAP_NFT_TYPE"), _uniV3PositionsLimit) {}

  /// @notice Transaction guard for Uniswap V3 non-fungible Position Manager
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
      uint16 txType,
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(to);

    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    address pool = poolManagerLogic.poolLogic();

    if (method == INonfungiblePositionManager.mint.selector) {
      INonfungiblePositionManager.MintParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.MintParams)
      );

      require(poolManagerLogicAssets.isSupportedAsset(param.token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(param.token1), "unsupported asset: tokenB");
      require(poolManagerLogicAssets.isSupportedAsset(to), "uniswap asset not enabled");

      require(pool == param.recipient, "recipient is not pool");

      UniswapV3PriceLibrary.assertFairPrice(
        IPoolLogic(pool).factory(),
        nonfungiblePositionManager.factory(),
        param.token0,
        param.token1,
        param.fee
      );

      txType = uint16(TransactionType.UniswapV3Mint);
    } else if (method == INonfungiblePositionManager.increaseLiquidity.selector) {
      INonfungiblePositionManager.IncreaseLiquidityParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.IncreaseLiquidityParams)
      );

      // validate token id from nft tracker
      bool isValidTokenId = isValidOwnedTokenId(pool, param.tokenId);
      require(isValidTokenId, "position is not in track");

      (, , address token0, address token1, uint24 fee, , , , , , , ) = nonfungiblePositionManager.positions(
        param.tokenId
      );

      UniswapV3PriceLibrary.assertFairPrice(
        IPoolLogic(pool).factory(),
        nonfungiblePositionManager.factory(),
        token0,
        token1,
        fee
      );

      txType = uint16(TransactionType.UniswapV3IncreaseLiquidity);
    } else if (method == INonfungiblePositionManager.decreaseLiquidity.selector) {
      txType = uint16(TransactionType.UniswapV3DecreaseLiquidity);
    } else if (method == INonfungiblePositionManager.burn.selector) {
      txType = uint16(TransactionType.UniswapV3Burn);
    } else if (method == INonfungiblePositionManager.collect.selector) {
      INonfungiblePositionManager.CollectParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.CollectParams)
      );
      (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(param.tokenId);

      require(poolManagerLogicAssets.isSupportedAsset(token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(token1), "unsupported asset: tokenB");
      require(pool == param.recipient, "recipient is not pool");

      txType = uint16(TransactionType.UniswapV3Collect);
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory params = abi.decode(getParams(data), (bytes[]));

      for (uint256 i = 0; i < params.length; i++) {
        (txType, ) = txGuard(_poolManagerLogic, to, params[i]);
        require(txType > 0, "invalid transaction");
      }

      txType = uint16(TransactionType.UniswapV3Multicall);
    }

    return (txType, false);
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev It supports close/open/forceClose position
  /// @param poolManagerLogic the pool manager logic
  /// @param data the transaction data
  function afterTxGuard(address poolManagerLogic, address to, bytes memory data) public virtual override {
    afterTxGuardHandle(poolManagerLogic, to, data);
  }

  function afterTxGuardHandle(
    address poolManagerLogic,
    address to,
    bytes memory data
  ) internal returns (bool isMintOrBurn) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(data);
    INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(to);

    if (method == INonfungiblePositionManager.mint.selector) {
      uint256 index = nonfungiblePositionManager.totalSupply();
      nftTracker.addUintId(
        to,
        nftType,
        poolLogic,
        nonfungiblePositionManager.tokenByIndex(index - 1), // revert if index is zero
        positionsLimit
      );

      return true;
    } else if (method == INonfungiblePositionManager.burn.selector) {
      uint256 tokenId = abi.decode(getParams(data), (uint256));

      // validate token id from nft tracker
      bool isValidTokenId = isValidOwnedTokenId(poolLogic, tokenId);
      require(isValidTokenId, "position is not in track");

      nftTracker.removeUintId(to, nftType, poolLogic, tokenId);

      return true;
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory params = abi.decode(getParams(data), (bytes[]));

      bool includeMintOrBurn;
      for (uint256 i = 0; i < params.length; i++) {
        if (afterTxGuardHandle(poolManagerLogic, to, params[i])) {
          // we support only one deposit or one withdraw transaction for the safety.
          require(!includeMintOrBurn, "invalid multicall");
          includeMintOrBurn = true;
        }
      }

      return includeMintOrBurn;
    }

    return false;
  }
}
