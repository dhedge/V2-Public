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

import {ERC20Guard} from "../ERC20Guard.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IMidasRedemptionVault} from "../../../interfaces/midas/IMidasRedemptionVault.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {PoolsWhitelist} from "../../../utils/PoolsWhitelist.sol";

/// @title Midas mToken asset guard
/// @dev Asset type = 42
/// @notice Values Midas mTokens (e.g. mAPOLLO) at their oracle NAV and, on withdrawal, transfers the
///         depositor's portion in-kind (plain `ERC20Guard` behavior). Depositors redeem the received
///         mToken via Midas themselves if they want the underlying.
/// @dev    Each mToken must be registered in the AssetHandler with an aggregator returning its real
///         NAV (`MidasPriceAggregator`). Any outstanding async redemption is accounted separately by
///         `MidasPendingRedemptionAssetGuard` (asset type 43), which pays withdrawals out of the free
///         mToken balance; its math relies on type 43 being processed BEFORE this type 42 asset in
///         `PoolLogic._withdrawTo` (supported assets are sorted by asset type descending).
/// @dev    LISTING A NEW MIDAS PRODUCT (e.g. mTBILL): do NOT mint a new asset type — any type above
///         43 silently inverts the withdrawal ordering (the pending leg must run before the mToken
///         leg) and overpays withdrawers. Instead, redeploy this stateless guard with the extended
///         redemption vault set (each served mToken is derived from its vault) and swap it in at
///         `assetGuards[42]`; the new redemption vault joins type 43, and everything keyed on these
///         types (removal checks, pricing freeze, withdrawal servicing, ordering) applies by
///         construction.
/// @dev    The mToken cannot be removed while a redemption request is unresolved — enforced by the
///         inherited `ERC20Guard._checkMidasPendingRedemptions` (settlement pays `tokenOut` in;
///         a rejected request is settled by Midas ops returning the mToken manually).
/// @dev    EasySwapperV2 withdrawals pay the mToken in-kind into the WithdrawalVault, which tracks
///         it as a claimable asset. mTokens have no secondary-market liquidity, so the swap-based
///         `completeWithdrawal` cannot unroll them into the single withdrawal asset — depositors
///         claim via the no-swap `completeWithdrawal()` and redeem the mToken via Midas themselves.
/// @dev    The integration is gated to protocol-chosen vaults: only whitelisted pools can enable an
///         mToken or the pending-redemption asset. The whitelist has a single owned holder — the
///         redemption vault's contract guard (`PoolsWhitelist`) — resolved through Governance at
///         call time from the mToken's configured redemption vault, so replacing the contract guard
///         does not require redeploying this guard. Pool addresses only exist after `createFund`, so
///         whitelisted pools enable the Midas assets via `changeAssets` afterwards.
contract MidasMTokenAssetGuard is ERC20Guard, IAddAssetCheckGuard {
  // solhint-disable-next-line const-name-snakecase
  bool public constant override isAddAssetCheckGuard = true;

  /// @notice The redemption vault paired with each served mToken; its contract guard holds the
  ///         integration's pool whitelist.
  mapping(address => address) public mTokenRedemptionVault;

  /// @dev Each served mToken is derived from its redemption vault, so the pairing cannot be
  ///      misconfigured by construction.
  constructor(address[] memory _redemptionVaults) {
    for (uint256 i; i < _redemptionVaults.length; ++i) {
      address redemptionVault = _redemptionVaults[i];
      require(redemptionVault != address(0), "invalid address");

      address mToken = IMidasRedemptionVault(redemptionVault).mToken();
      require(mToken != address(0), "invalid mToken");

      mTokenRedemptionVault[mToken] = redemptionVault;
    }
  }

  /// @notice Only whitelisted pools can enable a served mToken, and never as an investor deposit asset.
  function addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _asset) external view override {
    require(!_asset.isDeposit, "deposit not supported");

    address redemptionVault = mTokenRedemptionVault[_asset.asset];
    require(redemptionVault != address(0), "invalid mToken");

    address contractGuard = IHasGuardInfo(IPoolLogic(_poolLogic).factory()).getContractGuard(redemptionVault);
    require(
      contractGuard != address(0) && PoolsWhitelist(contractGuard).poolsWhitelist(_poolLogic),
      "pool not whitelisted"
    );
  }
}
