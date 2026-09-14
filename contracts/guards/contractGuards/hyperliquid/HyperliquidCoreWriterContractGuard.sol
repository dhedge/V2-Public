// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EnumerableMap} from "@openzeppelin/v5/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/v5/contracts/utils/structs/EnumerableSet.sol";
import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TxDataUtils, BytesLib} from "../../../utils/TxDataUtils.sol";
import {PrecompileHelper} from "../../../utils/hyperliquid/PrecompileHelper.sol";
import {HyperliquidConstants} from "../../../utils/hyperliquid/HyperliquidConstants.sol";
import {FixedPointMathLib} from "../../../utils/FixedPointMathLib.sol";

import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {ICoreWriter} from "../../../interfaces/hyperliquid/ICoreWriter.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IHyperliquidCoreWriterContractGuard} from "../../../interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";

/// @title HyperliquidCoreWriterContractGuard
/// @notice This contract parses the calls to the Hyperliquid CoreWriter contract
///         and only allows whitelisted methods to be called by the fund manager.
/// @dev Ideally, should be deployed as an upgradeable contract given new actions can be whitelisted and
///      we need the list of approved assets to be stored across updates.
/// @dev Only allows trading of whitelisted assets.
/// @dev [!WARNING] As of 25-March-2026, only HIP-3 perps with cross-margin as the default margin type
///      SHOULD be approved.
/// @dev Doesn't allow bridging native HYPE.
/// @dev [!WARNING] CoreWriter action 9 (register an API wallet / agent) is gated per-pool by the
///      Factory Owner via `apiWalletEnabled`. A registered agent can trade directly on HyperCore,
///      which breaks the pool's NAV accounting (positions in unsupported assets are invisible to
///      the valuation guards). It must therefore only be enabled for private vaults where accounting
///      accuracy is not required. Asset security is preserved: a Hyperliquid agent can only sign L1
///      trading actions and cannot withdraw or transfer assets out of the pool's account.
/// @author dHEDGE DAO
contract HyperliquidCoreWriterContractGuard is
  IGuard,
  IHyperliquidCoreWriterContractGuard,
  OwnableUpgradeable,
  TxDataUtils,
  PrecompileHelper
{
  using BytesLib for bytes;
  using FixedPointMathLib for uint256;
  using EnumerableMap for EnumerableMap.UintToUintMap;
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;

  /////////////////////////////////////////////
  //                  State                  //
  /////////////////////////////////////////////

  /// @notice Number of blocks after a spot order or spot asset bridging action during which no spot asset
  ///         can be removed from the pool's supported assets (action block B through B+SPOT_ACTION_LOCK_BLOCKS).
  /// @dev CoreWriter actions are "delayed onchain for a few seconds" (HL docs: interacting-with-hypercore).
  ///      At ~1s/block, a 10-block window comfortably outlasts that delay, so a late fill lands while
  ///      removal is still locked and is then caught by the zero-balance check in `removeAssetCheck`.
  uint256 public constant override SPOT_ACTION_LOCK_BLOCKS = 10;

  /// @dev DEPRECATED: the pool whitelist has been removed. This slot is kept only to preserve
  ///      the storage layout of the deployed proxy; do not reuse it.
  /// @custom:oz-renamed-from dHedgePoolsWhitelist
  // solhint-disable-next-line var-name-mixedcase
  mapping(address poolLogic => bool whitelisted) private __deprecated_dHedgePoolsWhitelist;

  /// @notice Approved perps by their asset IDs.
  /// @dev `asset` is the Asset ID on Hyperliquid <https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids>
  mapping(uint64 asset => bool) public approvedAssets;

  /// @notice Maximum permitted slippage per trade in WAD format (i.e, 1e18 = 100%).
  uint64 public maxPermittedSlippage;

  /// @notice Block in which a pool last performed a spot order or spot asset bridging action.
  /// @dev Spot-asset removal stays blocked for `SPOT_ACTION_LOCK_BLOCKS` further blocks (see
  ///      `hasPerformedSpotAction`) to outlast the CoreWriter settlement delay, after which the
  ///      zero-balance check covers any settled fill.
  mapping(address pool => uint256 blockNumber) private _spotActionBlockNumber;

  /// @notice Set of approved perp dex IDs for quick lookup.
  /// @dev Upon initialization, the core perp and spot dexes are enabled by default and cannot
  ///      be disabled or removed.
  /// @dev Stores the status (enabled/disabled). If the key doesn't exist, it is considered non-existent.
  EnumerableMap.UintToUintMap private dexIdStatus;

  /// @notice Set of approved asset IDs for enumeration.
  /// @dev Parallel to `approvedAssets` mapping.
  EnumerableSet.UintSet private _approvedAssetIds;

  /// @notice Pools opted in to Hyperliquid API wallet (agent) registration via CoreWriter action 9.
  /// @dev Set by the Factory Owner only. See warning in the contract NatSpec.
  EnumerableSet.AddressSet private _apiWalletEnabledPools;

  /// @notice Reference to the HyperliquidWithdrawalManager contract.
  /// @dev Not read by `txGuard`: the isPublic hooks for the withdrawal manager were removed while it is
  ///      not live. Kept, together with `setWithdrawalManager`, so a future re-integration is a pure
  ///      logic change.
  address public withdrawalManager;

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
    require(getMethod(data) == ICoreWriter.sendRawAction.selector, "unsupported method");
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(_CORE_WRITER), "CoreWriter not supported asset");

    bytes memory actionData = abi.decode(getParams(data), (bytes));
    uint24 actionId = _getActionId(actionData);

    // Limit order placement action.
    if (actionId == HyperliquidConstants.ACTION_LIMIT_ORDER) {
      bytes memory actionParams = getParams(actionData);
      LimitOrderParams memory params = abi.decode(actionParams, (LimitOrderParams));
      AssetType assetType = _getAssetType(params.asset);

      // Allow spot asset orders without checking for approval as that's managed by the pool's supported assets.
      if (assetType == AssetType.CORE_SPOT) {
        // A spot order swaps the pair's two tokens: a SELL gives the base and is paid the quote, a BUY
        // gives the quote and is paid the base. Both legs must therefore be assets the vault can value.
        // Asset ID = 10000 + spotIndex, and spotInfo.tokens is [baseTokenIndex, quoteTokenIndex].
        SpotInfo memory pairInfo = spotInfo(params.asset - 10_000);
        uint64 baseTokenIndex = pairInfo.tokens[0];

        // Quote leg: must be USDC. HyperCore lists one token against several quote assets (see
        // "Permissionless spot quote assets"), but the whole valuation stack is USDC-denominated —
        // HyperliquidPositionGuard values only the USDC Core spot balance, HyperliquidSpotPriceAggregator
        // reads a USDC-denominated `spotPx`, and a non-USDC pair's own `spotPx` is priced in that quote
        // token, so it cannot value the position either. Trading a supported base on any other pair pays
        // the vault in a token no asset guard reads, silently dropping `totalFundValue` by the whole
        // amount traded. Requiring USDC covers the quote leg for both directions: the Core USDC balance is
        // valued by HyperliquidPositionGuard unconditionally, which `txGuard` has already required above.
        require(pairInfo.tokens[1] == _USDC_TOKEN_INDEX, "spot pair not USDC quoted");

        // Base leg: either the system address has to be a supported asset or the EVM contract linked to
        // the spot asset.
        require(
          IHasSupportedAsset(poolManagerLogic).isSupportedAsset(getSystemAddress(baseTokenIndex)) ||
            IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokenInfo(baseTokenIndex).evmContract),
          "unsupported spot asset"
        );

        // Record the block when a spot order is placed for the pool to disallow removal of any spot asset
        // from the supported assets list until the order's settlement window has elapsed.
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

      // Resting spot orders (GTC/ALO) must be sells. A resting spot buy can fill after the post-action
      // removal lock expires and deliver base tokens as a NAV-invisible balance (the asset may have been
      // removed by then). A sell only ever delivers tracked USDC and requires holding the still-supported
      // base, so it can't create an untracked balance. We key on the order side, not reduceOnly, because
      // reduce-only is a perp position concept with no well-defined spot meaning. Only IOC settles within
      // the CoreWriter delay. Perps are unaffected.
      if (params.encodedTif == uint8(OrderType.GTC) || params.encodedTif == uint8(OrderType.ALO)) {
        // For spot, only allow resting sells (e.g. a resting take-profit close).
        require(!params.isBuy || assetType != AssetType.CORE_SPOT, "resting spot order must be sell");
      } else if (params.encodedTif != uint8(OrderType.IOC)) {
        // Reject INVALID and any out-of-enum time-in-force value so unhandled TIFs can't
        // bypass the price bound by falling through with no validation.
        revert("unsupported tif");
      }

      // Bound every accepted order (GTC/IOC/ALO) to the oracle price. The check is one-directional,
      // so it only restricts the aggressive/loss-making side: a resting take-profit and a passive
      // ALO maker pass unaffected, while a GTC priced through the book (a taker fill with no slippage
      // cap) is blocked just like an IOC.
      uint256 slippageAmount = price.mulWadDown(maxPermittedSlippage);

      if (params.isBuy) {
        uint256 maxAcceptablePrice = price + slippageAmount;
        require(maxAcceptablePrice >= params.limitPx, "Slippage exceeds limit");
      } else {
        uint256 maxAcceptablePrice = price - slippageAmount;
        require(maxAcceptablePrice <= params.limitPx, "Slippage exceeds limit");
      }

      return (uint16(ITransactionTypes.TransactionType.HyperliquidLimitOrder), false);
    } else if (actionId == HyperliquidConstants.ACTION_SPOT_SEND) {
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

      // Record the block when a spot asset bridging is placed for the pool to disallow
      // removal of any spot asset from the supported assets list until the bridging is completed.
      _spotActionBlockNumber[poolLogic] = block.number;

      return (uint16(ITransactionTypes.TransactionType.HyperliquidSpotSendAction), false);
    } else if (actionId == HyperliquidConstants.ACTION_USD_CLASS_TRANSFER) {
      // Transfers USD to/from the spot and perp accounts on HyperCore.
      return (uint16(ITransactionTypes.TransactionType.HyperliquidUSDClassTransferAction), false);
    } else if (actionId == HyperliquidConstants.ACTION_OID_CANCEL) {
      // Cancel order by its OID.
      return (uint16(ITransactionTypes.TransactionType.HyperliquidOidCancelOrder), false);
    } else if (actionId == HyperliquidConstants.ACTION_CLOID_CANCEL) {
      // Cancel order by its CLOID.
      return (uint16(ITransactionTypes.TransactionType.HyperliquidCloidCancelOrder), false);
    } else if (actionId == HyperliquidConstants.ACTION_SEND_ASSET) {
      // Sends asset from one dex to another within Hyperliquid L1.
      bytes memory actionParams = getParams(actionData);

      SendAssetParams memory params = abi.decode(actionParams, (SendAssetParams));
      bool isBeingBridgedToEVM = params.destinationAddress == getSystemAddress(params.token);

      // The destination address must be this contract (the pool) or the system address for the token.
      require(params.destinationAddress == poolLogic || isBeingBridgedToEVM, "invalid destination addr");
      // The sub-account must be the null address.
      require(params.subAccountAddress == address(0), "invalid sub-account addr");
      // Only allow sending to enabled dexes on HyperCore (consistent with the CoreDepositWallet guard).
      require(isEnabledDexId(params.destinationDexId), "invalid destination dex");

      // If the asset is being bridged to EVM, the destination-side EVM asset must be tracked by the pool.
      if (isBeingBridgedToEVM) {
        address evmContract = _getBridgedEvmContract(params.token);

        require(
          evmContract != address(0) && IHasSupportedAsset(poolManagerLogic).isSupportedAsset(evmContract),
          "unsupported asset"
        );
      } else {
        // For L1 self-transfers between dexes, only allow USDC. HyperliquidPositionGuard assumes
        // perp `accountValue` is USDC-denominated, so moving any other spot token onto a perp dex
        // would drop it from the spot balance accounting and misvalue it as perp collateral.
        require(params.token == _USDC_TOKEN_INDEX, "only USDC self-transfers");
      }

      // Record the block for the pool when a spot asset is being bridged or sent to another dex to
      // disallow removal of any spot asset from the supported assets list until the action is completed.
      _spotActionBlockNumber[poolLogic] = block.number;

      return (uint16(ITransactionTypes.TransactionType.HyperliquidSendAssetAction), false);
    } else if (actionId == HyperliquidConstants.ACTION_ADD_API_WALLET) {
      // Add API wallet (agent). Gated per-pool by the Factory Owner via `apiWalletEnabled`.
      // A Hyperliquid agent can only sign L1 trading actions; it cannot withdraw or transfer
      // assets out of the pool's account (withdraw/usdSend/spotSend/approveAgent are master-signed).
      // [!WARNING] Once an agent trades unsupported assets, the pool's NAV accounting drifts.
      //            Only enable for private vaults where accounting accuracy is not required.
      require(_apiWalletEnabledPools.contains(poolLogic), "api wallet not enabled");

      return (uint16(ITransactionTypes.TransactionType.HyperliquidAddApiWallet), false);
    }
  }

  /// @notice Returns whether a pool performed a spot order or spot asset bridging action recently
  ///         enough that spot assets must not yet be removed.
  /// @param pool PoolLogic address.
  /// @return hasPerformed `true` if a spot action was performed within the last `SPOT_ACTION_LOCK_BLOCKS`
  ///         blocks (action block B through B+SPOT_ACTION_LOCK_BLOCKS), `false` otherwise.
  function hasPerformedSpotAction(address pool) external view returns (bool) {
    return block.number <= _spotActionBlockNumber[pool] + SPOT_ACTION_LOCK_BLOCKS;
  }

  /// @notice Returns the list of approved dexes.
  /// @dev A disabled dex is still considered an approved dex, just not enabled for new orders.
  /// @dev The core perp and spot dexes are always included in the list of approved dexes.
  /// @dev Will not return NO_OP dex IDs as they are removed during the `setdexIdStatus` call.
  /// @dev Includes the core perp and spot dexes by default.
  function getApprovedDexIds() external view returns (uint256[] memory) {
    return dexIdStatus.keys();
  }

  /// @notice Returns the list of approved asset IDs.
  function getApprovedAssets() external view returns (uint256[] memory) {
    return _approvedAssetIds.values();
  }

  /// @notice Returns whether API wallet registration is enabled for a pool.
  function apiWalletEnabled(address poolLogic) external view returns (bool enabled) {
    return _apiWalletEnabledPools.contains(poolLogic);
  }

  /// @notice Returns the list of pools with API wallet registration enabled.
  function getApiWalletEnabledPools() external view returns (address[] memory) {
    return _apiWalletEnabledPools.values();
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

  /// @notice Sets the HyperliquidWithdrawalManager contract reference.
  /// @param _withdrawalManager The address of the WithdrawalManager (or address(0) to disable).
  function setWithdrawalManager(address _withdrawalManager) external onlyOwner {
    withdrawalManager = _withdrawalManager;

    emit WithdrawalManagerUpdated(_withdrawalManager);
  }

  /// @notice Enables or disables API wallet (agent) registration for a dHEDGE pool.
  /// @dev [!WARNING] Enabling this allows the pool's manager to register a Hyperliquid agent that
  ///      can trade directly on HyperCore, breaking the pool's NAV accounting. Only enable for
  ///      private vaults where accounting accuracy is not required.
  /// @param settings Array of ApiWalletSetting structs.
  function setApiWalletEnabled(ApiWalletSetting[] calldata settings) external onlyOwner {
    for (uint256 i; i < settings.length; ++i) {
      require(settings[i].poolLogic != address(0), "invalid pool logic");

      if (settings[i].enabled) {
        _apiWalletEnabledPools.add(settings[i].poolLogic);
      } else {
        _apiWalletEnabledPools.remove(settings[i].poolLogic);
      }

      emit ApiWalletEnabledUpdated(settings[i].poolLogic, settings[i].enabled);
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

      if (settings[i].approved) {
        _approvedAssetIds.add(uint256(assetId));
      } else {
        _approvedAssetIds.remove(uint256(assetId));
      }

      emit ApprovedAssetUpdated(assetId, settings[i].approved);
    }
  }

  /// @notice Sets the maximum permitted slippage per trade.
  /// @dev The slippage is represented in WAD format (i.e, 1e18 = 100%).
  /// @dev Will revert if `maxSlippage` is greater than 100% (1e18).
  /// @param maxSlippage Maximum permitted slippage per trade in WAD format.
  function setMaxPermittedSlippage(uint64 maxSlippage) external onlyOwner {
    require(maxSlippage <= 1e18, "max slippage must be <= 100%");

    maxPermittedSlippage = maxSlippage;

    emit MaxPermittedSlippageUpdated(maxSlippage);
  }

  /// @notice Adds or removes dex IDs from the approved set.
  /// @dev [!WARNING] ONLY REMOVE DEX IDS IF NO VAULT HOLDS POSITIONS ON THE DEX.
  /// @dev [!WARNING] ONLY APPROVE DEXES WITH USDC AS THE COLLATERAL TOKEN. HyperliquidPositionGuard
  ///      assumes each dex's `accountValue` is USDC-denominated, so a dex with non-USDC collateral
  ///      would be misvalued in the pool's NAV.
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

      emit DexIdStatusUpdated(settings[i].dexId, settings[i].status);
    }
  }
}
