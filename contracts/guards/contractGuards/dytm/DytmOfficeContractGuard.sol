// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IDytmOffice} from "../../../interfaces/dytm/IDytmOffice.sol";
import {DytmHelperLib} from "../../../utils/dytm/DytmHelperLib.sol";
import {DytmParamStructs} from "../../../utils/dytm/DytmParamStructs.sol";
import {DytmConfigStructs} from "../../../utils/dytm/DytmConfigStructs.sol";
import {DytmDelegationCallCheckGuard} from "./DytmDelegationCallCheckGuard.sol";
import {IDytmPeriphery} from "../../../interfaces/dytm/IDytmPeriphery.sol";
import {NftTrackerConsumerGuardV2} from "../shared/NftTrackerConsumerGuardV2.sol";

/// @title DYTM Office Contract Guard
/// @notice Guards DYTM Office interactions, validates operations and tracks active markets
contract DytmOfficeContractGuard is ITxTrackingGuard, NftTrackerConsumerGuardV2, DytmDelegationCallCheckGuard {
  mapping(address => bool) public poolsWhitelist;
  mapping(uint88 => bool) public dytmMarketsWhitelist;
  address public immutable poolFactory;
  address public immutable dytmOffice;
  address public immutable dytmPeriphery;
  bool public override isTxTrackingGuard = true;
  uint256 public constant HEALTH_FACTOR_LOWER_BOUNDARY = 1.01e18;

  constructor(
    address[] memory _whitelistedPools,
    uint88[] memory _whitelistedMarkets,
    DytmConfigStructs.DytmConfig memory _dytmConfig
  ) NftTrackerConsumerGuardV2(_dytmConfig.nftTracker, keccak256("DYTM_MARKET_ID_TYPE"), _dytmConfig.maxDytmMarkets) {
    poolFactory = _dytmConfig.dhedgePoolFactory;
    dytmPeriphery = _dytmConfig.dytmPeriphery;
    dytmOffice = _dytmConfig.dytmOffice;
    for (uint256 i; i < _whitelistedPools.length; ++i) {
      poolsWhitelist[_whitelistedPools[i]] = true;
    }
    for (uint256 j; j < _whitelistedMarkets.length; ++j) {
      dytmMarketsWhitelist[_whitelistedMarkets[j]] = true;
    }
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
      require(address(params.delegatee) == poolLogic, "invalid delegatee");
      _checkAndSetDytmDelegateCall(poolLogic);
      txType = uint16(TransactionType.DytmDelegationCall);
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

  /// @notice Enforces minimum health factor after borrow/withdraw operations
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
