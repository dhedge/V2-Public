// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {VelodromeV2TestSetup} from "test/integration/common/velodromeV2/VelodromeV2TestSetup.t.sol";

/// @notice `VelodromeV2LPAssetGuard` is what lets a vault hold Velodrome LP: it values the
/// position and pays out the withdrawer's share of it. Both matter for the total fund value the
/// vault prices deposits and exits off.
abstract contract VelodromeV2LPAssetGuardTestSetup is VelodromeV2TestSetup {
  /// @dev Live pool ratios drift against the Chainlink feeds, so equality here is approximate.
  uint256 internal constant VALUATION_TOLERANCE = 0.04e18; // 4%

  /* ========== VALUATION ========== */

  function test_providing_liquidity_does_not_change_vault_value() public {
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _addStableLiquidity();

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  /* ========== WITHDRAW PROCESSING ========== */

  function test_withdrawer_receives_their_share_of_lp() public {
    uint256 lp = _addStableLiquidity();
    skip(poolFactoryProxy.getExitCooldown() + 1);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _withdrawHalf();

    assertApproxEqRel(IERC20(velo.stablePool).balanceOf(investor), lp / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(IERC20(velo.stablePool).balanceOf(address(fund)), lp / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore / 2, VALUATION_TOLERANCE);
  }
}
