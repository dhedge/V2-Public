// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {OndoGMTokenAssetGuard} from "contracts/guards/assetGuards/ondo/OndoGMTokenAssetGuard.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {OndoGMDirectWithdrawalTestSetup} from "test/integration/common/ondo/OndoGMDirectWithdrawalTestSetup.t.sol";
import {OndoGMSwapTestSetup} from "test/integration/common/ondo/OndoGMSwapTestSetup.t.sol";

contract OndoGMDirectWithdrawalTestEthereum is OndoGMDirectWithdrawalTestSetup, EthereumSetup {
  uint256 internal constant BPS_DENOMINATOR = 10_000;

  constructor() EthereumSetup(24724485) OndoGMSwapTestSetup() {}

  function setUp() public override(OndoGMDirectWithdrawalTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    OndoGMDirectWithdrawalTestSetup.setUp();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Golden path — direct PoolLogic.withdrawSafe
  // ═══════════════════════════════════════════════════════════════════════

  function test_directWithdraw_poolLogic_redeemsGMtoUSDC() public {
    uint256 investorBalance = testPool.balanceOf(investor);
    assertGt(investorBalance, 0, "investor must have pool tokens");

    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildOndoComplexAssetsData(
      _defaultOndoWithdrawData(),
      200 // 2% slippage tolerance
    );

    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);

    // Pool's GOOGLon decreased by exactly REDEEM_AMOUNT_IN
    assertEq(poolGooglonBefore - IERC20(GOOGLON).balanceOf(address(testPool)), REDEEM_AMOUNT_IN);
    // Investor received USDC (pro-rata of pool's USDC + redeem proceeds)
    uint256 investorUsdcGained = IERC20(usdcData.asset).balanceOf(investor) - investorUsdcBefore;
    assertGe(investorUsdcGained, REDEEM_MIN_RECEIVE);
    // Pool tokens fully burned
    assertEq(testPool.balanceOf(investor), 0);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Golden path — EasySwapperV2.initWithdrawal + completeWithdrawal
  // ═══════════════════════════════════════════════════════════════════════

  function test_directWithdraw_easySwapperV2_redeemsGMtoUSDC() public {
    uint256 investorBalance = testPool.balanceOf(investor);
    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildOndoComplexAssetsData(_defaultOndoWithdrawData(), 200);

    vm.startPrank(investor);
    IERC20(address(testPool)).approve(address(easySwapperV2Proxy), investorBalance);
    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Proxy.initWithdrawal(
      address(testPool),
      investorBalance,
      complexAssetsData
    );
    vm.stopPrank();

    assertEq(vault, investorVault, "predicted vault mismatch");

    // Tracked assets must include USDC (the redeem output) — and not GOOGLon.
    bool foundUsdc;
    for (uint256 i; i < trackedAssets.length; ++i) {
      assertTrue(trackedAssets[i].token != GOOGLON, "vault should not track GOOGLon");
      if (trackedAssets[i].token == usdcData.asset) {
        foundUsdc = true;
        assertGt(trackedAssets[i].balance, 0, "vault USDC balance must be > 0");
      }
    }
    assertTrue(foundUsdc, "vault should track USDC");

    vm.prank(investor);
    easySwapperV2Proxy.completeWithdrawal();

    assertEq(poolGooglonBefore - IERC20(GOOGLON).balanceOf(address(testPool)), REDEEM_AMOUNT_IN);
    assertGe(IERC20(usdcData.asset).balanceOf(investor) - investorUsdcBefore, REDEEM_MIN_RECEIVE);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // previewGmTokenAmount — frontend GM amount helper
  // ═══════════════════════════════════════════════════════════════════════

  function test_previewGmTokenAmount_bufferedPortionShrinksWithAccruedFees() public {
    uint256 investorBalance = testPool.balanceOf(investor);

    // Investor holds exactly 50% of the vault — manager and investor each deposited 20k USDC at
    // the same token price, and seeding GOOGLon afterwards mints no new pool tokens.
    assertEq((investorBalance * 1e18) / testPool.totalSupply(), 0.5e18, "investor should hold 50% of the vault");

    // Owner sets a 3% annual management fee (the factory maximum). No fee has accrued yet.
    vm.prank(owner);
    fundManagerLogic.ownerSetFeeNumerator(0, 300, 0, 0);

    // Baseline: with no fee accrued, the returned GM amount is the buffered 50% portion.
    // `previewGmTokenAmount` is `cannotExecute` — simulate the eth_call by zeroing tx.origin.
    vm.prank(address(0), address(0));
    uint256 gmAmountBefore = ondoGMTokenAssetGuard.previewGmTokenAmount(address(testPool), GOOGLON, investorBalance);

    // `previewGmTokenAmount` has already minted the manager fee — recompute the portion
    // from post-call state (the test pool has no exit fee, so no exit-fee reduction applies).
    uint256 portion = (investorBalance * 1e18) / testPool.totalSupply();
    uint256 rawPortionAmount = (IERC20(GOOGLON).balanceOf(address(testPool)) * portion) / 1e18;
    uint256 expected = (rawPortionAmount * 9_999) / 10_000; // 0.01% sim→exec drift buffer
    assertEq(gmAmountBefore, expected, "buffered GM amount mismatch");
    assertLt(gmAmountBefore, rawPortionAmount, "must be shaved below raw portion");

    // Fast-forward exactly half a year so the 3% annual management fee accrues as a streaming fee.
    vm.warp(block.timestamp + 365 days / 2);

    // Calling again mints the accrued management fee. Half a year at 3% annual = a 1.5% streaming
    // fee, inflating totalSupply by 1.5%, so the investor's portion shrinks to 1/1.015 of baseline.
    vm.prank(address(0), address(0));
    uint256 gmAmountAfter = ondoGMTokenAssetGuard.previewGmTokenAmount(address(testPool), GOOGLON, investorBalance);

    // Half a year at 3% annual = a 1.5% streaming fee: redeemable GM scales by exactly 1000/1015.
    assertApproxEqRel(gmAmountAfter, (gmAmountBefore * 1000) / 1015, 1, "GM amount should shrink 1.5%");
  }

  function test_previewGmTokenAmount_returnsZero_whenSubMinDust() public {
    // Shrink pool GOOGLon so the investor's portion is worth far below the $1.10 minRedeemValue.
    deal(GOOGLON, address(testPool), 1e15);

    uint256 investorBalance = testPool.balanceOf(investor);
    vm.prank(address(0), address(0));
    uint256 gmAmount = ondoGMTokenAssetGuard.previewGmTokenAmount(address(testPool), GOOGLON, investorBalance);

    assertEq(gmAmount, 0, "should return 0 for sub-min dust");
  }

  function test_previewGmTokenAmount_returnsZero_whenZeroBalance() public {
    // Drain the pool's GOOGLon entirely.
    deal(GOOGLON, address(testPool), 0);

    uint256 investorBalance = testPool.balanceOf(investor);
    vm.prank(address(0), address(0));
    uint256 gmAmount = ondoGMTokenAssetGuard.previewGmTokenAmount(address(testPool), GOOGLON, investorBalance);

    assertEq(gmAmount, 0, "should return 0 for zero balance");
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Negative — guard checks (one-sided mismatch tolerance)
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_quoteQuantityExceedsPortion() public {
    // Shrink pool GOOGLon so investor's portion is 1 wei below REDEEM_AMOUNT_IN.
    deal(GOOGLON, address(testPool), 2 * REDEEM_AMOUNT_IN - 2);

    uint256 investorBalance = testPool.balanceOf(investor);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildOndoComplexAssetsData(_defaultOndoWithdrawData(), 200);

    vm.expectRevert("quote quantity > reference");
    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);
  }

  function test_revert_quoteQuantityUndershootsBeyondDelta() public {
    // Inflate pool GOOGLon by ~10 bps, well beyond the 5 bps tolerance.
    uint256 inflated = (2 * REDEEM_AMOUNT_IN * (BPS_DENOMINATOR + 10)) / BPS_DENOMINATOR;
    deal(GOOGLON, address(testPool), inflated);

    uint256 investorBalance = testPool.balanceOf(investor);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildOndoComplexAssetsData(_defaultOndoWithdrawData(), 200);

    vm.expectRevert("quote quantity mismatch");
    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);
  }

  function test_quoteQuantityWithinDelta_succeeds() public {
    // Inflate pool GOOGLon by ~3 bps, inside the 5 bps tolerance.
    uint256 inflated = (2 * REDEEM_AMOUNT_IN * (BPS_DENOMINATOR + 3)) / BPS_DENOMINATOR;
    deal(GOOGLON, address(testPool), inflated);

    uint256 investorBalance = testPool.balanceOf(investor);
    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildOndoComplexAssetsData(_defaultOndoWithdrawData(), 200);

    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);

    // Only REDEEM_AMOUNT_IN GM is consumed (the signed quantity); the rest stays in the pool.
    assertEq(poolGooglonBefore - IERC20(GOOGLON).balanceOf(address(testPool)), REDEEM_AMOUNT_IN);
    assertGt(IERC20(GOOGLON).balanceOf(address(testPool)), 0, "leftover GM should remain in pool");
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Negative — empty withdrawData / amountOutMinimum floor
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_emptyWithdrawData() public {
    uint256 investorBalance = testPool.balanceOf(investor);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildEmptyComplexAssetsData();

    vm.expectRevert("withdrawData required");
    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Sub-$1 dust — empty withdrawData skips the redeem
  // ═══════════════════════════════════════════════════════════════════════

  function test_directWithdraw_subMinDust_skipsRedeem() public {
    // Shrink pool GOOGLon so the investor's 50% portion is worth far below the $1.10
    // `minRedeemValue` floor — Ondo can't attest a sub-$1 swap.
    uint256 dust = 1e15; // ~$0.30 of GOOGLon total
    deal(GOOGLON, address(testPool), dust);

    uint256 investorBalance = testPool.balanceOf(investor);
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);

    // Empty withdrawData routes GOOGLon through the 4-arg overload (slippageTolerance 0).
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildEmptyComplexAssetsData();

    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);

    // Redeem skipped: the dust GOOGLon stays in the pool, withdrawal still settles.
    assertEq(IERC20(GOOGLON).balanceOf(address(testPool)), dust, "dust GM should stay in pool");
    assertGt(IERC20(usdcData.asset).balanceOf(investor) - investorUsdcBefore, 0, "investor should receive USDC");
    assertEq(testPool.balanceOf(investor), 0, "pool tokens should be fully burned");
  }

  /// @notice An enabled-but-empty Ondo asset must not block withdrawals: with zero GM balance
  ///         there is nothing to redeem, so an empty withdrawData slot no-ops instead of
  ///         reverting "withdrawData required". Mirrors the frontend skipping attestation for a
  ///         zero-value Ondo asset while still withdrawing the pool's other assets.
  function test_emptyWithdrawData_zeroBalanceOndoAsset_noOps() public {
    // Drain the pool's GOOGLon so the Ondo asset is enabled but empty.
    deal(GOOGLON, address(testPool), 0);

    uint256 investorBalance = testPool.balanceOf(investor);
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);

    // Empty withdrawData for every slot, including the (now empty) GOOGLon Ondo asset.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildEmptyComplexAssetsData();

    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);

    // No revert: the empty GOOGLon slot no-ops; investor still receives their USDC share.
    assertEq(IERC20(GOOGLON).balanceOf(address(testPool)), 0, "GOOGLon stays empty");
    assertGt(IERC20(usdcData.asset).balanceOf(investor) - investorUsdcBefore, 0, "investor receives USDC");
    assertEq(testPool.balanceOf(investor), 0, "pool tokens fully burned");
  }

  function test_revert_amountOutMinimumBelowFloor() public {
    OndoGMTokenAssetGuard.OndoWithdrawData memory data = _defaultOndoWithdrawData();
    data.amountOutMinimum = 1; // 1 wei USDC — way below the 1% floor

    uint256 investorBalance = testPool.balanceOf(investor);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildOndoComplexAssetsData(data, 200);

    vm.expectRevert("amountOutMinimum too low");
    vm.prank(investor);
    testPool.withdrawSafe(investorBalance, complexAssetsData);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Negative — constructor
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_constructor_zeroOndoGMSwap() public {
    vm.expectRevert("invalid ondoGMSwap");
    new OndoGMTokenAssetGuard(address(0), MISMATCH_DELTA_NUMERATOR, MIN_REDEEM_VALUE);
  }

  function test_revert_constructor_invalidMismatchDelta() public {
    vm.expectRevert("invalid mismatch delta");
    new OndoGMTokenAssetGuard(ondoGMSwap, BPS_DENOMINATOR, MIN_REDEEM_VALUE);
  }

  function test_revert_constructor_invalidMinRedeemValue() public {
    vm.expectRevert("invalid minRedeemValue");
    new OndoGMTokenAssetGuard(ondoGMSwap, MISMATCH_DELTA_NUMERATOR, 1e18 - 1);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Negative — addAssetCheck
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_addAssetCheck_depositNotSupported() public {
    // Drain the pool's GOOGLon balance so the asset can be removed.
    deal(GOOGLON, address(testPool), 0);

    vm.startPrank(manager);
    address[] memory toRemove = new address[](1);
    toRemove[0] = GOOGLON;
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), toRemove);

    IHasSupportedAsset.Asset[] memory toAdd = new IHasSupportedAsset.Asset[](1);
    toAdd[0] = IHasSupportedAsset.Asset({asset: GOOGLON, isDeposit: true});

    vm.expectRevert("deposit not supported");
    fundManagerLogic.changeAssets(toAdd, new address[](0));
    vm.stopPrank();
  }
}
