// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IGmxSwapPricingUtils {
  enum SwapPricingType {
    Swap,
    Shift,
    Atomic,
    Deposit,
    Withdrawal
  }
}
