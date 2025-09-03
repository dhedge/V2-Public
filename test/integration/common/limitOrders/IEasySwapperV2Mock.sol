// SPDX-License-Identifier: MIT
// solhint-disable
pragma solidity 0.8.28;

library EasySwapperV2Mock {
  struct WhitelistSetting {
    address toWhitelist;
    bool whitelisted;
  }
}

library ISwapper {
  struct AggregatorData {
    bytes32 routerKey;
    bytes swapData;
  }

  struct DestData {
    address destToken;
    uint256 minDestAmount;
  }

  struct SrcTokenSwapDetails {
    address token;
    uint256 amount;
    AggregatorData aggregatorData;
  }
}

library IWithdrawalVault {
  struct MultiInSingleOutData {
    ISwapper.SrcTokenSwapDetails[] srcData;
    ISwapper.DestData destData;
  }

  struct TrackedAsset {
    address token;
    uint256 balance;
  }
}

interface IEasySwapperV2Mock {
  function completeLimitOrderWithdrawal() external;
  function completeLimitOrderWithdrawalFor(address _user) external;
  function getTrackedAssetsFromLimitOrders(
    address _depositor
  ) external view returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets_);
  function initialize(
    address _vaultLogic,
    address _weth,
    address _wrappedNativeToken,
    address _swapper,
    uint256 _customCooldown
  ) external;
  function limitOrderContracts(address) external view returns (address);
  function setAuthorizedWithdrawers(EasySwapperV2Mock.WhitelistSetting[] memory _whitelistSettings) external;
  function setdHedgePoolFactory(address _dHedgePoolFactory) external;
}
