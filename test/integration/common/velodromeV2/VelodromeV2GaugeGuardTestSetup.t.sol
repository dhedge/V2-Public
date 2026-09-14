// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IVelodromeV2Gauge} from "contracts/interfaces/velodrome/IVelodromeV2Gauge.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {VelodromeV2TestSetup} from "test/integration/common/velodromeV2/VelodromeV2TestSetup.t.sol";

/// @notice `VelodromeV2GaugeContractGuard` governs staking a vault's LP for emissions. The vault
/// may only stake LP it is allowed to hold, emissions must be claimed to the vault itself, and the
/// vault must be able to price the reward token before it accepts any.
abstract contract VelodromeV2GaugeGuardTestSetup is VelodromeV2TestSetup {
  /* ========== DEPOSIT ========== */

  function test_manager_can_stake_lp_in_the_gauge() public {
    uint256 lp = _addStableLiquidity();
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _stakeLp(lp);

    assertEq(IERC20(velo.stablePool).balanceOf(address(fund)), 0);
    assertEq(IVelodromeV2Gauge(velo.stableGauge).balanceOf(address(fund)), lp);
    // Staked LP is still vault value, just held by the gauge.
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.001e18);
  }

  function test_revert_stake_when_the_lp_asset_is_not_supported() public {
    uint256 lp = _addStableLiquidity();
    _approveGauge(lp);
    _removeSupportedAsset(velo.stablePool);

    vm.prank(manager);
    vm.expectRevert("unsupported lp asset");
    fund.execTransaction(velo.stableGauge, abi.encodeWithSignature("deposit(uint256)", lp));
  }

  /* ========== WITHDRAW ========== */

  function test_manager_can_unstake_lp_from_the_gauge() public {
    uint256 lp = _addStableLiquidity();
    _stakeLp(lp);

    _managerExec(velo.stableGauge, abi.encodeWithSelector(IVelodromeV2Gauge.withdraw.selector, lp));

    assertEq(IERC20(velo.stablePool).balanceOf(address(fund)), lp);
    assertEq(IVelodromeV2Gauge(velo.stableGauge).balanceOf(address(fund)), 0);
  }

  /// @dev The guard rejects the call before it reaches the gauge, so nothing needs to be staked.
  /// Staked LP still counts towards the vault's balance and so cannot be dropped anyway.
  function test_revert_unstake_when_the_lp_asset_is_not_supported() public {
    _removeSupportedAsset(velo.stablePool);

    vm.prank(manager);
    vm.expectRevert("unsupported lp asset");
    fund.execTransaction(velo.stableGauge, abi.encodeWithSelector(IVelodromeV2Gauge.withdraw.selector, 1e18));
  }

  /* ========== REWARDS ========== */

  function test_manager_can_claim_emissions_into_the_vault() public {
    _stakeLp(_addStableLiquidity());
    skip(7 days);

    uint256 rewardBefore = IERC20(velo.protocolToken).balanceOf(address(fund));

    _managerExec(velo.stableGauge, abi.encodeWithSelector(IVelodromeV2Gauge.getReward.selector, address(fund)));

    // Emissions land in the vault, never with the manager.
    assertGt(IERC20(velo.protocolToken).balanceOf(address(fund)), rewardBefore);
    assertEq(IERC20(velo.protocolToken).balanceOf(manager), 0);
  }

  function test_revert_claiming_emissions_for_anyone_but_the_vault() public {
    _stakeLp(_addStableLiquidity());
    skip(7 days);

    vm.prank(manager);
    vm.expectRevert("invalid claimer");
    fund.execTransaction(velo.stableGauge, abi.encodeWithSelector(IVelodromeV2Gauge.getReward.selector, manager));
  }

  /// @dev The reward asset guard refuses to let go of a reward token while a vault still holds an
  /// asset that earns it, so both pools have to be dropped before the reward token can be.
  function test_revert_claiming_emissions_the_vault_cannot_price() public {
    _removeSupportedAsset(velo.stablePool);
    _removeSupportedAsset(velo.variablePool);
    _removeSupportedAsset(velo.protocolToken);

    vm.prank(manager);
    vm.expectRevert("enable reward token");
    fund.execTransaction(velo.stableGauge, abi.encodeWithSelector(IVelodromeV2Gauge.getReward.selector, address(fund)));
  }
}
