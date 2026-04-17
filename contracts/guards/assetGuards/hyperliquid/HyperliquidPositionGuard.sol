// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";

import {HyperliquidCoreDepositWalletContractGuard} from "../../contractGuards/hyperliquid/HyperliquidCoreDepositWalletContractGuard.sol";
import {IAssetGuard} from "../../../interfaces/guards/IAssetGuard.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHyperliquidCoreWriterContractGuard} from "../../../interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {PrecompileHelper} from "../../../utils/hyperliquid/PrecompileHelper.sol";
import {FixedPointMathLib} from "../../../utils/FixedPointMathLib.sol";

/// @title Hyperliquid Position asset guard
/// @notice Asset guard to account for Hyperliquid positions (perps + spot USDC in HyperCore).
/// @dev Set the asset to the `_CORE_WRITER` contract address to use this asset guard.
/// @dev NOTE: Assumes that the pool has kept USDC/`WITHDRAWAL_ASSET` balance as withdrawal liquidity.
/// @dev AssetType = 39
contract HyperliquidPositionGuard is IAssetGuard, PrecompileHelper {
  using FixedPointMathLib for uint256;

  /// @notice Calculates the amount to withdraw to the user when the pool has an active account on Hyperliquid.
  /// @param pool PoolLogic address.
  /// @param withdrawPortion Portion of shares to withdraw.
  function withdrawProcessing(
    address pool,
    address,
    uint256 withdrawPortion,
    address
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    return _withdrawProcessing(pool, withdrawPortion);
  }

  /// @notice Returns the total value of Hyperliquid positions for `pool`.
  /// @dev Includes perps account value, USDC spot balance in HyperCore, and in-flight USDC deposits.
  /// @dev The value is denominated in USDC with 6 decimals.
  /// @dev Returns 0 even if the account value is negative.
  /// @param pool PoolLogic address.
  /// @return balance Total value of Hyperliquid positions.
  function getBalance(address pool, address) public view override returns (uint256 balance) {
    // Fetch the list of approved dex IDs from the contract guard's state.
    IHyperliquidCoreWriterContractGuard contractGuard = _useContractGuard(IPoolLogic(pool).factory());

    // 1. Sum the account value of all perp positions across all the dex IDs in the approved list.
    uint256[] memory approvedDexIds = contractGuard.getApprovedDexIds();
    for (uint256 i; i < approvedDexIds.length; ++i) {
      // Skip the spot dex as it doesn't have an account value and we are already accounting for the USDC spot balance separately.
      if (approvedDexIds[i] == _DEX_ID_CORE_SPOT) continue;

      AccountMarginSummary memory perpSummary = accountMarginSummary(pool, approvedDexIds[i]);

      // If the account value is positive, add it to the balance.
      // Negative value means the account should technically be liquidated and
      // if it wasn't, creating any order on Hyperliquid would most likely fail.
      // Note: We are making an implicit assumption that the `accountValue` is in USDC denomination.
      if (perpSummary.accountValue > 0) {
        balance += uint256(uint64(perpSummary.accountValue));
      }
    }

    // 2. USDC spot balance in HyperCore
    // Given that USDC's `evmExtraWeiDecimals` is -2 and `weiDecimals` is 8,
    // the spot balance on HyperCore needs to be divided by 1e2 to scale it back to 6 decimals.
    balance += spotBalance(pool, _USDC_TOKEN_INDEX).total / 1e2;

    // 3. In-flight USDC deposits (read from CoreDepositWallet contract guard)
    address poolFactory = IPoolLogic(pool).factory();
    address coreDepositWalletGuard = IHasGuardInfo(poolFactory).getContractGuard(_CORE_DEPOSIT_WALLET);
    if (coreDepositWalletGuard != address(0)) {
      balance += HyperliquidCoreDepositWalletContractGuard(coreDepositWalletGuard).inFlightAmount(pool, _USDC_ADDRESS);
    }
  }

  /// @notice Checks that the total value of Hyperliquid positions for `pool` is zero.
  /// @dev This is to ensure that the manager of `pool` cannot remove the asset guard while it still
  ///      has an open position on Hyperliquid.
  /// @dev We also disallow removal of the asset guard if a spot asset action (bridging/trading) has been
  ///      performed in the current block.
  /// @param pool PoolLogic address.
  function removeAssetCheck(address pool, address) external view override {
    IHyperliquidCoreWriterContractGuard contractGuard = _useContractGuard(IPoolLogic(pool).factory());

    require(getBalance(pool, address(0)) == 0, "account value !0");
    require(!contractGuard.hasPerformedSpotAction(pool), "spot asset action performed");
  }

  /// @notice Returns the decimals related to the account value of the Hyperliquid positions.
  /// @dev The value is denominated in USDC with 6 decimals.
  function getDecimals(address) public pure override returns (uint256 decimals) {
    return 6;
  }

  /// @notice Helper function for withdrawing USDC for the Hyperliquid position value.
  /// @dev The position value (getBalance) is denominated in USDC.
  /// @dev Includes compensation for decreased USDC balance when other guards withdraw proportionally.
  /// @param _pool PoolLogic address.
  /// @param _withdrawPortion Portion to withdraw (18 decimals)
  /// @return withdrawAsset Will always be the USDC address for Hyperliquid position withdrawals.
  /// @return withdrawBalance Amount of USDC to withdraw.
  /// @return transactions Transactions to be executed (empty).
  function _withdrawProcessing(
    address _pool,
    uint256 _withdrawPortion
  )
    internal
    view
    returns (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions)
  {
    // Value to withdraw in USDC terms (6 decimals).
    // The `address(0)` parameter is just a placeholder since `getBalance` doesn't use the asset parameter.
    uint256 valueToWithdraw = getBalance(_pool, address(0)).mulWadDown(_withdrawPortion);

    if (valueToWithdraw == 0) {
      return (withdrawAsset, withdrawBalance, transactions);
    }

    withdrawAsset = _USDC_ADDRESS;

    // Revert full withdrawal from single remaining depositor.
    require(_withdrawPortion < FixedPointMathLib.WAD, "invalid withdraw portion");
    require(
      IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic()).isSupportedAsset(withdrawAsset),
      "withdrawal asset not enabled"
    );

    // Apply compensation factor for other guards withdrawing USDC proportionally
    // withdrawBalance = valueToWithdraw * 1e18 / (1e18 - _withdrawPortion)
    withdrawBalance = valueToWithdraw.divWadDown(FixedPointMathLib.WAD - _withdrawPortion);

    require(IERC20(withdrawAsset).balanceOf(_pool) >= withdrawBalance, "not enough withdrawal liquidity");
  }

  function _useContractGuard(
    address _poolFactory
  ) internal view returns (IHyperliquidCoreWriterContractGuard contractguard) {
    contractguard = IHyperliquidCoreWriterContractGuard(IHasGuardInfo(_poolFactory).getContractGuard(_CORE_WRITER));
  }
}
