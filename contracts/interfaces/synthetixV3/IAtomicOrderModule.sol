// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/**
 * @title Module for atomic buy and sell orders for traders.
 */
interface IAtomicOrderModule {
  struct OrderFees {
    uint256 fixedFees;
    uint256 utilizationFees;
    int256 skewFees;
    int256 wrapperFees;
  }

  /**
   * @notice Initiates a buy trade returning synth for the specified amountUsd.
   * @dev Transfers the specified amountUsd, collects fees through configured fee collector, returns synth to the trader.
   * @dev Leftover fees not collected get deposited into the market manager to improve market PnL.
   * @dev Uses the buyFeedId configured for the market.
   * @param synthMarketId Id of the market used for the trade.
   * @param amountUsd Amount of snxUSD trader is providing allowance for the trade.
   * @param minAmountReceived Min Amount of synth is expected the trader to receive otherwise the transaction will revert.
   * @param referrer Optional address of the referrer, for fee share
   * @return synthAmount Synth received on the trade based on amount provided by trader.
   * @return fees breakdown of all the fees incurred for the transaction.
   */
  function buyExactIn(
    uint128 synthMarketId,
    uint256 amountUsd,
    uint256 minAmountReceived,
    address referrer
  ) external returns (uint256 synthAmount, OrderFees memory fees);

  /**
   * @notice  alias for buyExactIn
   * @param   marketId  (see buyExactIn)
   * @param   usdAmount  (see buyExactIn)
   * @param   minAmountReceived  (see buyExactIn)
   * @param   referrer  (see buyExactIn)
   * @return  synthAmount  (see buyExactIn)
   * @return  fees  (see buyExactIn)
   */
  function buy(
    uint128 marketId,
    uint256 usdAmount,
    uint256 minAmountReceived,
    address referrer
  ) external returns (uint256 synthAmount, OrderFees memory fees);

  /**
   * @notice Initiates a sell trade returning snxUSD for the specified amount of synth (sellAmount)
   * @dev Transfers the specified synth, collects fees through configured fee collector, returns snxUSD to the trader.
   * @dev Leftover fees not collected get deposited into the market manager to improve market PnL.
   * @param synthMarketId Id of the market used for the trade.
   * @param sellAmount Amount of synth provided by trader for trade into snxUSD.
   * @param minAmountReceived Min Amount of snxUSD trader expects to receive for the trade
   * @param referrer Optional address of the referrer, for fee share
   * @return returnAmount Amount of snxUSD returned to user
   * @return fees breakdown of all the fees incurred for the transaction.
   */
  function sellExactIn(
    uint128 synthMarketId,
    uint256 sellAmount,
    uint256 minAmountReceived,
    address referrer
  ) external returns (uint256 returnAmount, OrderFees memory fees);

  /**
   * @notice  alias for sellExactIn
   * @param   marketId  (see sellExactIn)
   * @param   synthAmount  (see sellExactIn)
   * @param   minUsdAmount  (see sellExactIn)
   * @param   referrer  (see sellExactIn)
   * @return  usdAmountReceived  (see sellExactIn)
   * @return  fees  (see sellExactIn)
   */
  function sell(
    uint128 marketId,
    uint256 synthAmount,
    uint256 minUsdAmount,
    address referrer
  ) external returns (uint256 usdAmountReceived, OrderFees memory fees);

  /**
   * @notice Returns the USD token associated with this synthetix core system
   */
  function getUsdToken() external view returns (address);
}
