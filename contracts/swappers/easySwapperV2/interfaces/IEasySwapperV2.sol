// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {ISwapper} from "../../../interfaces/flatMoney/swapper/ISwapper.sol";
import {IWithdrawalVault} from "./IWithdrawalVault.sol";

interface IEasySwapperV2 {
  function swapper() external view returns (ISwapper swapper_);

  function withdrawalContracts(address _depositor) external view returns (address withdrawalVault_);

  function getTrackedAssets(
    address _depositor
  ) external view returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets_);

  function partialWithdraw(uint256 _portion, address _to) external;

  function isdHedgeVault(address _dHedgeVault) external view returns (bool isVault);
}
