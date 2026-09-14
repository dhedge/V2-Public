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

import {RouterProcessorStorage} from "./RouterProcessorStorage.sol";
import "./SwapperStructs.sol" as SwapperStructs;

abstract contract RouterProcessor is RouterProcessorStorage {
  using SafeERC20 for IERC20;

  //////////////////////////
  //        Events        //
  //////////////////////////

  event SwapComplete(address indexed router, SwapperStructs.SrcTokenSwapDetails indexed srcTokenSwapDetails);

  //////////////////////////
  //        Errors        //
  //////////////////////////

  error InvalidAggregator(bytes32 routerKey);
  error FailedToApproveParaswap(bytes returnData);
  error SwapFailed(address router, SwapperStructs.SrcTokenSwapDetails srcTokenSwapDetails, bytes returnData);
  error EmptyPayload();

  //////////////////////////
  //       Functions      //
  //////////////////////////

  function _processSwap(SwapperStructs.SrcTokenSwapDetails memory srcTokenSwapDetails_) internal {
    bytes32 routerKey = srcTokenSwapDetails_.aggregatorData.routerKey;
    address router = getRouter(routerKey);

    if (router == address(0)) revert InvalidAggregator(routerKey);

    if (srcTokenSwapDetails_.aggregatorData.swapData.length == 0) revert EmptyPayload();

    address contractToApprove;
    bool success;
    bytes memory returnData;

    // In case the aggregator to be used is Paraswap then we need to approve the TokenTransferProxy contract.
    contractToApprove = (routerKey == bytes32("PARASWAP")) ? _preParaswap(router) : router;

    (success, returnData) = _approveAndCallRouter({
      srcTokenSwapDetails_: srcTokenSwapDetails_,
      contractToApprove_: contractToApprove,
      router_: router
    });

    if (!success) revert SwapFailed(router, srcTokenSwapDetails_, returnData);

    emit SwapComplete(router, srcTokenSwapDetails_);
  }

  /// @dev Returns the remaining source token amount to the caller.
  function _approveAndCallRouter(
    SwapperStructs.SrcTokenSwapDetails memory srcTokenSwapDetails_,
    address contractToApprove_,
    address router_
  ) private returns (bool success_, bytes memory returnData_) {
    uint256 currentAllowance = srcTokenSwapDetails_.token.allowance(address(this), contractToApprove_);

    // Contract balance of source token before caller initiated the transaction.
    uint256 balanceBeforeSwap = srcTokenSwapDetails_.token.balanceOf(address(this)) - srcTokenSwapDetails_.amount;

    // We max approve the contract which will take the `srcToken_` as it reduces the number of approval calls in the future.
    // This should be safe as long as this contract doesn't hold tokens after a swap.
    if (currentAllowance < srcTokenSwapDetails_.amount)
      srcTokenSwapDetails_.token.safeIncreaseAllowance(contractToApprove_, type(uint256).max - currentAllowance);

    // solhint-disable-next-line avoid-low-level-calls
    (success_, returnData_) = router_.call(srcTokenSwapDetails_.aggregatorData.swapData);

    uint256 balanceAfterSwap = srcTokenSwapDetails_.token.balanceOf(address(this));

    // Return the remaining tokens to the caller.
    if (balanceAfterSwap > balanceBeforeSwap) {
      srcTokenSwapDetails_.token.safeTransfer(msg.sender, balanceAfterSwap - balanceBeforeSwap);
    }
  }

  function _preParaswap(address router_) private view returns (address contractToApprove_) {
    // In certain cases, the `srcToken` required for swapping is taken by a different contract than the router.
    // This is the case for Paraswap, where the TokenTransferProxy contract is used to transfer the token.

    // solhint-disable-next-line avoid-low-level-calls
    (bool fetchSuccess, bytes memory fetchedData) = router_.staticcall(
      abi.encodeWithSignature("getTokenTransferProxy()")
    );
    if (!fetchSuccess) revert FailedToApproveParaswap(fetchedData);

    contractToApprove_ = abi.decode(fetchedData, (address));
  }
}
