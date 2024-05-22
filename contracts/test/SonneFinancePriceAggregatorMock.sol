// SPDX-License-Identifier: BUSL-1.1
// solhint-disable-next-line
pragma solidity 0.8.10;

import "../utils/sonne/ExponentialNoError.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/sonne/CTokenInterfaces.sol";
import "../interfaces/sonne/IChainlinkPriceOracle.sol";
import "../interfaces/IHasAssetInfo.sol";

contract SonneFinancePriceAggregatorMock is ExponentialNoError {
  constructor(address cToken_, uint256 initialExchangeRateMantissa_) {
    uint256 _initialExchangeRateMantissa = initialExchangeRateMantissa_;

    uint256 simulatedExchangeRate = exchangeRate(cToken_, _initialExchangeRateMantissa);

    bytes memory returnData = abi.encode(simulatedExchangeRate);

    assembly {
      // Return from the start of the data (discarding the original data address)
      // up to the end of the memory used
      let dataStart := add(returnData, 0x20)
      return(dataStart, sub(msize(), dataStart))
    }
  }

  /* ========== VIEWS ========== */

  function exchangeRate(
    address cToken_,
    uint256 intitialExchangeRateMantissa_
  ) public view returns (uint256 exchangeRate_) {
    CTokenInterface cTokenInterface = CTokenInterface(cToken_);

    uint256 _totalSupply = cTokenInterface.totalSupply();

    if (_totalSupply == 0) {
      /*
       * If there are no tokens minted:
       *  exchangeRate = initialExchangeRate
       */
      return intitialExchangeRateMantissa_;
    } else {
      (uint256 cashPrior, uint256 totalBorrowsNew, uint256 totalReservesNew) = _accrueInterest(cToken_);

      /*
       * Otherwise:
       *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
       */
      uint256 cashPlusBorrowsMinusReserves = cashPrior + totalBorrowsNew - totalReservesNew;
      exchangeRate_ = (cashPlusBorrowsMinusReserves * expScale) / _totalSupply;

      return exchangeRate_;
    }
  }

  function _accrueInterest(
    address cToken_
  ) internal view returns (uint256 cashPrior_, uint256 totalBorrowsNew_, uint256 totalReservesNew_) {
    CTokenInterface cTokenInterface = CTokenInterface(cToken_);

    /* Remember the initial block number */

    // Note that Sonne Finance used timestamp rather than number of blocks.
    // Originally, here `getBlockNumber` was used.
    // This is equivalent to getting current timestamp <https://github.com/sonne-finance/lending-protocol/blob/c4cb9b22a6cd227c0fee7e0d97a97a6852d52fc0/contracts/CToken.sol#L253>
    uint256 currentBlockNumber = block.timestamp;
    uint256 accrualBlockNumberPrior = cTokenInterface.accrualBlockNumber();

    /* Read the previous values out of storage */

    // As per <https://github.com/sonne-finance/lending-protocol/blob/c4cb9b22a6cd227c0fee7e0d97a97a6852d52fc0/contracts/CErc20.sol#L147>
    // `getCashPrior` returns the balance of the underlying token of the cToken contract.
    uint256 cashPrior = IERC20Extended(CErc20Interface(cToken_).underlying()).balanceOf(cToken_);

    uint256 borrowsPrior = cTokenInterface.totalBorrows();
    uint256 reservesPrior = cTokenInterface.totalReserves();

    /* Short-circuit accumulating 0 interest */
    if (accrualBlockNumberPrior == currentBlockNumber) {
      return (cashPrior, borrowsPrior, reservesPrior);
    }

    // uint256 borrowIndexPrior = cTokenInterface.borrowIndex();

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
    // uint256 borrowIndexNew = mul_ScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);

    return (cashPrior, totalBorrowsNew, totalReservesNew);
  }
}
