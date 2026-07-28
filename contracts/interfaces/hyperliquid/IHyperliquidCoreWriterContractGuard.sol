// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

interface IHyperliquidCoreWriterContractGuard {
  /////////////////////////////////////////////
  //             Enums & Structs             //
  /////////////////////////////////////////////

  enum AssetType {
    CORE_PERP,
    CORE_SPOT,
    HIP3_PERP
  }

  enum DexStatus {
    NO_OP,
    ENABLED,
    DISABLED
  }

  struct WhitelistSetting {
    address poolLogic;
    bool whitelisted;
  }

  struct ApprovedAssetSetting {
    uint64 assetId;
    bool approved;
  }

  struct DexIdStatusSettings {
    uint256 dexId;
    DexStatus status;
  }

  struct ApiWalletSetting {
    address poolLogic;
    bool enabled;
  }

  /////////////////////////////////////////////
  //                Events                   //
  /////////////////////////////////////////////
  event PoolWhitelistUpdated(address indexed poolLogic, bool whitelisted);
  event ApprovedAssetUpdated(uint64 indexed assetId, bool approved);
  event DexIdStatusUpdated(uint256 indexed dexId, DexStatus status);
  event MaxPermittedSlippageUpdated(uint64 maxPermittedSlippage);
  event ApiWalletEnabledUpdated(address indexed poolLogic, bool enabled);
  event WithdrawalManagerUpdated(address indexed withdrawalManager);

  /////////////////////////////////////////////
  //                Functions                //
  /////////////////////////////////////////////
  function initialize(address admin, uint64 maxSlippage) external;
  function dHedgePoolsWhitelist(address poolLogic) external view returns (bool isWhitelisted);
  function apiWalletEnabled(address poolLogic) external view returns (bool enabled);
  function getApiWalletEnabledPools() external view returns (address[] memory);
  function hasPerformedSpotAction(address pool) external view returns (bool);
  function getApprovedAssets() external view returns (uint256[] memory);
  function getApprovedDexIds() external view returns (uint256[] memory);
  function isEnabledDexId(uint256 dexId) external view returns (bool);
  function withdrawalManager() external view returns (address);

  // Admin functions
  function setMaxPermittedSlippage(uint64 maxSlippage) external;
  function setDhedgePoolsWhitelist(WhitelistSetting[] memory settings) external;
  function setApprovedAssets(ApprovedAssetSetting[] calldata settings) external;
  function setDexIdStatus(DexIdStatusSettings[] calldata settings) external;
  function setApiWalletEnabled(ApiWalletSetting[] calldata settings) external;
  function setWithdrawalManager(address _withdrawalManager) external;
}
