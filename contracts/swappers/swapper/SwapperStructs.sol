// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "../../interfaces/permit2/ISignatureTransfer.sol";

//////////////////////////
//    Structs & Enums   //
//////////////////////////

enum TransferMethod {
  ALLOWANCE,
  PERMIT2,
  NATIVE
}

enum Permit2TransferType {
  SINGLE_TRANSFER,
  BATCH_TRANSFER
}

struct Permit2EncodedData {
  Permit2TransferType transferType;
  bytes encodedData;
}

struct Permit2SingleTransfer {
  ISignatureTransfer.PermitTransferFrom permit;
  ISignatureTransfer.SignatureTransferDetails transferDetails;
  bytes signature;
}

struct Permit2BatchTransfer {
  ISignatureTransfer.PermitBatchTransferFrom permit;
  ISignatureTransfer.SignatureTransferDetails[] transferDetails;
  bytes signature;
}

/// @dev `methodData` here contains additional data for using the transfer method.
///       For `ALLOWANCE`, it's empty and for `PERMIT2`, it's encoded `Permit2EncodedData`.
struct TransferMethodData {
  TransferMethod method;
  bytes methodData;
}

struct SrcTokenSwapDetails {
  IERC20 token;
  uint256 amount;
  AggregatorData aggregatorData;
}

struct SrcData {
  SrcTokenSwapDetails[] srcTokenSwapDetails;
  TransferMethodData transferMethodData;
}

struct DestData {
  IERC20 destToken;
  uint256 minDestAmount;
}

struct AggregatorData {
  bytes32 routerKey;
  bytes swapData;
}

struct InOutData {
  SrcData[] srcData;
  DestData destData;
}
