// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {IStableModule} from "../IStableModule.sol";

interface IStableModuleV2 is IStableModule {
  function stableCollateralPerShare() external view returns (uint256 collateralPerShare);

  function stableCollateralPerShare(
    uint32 maxAge,
    bool priceDiffCheck
  ) external view returns (uint256 collateralPerShare);
}
