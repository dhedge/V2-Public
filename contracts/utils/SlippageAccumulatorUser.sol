// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManagerLogic} from "../interfaces/IPoolManagerLogic.sol";
import {ITxTrackingGuard} from "../interfaces/guards/ITxTrackingGuard.sol";

import {SlippageAccumulator} from "./SlippageAccumulator.sol";

abstract contract SlippageAccumulatorUser is ITxTrackingGuard {
  using SafeMath for *;

  bool public override isTxTrackingGuard = true;

  SlippageAccumulator internal immutable slippageAccumulator;

  /// @dev Note that the intermediateSwapData is used to store the data temporarily
  ///      after a swap is completed, this is used to update the slippage impact.
  ///      the `dstAmount` stored in this struct before execution of `afterTxGuard` is the prior balance of the pool for the destination asset.
  SlippageAccumulator.SwapData internal intermediateSwapData;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "invalid address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  function afterTxGuard(address poolManagerLogic, address to, bytes memory /* data */) public virtual override {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");

    slippageAccumulator.updateSlippageImpact(
      poolManagerLogic,
      to,
      SlippageAccumulator.SwapData({
        srcAsset: intermediateSwapData.srcAsset,
        dstAsset: intermediateSwapData.dstAsset,
        srcAmount: intermediateSwapData.srcAmount.sub(_getBalance(intermediateSwapData.srcAsset, poolLogic)),
        dstAmount: _getBalance(intermediateSwapData.dstAsset, poolLogic).sub(intermediateSwapData.dstAmount)
      })
    );
    intermediateSwapData = SlippageAccumulator.SwapData(address(0), address(0), 0, 0);
  }

  function _getBalance(address token, address holder) internal view returns (uint256) {
    // This is to avoid reverts during wrap/unwrap attempts via 1inch (which still should revert downstream)
    return (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) ? holder.balance : IERC20(token).balanceOf(holder);
  }
}
