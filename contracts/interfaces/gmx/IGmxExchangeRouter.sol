// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxOrderHandler} from "./IGmxOrderHandler.sol";
import {IGmxBaseOrderUtils} from "./IGmxBaseOrderUtils.sol";
import {IGmxDepositHandler} from "./IGmxDepositHandler.sol";
import {IGmxDepositUtils} from "./IGmxDepositUtils.sol";
import {IGmxWithdrawalUtils} from "./IGmxWithdrawalUtils.sol";
import {IGmxWithdrawalHandler} from "./IGmxWithdrawalHandler.sol";

interface IGmxExchangeRouter {
  // @dev Wraps the specified amount of native tokens into WNT then sends the WNT to the specified address
  function sendWnt(address receiver, uint256 amount) external payable;

  // @dev Sends the given amount of tokens to the given address
  function sendTokens(address token, address receiver, uint256 amount) external payable;

  /**
   * @dev Creates a new order with the given amount, order parameters. The order is
   * created by transferring the specified amount of collateral tokens from the caller's account to the
   * order store, and then calling the `createOrder()` function on the order handler contract. The
   * referral code is also set on the caller's account using the referral storage contract.
   */
  function createOrder(IGmxBaseOrderUtils.CreateOrderParams calldata params) external payable returns (bytes32);

  function orderHandler() external view returns (IGmxOrderHandler gmxOrderHandler);

  function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

  function claimFundingFees(
    address[] memory markets,
    address[] memory tokens,
    address receiver
  ) external payable returns (uint256[] memory);

  function claimCollateral(
    address[] memory markets,
    address[] memory tokens,
    uint256[] memory timeKeys,
    address receiver
  ) external payable returns (uint256[] memory);

  function cancelOrder(bytes32 key) external payable;

  function createDeposit(IGmxDepositUtils.CreateDepositParams calldata params) external payable returns (bytes32);

  function depositHandler() external view returns (IGmxDepositHandler gmxDepositHandler);

  function createWithdrawal(
    IGmxWithdrawalUtils.CreateWithdrawalParams calldata params
  ) external payable returns (bytes32);

  function cancelDeposit(bytes32 key) external payable;

  function cancelWithdrawal(bytes32 key) external payable;

  function withdrawalHandler() external view returns (IGmxWithdrawalHandler gmxWithdrawalHandler);
}
