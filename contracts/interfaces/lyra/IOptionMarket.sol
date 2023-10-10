// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IOptionMarket {
  enum TradeDirection {
    OPEN,
    CLOSE,
    LIQUIDATE
  }

  enum OptionType {
    LONG_CALL,
    LONG_PUT,
    SHORT_CALL_BASE,
    SHORT_CALL_QUOTE,
    SHORT_PUT_QUOTE
  }

  struct TradeInputParameters {
    // id of strike
    uint256 strikeId;
    // OptionToken ERC721 id for position (set to 0 for new positions)
    uint256 positionId;
    // number of sub-orders to break order into (reduces slippage)
    uint256 iterations;
    // type of option to trade
    OptionType optionType;
    // number of contracts to trade
    uint256 amount;
    // final amount of collateral to leave in OptionToken position
    uint256 setCollateralTo;
    // revert trade if totalCost is below this value
    uint256 minTotalCost;
    // revert trade if totalCost is above this value
    uint256 maxTotalCost;
  }

  struct Strike {
    // strike listing identifier
    uint256 id;
    // strike price
    uint256 strikePrice;
    // volatility component specific to the strike listing (boardIv * skew = vol of strike)
    uint256 skew;
    // total user long call exposure
    uint256 longCall;
    // total user short call (base collateral) exposure
    uint256 shortCallBase;
    // total user short call (quote collateral) exposure
    uint256 shortCallQuote;
    // total user long put exposure
    uint256 longPut;
    // total user short put (quote collateral) exposure
    uint256 shortPut;
    // id of board to which strike belongs
    uint256 boardId;
  }

  function getStrike(uint256 strikeId) external view returns (Strike memory);

  function getStrikeAndExpiry(uint256 strikeId) external view returns (uint256 strikePrice, uint256 expiry);

  function getSettlementParameters(uint256 strikeId)
    external
    view
    returns (
      uint256 strikePrice,
      uint256 priceAtExpiry,
      uint256 strikeToBaseReturned
    );

  ///

  function addCollateral(uint256 positionId, uint256 amountCollateral) external;

  function liquidatePosition(uint256 positionId, address rewardBeneficiary) external;

  function closePosition(TradeInputParameters memory params) external;

  function forceClosePosition(TradeInputParameters memory params) external;

  function openPosition(TradeInputParameters memory params) external;
}
