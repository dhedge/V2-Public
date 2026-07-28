// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {IDytmDelegatee} from "../../interfaces/dytm/IDytmDelegatee.sol";

library DytmParamStructs {
  struct MarketId {
    uint88 value; // Underlying value as uint88
  }

  enum TokenType {
    NONE, // 0
    ESCROW, // 1
    LEND, // 2
    DEBT, // 3
    ISOLATED_ACCOUNT // 4
  }

  struct DelegationCallParams {
    IDytmDelegatee delegatee;
    bytes callbackData;
  }

  struct SupplyParams {
    uint256 account;
    uint256 tokenId;
    uint256 assets;
    bytes extraData;
  }

  struct WithdrawParams {
    uint256 account;
    uint256 tokenId;
    address receiver;
    uint256 assets;
    uint256 shares;
    bytes extraData;
  }

  struct BorrowParams {
    uint256 account;
    uint248 key;
    address receiver;
    uint256 assets;
    bytes extraData;
  }

  struct RepayParams {
    uint256 account;
    uint248 key;
    TokenType withCollateralType;
    uint256 assets;
    uint256 shares;
    bytes extraData;
  }

  struct SwitchCollateralParams {
    uint256 account;
    uint256 tokenId;
    uint256 assets;
    uint256 shares;
  }

  struct DebtInfo {
    uint256 debtShares;
    uint256 debtAssets;
    uint256 debtValueUSD;
    uint248 debtKey;
    address debtAsset;
  }
  struct CollateralInfo {
    uint256 tokenId;
    uint256 shares;
    uint256 assets;
    uint256 valueUSD;
    uint256 weightedValueUSD;
    uint64 weight;
    uint248 key;
    address asset;
    TokenType tokenType;
  }

  struct AccountPosition {
    DebtInfo debt;
    CollateralInfo[] collaterals;
    uint256 totalCollateralValueUSD;
    uint256 totalWeightedCollateralValueUSD;
    uint256 healthFactor;
    bool isHealthy;
  }

  /// @notice Per-asset withdrawal planning entry emitted by `DytmWithdrawalCalculator.previewWithdrawal`.
  /// @dev    Flat list across all withdrawable DYTM markets; one entry per collateral slot and
  ///         per debt slot (when non-zero). Carries everything the frontend needs to:
  ///           - Plan off-chain work (DEX aggregator / Pendle redeem / Ondo attestation) using
  ///             `asset`, `amount`, `assetType`, `isPool`.
  ///           - Build the on-chain `WithdrawParams` / `RepayParams` calldata using
  ///             `accountId`, `marketId`, `tokenId` (collateral) or `debtKey` (debt), and `shares`.
  ///         Collateral entries: `tokenId` set, `debtKey == 0`, `isDebt == false`.
  ///         Debt entries:       `tokenId == 0`, `debtKey` set, `isDebt == true`.
  ///         dHEDGE-vault collateral: `isPool == true`. The frontend handles the vault token's
  ///         underlying-resolution + per-underlying off-chain handling itself.
  struct AssetData {
    address asset;
    uint256 amount;
    uint16 assetType;
    bool isPool;
    bool isDebt;
    uint88 marketId;
    uint256 accountId;
    uint256 tokenId;
    uint248 debtKey;
    uint256 shares;
  }
}
