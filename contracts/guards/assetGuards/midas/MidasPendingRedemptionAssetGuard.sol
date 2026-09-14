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
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {ClosedAssetGuard} from "../ClosedAssetGuard.sol";
import {OutsidePositionWithdrawalHelper} from "../OutsidePositionWithdrawalHelper.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IMidasRedemptionVault} from "../../../interfaces/midas/IMidasRedemptionVault.sol";
import {IMidasRedemptionVaultContractGuard} from "../../../interfaces/midas/IMidasRedemptionVaultContractGuard.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {PoolsWhitelist} from "../../../utils/PoolsWhitelist.sol";

/// @title Midas pending redemption asset guard
/// @dev Asset type = 43
/// @notice Accounts for a pool's outstanding async Midas redemption requests. The "asset" is the
///         redemption vault address; `getBalance` returns the total mToken amount still Pending, so the
///         claim keeps its NAV contribution between the moment the mToken leaves the pool
///         (`redeemRequest`) and the moment `tokenOut` is paid in (`approveRequest`). Register this
///         asset in the AssetHandler with the same aggregator as the mToken (`MidasPriceAggregator`)
///         so the claim is valued at NAV.
/// @dev    Only the Midas vault admin can settle (`approveRequest`) or reject (`rejectRequest`) a
///         request. Rejection does NOT auto-return the mToken, so a Canceled tracked request makes
///         `getBalance` REVERT — freezing all vault pricing rather than understating total value —
///         until dHEDGE ops verify Midas returned the tokens and lift the freeze via
///         `MidasRedemptionVaultContractGuard.reconcileCanceledRequests`. (Related: neither the
///         mToken nor the request's `tokenOut` can be removed while a request is unresolved — see
///         `ERC20Guard._checkMidasPendingRedemptions`.)
/// @notice On withdrawal, the depositor's share of the pending claim is paid out of the FREE mToken
///         balance sitting in the pool (`OutsidePositionWithdrawalHelper` pattern with the mToken as
///         the withdrawal asset). Both the claim and the payout are denominated in the same mToken, so
///         the conversion is the identity — no oracle is involved in this leg. If the free mToken
///         balance cannot cover the (grossed-up) payment, the withdrawal reverts until the curator
///         settles the request.
/// @dev    EasySwapperV2 withdrawals: the claim's withdrawal leg is paid in the mToken, which the
///         WithdrawalVault tracks through the mToken's own supported-asset entry (type 42). Having
///         no secondary-market liquidity, the mToken can only be claimed in-kind via the no-swap
///         `completeWithdrawal()`, never swapped into the single withdrawal asset.
/// @dev    ORDERING INVARIANT: the grossing-up in `OutsidePositionWithdrawalHelper` (`x / (1 - portion)`)
///         is exact only because this asset (type 43) is processed BEFORE the mToken asset (type 42) in
///         `PoolLogic._withdrawTo` — supported assets are sorted by asset type DESCENDING
///         (`PoolManagerLogic._addAsset`) and payouts are transferred inline. The withdrawer then
///         receives `portion` of the already-reduced mToken balance from the type 42 guard, totalling
///         exactly `portion * (free + pending)`. Type 43 must stay greater than type 42.
contract MidasPendingRedemptionAssetGuard is OutsidePositionWithdrawalHelper, ClosedAssetGuard, IAddAssetCheckGuard {
  using SafeMath for uint256;

  // solhint-disable-next-line const-name-snakecase
  bool public constant override isAddAssetCheckGuard = true;

  /// @notice Total mToken amount across the pool's still-Pending redemption requests (18 decimals).
  /// @param _pool The pool logic address.
  /// @param _asset The redemption vault address.
  function getBalance(
    address _pool,
    address _asset
  ) public view override(ClosedAssetGuard, OutsidePositionWithdrawalHelper) returns (uint256 balance) {
    address contractGuard = _getContractGuard(_pool, _asset);

    // No contract guard means no requests could have been tracked.
    if (contractGuard == address(0)) {
      return 0;
    }

    uint256[] memory requestIds = IMidasRedemptionVaultContractGuard(contractGuard).getPendingRequestIds(_pool, _asset);

    for (uint256 i = 0; i < requestIds.length; i++) {
      (address sender, , uint8 status, uint256 amountMToken, , ) = IMidasRedemptionVault(_asset).redeemRequests(
        requestIds[i]
      );

      if (sender != _pool) continue;

      if (status == uint8(IMidasRedemptionVault.RequestStatus.Pending)) {
        balance = balance.add(amountMToken);
      } else if (status == uint8(IMidasRedemptionVault.RequestStatus.Canceled)) {
        // Midas rejected the request WITHOUT returning the mToken (rejection only flips the status;
        // the return is a manual, unattributable ops transfer). The claim's value is neither in the
        // pool nor in a Pending claim, so any reported total value would be understated — freeze all
        // pricing (and thus deposits/withdrawals/trading) instead of transacting at a wrong value,
        // until dHEDGE ops verify the return and lift the freeze via
        // `MidasRedemptionVaultContractGuard.reconcileCanceledRequests`.
        revert("canceled redemption unreconciled");
      }
    }
  }

  /// @notice mToken amounts are always 18 decimals.
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Pays the depositor's share of the pending claim out of the pool's free mToken balance.
  /// @dev The withdrawal asset is derived from the redemption vault itself, keeping this guard generic
  ///      across mTokens. The mToken must be a supported asset of the pool (enforced by the helper).
  ///      Reverts with "not enough available balance_1" when the free mToken balance cannot cover the
  ///      grossed-up payment, and with "invalid withdraw portion" on a 100% withdrawal while a claim is
  ///      outstanding; returns empty when nothing is pending so withdrawals proceed normally.
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address /* _to */
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(
      _pool,
      _asset,
      _withdrawPortion,
      IMidasRedemptionVault(_asset).mToken()
    );
  }

  /// @dev Identity conversion: `getBalance` (hence `_valueToWithdraw`) and the withdrawal asset are
  ///      both denominated in the same mToken, so no oracle is involved in this leg.
  function _valueToWithdrawAssetAmount(
    address /* _poolManagerLogic */,
    address /* _withdrawAsset */,
    uint256 /* _withdrawAssetBalanceInPool */,
    uint256 _valueToWithdraw
  ) internal pure override returns (uint256 withdrawAssetAmount) {
    withdrawAssetAmount = _valueToWithdraw;
  }

  /// @notice Only whitelisted pools can enable the pending-redemption position, and never as an
  ///         investor deposit asset.
  /// @dev The whitelist has a single owned holder — the redemption vault's contract guard
  ///      (`MidasRedemptionVaultContractGuard is PoolsWhitelist`) — resolved from the asset being
  ///      added exactly the way `getBalance` resolves request tracking, so both Midas asset guards
  ///      always agree with it. For a never-whitelisted pool this check is defense in depth (the
  ///      vault asset alone is inert: `redeemRequest` requires the mToken enabled, which requires
  ///      the whitelist). What it actually closes is the revocation path: an un-whitelisted pool
  ///      that still has the mToken enabled must not be able to expand into async redemptions by
  ///      adding this asset later.
  ///      No `removeAssetCheck` override is needed: while a request is Pending, `getBalance` is
  ///      non-zero (and while one is Canceled it reverts outright), so removal is already rejected
  ///      by the standard non-empty-asset checks.
  function addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _asset) external view override {
    require(!_asset.isDeposit, "deposit not supported");

    address contractGuard = _getContractGuard(_poolLogic, _asset.asset);
    require(
      contractGuard != address(0) && PoolsWhitelist(contractGuard).poolsWhitelist(_poolLogic),
      "pool not whitelisted"
    );
  }

  /// @dev The redemption vault's contract guard is the integration's single owned contract: it tracks
  ///      the pool's async requests AND holds the pool whitelist.
  function _getContractGuard(address _pool, address _vault) internal view returns (address contractGuard) {
    contractGuard = IHasGuardInfo(IPoolLogic(_pool).factory()).getContractGuard(_vault);
  }
}
