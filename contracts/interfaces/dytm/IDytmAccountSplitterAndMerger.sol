// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IDytmAccountSplitterAndMerger {
  enum Operation {
    INVALID, // 0
    SPLIT_ACCOUNT, // 1
    MERGE_ACCOUNTS // 2
  }

  struct CallbackData {
    Operation operation;
    bytes data;
  }

  struct SplitAccountParams {
    uint256 sourceAccount;
    uint88 market;
    uint64 fraction;
  }
}
