// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {FlatcoinModuleKeys} from "../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {IDelayedOrder} from "../../../interfaces/flatMoney/IDelayedOrder.sol";
import {IFlatcoinVault} from "../../../interfaces/flatMoney/IFlatcoinVault.sol";
import {IERC721VerifyingGuard} from "../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {FlatMoneyBasisContractGuard} from "./shared/FlatMoneyBasisContractGuard.sol";

/// @notice Allows buying and selling FlatMoney's flatcoin UNIT and manage leverage positions (NFTs).
contract FlatMoneyDelayedOrderContractGuard is FlatMoneyBasisContractGuard, IERC721VerifyingGuard {
  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _whitelisteddHedgePools dHEDGE pools that are allowed to use Flat Money Perp Market
  constructor(
    address _nftTracker,
    PoolSetting[] memory _whitelisteddHedgePools
  ) FlatMoneyBasisContractGuard(_nftTracker, keccak256("FLAT_MONEY_LEVERAGE_NFT"), 3, _whitelisteddHedgePools, 7e18) {}

  /// @notice Transaction guard for FlatMoney's DelayedOrder contract.
  /// @param _poolManagerLogic Address of the PoolManagerLogic contract
  /// @param _to DelayedOrder contract address
  /// @param _data Transaction data payload
  /// @return txType The transaction type of a given transaction data
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    bytes4 method = getMethod(_data);
    IFlatcoinVault vault = IDelayedOrder(_to).vault();
    address collateralAsset = vault.collateral();
    address leverageModule = vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY);

    if (method == IDelayedOrder.announceStableDeposit.selector) {
      txType = _verifyStableDeposit(_poolManagerLogic, address(vault));
    } else if (method == IDelayedOrder.announceStableWithdraw.selector) {
      txType = _verifyStableWithdraw(_poolManagerLogic, collateralAsset);
    } else if (method == IDelayedOrder.cancelExistingOrder.selector) {
      txType = uint16(TransactionType.FlatMoneyCancelOrder);
    } else if (method == IDelayedOrder.announceLeverageOpen.selector) {
      require(_isPoolWhitelisted(poolLogic), "not perps whitelisted");

      txType = _verifyLeverageOpen({
        _poolManagerLogic: _poolManagerLogic,
        _leverageModule: leverageModule,
        _params: getParams(_data)
      });
    } else if (method == IDelayedOrder.announceLeverageAdjust.selector) {
      require(_isPoolWhitelisted(poolLogic), "not perps whitelisted");

      txType = _verifyLeverageAdjust({
        _poolManagerLogic: _poolManagerLogic,
        _poolLogic: poolLogic,
        _collateralAsset: collateralAsset,
        _leverageModule: leverageModule,
        _vault: address(vault),
        _params: getParams(_data)
      });
    } else if (method == IDelayedOrder.announceLeverageClose.selector) {
      txType = _verifyLeverageClose({
        _poolManagerLogic: _poolManagerLogic,
        _poolLogic: poolLogic,
        _collateralAsset: collateralAsset,
        _params: getParams(_data)
      });
    }

    return (txType, false);
  }

  /// @param _operator Address which calls onERC721Received callback
  /// @param _from Address which transfers the NFT
  /// @param _tokenId ID of the NFT
  /// @return verified True if the NFT is verified
  function verifyERC721(
    address _operator,
    address _from,
    uint256 _tokenId,
    bytes calldata
  ) external override returns (bool verified) {
    require(_isPoolWhitelisted(msg.sender), "not perps whitelisted");

    return _verifyERC721(_operator, _from, _tokenId);
  }
}
