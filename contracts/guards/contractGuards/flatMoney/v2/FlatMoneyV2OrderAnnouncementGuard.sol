// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IOrderAnnouncementModule} from "../../../../interfaces/flatMoney/v2/IOrderAnnouncementModule.sol";
import {IFlatcoinVaultV2} from "../../../../interfaces/flatMoney/v2/IFlatcoinVaultV2.sol";
import {IPoolManagerLogic} from "../../../../interfaces/IPoolManagerLogic.sol";
import {FlatMoneyV2PerpsConfig} from "../shared/FlatMoneyV2PerpsConfig.sol";
import {FlatMoneyOptionsOrderAnnouncementGuard} from "./FlatMoneyOptionsOrderAnnouncementGuard.sol";

contract FlatMoneyV2OrderAnnouncementGuard is FlatMoneyOptionsOrderAnnouncementGuard {
  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _whitelisteddHedgePools dHEDGE pools that are allowed to use Order Announcement
  constructor(
    address _nftTracker,
    PoolSetting[] memory _whitelisteddHedgePools
  )
    FlatMoneyOptionsOrderAnnouncementGuard(
      _nftTracker,
      FlatMoneyV2PerpsConfig.NFT_TYPE,
      FlatMoneyV2PerpsConfig.MAX_POSITIONS,
      _whitelisteddHedgePools,
      FlatMoneyV2PerpsConfig.MAX_ALLOWED_LEVERAGE
    )
  {}

  /// @param _poolManagerLogic Address of the PoolManagerLogic contract
  /// @param _to OrderAnnouncement contract address
  /// @param _data Transaction data payload
  /// @return txType The transaction type of a given transaction data
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(_isPoolWhitelisted(poolLogic), "not whitelisted");

    bytes4 method = getMethod(_data);
    IFlatcoinVaultV2 vault = IOrderAnnouncementModule(_to).vault();

    if (method == IOrderAnnouncementModule.announceStableDeposit.selector) {
      txType = _verifyStableDeposit(_poolManagerLogic, address(vault));
    } else if (method == IOrderAnnouncementModule.announceStableWithdraw.selector) {
      txType = _verifyStableWithdraw(_poolManagerLogic, vault.collateral());
    } else {
      (txType, ) = FlatMoneyOptionsOrderAnnouncementGuard._txGuardProcessing({
        _poolManagerLogic: _poolManagerLogic,
        _poolLogic: poolLogic,
        _vault: vault,
        _method: method,
        _params: getParams(_data)
      });
    }

    return (txType, false);
  }
}
