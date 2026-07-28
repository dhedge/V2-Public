// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/v5/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/v5/contracts/utils/structs/EnumerableSet.sol";

import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IDytmOffice} from "../../../interfaces/dytm/IDytmOffice.sol";
import {IDytmAccountSplitterAndMerger} from "../../../interfaces/dytm/IDytmAccountSplitterAndMerger.sol";
import {IDytmOfficeContractGuard} from "../../../interfaces/dytm/IDytmOfficeContractGuard.sol";
import {DytmHelperLib} from "../../../utils/dytm/DytmHelperLib.sol";
import {DytmParamStructs} from "../../../utils/dytm/DytmParamStructs.sol";
import {DytmConfigStructs} from "../../../utils/dytm/DytmConfigStructs.sol";
import {DytmDelegationCallCheckGuard} from "./DytmDelegationCallCheckGuard.sol";
import {IDytmPeriphery} from "../../../interfaces/dytm/IDytmPeriphery.sol";
import {NftTrackerConsumerGuardV2} from "../shared/NftTrackerConsumerGuardV2.sol";
import {SafeSignerAccess} from "../../../utils/SafeSignerAccess.sol";

/// @title DYTM Office Contract Guard
/// @notice Guards DYTM Office interactions, validates operations and tracks active markets
contract DytmOfficeContractGuard is
  IDytmOfficeContractGuard,
  ITxTrackingGuard,
  NftTrackerConsumerGuardV2,
  DytmDelegationCallCheckGuard,
  Ownable,
  SafeSignerAccess
{
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => bool) public override poolsWhitelist;
  mapping(uint88 => bool) public override dytmMarketsWhitelist;
  address public immutable override poolFactory;
  address public immutable override dytmOffice;
  address public immutable override dytmPeriphery;
  address public immutable accountSplitterAndMerger;
  bool public override isTxTrackingGuard = true;
  uint256 public constant HEALTH_FACTOR_LOWER_BOUNDARY = 1.01e18;
  /// @dev Max relative drop of the pool's main-account HF allowed per merge, in bps.
  ///      Backstops the dust cap on split remnants by bounding leverage folded into `main`.
  uint256 public constant MERGE_MAX_HF_DEGRADATION_BPS = 500; // 5%
  uint256 private constant _BPS_DENOMINATOR = 10_000;

  /// @dev Pre-merge HF of the pool's main account on the merge market.
  ///      - set in `txGuard`, consumed and cleared in `afterTxGuard`.
  ///      - a single slot suffices: PoolLogic runs txGuard → call → afterTxGuard per
  ///        `execTransaction`, and DYTM's delegation context blocks nested merges.
  uint256 private transient _preMergeMainHealthFactor;

  /// @notice Set of whitelisted pools for enumeration.
  /// @dev Parallel to `poolsWhitelist` mapping; kept in sync by the constructor and `setPoolsWhitelist`.
  EnumerableSet.AddressSet private _whitelistedPoolsSet;

  constructor(
    address[] memory _whitelistedPools,
    uint88[] memory _whitelistedMarkets,
    DytmConfigStructs.DytmConfig memory _dytmConfig
  )
    NftTrackerConsumerGuardV2(_dytmConfig.nftTracker, keccak256("DYTM_MARKET_ID_TYPE"), _dytmConfig.maxDytmMarkets)
    Ownable(_dytmConfig.admin)
  {
    require(_dytmConfig.accountSplitterAndMerger != address(0), "invalid splitter");
    poolFactory = _dytmConfig.dhedgePoolFactory;
    dytmPeriphery = _dytmConfig.dytmPeriphery;
    dytmOffice = _dytmConfig.dytmOffice;
    accountSplitterAndMerger = _dytmConfig.accountSplitterAndMerger;
    for (uint256 i; i < _whitelistedPools.length; ++i) {
      address pool = _whitelistedPools[i];
      require(pool != address(0), "invalid pool logic");
      poolsWhitelist[pool] = true;
      _whitelistedPoolsSet.add(pool);
    }
    for (uint256 j; j < _whitelistedMarkets.length; ++j) {
      dytmMarketsWhitelist[_whitelistedMarkets[j]] = true;
    }
  }

  /// @notice Adds or removes dHEDGE pools from the whitelist.
  /// @param settings Array of WhitelistSetting structs.
  function setPoolsWhitelist(WhitelistSetting[] calldata settings) external onlyOwnerOrSafeSigner(owner()) {
    for (uint256 i; i < settings.length; ++i) {
      require(settings[i].poolLogic != address(0), "invalid pool logic");

      poolsWhitelist[settings[i].poolLogic] = settings[i].whitelisted;

      if (settings[i].whitelisted) {
        _whitelistedPoolsSet.add(settings[i].poolLogic);
      } else {
        _whitelistedPoolsSet.remove(settings[i].poolLogic);
      }

      emit PoolWhitelistUpdated(settings[i].poolLogic, settings[i].whitelisted);
    }
  }

  /// @notice Returns the list of whitelisted pools.
  function getWhitelistedPools() external view override returns (address[] memory) {
    return _whitelistedPoolsSet.values();
  }

  /// @notice Validates supply/withdraw/borrow/repay/delegationCall transactions before execution
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = _accessControl(poolManagerLogic);
    bytes4 method = getMethod(data);
    require(poolsWhitelist[poolLogic], "pool not whitelisted");
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(to), "unsupported asset");

    if (method == IDytmOffice.supply.selector) {
      (uint256 accountId, uint256 tokenId) = _decodeSupplyParams(getParams(data));
      _checkUserAccount(accountId, poolLogic);
      _checkDytmMarket(DytmHelperLib.getReserveKey(tokenId));
      _checkAssetsSupported(poolManagerLogic, DytmHelperLib.getAssetFromTokenId(tokenId)); // supply asset

      txType = uint16(TransactionType.DytmSupply);
    } else if (method == IDytmOffice.withdraw.selector) {
      (uint256 accountId, uint256 tokenId, address receiver) = _decodeWithdrawParams(getParams(data));
      _checkUserAccount(accountId, poolLogic);
      _checkDytmMarket(DytmHelperLib.getReserveKey(tokenId));
      _checkAssetsSupported(poolManagerLogic, DytmHelperLib.getAssetFromTokenId(tokenId)); // withdraw asset
      require(receiver == poolLogic, "invalid receiver");

      txType = uint16(TransactionType.DytmWithdraw);
    } else if (method == IDytmOffice.borrow.selector) {
      (uint256 accountId, uint248 reserveKey, address receiver) = _decodeBorrowParams(getParams(data));
      _checkUserAccount(accountId, poolLogic);
      _checkDytmMarket(reserveKey);
      address borrowAsset = DytmHelperLib.getAsset(reserveKey);
      _checkAssetsSupported(poolManagerLogic, borrowAsset); // borrow asset
      if (!_checkIsOngoingDelegationCall(poolLogic)) {
        _checkNoMixedDebtAssets(poolLogic, accountId, borrowAsset);
      }
      require(receiver == poolLogic, "invalid receiver");
      txType = uint16(TransactionType.DytmBorrow);
    } else if (method == IDytmOffice.repay.selector) {
      (uint256 accountId, uint248 reserveKey) = _decodeRepayParams(getParams(data));
      _checkUserAccount(accountId, poolLogic);
      _checkDytmMarket(reserveKey);
      txType = uint16(TransactionType.DytmRepay);
    } else if (method == IDytmOffice.switchCollateral.selector) {
      // switchCollateral moves collateral between LEND and ESCROW reserve types within the same market.
      // No receiver check needed — assets stay within DYTM (no external transfer).
      (uint256 accountId, uint256 tokenId) = _decodeSwitchCollateralParams(getParams(data));
      _checkUserAccount(accountId, poolLogic);
      _checkDytmMarket(DytmHelperLib.getReserveKey(tokenId));
      _checkAssetsSupported(poolManagerLogic, DytmHelperLib.getAssetFromTokenId(tokenId));

      txType = uint16(TransactionType.DytmSwitchCollateral);
    } else if (method == IDytmOffice.delegationCall.selector) {
      DytmParamStructs.DelegationCallParams memory params = abi.decode(
        getParams(data),
        (DytmParamStructs.DelegationCallParams)
      );
      address delegatee = address(params.delegatee);
      if (delegatee == poolLogic) {
        _checkAndSetDytmDelegateCall(poolLogic);
        txType = uint16(TransactionType.DytmDelegationCall);
      } else if (delegatee == accountSplitterAndMerger) {
        // Manager-initiated merge of pool-owned isolated DYTM accounts.
        // - source must be isolated: main can never be a source, so value can't leave
        //   `getBalance`'s view (it only sums the main account).
        // - recipient must be pool-owned: DYTM only enforces source ownership (and same owner
        //   on both sides for debt) but lets collateral go to ANY recipient — this blocks
        //   routing dust collateral out of the pool.
        IDytmAccountSplitterAndMerger.CallbackData memory cbData = abi.decode(
          params.callbackData,
          (IDytmAccountSplitterAndMerger.CallbackData)
        );
        require(cbData.operation == IDytmAccountSplitterAndMerger.Operation.MERGE_ACCOUNTS, "merge op only");
        IDytmAccountSplitterAndMerger.MergeAccountsParams memory mergeParams = abi.decode(
          cbData.data,
          (IDytmAccountSplitterAndMerger.MergeAccountsParams)
        );
        require(
          DytmHelperLib.getAccountType(mergeParams.sourceAccount) == DytmHelperLib.AccountType.ISOLATED_ACCOUNT,
          "merge source must be isolated"
        );
        require(dytmMarketsWhitelist[mergeParams.market], "invalid market");
        require(
          IDytmOffice(dytmOffice).ownerOf(mergeParams.recipientAccount) == poolLogic,
          "merge recipient not pool-owned"
        );
        // Merging into the pool's main account: snapshot its pre-merge HF so `afterTxGuard`
        // can bound the degradation. Isolated recipients don't affect main's accounted leverage.
        uint256 mainAccount = DytmHelperLib.toUserAccount(poolLogic);
        if (mergeParams.recipientAccount == mainAccount) {
          _preMergeMainHealthFactor = IDytmPeriphery(dytmPeriphery)
            .getAccountPosition(mainAccount, mergeParams.market)
            .healthFactor;
        }
        txType = uint16(TransactionType.DytmMerge);
      } else {
        revert("invalid delegatee");
      }
    }
    return (txType, false);
  }

  /// @notice Post-tx validation: health factor checks, active market tracking, and inactive market cleanup
  function afterTxGuard(address poolManagerLogic, address to, bytes calldata data) public override {
    address poolLogic = _accessControl(poolManagerLogic);
    bytes4 method = getMethod(data);
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(to), "unsupported asset");

    if (method == IDytmOffice.supply.selector) {
      (, uint256 tokenId) = _decodeSupplyParams(getParams(data));
      _checkAssetsSupported(poolManagerLogic, DytmHelperLib.getAssetFromTokenId(tokenId)); // supply asset
      uint88 supplyMarketId = DytmHelperLib.getMarketId(DytmHelperLib.getReserveKey(tokenId));
      if (!_checkIsOngoingDelegationCall(poolLogic)) {
        _cleanupInactiveMarkets(poolLogic, to);
        _updateActiveMarketIds(poolLogic, to, supplyMarketId);
      } else {
        _addSupplyMarketForActiveMarketsTransientStorage(poolLogic, supplyMarketId);
      }
    } else if (method == IDytmOffice.withdraw.selector) {
      (uint256 accountId, uint256 tokenId, ) = _decodeWithdrawParams(getParams(data));
      _checkAssetsSupported(poolManagerLogic, DytmHelperLib.getAssetFromTokenId(tokenId)); // withdraw asset
      uint88 rawMarketId = DytmHelperLib.getMarketId(DytmHelperLib.getReserveKey(tokenId));
      if (!_checkIsOngoingDelegationCall(poolLogic)) {
        _checkHealthFactorLowerBoundary(accountId, rawMarketId);
      } else {
        _addMarketToCheckHFTransientStorage(poolLogic, rawMarketId);
      }
    } else if (method == IDytmOffice.borrow.selector) {
      (uint256 accountId, uint248 reserveKey, ) = _decodeBorrowParams(getParams(data));
      _checkAssetsSupported(poolManagerLogic, DytmHelperLib.getAsset(reserveKey)); // borrow asset
      uint88 rawMarketId = DytmHelperLib.getMarketId(reserveKey);
      if (!_checkIsOngoingDelegationCall(poolLogic)) {
        _checkHealthFactorLowerBoundary(accountId, rawMarketId);
      } else {
        _addMarketToCheckHFTransientStorage(poolLogic, rawMarketId);
      }
    } else if (method == IDytmOffice.switchCollateral.selector) {
      // Switching between LEND/ESCROW can change health factor if they have different weights.
      // No market tracking updates needed: market is already active (collateral must exist to switch),
      // and no cleanup needed (collateral stays in the market, just changes reserve type).
      (uint256 accountId, uint256 tokenId) = _decodeSwitchCollateralParams(getParams(data));
      _checkAssetsSupported(poolManagerLogic, DytmHelperLib.getAssetFromTokenId(tokenId));
      uint88 rawMarketId = DytmHelperLib.getMarketId(DytmHelperLib.getReserveKey(tokenId));
      if (!_checkIsOngoingDelegationCall(poolLogic)) {
        _checkHealthFactorLowerBoundary(accountId, rawMarketId);
      } else {
        _addMarketToCheckHFTransientStorage(poolLogic, rawMarketId);
      }
    } else if (method == IDytmOffice.delegationCall.selector) {
      DytmParamStructs.DelegationCallParams memory params = abi.decode(
        getParams(data),
        (DytmParamStructs.DelegationCallParams)
      );
      if (address(params.delegatee) == accountSplitterAndMerger) {
        IDytmAccountSplitterAndMerger.MergeAccountsParams memory mergeParams = abi.decode(
          abi.decode(params.callbackData, (IDytmAccountSplitterAndMerger.CallbackData)).data,
          (IDytmAccountSplitterAndMerger.MergeAccountsParams)
        );
        // Track and check only merges into the pool's main user account:
        // - main is the only account `getBalance` sums.
        // - pool-owned isolated recipients stay unaccounted by design; the manager can
        //   later merge them into main.
        uint256 mainAccount = DytmHelperLib.toUserAccount(poolLogic);
        if (mergeParams.recipientAccount == mainAccount) {
          _updateActiveMarketIds(poolLogic, to, mergeParams.market);
          _checkPositionAssetsSupported(poolManagerLogic, mainAccount, mergeParams.market);
          _checkNoMixedDebtAssets(poolLogic);
          _checkMergeHFDegradation(poolLogic, mergeParams.market);
        }
      } else {
        (uint88[] memory marketsForHFCheck, uint88[] memory marketsForActiveStorage) = _clearOngoingDelegationCall(
          poolLogic
        );
        for (uint256 i; i < marketsForHFCheck.length; ++i) {
          _checkHealthFactorLowerBoundary(DytmHelperLib.toUserAccount(poolLogic), marketsForHFCheck[i]);
        }
        _cleanupInactiveMarkets(poolLogic, to);
        for (uint256 j; j < marketsForActiveStorage.length; ++j) {
          _updateActiveMarketIds(poolLogic, to, marketsForActiveStorage[j]);
        }
        // After all markets are tracked, verify no mixed debt assets
        _checkNoMixedDebtAssets(poolLogic);
      }
    }
  }

  /// @notice Removes market IDs with zero collateral from tracking
  function _cleanupInactiveMarkets(address poolLogic, address to) internal {
    uint256 account = DytmHelperLib.toUserAccount(poolLogic);
    uint256[] memory tokenIds = getOwnedTokenIds(poolLogic);
    for (uint256 i; i < tokenIds.length; ++i) {
      uint256[] memory collateralIds = IDytmOffice(dytmOffice).getAllCollateralIds(account, uint88(tokenIds[i]));
      if (collateralIds.length == 0) {
        nftTracker.removeUintId(to, nftType, poolLogic, tokenIds[i]);
      }
    }
  }

  /// @notice Adds market ID to NFT tracker if not already tracked
  function _updateActiveMarketIds(address poolLogic, address to, uint88 supplyMarketId) internal {
    if (!isValidOwnedTokenId(poolLogic, uint256(supplyMarketId))) {
      nftTracker.addUintId(to, nftType, poolLogic, uint256(supplyMarketId), positionsLimit);
    }
  }

  /// @notice Validates the pool's main-account HF after a merge into it.
  ///         - absolute floor: post-merge HF must be at least HEALTH_FACTOR_LOWER_BOUNDARY.
  ///         - relative cap: if main had debt pre-merge (finite snapshot), the drop from the
  ///           pre-merge HF is capped at MERGE_MAX_HF_DEGRADATION_BPS.
  /// @dev Always clears the transient snapshot.
  function _checkMergeHFDegradation(address _poolLogic, uint88 _marketId) internal {
    uint256 hfBefore = _preMergeMainHealthFactor;
    _preMergeMainHealthFactor = 0;

    uint256 hfAfter = IDytmPeriphery(dytmPeriphery)
      .getAccountPosition(DytmHelperLib.toUserAccount(_poolLogic), _marketId)
      .healthFactor;
    require(hfAfter >= HEALTH_FACTOR_LOWER_BOUNDARY, "health factor too low");

    // No pre-merge debt (periphery returns max when debt is zero, including when main has no
    // position at all) — no baseline to measure degradation against; the floor above suffices.
    if (hfBefore == type(uint256).max) return;
    require(
      hfAfter * _BPS_DENOMINATOR >= hfBefore * (_BPS_DENOMINATOR - MERGE_MAX_HF_DEGRADATION_BPS),
      "merge HF degradation too high"
    );
  }

  /// @notice Enforces minimum health factor after borrow/withdraw/switchCollateral operations
  function _checkHealthFactorLowerBoundary(uint256 accountId, uint88 marketId) internal view {
    DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      accountId,
      marketId
    );
    require(position.healthFactor >= HEALTH_FACTOR_LOWER_BOUNDARY, "health factor too low");
  }

  function _decodeSupplyParams(bytes calldata _data) internal pure returns (uint256 accountId, uint256 tokenId) {
    DytmParamStructs.SupplyParams memory supplyParams = abi.decode(_data, (DytmParamStructs.SupplyParams));
    accountId = supplyParams.account;
    tokenId = supplyParams.tokenId;
  }

  function _decodeWithdrawParams(
    bytes calldata _data
  ) internal pure returns (uint256 accountId, uint256 tokenId, address receiver) {
    DytmParamStructs.WithdrawParams memory withdrawParams = abi.decode(_data, (DytmParamStructs.WithdrawParams));
    accountId = withdrawParams.account;
    tokenId = withdrawParams.tokenId;
    receiver = withdrawParams.receiver;
  }

  function _decodeBorrowParams(
    bytes calldata _data
  ) internal pure returns (uint256 accountId, uint248 reserveKey, address receiver) {
    DytmParamStructs.BorrowParams memory borrowParams = abi.decode(_data, (DytmParamStructs.BorrowParams));
    accountId = borrowParams.account;
    reserveKey = borrowParams.key;
    receiver = borrowParams.receiver;
  }

  function _decodeSwitchCollateralParams(
    bytes calldata _data
  ) internal pure returns (uint256 accountId, uint256 tokenId) {
    DytmParamStructs.SwitchCollateralParams memory params = abi.decode(
      _data,
      (DytmParamStructs.SwitchCollateralParams)
    );
    accountId = params.account;
    tokenId = params.tokenId;
  }

  function _decodeRepayParams(bytes calldata _data) internal pure returns (uint256 accountId, uint248 reserveKey) {
    DytmParamStructs.RepayParams memory repayParams = abi.decode(_data, (DytmParamStructs.RepayParams));
    accountId = repayParams.account;
    reserveKey = repayParams.key;
  }

  /// @notice For direct borrows: ensure borrow asset matches existing debt across tracked markets
  /// @dev Traverses markets instead of using a mapping to avoid persistent storage in guard contracts
  ///      (complicates upgrades) and to avoid cleanup when debt is repaid via asset guard's withdrawProcessing
  ///      if simply using a mapping
  function _checkNoMixedDebtAssets(address _poolLogic, uint256 _accountId, address _borrowAsset) internal view {
    uint256[] memory marketIds = getOwnedTokenIds(_poolLogic);
    for (uint256 i; i < marketIds.length; ++i) {
      uint256 debtId = IDytmOffice(dytmOffice).getDebtId(_accountId, uint88(marketIds[i]));
      if (debtId > 0) {
        require(DytmHelperLib.getAssetFromTokenId(debtId) == _borrowAsset, "mixed debt assets not supported");
      }
    }
  }

  /// @notice For delegation calls: after all markets tracked, verify uniform debt asset
  function _checkNoMixedDebtAssets(address _poolLogic) internal view {
    uint256[] memory marketIds = getOwnedTokenIds(_poolLogic);
    if (marketIds.length <= 1) return;

    uint256 accountId = DytmHelperLib.toUserAccount(_poolLogic);
    address debtAsset;
    for (uint256 i; i < marketIds.length; ++i) {
      uint256 debtId = IDytmOffice(dytmOffice).getDebtId(accountId, uint88(marketIds[i]));
      if (debtId > 0) {
        address currentDebtAsset = DytmHelperLib.getAssetFromTokenId(debtId);
        if (debtAsset == address(0)) {
          debtAsset = currentDebtAsset;
        } else {
          require(debtAsset == currentDebtAsset, "mixed debt assets not supported");
        }
      }
    }
  }

  /// @notice Asserts every collateral and debt asset of an account's position on a market is
  ///         a supported pool asset:
  ///         - keeps pool-side oracle/pricing guarantees for the position.
  ///         - entry-side counterpart of ERC20Guard's removeAssetCheck, which locks these
  ///           assets on exit.
  function _checkPositionAssetsSupported(address _poolManagerLogic, uint256 _account, uint88 _market) internal view {
    uint256[] memory collateralIds = IDytmOffice(dytmOffice).getAllCollateralIds(_account, _market);
    for (uint256 i; i < collateralIds.length; ++i) {
      _checkAssetsSupported(_poolManagerLogic, DytmHelperLib.getAssetFromTokenId(collateralIds[i]));
    }
    uint256 debtId = IDytmOffice(dytmOffice).getDebtId(_account, _market);
    if (debtId > 0) {
      _checkAssetsSupported(_poolManagerLogic, DytmHelperLib.getAssetFromTokenId(debtId));
    }
  }

  /// @notice Validates market is whitelisted
  function _checkDytmMarket(uint248 _reserveKey) internal view {
    uint88 marketId = DytmHelperLib.getMarketId(_reserveKey);
    require(dytmMarketsWhitelist[marketId], "invalid market");
  }

  function _checkUserAccount(uint256 _accountId, address _poolLogic) internal pure {
    require(DytmHelperLib.toUserAddress(_accountId) == _poolLogic, "recipient is not pool");
  }

  function _checkAssetsSupported(address _poolManagerLogic, address _assetToCheck) internal view {
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_assetToCheck), "unsupported asset");
  }
}
