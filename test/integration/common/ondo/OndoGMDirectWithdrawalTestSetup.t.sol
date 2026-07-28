// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {OndoGMTokenAssetGuard} from "contracts/guards/assetGuards/ondo/OndoGMTokenAssetGuard.sol";
import {OndoGMSwapTestSetup} from "test/integration/common/ondo/OndoGMSwapTestSetup.t.sol";

/// @title OndoGMDirectWithdrawalTestSetup
/// @notice Extends `OndoGMSwapTestSetup` with the asset-guard wiring needed to exercise
///         depositor withdrawals against a pool holding GOOGLon as an asset-type-41 supported
///         asset. Sized so the investor's full withdraw of their pool-token share matches the
///         signed redeem attestation's `quote.quantity` exactly.
abstract contract OndoGMDirectWithdrawalTestSetup is OndoGMSwapTestSetup {
  uint256 public constant MISMATCH_DELTA_NUMERATOR = 5; // 5 bps
  uint256 public constant MIN_REDEEM_VALUE = 1.1e18; // $1.10

  OndoGMTokenAssetGuard public ondoGMTokenAssetGuard;
  address public investorVault;

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    ondoGMTokenAssetGuard = new OndoGMTokenAssetGuard(ondoGMSwap, MISMATCH_DELTA_NUMERATOR, MIN_REDEEM_VALUE);
    governance.setAssetGuard(uint16(AssetTypeIncomplete.ONDO_GM_TOKEN), address(ondoGMTokenAssetGuard));

    // Re-register GOOGLon at assetType 41 (parent setup registered it as type 0).
    // AssetHandler.addAsset overwrites assetTypes[asset] in place — no remove needed.
    address googlonAggregator = address(assetHandlerProxy.priceAggregators(GOOGLON));
    assetHandlerProxy.addAsset(GOOGLON, uint16(AssetTypeIncomplete.ONDO_GM_TOKEN), googlonAggregator);

    // Disable exit cooldown so investor can withdraw inside the redeem attestation's narrow
    // validity window (~37 seconds at fork time; default 1-day cooldown would push us well past
    // the signed `quote.expiration`).
    poolFactoryProxy.setExitCooldown(0);

    vm.stopPrank();

    // Investor deposits 20k USDC matching the manager's deposit from parent setup. Done BEFORE
    // seeding GOOGLon so the pool's value at deposit time = 20k USDC alone, giving manager and
    // investor each 50% of pool tokens. Seeding GOOGLon after both deposits keeps the split
    // intact and makes investor's portion of GOOGLon = REDEEM_AMOUNT_IN exactly.
    deal(usdcData.asset, investor, 20_000e6);
    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), 20_000e6);
    testPool.deposit(usdcData.asset, 20_000e6);
    vm.stopPrank();

    // Seed pool with 2 × REDEEM_AMOUNT_IN GOOGLon. Investor's 50% portion = REDEEM_AMOUNT_IN —
    // matching the signed redeem attestation's `quote.quantity`.
    deal(GOOGLON, address(testPool), 2 * REDEEM_AMOUNT_IN);

    // Advance one second past the deposit timestamp — withdrawSafe requires
    // `lastDeposit[msg.sender] < block.timestamp` (PoolLogic dh11). Stays well within the
    // ~37-second attestation expiration window from the fork timestamp.
    vm.warp(block.timestamp + 1);

    _computeInvestorWithdrawalVault();
  }

  function _computeInvestorWithdrawalVault() internal {
    address existing = easySwapperV2Proxy.withdrawalContracts(investor);
    investorVault = existing != address(0)
      ? existing
      : vm.computeCreateAddress(address(easySwapperV2Proxy), vm.getNonce(address(easySwapperV2Proxy)));
  }

  /// @dev Build complexAssetsData with the GOOGLon slot populated and other slots empty.
  function _buildOndoComplexAssetsData(
    OndoGMTokenAssetGuard.OndoWithdrawData memory _data,
    uint256 _slippageTolerance
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    IHasSupportedAsset.Asset[] memory supported = fundManagerLogic.getSupportedAssets();
    complexAssetsData = new IPoolLogic.ComplexAsset[](supported.length);
    for (uint256 i; i < supported.length; ++i) {
      complexAssetsData[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supported[i].asset,
        withdrawData: supported[i].asset == GOOGLON ? abi.encode(_data) : new bytes(0),
        slippageTolerance: supported[i].asset == GOOGLON ? _slippageTolerance : 0
      });
    }
  }

  /// @dev Build complexAssetsData with an empty withdrawData blob for every slot (4-arg path).
  function _buildEmptyComplexAssetsData() internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    IHasSupportedAsset.Asset[] memory supported = fundManagerLogic.getSupportedAssets();
    complexAssetsData = new IPoolLogic.ComplexAsset[](supported.length);
    for (uint256 i; i < supported.length; ++i) {
      complexAssetsData[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supported[i].asset,
        withdrawData: new bytes(0),
        slippageTolerance: 0
      });
    }
  }

  function _defaultOndoWithdrawData() internal pure returns (OndoGMTokenAssetGuard.OndoWithdrawData memory) {
    return
      OndoGMTokenAssetGuard.OndoWithdrawData({
        attestationSignature: REDEEM_ATTESTATION_SIGNATURE,
        quote: _redeemQuotePure(),
        amountOutMinimum: REDEEM_MIN_RECEIVE
      });
  }

  /// @dev `_getRedeemQuote` is `view` in the parent; redeclare as `pure` here for use in
  ///      `_defaultOndoWithdrawData` (also `pure`).
  function _redeemQuotePure() private pure returns (IGMTokenManager.Quote memory) {
    return
      IGMTokenManager.Quote({
        chainId: 1,
        attestationId: 37434277619715409041656438775674234140,
        userId: ONDO_USER_ID,
        asset: GOOGLON,
        price: 300336783088357287484,
        quantity: 9726221784124645000,
        expiration: 1774320372,
        side: uint8(IGMTokenManager.QuoteSide.SELL),
        additionalData: bytes32(0)
      });
  }
}
