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
import "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/IHasSupportedAsset.sol";

contract UniswapV3NonfungiblePositionGuard is TxDataUtils, IGuard {
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

  // uniswap v3 liquidity position count limit
  uint256 public uniV3PositionsLimit;

  constructor(uint256 _uniV3PositionsLimit) {
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
    address to,
    bytes memory data
  )
    public
    override
    returns (
      uint16 txType, // transaction type
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

      emit Burn(poolManagerLogic.poolLogic(), tokenId, block.timestamp);

      txType = 23; // 'Burn' type
    } else if (method == INonfungiblePositionManager.collect.selector) {
      INonfungiblePositionManager.CollectParams memory param = abi.decode(
        getParams(data),
        (INonfungiblePositionManager.CollectParams)
      );
      (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(param.tokenId);

      require(poolManagerLogicAssets.isSupportedAsset(token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(token1), "unsupported asset: tokenB");
      require(pool == param.recipient, "recipient is not pool");

      emit Collect(poolManagerLogic.poolLogic(), param.tokenId, param.amount0Max, param.amount1Max, block.timestamp);

      txType = 24; // 'Collect' type
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory params = abi.decode(getParams(data), (bytes[]));

      for (uint256 i = 0; i < params.length; i++) {
        (txType, ) = txGuard(_poolManagerLogic, to, params[i]);
        require(txType > 0, "invalid transaction");
      }

      txType = 25; // 'Multicall' type
    }

    return (txType, false);
  }
}
