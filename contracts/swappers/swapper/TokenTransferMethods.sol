//
//    ===========  ======     ======         =         ====          ====   =========    ==========   ==========
//   ==        ==    ===        ==          ===          ===         ===     ==    ==     ===    ==     ==   ====
// ===          =    ===        ==         = ===         ====       ====     ==    ==     ===           ==    ===
// ====              =============        =   ===        = ===    == ===     ========     ========      =======
// ====              ===        ==       =========       =  ===  ==  ===     ==    ===    ===    =      ==  ===
// ==                ===        ==      =       ===      =   === ==  ===     ==     ===   ===           ==   ===
//   ===       ==    ===        ==     ==        ====    =    ===    ===     ==     ==    ===     ==    ==     ====
//     ==========  ======     ====== =====       ===== ====    ==    ====  ==========    ===========  ======     ====
//
// Chamber Finance - https://chamberfi.com
//
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";

import {ISignatureTransfer} from "../../interfaces/permit2/ISignatureTransfer.sol";
import {TokenTransferMethodsStorage} from "./TokenTransferMethodsStorage.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import "./SwapperStructs.sol" as SwapperStructs;

abstract contract TokenTransferMethods is TokenTransferMethodsStorage {
  using SafeERC20 for IERC20;

  error UnsupportedTokenTransferMethod();
  error NativeTokenSentWithoutNativeSwap();
  error InvalidNativeTokenTransferEncoding();
  error NotEnoughNativeTokenSent(uint256 expectedAmount, uint256 sentAmount);
  error UnsupportedPermit2Method(SwapperStructs.Permit2TransferType transferType);
  error AmountsAfterPermit2TransferMismatch(address token, uint256 expectedAmount, uint256 actualAmount);

  // solhint-disable-next-line func-name-mixedcase
  function __TokenTransferMethods_init(address permit2_, IWETH wrappedNativeToken_) internal {
    // Note that we aren't checking for the zero address here.
    // This is to avoid having the inheriting contract pass a valid address on chains where the permit2 contract is not deployed
    // and there is no wrapped native contract.
    _setPermit2Address(permit2_);
    _setWrappedNativeTokenAddress(wrappedNativeToken_);
  }

  /// @dev Transfer tokens from sender to the inheriting contract.
  function _transferFromCaller(address from_, SwapperStructs.SrcData[] memory srcData) internal virtual {
    bool nativeSwapIncluded;

    // Iterate over all the `TokenTransferMethods` used in the swap.
    for (uint8 i; i < srcData.length; ++i) {
      SwapperStructs.TransferMethod transferMethod = srcData[i].transferMethodData.method;

      if (transferMethod == SwapperStructs.TransferMethod.ALLOWANCE) {
        _transferUsingSimpleAllowance(from_, srcData[i]);
      } else if (transferMethod == SwapperStructs.TransferMethod.PERMIT2) {
        _transferUsingPermit2(from_, srcData[i]);
      } else if (transferMethod == SwapperStructs.TransferMethod.NATIVE) {
        nativeSwapIncluded = true;

        // Use native token wrapper to wrap to wrapped equivalent.
        _wrapNativeToken(srcData[i]);
      } else {
        revert UnsupportedTokenTransferMethod();
      }
    }

    // We revert if native token is sent without a native asset swapdata included in the `srcData`.
    if (!nativeSwapIncluded && msg.value > 0) revert NativeTokenSentWithoutNativeSwap();
  }

  function _transferUsingSimpleAllowance(address from_, SwapperStructs.SrcData memory srcData_) internal virtual {
    for (uint256 i; i < srcData_.srcTokenSwapDetails.length; ++i) {
      srcData_.srcTokenSwapDetails[i].token.safeTransferFrom(
        from_,
        address(this),
        srcData_.srcTokenSwapDetails[i].amount
      );
    }
  }

  /// @dev Note that the inheriting contract should be the receiver of the tokens.
  /// @dev Note that if any other token signature is provided, that token will be transferred
  ///      but the transaction won't revert. It will be stuck in the contract.
  function _transferUsingPermit2(address from_, SwapperStructs.SrcData memory srcData_) internal virtual {
    SwapperStructs.Permit2EncodedData memory permit2Data = abi.decode(
      srcData_.transferMethodData.methodData,
      (SwapperStructs.Permit2EncodedData)
    );

    uint256[] memory previousBalances = new uint256[](srcData_.srcTokenSwapDetails.length);
    for (uint256 i; i < srcData_.srcTokenSwapDetails.length; ++i) {
      previousBalances[i] = srcData_.srcTokenSwapDetails[i].token.balanceOf(address(this));
    }

    if (permit2Data.transferType == SwapperStructs.Permit2TransferType.SINGLE_TRANSFER) {
      SwapperStructs.Permit2SingleTransfer memory singleTransferData = abi.decode(
        permit2Data.encodedData,
        (SwapperStructs.Permit2SingleTransfer)
      );

      ISignatureTransfer(getPermit2Address()).permitTransferFrom(
        singleTransferData.permit,
        singleTransferData.transferDetails,
        from_,
        singleTransferData.signature
      );
    } else if (permit2Data.transferType == SwapperStructs.Permit2TransferType.BATCH_TRANSFER) {
      SwapperStructs.Permit2BatchTransfer memory batchTransferData = abi.decode(
        permit2Data.encodedData,
        (SwapperStructs.Permit2BatchTransfer)
      );

      ISignatureTransfer(getPermit2Address()).permitTransferFrom(
        batchTransferData.permit,
        batchTransferData.transferDetails,
        from_,
        batchTransferData.signature
      );
    } else {
      revert UnsupportedPermit2Method(permit2Data.transferType);
    }

    // Check that the received amounts are as expected.
    for (uint256 i; i < srcData_.srcTokenSwapDetails.length; ++i) {
      uint256 newBalance = srcData_.srcTokenSwapDetails[i].token.balanceOf(address(this));
      uint256 delta = newBalance - previousBalances[i];

      if (delta != srcData_.srcTokenSwapDetails[i].amount)
        revert AmountsAfterPermit2TransferMismatch(
          address(srcData_.srcTokenSwapDetails[i].token),
          srcData_.srcTokenSwapDetails[i].amount,
          delta
        );
    }
  }

  function _wrapNativeToken(SwapperStructs.SrcData memory srcData) internal virtual {
    IWETH wrappedNativeToken = getWrappedNativeToken();

    if (
      srcData.srcTokenSwapDetails.length != 1 ||
      srcData.srcTokenSwapDetails[0].token != IERC20(address(wrappedNativeToken))
    ) revert InvalidNativeTokenTransferEncoding();
    if (msg.value != srcData.srcTokenSwapDetails[0].amount)
      revert NotEnoughNativeTokenSent(srcData.srcTokenSwapDetails[0].amount, msg.value);

    wrappedNativeToken.deposit{value: msg.value}();
  }
}
