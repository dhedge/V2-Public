// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IPoolManagerLogic} from "../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../interfaces/IHasSupportedAsset.sol";
import {IHasGuardInfo} from "../interfaces/IHasGuardInfo.sol";
import {IAccountedTokenAssetGuard} from "../interfaces/guards/IAccountedTokenAssetGuard.sol";
import {ITxTrackingGuard} from "../interfaces/guards/ITxTrackingGuard.sol";

import {SlippageAccumulator} from "./SlippageAccumulator.sol";

abstract contract SlippageAccumulatorUser is ITxTrackingGuard {
  using SafeMath for *;

  bool public override isTxTrackingGuard = true;

  SlippageAccumulator public immutable slippageAccumulator;

  /// @dev Note that the intermediateSwapData is used to store the data temporarily
  ///      after a swap is completed, this is used to update the slippage impact.
  ///      the `dstAmount` stored in this struct before execution of `afterTxGuard` is the prior balance of the pool for the destination asset.
  SlippageAccumulator.SwapData internal intermediateSwapData;

  /// @dev Total fund value before a swap with an unsupported source asset; consumed by `afterTxGuard`.
  uint256 internal intermediateTotalValueBefore;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "invalid address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  function afterTxGuard(address poolManagerLogic, address to, bytes memory /* data */) public virtual override {
    address poolLogic = _accessControl(poolManagerLogic);

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

    // Unsupported source: per-asset pricing above is skipped, so catch value leaving via the fund-value delta.
    uint256 totalValueBefore = intermediateTotalValueBefore;
    if (totalValueBefore != 0) {
      intermediateTotalValueBefore = 0;
      slippageAccumulator.updateSlippageImpactByValue(
        poolManagerLogic,
        to,
        totalValueBefore,
        IPoolManagerLogic(poolManagerLogic).totalFundValue()
      );
    }
  }

  /// @dev Swap guards MUST call this in `txGuard` with the swap's source asset. For an unsupported source
  ///      (which the `SlippageAccumulator` cannot price) it forbids selling an already-accounted token and
  ///      snapshots total fund value for the net-value check in `afterTxGuard`.
  function _beforeSwapSourceGuard(address poolManagerLogic, address srcAsset) internal virtual {
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(srcAsset)) {
      _requireSrcNotAccounted(poolManagerLogic, srcAsset);
      intermediateTotalValueBefore = IPoolManagerLogic(poolManagerLogic).totalFundValue();
    }
  }

  /// @dev Forbids selling a token already counted by an "umbrella" asset guard (e.g. an Aave aToken); such
  ///      positions must be unwound through their protocol. Protocol-agnostic: guards declare their own
  ///      receipts via `IAccountedTokenAssetGuard`, so a new integration needs no change here. Same
  ///      capability probe as `PoolManagerLogic._addAsset`, via `staticcall` as this is a view.
  function _requireSrcNotAccounted(address poolManagerLogic, address srcAsset) internal view {
    address factory = slippageAccumulator.poolFactory();
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();

    for (uint256 i; i < supportedAssets.length; ++i) {
      address assetGuard = IHasGuardInfo(factory).getAssetGuard(supportedAssets[i].asset);

      if (assetGuard == address(0)) continue;

      // solhint-disable-next-line avoid-low-level-calls
      (bool hasFunction, bytes memory answer) = assetGuard.staticcall(
        abi.encodeWithSignature("isAccountedTokenAssetGuard()")
      );

      if (hasFunction && answer.length == 32 && abi.decode(answer, (bool))) {
        require(
          !IAccountedTokenAssetGuard(assetGuard).isAccountedToken(poolLogic, supportedAssets[i].asset, srcAsset),
          "accounted token source"
        );
      }
    }
  }

  function _getBalance(address token, address holder) internal view returns (uint256) {
    // This is to avoid reverts during wrap/unwrap attempts via 1inch (which still should revert downstream)
    return (token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) ? holder.balance : IERC20(token).balanceOf(holder);
  }

  function _accessControl(address poolManagerLogic) internal view returns (address poolLogic) {
    poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();

    require(
      msg.sender == poolLogic && IPoolFactory(slippageAccumulator.poolFactory()).isPool(poolLogic),
      "not pool logic"
    );
  }
}
