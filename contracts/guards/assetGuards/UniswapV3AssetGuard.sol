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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionValue.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "./ERC20Guard.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IERC20Extended.sol";

/// @title Uniswap V3 asset guard
/// @dev Asset type = 6
contract UniswapV3AssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;
  using PositionValue for INonfungiblePositionManager;

  IUniswapV3Factory public uniswapV3Factory;
  INonfungiblePositionManager public nonfungiblePositionManager;
  uint32 public priceUpdateInterval = 2 minutes;

  constructor(address _uniswapV3Factory, address _nonfungiblePositionManager) {
    // solhint-disable-next-line reason-string
    require(_nonfungiblePositionManager != address(0), "_nonfungiblePositionManager address cannot be 0");
    // solhint-disable-next-line reason-string
    require(_uniswapV3Factory != address(0), "_uniswapV3Factory address cannot be 0");

    uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
    nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
  }

  /// @notice Returns the pool position of Aave lending pool
  /// @dev Returns the balance priced in ETH
  /// @param pool The pool logic address
  /// @return balance The total balance of the pool
  function getBalance(address pool, address) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();

    uint256 length = nonfungiblePositionManager.balanceOf(pool);
    for (uint256 i = 0; i < length; ++i) {
      uint256 tokenId = nonfungiblePositionManager.tokenOfOwnerByIndex(pool, i);
      (, , address token0, address token1, uint24 fee, , , , , , , ) = nonfungiblePositionManager.positions(tokenId);
      // (
      //   uint96 nonce,
      //   address operator,
      //   address token0,
      //   address token1,
      //   uint24 fee,
      //   int24 tickLower,
      //   int24 tickUpper,
      //   uint128 liquidity,
      //   uint256 feeGrowthInside0LastX128,
      //   uint256 feeGrowthInside1LastX128,
      //   uint128 tokensOwed0,
      //   uint128 tokensOwed1
      // ) = nonfungiblePositionManager.positions(tokenId);

      (int24 tick, ) = OracleLibrary.consult(uniswapV3Factory.getPool(token0, token1, fee), priceUpdateInterval);
      uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
      (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.total(tokenId, sqrtRatioX96);

      {
        // add token0 USD amount
        uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token0);
        balance = balance.add(tokenPriceInUsd.mul(amount0).div(10**IERC20Extended(token0).decimals()));
      }
      {
        // add token0 USD amount
        uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token1);
        balance = balance.add(tokenPriceInUsd.mul(amount1).div(10**IERC20Extended(token1).decimals()));
      }
    }
  }

  /// @notice Returns decimal of the Aave lending pool asset
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @dev Withdrawal processing is not applicable for this guard
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address, // pool
    address, // asset
    uint256, // portion
    address // to
  )
    external
    view
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      MultiTransaction[] memory transactions
    )
  {
    return (withdrawAsset, withdrawBalance, transactions);
  }
}
