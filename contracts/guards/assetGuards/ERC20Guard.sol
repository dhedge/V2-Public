//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TxDataUtils} from "../../utils/TxDataUtils.sol";
import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {IAaveLendingPoolAssetGuard} from "../../interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import {IGovernance} from "../../interfaces/IGovernance.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IAaveV3Pool} from "../../interfaces/aave/v3/IAaveV3Pool.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IMidasRedemptionVault} from "../../interfaces/midas/IMidasRedemptionVault.sol";
import {IMidasRedemptionVaultContractGuard} from "../../interfaces/midas/IMidasRedemptionVaultContractGuard.sol";
import {IPoolLimitOrderManager} from "../../interfaces/IPoolLimitOrderManager.sol";
import {IDytmOfficeContractGuard} from "../../interfaces/dytm/IDytmOfficeContractGuard.sol";
import {IDytmPeriphery} from "../../interfaces/dytm/IDytmPeriphery.sol";
import {DytmParamStructs} from "../../utils/dytm/DytmParamStructs.sol";
import {DytmHelperLib} from "../../utils/dytm/DytmHelperLib.sol";
import {EasySwapperV2UnrolledAssetsGuard} from "./EasySwapperV2UnrolledAssetsGuard.sol";
import {DytmOfficeAssetGuard} from "./dytm/DytmOfficeAssetGuard.sol";

