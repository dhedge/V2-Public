// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapper {
  enum TransferMethod {
    ALLOWANCE,
    PERMIT2,
    NATIVE
  }

  struct AggregatorData {
    bytes32 routerKey;
    bytes swapData;
  }

  struct SrcTokenSwapDetails {
    IERC20 token;
    uint256 amount;
    AggregatorData aggregatorData;
  }

  struct TransferMethodData {
    TransferMethod method;
    bytes methodData;
  }

  struct SrcData {
    SrcTokenSwapDetails[] srcTokenSwapDetails;
    TransferMethodData transferMethodData;
  }

  struct DestData {
    IERC20 destToken;
    uint256 minDestAmount;
  }

  struct InOutData {
    SrcData[] srcData;
    DestData destData;
  }

  function swap(InOutData calldata swapStruct) external payable;
}
