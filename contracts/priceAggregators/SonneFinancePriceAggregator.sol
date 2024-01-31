// SPDX-License-Identifier: BUSL-1.1
// solhint-disable-next-line
pragma solidity 0.8.10;

import "../utils/sonne/ExponentialNoError.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/sonne/CTokenInterfaces.sol";
import "../interfaces/sonne/ComptrollerLensInterface.sol";
import "../interfaces/sonne/PriceOracle.sol";
import "../interfaces/sonne/IChainlinkPriceOracle.sol";
import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IHasAssetInfo.sol";

contract SonneFinancePriceAggregator is IAggregatorV3Interface, ExponentialNoError {
  address public immutable cToken;

  ComptrollerLensInterface public immutable comptrollerLens;

  uint256 private immutable _underlyingDecimals;

  uint256 private immutable _cTokenDecimals;

  uint256 private immutable _denominator;

  /// @dev - According to the Sonne Finance deployment script at <https://github.com/sonne-finance/lending-protocol/blob/c4cb9b22a6cd227c0fee7e0d97a97a6852d52fc0/tasks/deploy-ctoken.ts#L69>
  ///      the initial exchange rate is `0.02 * (underlyingDecimals + 18 - decimals)`.
  ///      - Pass it in the same manner as done in the Sonne Finance deployment script.
  ///      - Alternatively, use `cast storage <CTOKEN ADDRESS> --rpc-url <RPC URL> --etherscan-api-key <ETHERSCAN KEY>`
  ///        to find the initial exchange rate.
  uint256 private immutable _initialExchangeRateMantissa;

  constructor(
    address cToken_,
    address comptrollerLens_,
    uint256 initialExchangeRateMantissa_
  ) {
    require(cToken_ != address(0), "cToken address cannot be 0");
    require(comptrollerLens_ != address(0), "price oracle address cannot be 0");

    cToken = cToken_;
    comptrollerLens = ComptrollerLensInterface(comptrollerLens_);

    _underlyingDecimals = IERC20Extended(CErc20Interface(cToken_).underlying()).decimals();
    _cTokenDecimals = CTokenInterface(cToken_).decimals();

    _denominator = 10**(18 + _underlyingDecimals - _cTokenDecimals);
    _initialExchangeRateMantissa = initialExchangeRateMantissa_;
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of asset (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
   */
  function latestRoundData()
    external
    view
    override
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    PriceOracle priceOracle = comptrollerLens.oracle();

    uint256 scalingFactor = 10**(36 - _underlyingDecimals);

    // We are scaling up the value by 1e18 for more precision.
    uint256 oneCTokenInUnderlying = (exchangeRate() * 1e18) / _denominator;

    // Get the price of 1 underlying token in USD using Open Price Feed.
    // The returned price is scaled up by the scaling factor.
    uint256 oneUnderlyingInUSD = priceOracle.getUnderlyingPrice(cToken);

    // We don't need roundId, startedAt and answeredInRound.
    // Also, we need to convert the price to 8 decimals to match the chainlink aggregator decimals format.
    // Hence, divide the price by 1e10 (since we scaled up the price by 1e18).
    return (
      0,
      int256(oneCTokenInUnderlying * oneUnderlyingInUSD) / int256(scalingFactor * 1e10),
      0,
      block.timestamp,
      0
    );
  }

  /**
   * @notice Get the exchange rate of the cToken asset.
   * @dev Note that this is a modified implementation of `exchangeRateCurrent` in the `CToken` contract.
   *      The modification was necessary to make it a view function which is what we require in our contracts.
   *      The original implementation can be found at <https://github.com/sonne-finance/lending-protocol/blob/c4cb9b22a6cd227c0fee7e0d97a97a6852d52fc0/contracts/CToken.sol#L358>.
   * @return exchangeRate_ The exchange rate as per the latest block.
   */
  function exchangeRate() public view returns (uint256 exchangeRate_) {
    address cachedCToken = cToken;
    CTokenInterface cTokenInterface = CTokenInterface(cachedCToken);

    uint256 _totalSupply = cTokenInterface.totalSupply();

    if (_totalSupply == 0) {
      /*
       * If there are no tokens minted:
       *  exchangeRate = initialExchangeRate
       */
      return _initialExchangeRateMantissa;
    } else {
      (uint256 cashPrior, uint256 totalBorrowsNew, uint256 totalReservesNew) = _accrueInterest();

      /*
       * Otherwise:
       *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
       */
      uint256 cashPlusBorrowsMinusReserves = cashPrior + totalBorrowsNew - totalReservesNew;
      exchangeRate_ = (cashPlusBorrowsMinusReserves * expScale) / _totalSupply;

      return exchangeRate_;
    }
  }

  /***
   * @dev Necessary to calculate the exchange rate.
   *     This is a modified implementation of `accrueInterest` in the `CToken` contract.
   *     The modification was necessary to make it a view function which is what we require in our contracts.
   *     The original implementation can be found at <https://github.com/sonne-finance/lending-protocol/blob/c4cb9b22a6cd227c0fee7e0d97a97a6852d52fc0/contracts/CToken.sol#L424>.
   */
  function _accrueInterest()
    internal
    view
    returns (
      uint256 cashPrior_,
      uint256 totalBorrowsNew_,
      uint256 totalReservesNew_
    )
  {
    address cachedCToken = cToken;
    CTokenInterface cTokenInterface = CTokenInterface(cachedCToken);

    /* Remember the initial block number */

    // Note that Sonne Finance used timestamp rather than number of blocks.
    // Originally, here `getBlockNumber` was used.
    // This is equivalent to getting current timestamp <https://github.com/sonne-finance/lending-protocol/blob/c4cb9b22a6cd227c0fee7e0d97a97a6852d52fc0/contracts/CToken.sol#L253>
    uint256 currentBlockNumber = block.timestamp;
    uint256 accrualBlockNumberPrior = cTokenInterface.accrualBlockNumber();

    /* Read the previous values out of storage */

    // As per <https://github.com/sonne-finance/lending-protocol/blob/c4cb9b22a6cd227c0fee7e0d97a97a6852d52fc0/contracts/CErc20.sol#L147>
    // `getCashPrior` returns the balance of the underlying token of the cToken contract.
    uint256 cashPrior = IERC20Extended(CErc20Interface(cachedCToken).underlying()).balanceOf(cachedCToken);

    uint256 borrowsPrior = cTokenInterface.totalBorrows();
    uint256 reservesPrior = cTokenInterface.totalReserves();

    /* Short-circuit accumulating 0 interest */
    if (accrualBlockNumberPrior == currentBlockNumber) {
      return (cashPrior, borrowsPrior, reservesPrior);
    }

    /* Calculate the current borrow interest rate */
    uint256 borrowRateMantissa = cTokenInterface.interestRateModel().getBorrowRate(
      cashPrior,
      borrowsPrior,
      reservesPrior
    );

    // Note that the decimal number has been obtained from `CTokenInterface` contract (borrowRateMaxMantissa).
    require(borrowRateMantissa <= 0.00004e16, "borrow rate is absurdly high");

    /* Calculate the number of blocks elapsed since the last accrual */
    uint256 blockDelta = currentBlockNumber - accrualBlockNumberPrior;

    /*
     * Calculate the interest accumulated into borrows and reserves and the new index:
     *  simpleInterestFactor = borrowRate * blockDelta
     *  interestAccumulated = simpleInterestFactor * totalBorrows
     *  totalBorrowsNew = interestAccumulated + totalBorrows
     *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
     *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
     */

    Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
    uint256 interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, borrowsPrior);
    uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
    uint256 totalReservesNew = mul_ScalarTruncateAddUInt(
      Exp({mantissa: cTokenInterface.reserveFactorMantissa()}),
      interestAccumulated,
      reservesPrior
    );

    return (cashPrior, totalBorrowsNew, totalReservesNew);
  }
}
