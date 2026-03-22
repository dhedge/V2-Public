// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IOrderAnnouncementModule} from "../../../../interfaces/flatMoney/v2/IOrderAnnouncementModule.sol";
import {IFlatcoinVaultV2} from "../../../../interfaces/flatMoney/v2/IFlatcoinVaultV2.sol";
import {FlatcoinModuleKeys} from "../../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {IPoolManagerLogic} from "../../../../interfaces/IPoolManagerLogic.sol";
import {FlatMoneyBasisContractGuard} from "../shared/FlatMoneyBasisContractGuard.sol";

contract FlatMoneyOptionsOrderAnnouncementGuard is FlatMoneyBasisContractGuard {
  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _nftType Should pass keccak256("FLAT_MONEY_V2_LEVERAGE_NFT")
  /// @param _maxPositions Should pass 1, as we only allow one position per vault
  /// @param _whitelisteddHedgePools Should pass empty array, options are whitelisted at Flat Money level
  /// @param _maxAllowedLeverage Should pass 10e18, as we allow up to 10x leverage
  /// @dev Name for _nftType should better be "FLAT_MONEY_V2_OPTIONS_NFT", but it's late already
  constructor(
    address _nftTracker,
    bytes32 _nftType,
    uint256 _maxPositions,
    PoolSetting[] memory _whitelisteddHedgePools,
    uint256 _maxAllowedLeverage
  ) FlatMoneyBasisContractGuard(_nftTracker, _nftType, _maxPositions, _whitelisteddHedgePools, _maxAllowedLeverage) {}

  /// @param _poolManagerLogic Address of the PoolManagerLogic contract
  /// @param _to OrderAnnouncement contract address
  /// @param _data Transaction data payload
  /// @return txType The transaction type of a given transaction data
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view virtual override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    bytes4 method = getMethod(_data);
    IFlatcoinVaultV2 vault = IOrderAnnouncementModule(_to).vault();

    // Stable deposit/withdraw require whitelist
    if (method == IOrderAnnouncementModule.announceStableDeposit.selector) {
      require(_isPoolWhitelisted(poolLogic), "not whitelisted");
      txType = _verifyStableDeposit(_poolManagerLogic, address(vault));
    } else if (method == IOrderAnnouncementModule.announceStableWithdraw.selector) {
      require(_isPoolWhitelisted(poolLogic), "not whitelisted");
      txType = _verifyStableWithdraw(_poolManagerLogic, vault.collateral());
    } else {
      // Leverage operations - no whitelist (handled at Flat Money level)
      (txType, ) = _txGuardProcessing({
        _poolManagerLogic: _poolManagerLogic,
        _poolLogic: poolLogic,
        _vault: vault,
        _method: method,
        _params: getParams(_data)
      });
    }

    return (txType, false);
  }

  function _txGuardProcessing(
    address _poolManagerLogic,
    address _poolLogic,
    IFlatcoinVaultV2 _vault,
    bytes4 _method,
    bytes memory _params
  ) internal view returns (uint16 txType, bool) {
    if (_method == IOrderAnnouncementModule.announceLeverageOpen.selector) {
      txType = _verifyLeverageOpen({
        _poolManagerLogic: _poolManagerLogic,
        _leverageModule: _vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY),
        _params: _params
      });
    } else if (_method == IOrderAnnouncementModule.announceLeverageAdjust.selector) {
      txType = _verifyLeverageAdjust({
        _poolManagerLogic: _poolManagerLogic,
        _poolLogic: _poolLogic,
        _collateralAsset: _vault.collateral(),
        _leverageModule: _vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY),
        _vault: address(_vault),
        _params: _params
      });
    } else if (_method == IOrderAnnouncementModule.announceLeverageClose.selector) {
      txType = _verifyLeverageClose({
        _poolManagerLogic: _poolManagerLogic,
        _poolLogic: _poolLogic,
        _collateralAsset: _vault.collateral(),
        _params: _params
      });
    }

    return (txType, false);
  }
}
