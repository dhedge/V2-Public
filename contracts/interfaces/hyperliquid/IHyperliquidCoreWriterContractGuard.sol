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

  /////////////////////////////////////////////
  //                Events                   //
  /////////////////////////////////////////////
  event PoolWhitelistUpdated(address indexed poolLogic, bool whitelisted);

  /////////////////////////////////////////////
  //                Functions                //
  /////////////////////////////////////////////
  function initialize(address admin, uint64 maxSlippage) external;
  function dHedgePoolsWhitelist(address poolLogic) external view returns (bool isWhitelisted);
  function hasPerformedSpotAction(address pool) external view returns (bool);
  function getApprovedDexIds() external view returns (uint256[] memory);
  function isEnabledDexId(uint256 dexId) external view returns (bool);

  // Admin functions
  function setMaxPermittedSlippage(uint64 maxSlippage) external;
  function setDhedgePoolsWhitelist(WhitelistSetting[] memory settings) external;
  function setApprovedAssets(ApprovedAssetSetting[] calldata settings) external;
  function setDexIdStatus(DexIdStatusSettings[] calldata settings) external;
}
