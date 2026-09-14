// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IVelodromeV2Gauge} from "contracts/interfaces/velodrome/IVelodromeV2Gauge.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {VelodromeV2TestSetup} from "test/integration/common/velodromeV2/VelodromeV2TestSetup.t.sol";

/// @notice `VelodromeV2LPAssetGuard` is what lets a vault hold Velodrome LP: it values the
/// position (staked or not, including emissions still owed) and unwinds the right share of it on
/// withdrawal. Both matter for the total fund value the vault prices deposits and exits off.
abstract contract VelodromeV2LPAssetGuardTestSetup is VelodromeV2TestSetup {
  /// @dev Live pool ratios drift against the Chainlink feeds, so equality here is approximate.
  uint256 internal constant VALUATION_TOLERANCE = 0.04e18; // 4%

  /* ========== VALUATION ========== */

  function test_providing_liquidity_does_not_change_vault_value() public {
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _addStableLiquidity();

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  function test_staking_lp_does_not_change_vault_value() public {
    uint256 lp = _addStableLiquidity();
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 stableBefore = IERC20(velo.poolStable).balanceOf(address(fund));

    // Stake half, so the guard has to value a split position.
    _stakeLp(lp / 2);

    assertApproxEqAbs(IERC20(velo.stablePool).balanceOf(address(fund)), lp - lp / 2, 1);
    assertEq(IERC20(velo.poolStable).balanceOf(address(fund)), stableBefore);
    assertEq(fundManagerLogic.totalFundValue(), valueBefore);
  }

  function test_unclaimed_emissions_count_towards_vault_value() public {
    _stakeLp(_addStableLiquidity());

    uint256 valueBeforeAccrual = fundManagerLogic.totalFundValue();

    skip(3 days);

    // Emissions owed but not yet claimed are still the vault's.
    assertGt(IVelodromeV2Gauge(velo.stableGauge).earned(address(fund)), 0);
    assertGt(fundManagerLogic.totalFundValue(), valueBeforeAccrual);
  }

  /* ========== WITHDRAW PROCESSING ========== */

  function test_withdrawing_half_unwinds_half_of_everything() public {
    _stakeLp(_addStableLiquidity());
    skip(3 days);

    uint256 stableBefore = IERC20(velo.poolStable).balanceOf(address(fund));
    uint256 daiBefore = IERC20(daiData.asset).balanceOf(address(fund));
    uint256 gaugeBefore = IVelodromeV2Gauge(velo.stableGauge).balanceOf(address(fund));
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _withdrawHalf();

    assertApproxEqRel(IERC20(velo.poolStable).balanceOf(address(fund)), stableBefore / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(IERC20(daiData.asset).balanceOf(address(fund)), daiBefore / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(
      IVelodromeV2Gauge(velo.stableGauge).balanceOf(address(fund)),
      gaugeBefore / 2,
      VALUATION_TOLERANCE
    );
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore / 2, VALUATION_TOLERANCE);
  }

  /// @dev Withdrawing forces a claim, so emissions owed to the vault are realised rather than
  /// left behind for whoever exits last.
  function test_withdrawing_claims_outstanding_emissions_for_the_vault() public {
    _stakeLp(_addStableLiquidity());
    skip(3 days);

    uint256 owed = IVelodromeV2Gauge(velo.stableGauge).earned(address(fund));
    assertGt(owed, 0);

    _withdrawHalf();

    assertApproxEqRel(IERC20(velo.protocolToken).balanceOf(address(fund)), owed / 2, VALUATION_TOLERANCE);
  }

  function test_withdrawer_receives_their_share_of_lp_and_emissions() public {
    uint256 lp = _addStableLiquidity();
    _stakeLp(lp);
    skip(3 days);

    uint256 owed = IVelodromeV2Gauge(velo.stableGauge).earned(address(fund));
    assertGt(owed, 0);

    _withdrawHalf();

    assertApproxEqRel(IERC20(velo.stablePool).balanceOf(investor), lp / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(IERC20(velo.protocolToken).balanceOf(investor), owed / 2, VALUATION_TOLERANCE);
  }
}
