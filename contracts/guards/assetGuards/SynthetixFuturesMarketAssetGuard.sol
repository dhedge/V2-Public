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

import "./ClosedAssetGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "../../interfaces/synthetix/IFuturesMarket.sol";
import "../../interfaces/synthetix/IFuturesMarketSettings.sol";
import "../../interfaces/synthetix/ISynth.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title FuturesMarket (Synthetix) Asset Guard
/// @dev Asset type = 101
/// @dev A wallet/user can only have one position per market
contract SynthetixFuturesMarketAssetGuard is ClosedAssetGuard {
  using SafeMath for uint256;
  using SignedSafeMath for int128;
  using SignedSafeMath for int256;

  /// @notice Creates transaction data for reducing a futures position by the portion
  /// @param pool Pool address
  /// @param asset FuturesMarket
  /// @param portion The fraction of total future asset to withdraw
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the reduction of the futures position in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address withdrawerAddress
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
    bool canLiquidate = IFuturesMarket(asset).canLiquidate(pool);
    // This should nearly never happen, should always be previously liquidated by keeper.
    if (canLiquidate) {
      transactions = new MultiTransaction[](1);
      transactions[0].to = asset;
      // https://github.com/Synthetixio/synthetix/blob/master/contracts/MixinFuturesViews.sol#L130
      transactions[0].txData = abi.encodeWithSelector(IFuturesMarket.liquidatePosition.selector, pool);
      return (withdrawAsset, withdrawBalance, transactions);
    }

    // When a user withdraws, we close their portion of the future position (modifyPosition)
    // Then we withdraw their portion of the margin to the pool (transferMargin)
    // Then we withdraw their porition of the margin to the user (transfer)
    // If this withdraw would cause the positions margin to drop below minMargin we (closePosition) and (withdrawAllMargin)

    (uint256 margin, ) = IFuturesMarket(asset).remainingMargin(pool);
    // This is the fee for closing this portion of the position
    // We account for it so that withdrawing doesn't negatively impact the performance of the pool
    uint256 marginPortion = margin.mul(portion).div(10**18);
    uint256 minMargin = IFuturesMarketSettings(IFuturesMarket(asset).resolver().getAddress("FuturesMarketSettings"))
      .minInitialMargin();
    (, , , , int128 size) = IFuturesMarket(asset).positions(pool);

    // If there is an open position and the withdraw brings the margin under the minimum margin we close the whole position
    // This returns the funds to the pool. Where they will be distributed to the withdrawer upstream.
    if (size != 0 && (margin.sub(marginPortion) < minMargin || portion == 10**18)) {
      transactions = new MultiTransaction[](2);
      transactions[0].to = asset;
      transactions[0].txData = abi.encodeWithSelector(IFuturesMarket.closePosition.selector);
      transactions[1].to = asset;
      transactions[1].txData = abi.encodeWithSelector(IFuturesMarket.withdrawAllMargin.selector);
      return (withdrawAsset, withdrawBalance, transactions);
    }

    int256 reduceDelta = -size.mul(int256(portion)).div(10**18);
    (uint256 fee, ) = IFuturesMarket(asset).orderFee(reduceDelta);
    uint256 marginSubFee = marginPortion > fee ? marginPortion.sub(fee) : 0;

    uint256 start = 0;
    // reduceDelta is a signed Int, for a short reduceDelta will be > 0 and for a long < 0
    if (reduceDelta != 0) {
      transactions = new MultiTransaction[](3);
      transactions[start].to = asset;
      // https://github.com/Synthetixio/synthetix/blob/master/contracts/interfaces/IFuturesMarket.sol#L85
      transactions[start].txData = abi.encodeWithSelector(IFuturesMarket.modifyPosition.selector, reduceDelta);
      start++;
    }

    // There can still be margin inside the contract even if there is no open position
    if (marginSubFee > 0) {
      if (start == 0) {
        transactions = new MultiTransaction[](2);
      }
      // Withdraws margin to the pool
      transactions[start].to = asset;
      // https://github.com/Synthetixio/synthetix/blob/master/contracts/interfaces/IFuturesMarket.sol#L81
      transactions[start].txData = abi.encodeWithSelector(
        IFuturesMarket.transferMargin.selector,
        -int256(marginSubFee)
      );

      // Erc20.transfer of margin to withdrawer
      transactions[start + 1].to = ISynth(IFuturesMarket(asset).resolver().getSynth("sUSD")).proxy();
      transactions[start + 1].txData = abi.encodeWithSelector(
        IERC20.transfer.selector,
        withdrawerAddress,
        marginSubFee
      );
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns the sUSD value of the Future if it was closed now
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    IFuturesMarket futuresMarket = IFuturesMarket(asset);
    (balance, ) = futuresMarket.remainingMargin(pool);
    (, , , , int128 size) = futuresMarket.positions(pool);
    if (size != 0) {
      (uint256 fee, ) = futuresMarket.orderFee(-size);
      // In this case it should have been liquidated
      return fee > balance ? 0 : balance.sub(fee);
    }
  }

  /// @notice Returns decimal of the FuturesMarket Asset
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }
}
