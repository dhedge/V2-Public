// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EnumerableMap} from "@openzeppelin/v5/contracts/utils/structs/EnumerableMap.sol";
import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TxDataUtils, BytesLib} from "../../../utils/TxDataUtils.sol";
import {PrecompileHelper} from "../../../utils/hyperliquid/PrecompileHelper.sol";
import {FixedPointMathLib} from "../../../utils/FixedPointMathLib.sol";

import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {ICoreWriter} from "../../../interfaces/hyperliquid/ICoreWriter.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IHyperliquidCoreWriterContractGuard} from "../../../interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";
import {SafeSignerAccess} from "../../../utils/SafeSignerAccess.sol";

/// @title HyperliquidCoreWriterContractGuard
/// @notice This contract parses the calls to the Hyperliquid CoreWriter contract
///         and only allows whitelisted methods to be called by the fund manager.
/// @dev Ideally, should be deployed as an upgradeable contract given new actions can be whitelisted and
///      we need the list of approved assets and pools to be stored across updates.
/// @dev Only allows whitelisted pools to use Hyperliquid and with whitelisted assets.
/// @dev [!WARNING] As of 25-March-2026, only HIP-3 perps with cross-margin as the default margin type
///      SHOULD be approved.
/// @dev Doesn't allow bridging native HYPE.
/// @author dHEDGE DAO
contract HyperliquidCoreWriterContractGuard is
  IGuard,
  IHyperliquidCoreWriterContractGuard,
  OwnableUpgradeable,
  TxDataUtils,
  PrecompileHelper,
  SafeSignerAccess
{
  using BytesLib for bytes;
  using FixedPointMathLib for uint256;
  using EnumerableMap for EnumerableMap.UintToUintMap;

  /////////////////////////////////////////////
  //                  State                  //
  /////////////////////////////////////////////

  /// @notice Whitelist of dHEDGE pools allowed to use Hyperliquid.
  mapping(address poolLogic => bool whitelisted) public dHedgePoolsWhitelist;

  /// @notice Approved perps by their asset IDs.
  /// @dev `asset` is the Asset ID on Hyperliquid <https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids>
  mapping(uint64 asset => bool) public approvedAssets;

  /// @notice Maximum permitted slippage per trade in WAD format (i.e, 1e18 = 100%).
  uint64 public maxPermittedSlippage;

  /// @notice Mapping to track if a pool has placed a spot order or spot asset bridging action for any asset.
  /// @dev Should be set when a spot order is placed or a spot asset bridging action is performed.
  mapping(address pool => uint256 blockNumber) private _spotActionBlockNumber;

  /// @notice Set of approved perp dex IDs for quick lookup.
  /// @dev Upon initialization, the core perp and spot dexes are enabled by default and cannot
  ///      be disabled or removed.
  /// @dev Stores the status (enabled/disabled). If the key doesn't exist, it is considered non-existent.
  EnumerableMap.UintToUintMap private dexIdStatus;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /////////////////////////////////////////////
  //                Functions                //
  /////////////////////////////////////////////

  function initialize(address admin, uint64 maxSlippage) external initializer {
    __Ownable_init(admin);

    require(maxSlippage <= 1e18, "max slippage must be <= 100%");
    maxPermittedSlippage = maxSlippage;

    // Enable the core dexes by default.
    dexIdStatus.set(_DEX_ID_CORE_PERP, uint256(DexStatus.ENABLED));
    dexIdStatus.set(_DEX_ID_CORE_SPOT, uint256(DexStatus.ENABLED));
  }

  /// @notice Guard function for Hyperliquid CoreWriter contract.
  /// @dev Refer <https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore>
  ///      for more details on transaction decoding and action ids.
  /// @param poolManagerLogic PoolManagerLogic address.
  /// @param data Transaction call data attempt by manager.
  /// @return txType transaction type described in ITransactionTypes.
  /// @return isPublic Whether the transaction is public.
  function txGuard(
    address poolManagerLogic,
    address,
    bytes calldata data
  ) external override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "caller must be pool logic");
    require(dHedgePoolsWhitelist[poolLogic], "pool not whitelisted");
    require(getMethod(data) == ICoreWriter.sendRawAction.selector, "unsupported method");
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(_CORE_WRITER), "CoreWriter not supported asset");

    bytes memory actionData = abi.decode(getParams(data), (bytes));
    uint24 actionId = _getActionId(actionData);

    // Limit order placement action.
    if (actionId == 1) {
      bytes memory actionParams = getParams(actionData);
      LimitOrderParams memory params = abi.decode(actionParams, (LimitOrderParams));
      AssetType assetType = _getAssetType(params.asset);

      // Allow spot asset orders without checking for approval as that's managed by the pool's supported assets.
      if (assetType == AssetType.CORE_SPOT) {
        // Get the base token index from the spot pair info
        // Asset ID = 10000 + spotIndex, and spotInfo.tokens[0] is the base token index
        uint64 baseTokenIndex = spotInfo(params.asset - 10_000).tokens[0];

        // Either the system address has to be a supported asset or the EVM contract linked to the spot asset.
        require(
          IHasSupportedAsset(poolManagerLogic).isSupportedAsset(getSystemAddress(baseTokenIndex)) ||
            IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokenInfo(baseTokenIndex).evmContract),
          "unsupported spot asset"
        );

        // Record the block number when a spot order is placed for the pool to disallow removal of any spot asset
        // from the supported assets list until the order is executed or cancelled.
        _spotActionBlockNumber[poolLogic] = block.number;
      } else {
        // Allow reduce-only orders even for disabled assets to enable position closure.
        // For non-reduce-only orders, the asset must be approved.
        if (!params.reduceOnly) {
          require(approvedAssets[params.asset], "unsupported asset");

          if (assetType == AssetType.HIP3_PERP) {
            uint256 dexId = _getHIP3PerpDexId(params.asset);

            require(isEnabledDexId(dexId), "unsupported dex id");
          }
        }
      }

      uint256 price = _getPrice(params.asset, assetType);

      // GTC orders are allowed in the following cases:
      // 1. For spot assets, only if they are reduce-only (for stop-loss and take-profit orders).
      // 2. For perps even if they are not reduce-only.
      if (params.encodedTif == uint8(OrderType.GTC)) {
        // For spot, only allow stop-loss and take-profit orders.
        require(params.reduceOnly || assetType != AssetType.CORE_SPOT, "GTC reduce-only for spot");

        // No price restriction for GTC orders as they can be either:
        // - Stop-loss: buy above market (close short) or sell below market (close long)
        // - Take-profit: buy below market (close short) or sell above market (close long)
      } else if (params.encodedTif == uint8(OrderType.IOC)) {
        // Calculate maximum acceptable price including slippage using global slippage setting
        uint256 slippageAmount = price.mulWadDown(maxPermittedSlippage);

        // If the order is a buy, the max acceptable price is increased by slippage amount.
        if (params.isBuy) {
          uint256 maxAcceptablePrice = price + slippageAmount;
          require(maxAcceptablePrice >= params.limitPx, "Slippage exceeds limit");
        } else {
          // If the order is a sell, the max acceptable price is decreased by slippage amount.
          uint256 maxAcceptablePrice = price - slippageAmount;
          require(maxAcceptablePrice <= params.limitPx, "Slippage exceeds limit");
        }
      }

      return (uint16(ITransactionTypes.TransactionType.HyperliquidLimitOrder), false);
    } else if (actionId == 6) {
      // Spot send action.
      // Remaining bytes represent the action parameters.
      bytes memory actionParams = getParams(actionData);

      // Spot send action which can be used for bridging spot assets from Hyperliquid Core provided
      // the spot asset is linked to an EVM contract on HyperEVM.
      // In such a case, the evm contract should be present and whitelisted as a supported asset
      // in the pool.
      SpotSendParams memory params = abi.decode(actionParams, (SpotSendParams));
      address evmContract = _getBridgedEvmContract(params.token);

      require(
        evmContract != address(0) && IHasSupportedAsset(poolManagerLogic).isSupportedAsset(evmContract),
        "unsupported asset"
      );

      // The destination must be the system address (to bridge tokens from core).
      require(params.destinationAddress == getSystemAddress(params.token), "invalid destination");

      // Record the block number when a spot asset bridging is placed for the pool to disallow
      // removal of any spot asset from the supported assets list until the bridging is completed.
      _spotActionBlockNumber[poolLogic] = block.number;

      return (uint16(ITransactionTypes.TransactionType.HyperliquidSpotSendAction), false);
    } else if (actionId == 7) {
      // Transfers USD to/fro the spot and perp accounts on HyperCore.
      return (uint16(ITransactionTypes.TransactionType.HyperliquidUSDClassTransferAction), false);
    } else if (actionId == 10) {
      // Cancel order by its OID.
      return (uint16(ITransactionTypes.TransactionType.HyperliquidOidCancelOrder), false);
    } else if (actionId == 11) {
      // Cancel order by its CLOID.
      return (uint16(ITransactionTypes.TransactionType.HyperliquidCloidCancelOrder), false);
    } else if (actionId == 13) {
      // Sends asset from one dex to another within Hyperliquid L1.
      bytes memory actionParams = getParams(actionData);

      SendAssetParams memory params = abi.decode(actionParams, (SendAssetParams));
      bool isBeingBridgedToEVM = params.destinationAddress == getSystemAddress(params.token);

      // The destination address must be this contract (the pool) or the system address for the token.
      require(params.destinationAddress == poolLogic || isBeingBridgedToEVM, "invalid destination addr");
      // The sub-account must be the null address.
      require(params.subAccountAddress == address(0), "invalid sub-account addr");
      // Only allow sending to approved dexes on HyperCore.
      require(dexIdStatus.contains(params.destinationDexId), "invalid destination dex");

      // If the asset is being bridged to EVM, the destination-side EVM asset must be tracked by the pool.
      if (isBeingBridgedToEVM) {
        address evmContract = _getBridgedEvmContract(params.token);

        require(
          evmContract != address(0) && IHasSupportedAsset(poolManagerLogic).isSupportedAsset(evmContract),
          "unsupported asset"
        );
      }

      // Record the block number for the pool when a spot asset is being bridged or sent to another dex to
      // disallow removal of any spot asset from the supported assets list until the action is completed.
      _spotActionBlockNumber[poolLogic] = block.number;

      return (uint16(ITransactionTypes.TransactionType.HyperliquidSendAssetAction), false);
    }
  }

  /// @notice Returns whether a spot order or a spot asset bridging action has been performed for a given pool in the same block.
  /// @param pool PoolLogic address.
  /// @return hasPerformed `true` if a spot order or a spot asset bridging action has been performed for the given pool in the same block,
  ///        `false` otherwise.
  function hasPerformedSpotAction(address pool) external view returns (bool) {
    return _spotActionBlockNumber[pool] == block.number;
  }

  /// @notice Returns the list of approved dexes.
  /// @dev A disabled dex is still considered an approved dex, just not enabled for new orders.
  /// @dev The core perp and spot dexes are always included in the list of approved dexes.
  /// @dev Will not return NO_OP dex IDs as they are removed during the `setdexIdStatus` call.
  /// @dev Includes the core perp and spot dexes by default.
  function getApprovedDexIds() external view returns (uint256[] memory) {
    return dexIdStatus.keys();
  }

  /// @notice Checks if a dex ID is enabled.
  /// @param dexId The dex ID to check.
  /// @return isEnabled True if the dex ID is enabled, false otherwise.
  function isEnabledDexId(uint256 dexId) public view returns (bool) {
    (, uint256 status) = dexIdStatus.tryGet(dexId);

    return status == uint256(DexStatus.ENABLED);
  }

  function _getActionId(bytes memory actionData) private pure returns (uint24) {
    // First byte represents the version.
    require(uint8(actionData[0]) == 1, "unsupported version");

    // The next 3 bytes represent the action id.
    return BytesLib.toUint24(actionData, 1);
  }

  function _getAssetType(uint64 assetId) private pure returns (AssetType) {
    if (assetId < 10_000) {
      return AssetType.CORE_PERP; // Validator-operated perpetual
    } else if (assetId < 100_000) {
      return AssetType.CORE_SPOT; // Spot asset
    } else {
      // It may be a HIP-3 asset ID.
      // Note that this is a simplified assumption based on the current asset ID schema on Hyperliquid.
      return AssetType.HIP3_PERP;
    }
  }

  /// @notice Gets the price in the same format as limitPx.
  /// @dev Returns price in 8 decimals.
  /// @param assetId The asset ID.
  /// @param assetType The asset type.
  /// @return price The price for validation.
  function _getPrice(uint64 assetId, AssetType assetType) private view returns (uint256 price) {
    if (assetType == AssetType.CORE_SPOT) {
      // CORE_SPOT: assetId = 10000 + spotIndex
      // Return normalized price for spot assets to get it in the same format as limitPx
      // which is expected to be in 8 decimals.
      uint64 spotIndex = assetId - 10_000;
      return normalizedSpotPx(spotIndex);
    } else {
      // For core perps, asset ID is the perp index and for HIP-3 perps, the perp index
      // is derived from the asset ID as (assetId - 100000).
      uint32 perpIndex = (assetType == AssetType.CORE_PERP) ? uint32(assetId) : uint32(assetId - 100_000);

      return normalizedOraclePx(perpIndex) * 1e2;
    }
  }

  function _getHIP3PerpDexId(uint64 assetId) private pure returns (uint256 dexId) {
    require(assetId >= 100_000, "not a HIP-3 asset");

    return (assetId - 100_000) / 10_000;
  }

  function _getBridgedEvmContract(uint64 token) private view returns (address evmContract) {
    if (token == _USDC_TOKEN_INDEX) {
      return _USDC_ADDRESS;
    }

    return tokenInfo(token).evmContract;
  }

  /////////////////////////////////////////////
  //                  Admin                  //
  /////////////////////////////////////////////

  /// @notice Adds or removes a dHEDGE pool from the whitelist.
  /// @param settings Array of WhitelistSetting structs.
  function setDhedgePoolsWhitelist(WhitelistSetting[] calldata settings) external onlyOwnerOrSafeSigner(owner()) {
    for (uint256 i; i < settings.length; ++i) {
      require(settings[i].poolLogic != address(0), "invalid pool logic");

      dHedgePoolsWhitelist[settings[i].poolLogic] = settings[i].whitelisted;

      emit PoolWhitelistUpdated(settings[i].poolLogic, settings[i].whitelisted);
    }
  }

  /// @notice Sets an asset ID as approved or not.
  /// @dev Won't revert if the asset is already approved/disapproved.
  /// @dev Will revert if a spot asset is being approved.
  /// @param settings Array of ApprovedAssetSetting structs.
  function setApprovedAssets(ApprovedAssetSetting[] calldata settings) external onlyOwner {
    for (uint256 i; i < settings.length; ++i) {
      uint64 assetId = settings[i].assetId;
      AssetType assetType = _getAssetType(assetId);

      require(assetType != AssetType.CORE_SPOT, "only perp assets can be approved");

      if (assetType == AssetType.HIP3_PERP) {
        uint256 dexId = _getHIP3PerpDexId(assetId);

        require(dexIdStatus.contains(dexId), "unapproved dex id");

        // Make sure that the HIP-3 perp is not using isolated margin.
        require(!perpAssetInfo(uint32(assetId - 100_000)).onlyIsolated, "only isolated margin");
      }

      approvedAssets[assetId] = settings[i].approved;
    }
  }

  /// @notice Sets the maximum permitted slippage per trade.
  /// @dev The slippage is represented in WAD format (i.e, 1e18 = 100%).
  /// @dev Will revert if `maxSlippage` is greater than 100% (1e18).
  /// @param maxSlippage Maximum permitted slippage per trade in WAD format.
  function setMaxPermittedSlippage(uint64 maxSlippage) external onlyOwner {
    require(maxSlippage <= 1e18, "max slippage must be <= 100%");

    maxPermittedSlippage = maxSlippage;
  }

  /// @notice Adds or removes dex IDs from the approved set.
  /// @dev [!WARNING] ONLY REMOVE DEX IDS IF NO VAULT HOLDS POSITIONS ON THE DEX.
  /// @dev Core dex IDs (core perp and core spot) cannot be removed.
  /// @param settings Array of DexIdStatusSettings structs.
  function setDexIdStatus(DexIdStatusSettings[] calldata settings) external onlyOwner {
    for (uint256 i; i < settings.length; ++i) {
      require(
        settings[i].dexId != _DEX_ID_CORE_PERP && settings[i].dexId != _DEX_ID_CORE_SPOT,
        "cannot modify core dex IDs"
      );

      // Remove the dex ID from the mapping in case of NO_OP.
      if (settings[i].status == DexStatus.NO_OP) {
        dexIdStatus.remove(settings[i].dexId);
      } else {
        // Add or update the dex ID status in the mapping.
        dexIdStatus.set(settings[i].dexId, uint256(settings[i].status));
      }
    }
  }
}
