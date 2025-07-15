// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {ISwapper} from "../flatMoney/swapper/ISwapper.sol";
import {IComplexAssetGuard} from "./IComplexAssetGuard.sol";

interface ISwapDataConsumingGuard is IComplexAssetGuard {
  struct ComplexAssetSwapData {
    bytes srcData; // ISwapper.SrcTokenSwapDetails[]
    ISwapper.DestData destData;
    uint256 slippageTolerance;
  }

  struct AssetStructure {
    address asset;
    uint256 amount;
  }

  struct SwapDataParams {
    AssetStructure[] srcData;
    AssetStructure dstData;
  }

  /// @notice Calculates the swap data parameters for the frontend to get offchain swap tx data
  /// @dev State mutating call, should be called using `callStatic` or similar to avoid state changes
  /// @param pool The pool logic address
  /// @param poolTokenAmount The amount of pool token to be withdrawn
  /// @param slippageTolerance Slippage tolerance user agrees to be applied to the portion of the withdrawal that corresponds to the complex asset
  /// @return swapDataParams The swap data parameters
  function calculateSwapDataParams(
    address pool,
    uint256 poolTokenAmount,
    uint256 slippageTolerance
  ) external returns (SwapDataParams memory swapDataParams);
}
