// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {ICoreDepositWallet} from "../../../interfaces/hyperliquid/ICoreDepositWallet.sol";
import {IHyperliquidCoreWriterContractGuard} from "../../../interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";

import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {InFlightTracker} from "../../../utils/hyperliquid/InFlightTracker.sol";

/// @title HyperliquidCoreDepositWalletContractGuard
/// @notice Contract guard for Circle CoreDepositWallet
/// @dev Allows bridging of USDC to HyperCore via the CoreDepositWallet contract.
/// @dev Tracks in-flight USDC deposits for balance accounting in HyperliquidPositionGuard.
/// @author dHEDGE DAO
contract HyperliquidCoreDepositWalletContractGuard is
  TxDataUtils,
  IGuard,
  ITxTrackingGuard,
  ITransactionTypes,
  InFlightTracker
{
  /////////////////////////////////////////////
  //                  State                  //
  /////////////////////////////////////////////

  // solhint-disable-next-line const-name-snakecase
  bool public constant isTxTrackingGuard = true;

  /////////////////////////////////////////////
  //                Functions                //
  /////////////////////////////////////////////

  /// @notice Post transaction processing for tx tracking guards.
  /// @dev Tracks in-flight deposits to HyperCore for USDC.
  /// @param poolManagerLogic The address of the pool manager logic contract.
  /// @param data The transaction data.
  function afterTxGuard(address poolManagerLogic, address, bytes calldata data) external override {
    if (bytes4(data) == ICoreDepositWallet.deposit.selector) {
      address pool = IPoolManagerLogic(poolManagerLogic).poolLogic();
      require(msg.sender == pool, "not authorized");

      (uint256 amount, ) = abi.decode(data[4:], (uint256, uint32));

      trackInFlightToCore({pool: pool, asset: _USDC_ADDRESS, amount: amount});
    }
  }

  /// @notice Transaction guard for CoreDepositWallet deposits.
  /// @dev Allows bridging USDC to HyperCore to any of the approved dexes (and core spot dex).
  /// @param poolManagerLogic The address of the pool manager logic contract.
  /// @param to The transaction target address.
  /// @param data The transaction data.
  /// @return txType The transaction type.
  /// @return isPublic Whether the transaction is public.
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) public view override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    address poolFactory = IPoolLogic(poolLogic).factory();
    IHyperliquidCoreWriterContractGuard contractGuard = _useContractGuard(poolFactory);

    require(contractGuard.dHedgePoolsWhitelist(poolLogic), "pool not whitelisted");

    bytes4 method = getMethod(data);

    if (method == ICoreDepositWallet.deposit.selector) {
      // Ensure the transaction is targeting the CoreDepositWallet contract.
      require(to == _CORE_DEPOSIT_WALLET, "invalid target contract");

      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(_CORE_WRITER), "CoreWriter not supported asset");

      // USDC has to be the supported asset for the pool.
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(_USDC_ADDRESS), "USDC not supported asset");

      // Restrict destination dex ID to enabled dexes only (validated via CoreWriter guard).
      (, uint32 destinationDex) = abi.decode(getParams(data), (uint256, uint32));

      require(contractGuard.isEnabledDexId(destinationDex), "invalid dex id");

      return (uint16(ITransactionTypes.TransactionType.CoreWalletDeposit), false);
    }
  }

  /// @notice Returns the amount of tokens currently in flight for a given pool and asset.
  /// @dev Used by HyperliquidPositionGuard to read in-flight amounts for balance accounting.
  /// @param pool The address of the pool.
  /// @param asset The address of the asset (e.g., USDC).
  /// @return amount The amount of tokens in flight.
  function inFlightAmount(address pool, address asset) external view returns (uint256 amount) {
    return getInFlightAmount(pool, asset);
  }

  function _useContractGuard(
    address _poolFactory
  ) internal view returns (IHyperliquidCoreWriterContractGuard contractguard) {
    contractguard = IHyperliquidCoreWriterContractGuard(IHasGuardInfo(_poolFactory).getContractGuard(_CORE_WRITER));
  }
}
