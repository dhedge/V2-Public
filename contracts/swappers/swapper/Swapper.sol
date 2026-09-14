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
import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {RouterProcessor} from "./RouterProcessor.sol";
import {TokenTransferMethods} from "./TokenTransferMethods.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import "./SwapperStructs.sol" as SwapperStructs;

contract Swapper is RouterProcessor, TokenTransferMethods, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  //////////////////////////
  //        Events        //
  //////////////////////////

  event RouterAdded(bytes32 indexed routerKey, address router);
  event RouterRemoved(bytes32 indexed routerKey);

  //////////////////////////
  //        Errors        //
  //////////////////////////

  error ZeroAddress(string field);
  error InsufficientAmountReceived(IERC20 destToken, uint256 receivedAmount, uint256 minAmount);

  //////////////////////////
  //       Functions      //
  //////////////////////////

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address owner_, address permit2_, IWETH wrappedNativeToken_) external initializer {
    __Ownable_init(owner_);
    __TokenTransferMethods_init(permit2_, wrappedNativeToken_);
  }

  /// @notice Swap tokens using the given `swapStruct_`.
  /// @dev Only supports SINGLE_IN_SINGLE_OUT and MULTI_IN_SINGLE_OUT swap types.
  /// @param swapStruct_ The struct containing all the data required to process the swap(s).
  /// @return destAmountReceived_ The amount of `destToken` received by the caller.
  function swap(SwapperStructs.InOutData calldata swapStruct_) external payable returns (uint256 destAmountReceived_) {
    uint256 destAmountBefore = swapStruct_.destData.destToken.balanceOf(address(this));

    // Transfer all the `srcTokens` to this contract.
    _transferFromCaller(msg.sender, swapStruct_.srcData);

    // Process swaps based on `srcData` array.
    // The first loop iterates over the `srcData` array. The number of iterations is equal to the number of transfer methods used in the swap.
    // For example if the swap uses `TokenTransferMethod.ALLOWANCE` for all `srcTokens`, then the outer loop will iterate only once.
    // If the swap uses `TransferMethod.ALLOWANCE` for the first x `srcTokens` and `TransferMethod.PERMIT` for the next y `srcTokens`,
    // then the outer loop will iterate twice.
    for (uint256 i; i < swapStruct_.srcData.length; ++i) {
      // The second loop iterates over the `srcTokens` array in which the `srcTokens` are transferred and swapped using the same token transfer method.
      for (uint256 j; j < swapStruct_.srcData[i].srcTokenSwapDetails.length; ++j) {
        _processSwap({srcTokenSwapDetails_: swapStruct_.srcData[i].srcTokenSwapDetails[j]});
      }
    }

    // Check that we got enough of each `destToken` after processing and transfer them to the caller.
    // Note that we don't consider the current `destToken` balance of this contract as the received amount
    // as the amount can be more than the actual received amount due to someone else transferring tokens to this contract.
    // The following approach gives us the ability to rescue funds from this contract.
    destAmountReceived_ = swapStruct_.destData.destToken.balanceOf(address(this)) - destAmountBefore;

    if (destAmountReceived_ < swapStruct_.destData.minDestAmount)
      revert InsufficientAmountReceived(
        swapStruct_.destData.destToken,
        destAmountReceived_,
        swapStruct_.destData.minDestAmount
      );

    swapStruct_.destData.destToken.safeTransfer(msg.sender, destAmountReceived_);
  }

  //////////////////////////
  //    Admin functions   //
  //////////////////////////

  /// @notice Add a new router to the whitelist.
  /// @dev Note that this function will modify the router address if the given key already exists.
  /// @param routerKey_ A unique key to identify the router.
  /// @param router_ Address of the router.
  function addRouter(bytes32 routerKey_, address router_) external onlyOwner {
    if (router_ == address(0)) revert ZeroAddress("router");

    _addRouter(routerKey_, router_);

    emit RouterAdded(routerKey_, router_);
  }

  /// @notice Remove a router from the whitelist.
  /// @param routerKey_ The key of the router to be removed.
  function removeRouter(bytes32 routerKey_) external onlyOwner {
    if (getRouter(routerKey_) == address(0)) revert ZeroAddress("router");

    _removeRouter(routerKey_);

    emit RouterRemoved(routerKey_);
  }

  /// @notice Rescue funds from the contract.
  /// @param token_ Address of the token to be rescued.
  /// @param to_ Address to which the funds will be transferred.
  /// @param amount_ Amount of tokens to be rescued.
  function rescueFunds(IERC20 token_, address to_, uint256 amount_) external onlyOwner {
    token_.safeTransfer(to_, amount_);
  }

  /// @notice Sets the wrapped equivalent of native token's contract address.
  /// @dev This is intended to be used once as this is the new state variable introduced in the newer version
  ///      of the TokenTransferMethods contract.
  /// @param wrappedNativeToken_ Address of the wrapped native token contract.
  function setWrappedNativeToken(IWETH wrappedNativeToken_) external onlyOwner {
    _setWrappedNativeTokenAddress(wrappedNativeToken_);
  }
}
