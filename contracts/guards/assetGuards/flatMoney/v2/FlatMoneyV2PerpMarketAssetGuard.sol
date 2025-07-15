// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {FlatMoneyV2BasisAssetGuard} from "./shared/FlatMoneyV2BasisAssetGuard.sol";

/// @notice AssetType = 36
contract FlatMoneyV2PerpMarketAssetGuard is FlatMoneyV2BasisAssetGuard {
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    (, address withdrawalAsset) = _useContractGuard(_pool, _asset).dHedgePoolsWhitelist(_pool);

    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(
      _pool,
      _asset,
      _withdrawPortion,
      withdrawalAsset
    );
  }
}
