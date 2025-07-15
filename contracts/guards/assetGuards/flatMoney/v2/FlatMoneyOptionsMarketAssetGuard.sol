// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ILeverageModuleV2} from "../../../../interfaces/flatMoney/v2/ILeverageModuleV2.sol";
import {FlatMoneyV2BasisAssetGuard} from "./shared/FlatMoneyV2BasisAssetGuard.sol";

/// @notice AssetType = 32
contract FlatMoneyOptionsMarketAssetGuard is FlatMoneyV2BasisAssetGuard {
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
    address collateral = ILeverageModuleV2(_asset).vault().collateral();

    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(_pool, _asset, _withdrawPortion, collateral);
  }
}