/// @title Generic ERC20 asset guard
/// @dev Asset type = 0
contract ERC20Guard is TxDataUtils, IGuard, IAssetGuard, ITransactionTypes {
  using SafeMath for uint256;

  /// @dev Must match `AssetHandler` asset type 43 (Midas Pending Redemption Asset); used by
  ///      `_checkMidasPendingRedemptions` to find the pool's Midas redemption vault positions.
  uint16 internal constant MIDAS_PENDING_REDEMPTION_ASSET_TYPE = 43;

  /// @notice Transaction guard for approving assets
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param poolManagerLogic PoolManagerLogic address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in ITransactionTypes
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address /* to */,
    bytes calldata data
  ) external view override returns (uint16 txType, bool) {
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("approve(address,uint256)"))) {
      address spender = convert32toAddress(getInput(data, 0));

      address factory = IPoolManagerLogic(poolManagerLogic).factory();
      address spenderGuard = IHasGuardInfo(factory).getContractGuard(spender);
      require(spenderGuard != address(0) && spenderGuard != address(this), "unsupported spender approval"); // checks that the spender is an approved address

      txType = uint16(TransactionType.Approve);
    }

    return (txType, false);
  }

  /// @notice Withdraw processing for ERC20 asset
  /// @param pool Address of the pool
  /// @param asset Address of the managed asset
  /// @param portion Portion of the asset balance to withdraw, in 10^18 scale
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to depositor
  /// @return transactions are used to execute the withdrawal transactions in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address /* to */
  )
    external
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    withdrawAsset = asset;
    uint256 totalAssetBalance = getBalance(pool, asset);
    withdrawBalance = totalAssetBalance.mul(portion).div(10 ** 18);
    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns the balance of the managed asset
  /// @param pool Address of the pool
  /// @param asset Address of the managed asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view virtual override returns (uint256 balance) {
    // The base ERC20 guard has no externally staked tokens
    balance = IERC20(asset).balanceOf(pool);
  }

  /// @notice Returns the decimal of the managed asset
  /// @param asset Address of the managed asset
  /// @return decimals The decimal of given asset
  function getDecimals(address asset) external view virtual override returns (uint256 decimals) {
    decimals = IERC20Extended(asset).decimals();
  }

  /// @notice Necessary check for remove asset.
  ///         In AaveLendingPoolAssetGuard, when calculating getBalance, the function loops through all the supported assets.
  ///         Supported asset balance can be 0, but aave collateral or debt can be > 0. If it was able to remove the asset,
  ///         the value of Aave lending pool position would become lower. Having this asset guard with removeAssetCheck prevents this.
  ///         If there is any collateral or debt of a particular asset in Aave, it's not possible to remove that asset.
  /// @param pool Address of the pool
  /// @param asset Address of the remove asset
  function removeAssetCheck(address pool, address asset) public view virtual override {
    require(getBalance(pool, asset) == 0, "cannot remove non-empty asset");

    address factory = IPoolLogic(pool).factory();
    address governance = IPoolFactory(factory).governanceAddress();

    _checkAaveAssetPositions(pool, asset, governance);
    _checkLimitOrderPositions(pool, asset, governance);
    _checkDytmAssetPositions(pool, asset, factory, governance);
    _checkMidasPendingRedemptions(pool, asset, factory, governance);
  }

  function _checkAaveAssetPositions(address pool, address asset, address governance) internal view {
    // Magic number 8 is Aave lending pool "asset" asset type
    address aaveLendingPoolAssetGuard = IGovernance(governance).assetGuards(8);

    if (aaveLendingPoolAssetGuard == address(0)) {
      // If Aave lending pool asset guard is not set, skip the check
      return;
    }

    address aaveLendingPool = IAaveLendingPoolAssetGuard(aaveLendingPoolAssetGuard).aaveLendingPool();

    if (!IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(aaveLendingPool)) {
      // If Aave lending pool asset is not supported, skip the check
      return;
    }

    // Returns address(0) if it's not supported in Aave
    address variableDebtToken = IAaveV3Pool(aaveLendingPool).getReserveVariableDebtToken(asset);

    if (variableDebtToken != address(0))
      require(IERC20(variableDebtToken).balanceOf(pool) == 0, "repay Aave debt first");

    // Returns address(0) if it's not supported in Aave
    address aToken = IAaveV3Pool(aaveLendingPool).getReserveAToken(asset);
    if (aToken != address(0)) require(IERC20(aToken).balanceOf(pool) == 0, "withdraw Aave collateral first");
  }

  function _checkLimitOrderPositions(address pool, address asset, address governance) internal view {
    // Magic number 30 is EasySwapperV2 "asset" asset type
    address unrolledAssetsGuard = IGovernance(governance).assetGuards(30);

    if (unrolledAssetsGuard == address(0)) {
      // If guard is not set, skip the check
      return;
    }

    IPoolLimitOrderManager poolLimitOrderManagerProxy = EasySwapperV2UnrolledAssetsGuard(unrolledAssetsGuard)
      .poolLimitOrderManagerProxy();

    address settlementToken = poolLimitOrderManagerProxy.limitOrderSettlementToken();

    // If the asset is the settlement token, check pool has no open limit orders or settlement order
    if (asset == settlementToken) {
      require(
        poolLimitOrderManagerProxy.hasOpenLimitOrder(pool) == false &&
          poolLimitOrderManagerProxy.hasSettlementOrder(pool) == false,
        "has open order"
      );
    }
  }

  /// @notice Block removal while the asset is held as DYTM collateral or debt — prevents
  ///         bypassing the per-asset oracle-freshness gate that runs on deposits.
  function _checkDytmAssetPositions(address pool, address asset, address factory, address governance) internal view {
    // Magic number 106 is DYTM Office asset type
    address dytmGuard = IGovernance(governance).assetGuards(106);

    if (dytmGuard == address(0)) {
      // If DYTM Office asset guard is not set, skip the check
      return;
    }

    address dytmOffice = DytmOfficeAssetGuard(dytmGuard).dytmOffice();

    if (!IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(dytmOffice)) {
      // If DYTM Office is not supported by the pool, skip the check
      return;
    }

    address periphery = DytmOfficeAssetGuard(dytmGuard).dytmPeriphery();
    uint256[] memory marketIds = IDytmOfficeContractGuard(IHasGuardInfo(factory).getContractGuard(dytmOffice))
      .getOwnedTokenIds(pool);
    uint256 account = DytmHelperLib.toUserAccount(pool);

    for (uint256 i; i < marketIds.length; ++i) {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(periphery).getAccountPosition({
        account: account,
        market: uint88(marketIds[i])
      });

      require(pos.debt.debtAsset != asset, "asset held as DYTM debt");

      for (uint256 j; j < pos.collaterals.length; ++j) {
        require(pos.collaterals[j].asset != asset, "asset held as DYTM collateral");
      }
    }
  }

  /// @notice Block removal while a Midas async redemption involving the asset is unresolved:
  ///         settlement (`approveRequest`) pays the request's `tokenOut` into the pool, and a
  ///         rejected (Canceled) request is settled by Midas ops transferring the mToken back
  ///         manually — either way the incoming tokens would sit in the pool unaccounted if the
  ///         asset were no longer enabled. The mToken is owed back on BOTH Pending (via rejection)
  ///         and Canceled (return in flight); `tokenOut` is only owed while Pending.
  ///         NOTE: this protection only runs for assets whose asset guard inherits ERC20Guard —
  ///         which holds for Midas payment tokens (plain ERC20 stablecoins like USDC) and mTokens
  ///         (`MidasMTokenAssetGuard` extends ERC20Guard).
  function _checkMidasPendingRedemptions(
    address pool,
    address asset,
    address factory,
    address governance
  ) internal view {
    if (IGovernance(governance).assetGuards(MIDAS_PENDING_REDEMPTION_ASSET_TYPE) == address(0)) {
      // If Midas pending redemption asset guard is not set, skip the check
      return;
    }

    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic())
      .getSupportedAssets();

    for (uint256 i; i < supportedAssets.length; ++i) {
      address redemptionVault = supportedAssets[i].asset;

      if (IHasAssetInfo(factory).getAssetType(redemptionVault) != MIDAS_PENDING_REDEMPTION_ASSET_TYPE) continue;

      address contractGuard = IHasGuardInfo(factory).getContractGuard(redemptionVault);
      if (contractGuard == address(0)) continue;

      bool isMToken = IMidasRedemptionVault(redemptionVault).mToken() == asset;
      uint256[] memory requestIds = IMidasRedemptionVaultContractGuard(contractGuard).getPendingRequestIds(
        pool,
        redemptionVault
      );

      for (uint256 j; j < requestIds.length; ++j) {
        (address sender, address tokenOut, uint8 status, , , ) = IMidasRedemptionVault(redemptionVault).redeemRequests(
          requestIds[j]
        );

        if (sender != pool) continue;

        if (status == uint8(IMidasRedemptionVault.RequestStatus.Pending)) {
          require(!isMToken && tokenOut != asset, "pending redemption in progress");
        } else if (status == uint8(IMidasRedemptionVault.RequestStatus.Canceled)) {
          require(!isMToken, "pending redemption in progress");
        }
      }
    }
  }
}
