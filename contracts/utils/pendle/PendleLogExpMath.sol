// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;

/// @notice Ported from Pendle's LogExpMath (Solidity ^0.8.0) to 0.7.6.
///         Only the `exp` function is included — the minimum needed for fee rate computation.
/// @author Original: Fernando Martinelli, Sergio Yuhjtman, Daniel Fernandez (Balancer)
library PendleLogExpMath {
  int256 internal constant ONE_18 = 1e18;
  int256 internal constant ONE_20 = 1e20;

  int256 internal constant MAX_NATURAL_EXPONENT = 130e18;
  int256 internal constant MIN_NATURAL_EXPONENT = -41e18;

  // 18 decimal constants
  int256 internal constant x0 = 128000000000000000000; // 2^7
  int256 internal constant a0 = 38877084059945950922200000000000000000000000000000000000; // e^(x0)
  int256 internal constant x1 = 64000000000000000000; // 2^6
  int256 internal constant a1 = 6235149080811616882910000000; // e^(x1)

  // 20 decimal constants
  int256 internal constant x2 = 3200000000000000000000; // 2^5
  int256 internal constant a2 = 7896296018268069516100000000000000; // e^(x2)
  int256 internal constant x3 = 1600000000000000000000; // 2^4
  int256 internal constant a3 = 888611052050787263676000000; // e^(x3)
  int256 internal constant x4 = 800000000000000000000; // 2^3
  int256 internal constant a4 = 298095798704172827474000; // e^(x4)
  int256 internal constant x5 = 400000000000000000000; // 2^2
  int256 internal constant a5 = 5459815003314423907810; // e^(x5)
  int256 internal constant x6 = 200000000000000000000; // 2^1
  int256 internal constant a6 = 738905609893065022723; // e^(x6)
  int256 internal constant x7 = 100000000000000000000; // 2^0
  int256 internal constant a7 = 271828182845904523536; // e^(x7)
  int256 internal constant x8 = 50000000000000000000; // 2^-1
  int256 internal constant a8 = 164872127070012814685; // e^(x8)
  int256 internal constant x9 = 25000000000000000000; // 2^-2
  int256 internal constant a9 = 128402541668774148407; // e^(x9)

  /// @dev Natural exponentiation (e^x) with signed 18 decimal fixed point exponent.
  ///      Reverts if `x` is outside [MIN_NATURAL_EXPONENT, MAX_NATURAL_EXPONENT].
  function exp(int256 x) internal pure returns (int256) {
    require(x >= MIN_NATURAL_EXPONENT && x <= MAX_NATURAL_EXPONENT, "Invalid exponent");

    if (x < 0) {
      return ((ONE_18 * ONE_18) / exp(-x));
    }

    int256 firstAN;
    if (x >= x0) {
      x -= x0;
      firstAN = a0;
    } else if (x >= x1) {
      x -= x1;
      firstAN = a1;
    } else {
      firstAN = 1;
    }

    // Transform to 20 decimal fixed point for enhanced precision
    x *= 100;

    int256 product = ONE_20;

    if (x >= x2) {
      x -= x2;
      product = (product * a2) / ONE_20;
    }
    if (x >= x3) {
      x -= x3;
      product = (product * a3) / ONE_20;
    }
    if (x >= x4) {
      x -= x4;
      product = (product * a4) / ONE_20;
    }
    if (x >= x5) {
      x -= x5;
      product = (product * a5) / ONE_20;
    }
    if (x >= x6) {
      x -= x6;
      product = (product * a6) / ONE_20;
    }
    if (x >= x7) {
      x -= x7;
      product = (product * a7) / ONE_20;
    }
    if (x >= x8) {
      x -= x8;
      product = (product * a8) / ONE_20;
    }
    if (x >= x9) {
      x -= x9;
      product = (product * a9) / ONE_20;
    }

    // Taylor series for the remainder: 1 + x + x^2/2! + ... + x^12/12!
    int256 seriesSum = ONE_20;
    int256 term;

    term = x;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 2;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 3;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 4;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 5;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 6;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 7;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 8;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 9;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 10;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 11;
    seriesSum += term;

    term = ((term * x) / ONE_20) / 12;
    seriesSum += term;

    return (((product * seriesSum) / ONE_20) * firstAN) / 100;
  }
}
