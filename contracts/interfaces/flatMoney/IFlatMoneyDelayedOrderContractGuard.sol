// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IFlatMoneyDelayedOrderContractGuard {
  struct PoolSetting {
    address poolLogic;
    address withdrawalAsset;
  }

  function dHedgePoolsWhitelist(address _poolLogic) external view returns (address poolLogic, address withdrawalAsset);

  function getOwnedTokenIds(address _poolLogic) external view returns (uint256[] memory tokenIds);
}
