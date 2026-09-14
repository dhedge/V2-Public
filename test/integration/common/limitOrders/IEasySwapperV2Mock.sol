// SPDX-License-Identifier: MIT
// solhint-disable
pragma solidity 0.8.28;

import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";

library EasySwapperV2Mock {
  struct WhitelistSetting {
    address toWhitelist;
    bool whitelisted;
  }
}

/// @dev EasySwapperV2 entry points not present in IEasySwapperV2 (0.7.6 contract, deployed via deployCode).
interface IEasySwapperV2Mock {
  function completeLimitOrderWithdrawal() external;
  function completeLimitOrderWithdrawalFor(address _user) external;
  function completeWithdrawal() external;
  function getTrackedAssetsFromLimitOrders(
    address _depositor
  ) external view returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets_);
  function initialize(
    address _vaultLogic,
    address _unused,
    address _wrappedNativeToken,
    address _swapper,
    uint256 _customCooldown
  ) external;
  function initWithdrawal(
    address _dHedgeVault,
    uint256 _amountIn,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) external returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets_, address vault_);
  function limitOrderContracts(address) external view returns (address);
  function setAuthorizedWithdrawers(EasySwapperV2Mock.WhitelistSetting[] memory _whitelistSettings) external;
  function setdHedgePoolFactory(address _dHedgePoolFactory) external;
}
