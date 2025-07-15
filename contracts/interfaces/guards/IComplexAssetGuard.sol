// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {IAssetGuard} from "./IAssetGuard.sol";

interface IComplexAssetGuard {
  /// @notice Processes the withdrawal of a complex asset
  /// @param pool The PoolLogic address
  /// @param asset The asset to be withdrawn
  /// @param withdrawPortion The portion of asset to be withdrawn
  /// @param to The recipient address
  /// @param withdrawData Custom withdraw data specific to the asset
  /// @return withdrawAsset Asset received after processing the withdrawal
  /// @return withdrawBalance Portion of withdraw asset which goes to depositor
  /// @return transactions Transaction data to execute in the PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 withdrawPortion,
    address to,
    bytes memory withdrawData
  )
    external
    returns (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions);
}
