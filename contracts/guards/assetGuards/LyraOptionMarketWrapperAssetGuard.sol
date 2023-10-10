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

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./ClosedAssetGuard.sol";
import "../contractGuards/LyraOptionMarketWrapperContractGuard.sol";
import "../../utils/lyra/DhedgeOptionMarketWrapperForLyra.sol";
import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/lyra/IOptionMarketViewer.sol";
import "../../interfaces/lyra/IOptionGreekCache.sol";
import "../../interfaces/lyra/ISynthetixAdapter.sol";
import "../../interfaces/lyra/ILiquidityPool.sol";
import "../../interfaces/lyra/IOptionMarket.sol";

/// @title Lyra OptionMarketWrapper asset guard
/// @dev Asset type = 100
contract LyraOptionMarketWrapperAssetGuard is ClosedAssetGuard {
  using SafeMath for uint256;

  DhedgeOptionMarketWrapperForLyra public immutable dhedgeLyraWrapper;
  uint256 public constant PRICE_GWAV_DURATION = 10 minutes;
  uint256 public constant CHECK_GWAV_DURATION = 6 hours;
  uint256 public constant GWAV_DIVERGENCE_CB_AMOUNT_DENOMINATOR = 1000;
  // 5%
  uint256 public constant GWAV_DIVERGENCE_CB_AMOUNT_NUMERATOR = (GWAV_DIVERGENCE_CB_AMOUNT_DENOMINATOR / 100) * 5;

  constructor(DhedgeOptionMarketWrapperForLyra _dhedgeLyraWrapper) {
    dhedgeLyraWrapper = _dhedgeLyraWrapper;
  }

  function marketViewer() public view returns (IOptionMarketViewer) {
    return dhedgeLyraWrapper.getOptionMarketViewer();
  }

  function getGWAVCallPrice(address optionMarket, uint256 strikeId) public view returns (uint256 callPrice) {
    ILyraRegistry.OptionMarketAddresses memory c = dhedgeLyraWrapper.lyraRegistry().getMarketAddresses(optionMarket);

    (callPrice, ) = IGWAVOracle(c.gwavOracle).optionPriceGWAV(strikeId, PRICE_GWAV_DURATION);
    (uint256 checkCallPrice, ) = IGWAVOracle(c.gwavOracle).optionPriceGWAV(strikeId, CHECK_GWAV_DURATION);

    assertNoGWAVDivergence(callPrice, checkCallPrice);
  }

  function getGWAVPutPrice(address optionMarket, uint256 strikeId) public view returns (uint256 putPrice) {
    ILyraRegistry.OptionMarketAddresses memory c = dhedgeLyraWrapper.lyraRegistry().getMarketAddresses(optionMarket);

    (, putPrice) = IGWAVOracle(c.gwavOracle).optionPriceGWAV(strikeId, PRICE_GWAV_DURATION);
    (, uint256 checkPutPrice) = IGWAVOracle(c.gwavOracle).optionPriceGWAV(strikeId, CHECK_GWAV_DURATION);

    assertNoGWAVDivergence(putPrice, checkPutPrice);
  }

  function assertNoGWAVDivergence(uint256 price1, uint256 price2) public pure {
    uint256 difference = price1 > price2 ? price1 - price2 : price2 - price1;
    uint256 acceptableDifference = price1.mul(GWAV_DIVERGENCE_CB_AMOUNT_NUMERATOR).div(
      GWAV_DIVERGENCE_CB_AMOUNT_DENOMINATOR
    );
    require(difference <= acceptableDifference, "gwav divergence too high");
  }

  /// @notice Creates transaction data for withdrawing staked tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset lyra option market wrapper contract address
  /// @param portion The fraction of total staked asset to withdraw
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the staked withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address to
  )
    external
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      MultiTransaction[] memory transactions
    )
  {
    // settle expired positions
    address lyraOptionMarketWrapperContractGuard = IHasGuardInfo(IPoolLogic(pool).factory()).getContractGuard(asset);
    LyraOptionMarketWrapperContractGuard(lyraOptionMarketWrapperContractGuard).settleExpiredAndFilterActivePositions(
      pool
    );

    // get active positions
    LyraOptionMarketWrapperContractGuard.OptionPosition[] memory positions = LyraOptionMarketWrapperContractGuard(
      lyraOptionMarketWrapperContractGuard
    ).getOptionPositions(pool);

    // create the transactions array
    transactions = new MultiTransaction[](positions.length * 2);
    uint256 txCount;
    for (uint256 i = 0; i < positions.length; i++) {
      // Transfer the Option NFT ownership to the wrapper contract.
      // We need to do this because before we call `forceClose` on a position we don't know exactly how much the withdrawer will receive back.
      IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer().marketAddresses(
        positions[i].optionMarket
      );
      transactions[txCount].to = address(optionMarketAddresses.optionToken);
      transactions[txCount].txData = abi.encodeWithSelector(
        IERC721.transferFrom.selector,
        pool,
        dhedgeLyraWrapper,
        positions[i].positionId
      );
      txCount++;

      // DhedgeOptionMarketWrapperForLyra will return the nft after forceClosing the withdrawers portion
      transactions[txCount].to = address(dhedgeLyraWrapper);
      transactions[txCount].txData = abi.encodeWithSelector(
        DhedgeOptionMarketWrapperForLyra.tryCloseAndForceClosePosition.selector,
        positions[i],
        portion,
        to // recipient
      );
      txCount++;
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns decimal of the Lyra option market asset
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include any external balance in staking contracts
  /// @param pool address of the pool
  /// @param asset lyra option market wrapper contract address
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    address factory = IPoolLogic(pool).factory();
    address lyraContractGuard = IHasGuardInfo(factory).getContractGuard(asset);

    LyraOptionMarketWrapperContractGuard.OptionPosition[] memory positions = LyraOptionMarketWrapperContractGuard(
      lyraContractGuard
    ).getOptionPositions(pool);

    for (uint256 i = 0; i < positions.length; i++) {
      IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer().marketAddresses(
        positions[i].optionMarket
      );

      IOptionToken.OptionPosition memory position = IOptionToken(optionMarketAddresses.optionToken).positions(
        positions[i].positionId
      );

      if (position.state == IOptionToken.PositionState.ACTIVE) {
        uint256 basePrice = dhedgeLyraWrapper.getSynthetixAdapter().getSpotPriceForMarket(positions[i].optionMarket);
        (uint256 strikePrice, uint256 priceAtExpiry, uint256 ammShortCallBaseProfitRatio) = IOptionMarket(
          positions[i].optionMarket
        ).getSettlementParameters(position.strikeId);

        uint256 marketValue;
        if (priceAtExpiry != 0) {
          // option is expired
          if (position.optionType == IOptionMarket.OptionType.LONG_CALL) {
            marketValue = (priceAtExpiry > strikePrice)
              ? position.amount.mul(priceAtExpiry.sub(strikePrice)).div(1e18)
              : 0;
          } else if (position.optionType == IOptionMarket.OptionType.LONG_PUT) {
            marketValue = (strikePrice > priceAtExpiry)
              ? position.amount.mul(strikePrice.sub(priceAtExpiry)).div(1e18)
              : 0;
          } else if (position.optionType == IOptionMarket.OptionType.SHORT_CALL_BASE) {
            uint256 ammProfit = position.amount.mul(ammShortCallBaseProfitRatio).div(1e18);
            marketValue = position.collateral > ammProfit
              ? (position.collateral.sub(ammProfit)).mul(basePrice).div(1e18)
              : 0;
          } else if (position.optionType == IOptionMarket.OptionType.SHORT_CALL_QUOTE) {
            uint256 ammProfit = (priceAtExpiry > strikePrice)
              ? position.amount.mul(priceAtExpiry.sub(strikePrice)).div(1e18)
              : 0;
            marketValue = position.collateral > ammProfit ? position.collateral.sub(ammProfit) : 0;
          } else if (position.optionType == IOptionMarket.OptionType.SHORT_PUT_QUOTE) {
            uint256 ammProfit = (strikePrice > priceAtExpiry)
              ? position.amount.mul(strikePrice.sub(priceAtExpiry)).div(1e18)
              : 0;
            marketValue = position.collateral > ammProfit ? position.collateral.sub(ammProfit) : 0;
          } else {
            revert("invalid option type");
          }
        } else {
          if (position.optionType == IOptionMarket.OptionType.LONG_CALL) {
            // position.amount.multiplyDecimal(callPrice)
            marketValue = position.amount.mul(getGWAVCallPrice(positions[i].optionMarket, position.strikeId)).div(1e18);
          } else if (position.optionType == IOptionMarket.OptionType.LONG_PUT) {
            // position.amount.multiplyDecimal(putPrice)
            marketValue = position.amount.mul(getGWAVPutPrice(positions[i].optionMarket, position.strikeId)).div(1e18);
          } else if (position.optionType == IOptionMarket.OptionType.SHORT_CALL_BASE) {
            // position.collateral.multiplyDecimal(basePrice) - position.amount.multiplyDecimal(callPrice)
            uint256 collateralValue = position.collateral.mul(basePrice).div(1e18);
            uint256 callValue = position.amount.mul(getGWAVCallPrice(positions[i].optionMarket, position.strikeId)).div(
              1e18
            );
            marketValue = collateralValue > callValue ? collateralValue.sub(callValue) : 0;
          } else if (position.optionType == IOptionMarket.OptionType.SHORT_CALL_QUOTE) {
            // position.collateral - position.amount.multiplyDecimal(callPrice)
            uint256 collateralValue = position.collateral;
            uint256 callValue = position.amount.mul(getGWAVCallPrice(positions[i].optionMarket, position.strikeId)).div(
              1e18
            );
            marketValue = collateralValue > callValue ? collateralValue.sub(callValue) : 0;
          } else if (position.optionType == IOptionMarket.OptionType.SHORT_PUT_QUOTE) {
            // position.collateral - position.amount.multiplyDecimal(putPrice)
            uint256 collateralValue = position.collateral;
            uint256 putValue = position.amount.mul(getGWAVPutPrice(positions[i].optionMarket, position.strikeId)).div(
              1e18
            );
            marketValue = collateralValue > putValue ? collateralValue.sub(putValue) : 0;
          } else {
            revert("invalid option type");
          }
        }
        balance = balance.add(marketValue);
      }
    }
  }
}
