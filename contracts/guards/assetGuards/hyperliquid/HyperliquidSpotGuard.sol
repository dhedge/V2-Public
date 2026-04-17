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

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";

import {IAssetGuard} from "../../../interfaces/guards/IAssetGuard.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IERC20Extended} from "../../../interfaces/IERC20Extended.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IHyperliquidCoreWriterContractGuard} from "../../../interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";

import {InFlightTracker} from "../../../utils/hyperliquid/InFlightTracker.sol";
import {FixedPointMathLib} from "../../../utils/FixedPointMathLib.sol";

/// @title Hyperliquid ERC20 asset guard
/// @notice Asset guard for spot assets and combination of asset and contract guard for linked EVM tokens on HyperEVM.
/// @dev Can be used for spot assets with or without a linked EVM contract on HyperEVM.
///      For the former, the `txGuard` function will revert.
/// @dev WARNING: HyperEVM token contracts linked to a HyperCore spot token may not be ERC20 compliant.
///      This guard SHOULD NOT BE USED for non-compliant linked EVM tokens.
/// @dev WARNING: DON'T USE THIS GUARD FOR NATIVE HYPE.
/// @dev WARNING: MUST BE USED FOR SPOT TOKENS WITH USDC AS THE QUOTE ASSET.
/// @dev MUST NOT BE USED FOR USDC.
/// @dev Asset type = 40
contract HyperliquidSpotGuard is
  IGuard,
  ITxTrackingGuard,
  IAssetGuard,
  ITransactionTypes,
  IAddAssetCheckGuard,
  InFlightTracker
{
  using FixedPointMathLib for uint256;

  /////////////////////////////////////////////
  //                 State                   //
  /////////////////////////////////////////////

  /// @notice Indicates the pool using this guard in a transaction should
  ///         call `afterTxGuard` after the transaction is executed.
  // solhint-disable-next-line const-name-snakecase
  bool public constant override isTxTrackingGuard = true;

  /// @notice Indicates the pool using this guard should call `addAssetCheck` before adding an asset.
  // solhint-disable-next-line const-name-snakecase
  bool public constant override isAddAssetCheckGuard = true;

  /////////////////////////////////////////////
  //                Functions                //
  /////////////////////////////////////////////

  /// @notice Post transaction processing for tx tracking guards.
  /// @dev Updates the composite block number for the pool and asset combination during bridging to HyperCore.
  /// @param poolManagerLogic The address of the pool manager logic contract.
  /// @param to The transaction target address (in this case the token address).
  /// @param data The transaction data.
  function afterTxGuard(address poolManagerLogic, address to, bytes calldata data) external virtual override {
    if (bytes4(data) == IERC20.transfer.selector) {
      address pool = IPoolManagerLogic(poolManagerLogic).poolLogic();

      require(msg.sender == pool, "not authorized");

      (, uint256 amount) = abi.decode(data[4:], (address, uint256));

      trackInFlightToCore({pool: pool, asset: to, amount: amount});
    }
  }

  /// @notice Transaction guard for approving assets
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param poolManagerLogic PoolManagerLogic address
  /// @param to Transaction target address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in ITransactionTypes
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) public view virtual override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    address poolFactory = IPoolLogic(poolLogic).factory();

    require(!isSystemAddress(to), "invalid transaction target");
    require(_useContractGuard(poolFactory).dHedgePoolsWhitelist(poolLogic), "pool not whitelisted");

    bytes4 method = bytes4(data);

    // Allow transfers only to the system address of the token contract on HyperEVM.
    if (method == IERC20.transfer.selector) {
      (address receiver, ) = abi.decode(data[4:], (address, uint256));
      address systemAddress = getSystemAddress(TOKEN_REGISTRY.getTokenIndex(to));

      require(receiver == systemAddress, "invalid transfer receiver");

      return (uint16(TransactionType.HyperliquidSystemAddressTransfer), false);
    } else if (method == IERC20.approve.selector) {
      (address spender, ) = abi.decode(data[4:], (address, uint256));

      address spenderGuard = IHasGuardInfo(poolFactory).getContractGuard(spender);

      // Checks that the spender is an approved address.
      require(spenderGuard != address(0), "unsupported spender approval");

      return (uint16(TransactionType.Approve), false);
    }
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
    view
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    return _withdrawProcessing({_pool: pool, _asset: asset, _withdrawPortion: portion});
  }

  /// @notice Returns the balance of the managed asset
  /// @dev Accounts for the spot token balance on HyperCore ONLY IF the system address of the asset is not mapped.
  /// @param pool Address of the pool
  /// @param asset Address of the managed asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view virtual override returns (uint256 balance) {
    // If the `asset` is a system address, just get the balance on HyperCore.
    if (isSystemAddress(asset)) {
      balance = getCoreBalance(pool, getTokenIndexFromSystemAddress(asset));
    } else {
      uint64 tokenIndex = getTokenIndex(asset);

      // Check if the system address of the `asset` is mapped. If it is, we ignore the core balance
      // and only return the balance of the evmContract and any in-flight amount to HyperCore.
      uint256 coreBalance = (
        IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(getSystemAddress(tokenIndex))
      )
        ? 0
        : getCoreBalance(pool, tokenIndex);

      // If the `asset` is the evmContract address, get the balance on the pool and also account for the in-flight amount to HyperCore.
      balance = IERC20(asset).balanceOf(pool) + coreBalance + getInFlightAmount(pool, asset);
    }
  }

  /// @notice Returns the decimal of the managed asset
  /// @dev If the `asset` is a system address, return the EVM decimals (weiDecimals + evmExtraWeiDecimals)
  ///      since the balance is scaled to EVM decimals.
  ///      Otherwise, return the decimals of the `asset` which is the evmContract address.
  /// @param asset Address of the managed asset
  /// @return decimals The decimal of given asset
  function getDecimals(address asset) public view virtual override returns (uint256 decimals) {
    if (isSystemAddress(asset)) {
      TokenInfo memory info = tokenInfo(getTokenIndexFromSystemAddress(asset));
      // Return EVM decimals: weiDecimals + evmExtraWeiDecimals
      // This matches the balance format returned by getBalance
      int256 evmDecimals = int256(uint256(info.weiDecimals)) + int256(info.evmExtraWeiDecimals);
      require(evmDecimals >= 0, "invalid EVM decimals");
      decimals = uint256(evmDecimals);
    } else {
      decimals = IERC20Extended(asset).decimals();
    }
  }

  /// @notice Checks if the pool's account on HyperCore has been manually activated before allowing the asset to be added.
  /// @dev This is necessary in this guard because a core account needs to be activated before the asset can be added
  ///      If the account is not activated, bridged assets may not appear in spotBalance, causing them to become invisible
  ///      to the guards' balance accounting.
  /// @dev Manual activation can be done by sending 1 USDC to the pool's account on HyperCore directly.
  /// @param pool PoolLogic address.
  function addAssetCheck(address pool, IHasSupportedAsset.Asset calldata asset) external view override {
    require(coreUserExists(pool), "core user not activated");

    if (isSystemAddress(asset.asset)) {
      require(!asset.isDeposit, "deposit not supported");
    }
  }

  /// @notice Necessary check for remove asset.
  /// @dev Checks if the spot asset balance is zero before allowing the asset to be removed from the pool.
  /// @dev Checks if a corewriter action related to any spot asset has been done before allowing the asset to be removed from the pool.
  /// @param pool Address of the pool
  /// @param asset Address of the remove asset
  function removeAssetCheck(address pool, address asset) public view virtual override {
    IHyperliquidCoreWriterContractGuard contractGuard = _useContractGuard(IPoolLogic(pool).factory());

    require(getBalance(pool, asset) == 0, "cannot remove non-empty asset");
    require(!contractGuard.hasPerformedSpotAction(pool), "spot asset action performed");
  }

  function getCoreBalance(address pool, uint64 tokenIndex) public view returns (uint256 coreBalance) {
    coreBalance = spotBalance(pool, tokenIndex).total;
    TokenInfo memory info = tokenInfo(tokenIndex);

    // Scale the spot balance to the EVM token decimals.
    // This can reduce the precision of the spot balance if the EVM token
    // has less decimals than the spot token.
    if (info.evmExtraWeiDecimals > 0) {
      coreBalance = coreBalance * 10 ** uint8(info.evmExtraWeiDecimals);
    } else {
      coreBalance = coreBalance / 10 ** uint8(-info.evmExtraWeiDecimals);
    }
  }

  /// @notice Helper function for withdrawing using specially configured asset sitting in the pool outside
  /// @dev Adapted from `OutsidePositionWithdrawalHelper.sol`.
  /// @param _pool PoolLogic address
  /// @param _asset Complex position address
  /// @param _withdrawPortion Portion to withdraw
  /// @return withdrawAsset By default this will be USDC.
  /// @return withdrawBalance Amount to withdraw
  /// @return transactions Transactions to be executed
  function _withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion
  )
    internal
    view
    returns (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions)
  {
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(IPoolLogic(_pool).poolManagerLogic());

    // Get asset balance and convert to USD value (18 decimals)
    uint256 valueToWithdraw = poolManagerLogic.assetValue(_asset, getBalance(_pool, _asset)).mulWadDown(
      _withdrawPortion
    );

    if (valueToWithdraw == 0) {
      return (withdrawAsset, withdrawBalance, transactions);
    }

    withdrawAsset = _USDC_ADDRESS;

    // If withdrawal asset (USDC) configured for current pool is not enabled, then withdraw should revert.
    require(
      IHasSupportedAsset(address(poolManagerLogic)).isSupportedAsset(withdrawAsset),
      "withdrawal asset not enabled"
    );

    uint256 withdrawAssetBalanceInPool = IERC20(withdrawAsset).balanceOf(_pool);
    uint256 withdrawAssetValueInPool = poolManagerLogic.assetValue(withdrawAsset, withdrawAssetBalanceInPool);

    // if withdrawal asset is enabled, but has no balance or no value (for some reason), then withdraw should revert.
    require(withdrawAssetValueInPool > 0, "not enough available balance_0");

    // Revert withdraw from single remaining depositor, assuming that integration will only be available for Toros.
    require(_withdrawPortion < FixedPointMathLib.WAD, "invalid withdraw portion");

    // How many withdrawal asset tokens should be withdrawn for depositor's portion of leverage position.
    // Both valueToWithdraw and withdrawAssetValueInPool are in 18 decimals.
    // Also apply compensation factor for other guards withdrawing USDC proportionally.
    withdrawBalance = withdrawAssetBalanceInPool.mulDivDown(valueToWithdraw, withdrawAssetValueInPool).divWadDown(
      FixedPointMathLib.WAD - _withdrawPortion
    );

    // Otherwise there is not enough withdrawal asset balance to cover leverage position portion
    require(withdrawAssetBalanceInPool >= withdrawBalance, "not enough available balance_1");
  }

  function _useContractGuard(
    address _poolFactory
  ) internal view returns (IHyperliquidCoreWriterContractGuard contractguard) {
    contractguard = IHyperliquidCoreWriterContractGuard(IHasGuardInfo(_poolFactory).getContractGuard(_CORE_WRITER));
  }
}
