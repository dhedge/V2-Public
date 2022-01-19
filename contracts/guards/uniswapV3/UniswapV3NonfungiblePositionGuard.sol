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

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./Path.sol";
import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IUniswapV3NonfungiblePositionGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";

contract UniswapV3NonfungiblePositionGuard is TxDataUtils, IGuard, IUniswapV3NonfungiblePositionGuard {
  using SafeMathUpgradeable for uint256;

  event Mint(
    address fundAddress,
    address token0,
    address token1,
    uint24 fee,
    int24 tickLower,
    int24 tickUpper,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 time
  );
  event IncreaseLiquidity(
    address fundAddress,
    uint256 tokenId,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 time
  );
  event DecreaseLiquidity(
    address fundAddress,
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 time
  );
  event Burn(address fundAddress, uint256 tokenId, uint256 time);
  event Collect(address fundAddress, uint256 tokenId, uint128 amount0Max, uint128 amount1Max, uint256 time);

  INonfungiblePositionManager public nonfungiblePositionManager;
  // uniswap v3 liquidity position count limit
  uint256 public override uniV3PositionsLimit;

  constructor(address _nonfungiblePositionManager, uint256 _uniV3PositionsLimit) {
    nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
    uniV3PositionsLimit = _uniV3PositionsLimit;
  }

  /// @notice Transaction guard for Uniswap V3 non-fungible Position Manager
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param _poolManagerLogic Pool address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in PoolLogic
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address, // to
    bytes calldata data
  )
    external
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

    if (method == INonfungiblePositionManager.mint.selector) {
      INonfungiblePositionManager.MintParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.MintParams)
      );

      require(poolManagerLogicAssets.isSupportedAsset(param.token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(param.token1), "unsupported asset: tokenB");

      require(nonfungiblePositionManager.balanceOf(pool) < uniV3PositionsLimit, "too many uniswap v3 positions");

      require(pool == param.recipient, "recipient is not pool");

      emit Mint(
        poolManagerLogic.poolLogic(),
        param.token0,
        param.token1,
        param.fee,
        param.tickLower,
        param.tickUpper,
        param.amount0Desired,
        param.amount1Desired,
        param.amount0Min,
        param.amount1Min,
        block.timestamp
      );

      txType = 20; // 'Mint' type
    } else if (method == INonfungiblePositionManager.increaseLiquidity.selector) {
      INonfungiblePositionManager.IncreaseLiquidityParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.IncreaseLiquidityParams)
      );

      require(pool == nonfungiblePositionManager.ownerOf(param.tokenId), "not position owner");

      emit IncreaseLiquidity(
        poolManagerLogic.poolLogic(),
        param.tokenId,
        param.amount0Desired,
        param.amount1Desired,
        param.amount0Min,
        param.amount1Min,
        block.timestamp
      );

      txType = 21; // 'IncreaseLiquidity' type
    } else if (method == INonfungiblePositionManager.decreaseLiquidity.selector) {
      INonfungiblePositionManager.DecreaseLiquidityParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.DecreaseLiquidityParams)
      );

      require(pool == nonfungiblePositionManager.ownerOf(param.tokenId), "not position owner");

      emit DecreaseLiquidity(
        poolManagerLogic.poolLogic(),
        param.tokenId,
        param.liquidity,
        param.amount0Min,
        param.amount1Min,
        block.timestamp
      );

      txType = 22; // 'DecreaseLiquidity' type
    } else if (method == INonfungiblePositionManager.burn.selector) {
      uint256 tokenId = abi.decode(getParams(data), (uint256));

      require(pool == nonfungiblePositionManager.ownerOf(tokenId), "not position owner");

      emit Burn(poolManagerLogic.poolLogic(), tokenId, block.timestamp);

      txType = 23; // 'Burn' type
    } else if (method == INonfungiblePositionManager.collect.selector) {
      INonfungiblePositionManager.CollectParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.CollectParams)
      );

      require(pool == nonfungiblePositionManager.ownerOf(param.tokenId), "not position owner");
      require(pool == param.recipient, "recipient is not pool");

      emit Collect(poolManagerLogic.poolLogic(), param.tokenId, param.amount0Max, param.amount1Max, block.timestamp);

      txType = 24; // 'Collect' type
    }

    return (txType, false);
  }
}
