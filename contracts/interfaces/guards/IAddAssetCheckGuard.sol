// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../IHasSupportedAsset.sol";

interface IAddAssetCheckGuard {
  function isAddAssetCheckGuard() external view returns (bool);
  function addAssetCheck(address poolLogic, IHasSupportedAsset.Asset calldata asset) external view;
}
