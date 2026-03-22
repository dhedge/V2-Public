// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IGmxSwapPricingUtils {
  enum SwapPricingType {
    Swap,
    Shift,
    AtomicWithdrawal,
    Deposit,
    Withdrawal,
    AtomicSwap
  }
}
