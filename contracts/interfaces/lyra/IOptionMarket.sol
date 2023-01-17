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
}
