// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {VelodromeV2TestSetup} from "test/integration/common/velodromeV2/VelodromeV2TestSetup.t.sol";

/// @notice `VelodromeV2RouterGuard` lets a manager move vault funds into and out of a Velodrome
/// pool. It must only ever do so between assets the vault supports, and the proceeds must come
/// back to the vault rather than anywhere the manager chooses.
abstract contract VelodromeV2RouterGuardTestSetup is VelodromeV2TestSetup {
  /* ========== ADD LIQUIDITY ========== */

  function test_manager_can_add_liquidity() public {
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    uint256 lpReceived = _addStableLiquidity();

    assertGt(lpReceived, 0);
    // Providing liquidity moves value between assets; it does not create or destroy any.
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  function test_revert_add_liquidity_when_tokenA_is_not_supported() public {
    _removeSupportedAsset(velo.poolStable);

    vm.prank(manager);
    vm.expectRevert("unsupported asset: tokenA");
    fund.execTransaction(
      velo.router,
      _addLiquidityCalldata(velo.poolStable, daiData.asset, true, 1_000e6, 1_000e18, address(fund))
    );
  }

  function test_revert_add_liquidity_when_tokenB_is_not_supported() public {
    _removeSupportedAsset(daiData.asset);

    vm.prank(manager);
    vm.expectRevert("unsupported asset: tokenB");
    fund.execTransaction(
      velo.router,
      _addLiquidityCalldata(velo.poolStable, daiData.asset, true, 1_000e6, 1_000e18, address(fund))
    );
  }

  function test_revert_add_liquidity_when_the_lp_token_is_not_supported() public {
    _removeSupportedAsset(velo.stablePool);

    vm.prank(manager);
    vm.expectRevert("unsupported lp asset");
    fund.execTransaction(
      velo.router,
      _addLiquidityCalldata(velo.poolStable, daiData.asset, true, 1_000e6, 1_000e18, address(fund))
    );
  }

  function test_revert_add_liquidity_to_a_recipient_other_than_the_vault() public {
    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    fund.execTransaction(
      velo.router,
      _addLiquidityCalldata(velo.poolStable, daiData.asset, true, 1_000e6, 1_000e18, manager)
    );
  }

  /* ========== REMOVE LIQUIDITY ========== */

  function test_manager_can_remove_liquidity() public {
    uint256 lp = _addStableLiquidity();
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _approveRouter(velo.stablePool, lp);
    _managerExec(velo.router, _removeLiquidityCalldata(velo.poolStable, daiData.asset, true, lp, address(fund)));

    assertEq(IERC20(velo.stablePool).balanceOf(address(fund)), 0);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  function test_revert_remove_liquidity_when_the_lp_token_is_not_supported() public {
    uint256 lp = _addStableLiquidity();
    _approveRouter(velo.stablePool, lp);
    _removeSupportedAsset(velo.stablePool);

    vm.prank(manager);
    vm.expectRevert("unsupported lp asset");
    fund.execTransaction(
      velo.router,
      _removeLiquidityCalldata(velo.poolStable, daiData.asset, true, lp, address(fund))
    );
  }

  function test_revert_remove_liquidity_when_tokenA_is_not_supported() public {
    uint256 lp = _addStableLiquidity();
    _approveRouter(velo.stablePool, lp);
    _removeSupportedAsset(velo.poolStable);

    vm.prank(manager);
    vm.expectRevert("unsupported asset: tokenA");
    fund.execTransaction(
      velo.router,
      _removeLiquidityCalldata(velo.poolStable, daiData.asset, true, lp, address(fund))
    );
  }

  function test_revert_remove_liquidity_when_tokenB_is_not_supported() public {
    uint256 lp = _addStableLiquidity();
    _approveRouter(velo.stablePool, lp);
    _removeSupportedAsset(daiData.asset);

    vm.prank(manager);
    vm.expectRevert("unsupported asset: tokenB");
    fund.execTransaction(
      velo.router,
      _removeLiquidityCalldata(velo.poolStable, daiData.asset, true, lp, address(fund))
    );
  }

  function test_revert_remove_liquidity_to_a_recipient_other_than_the_vault() public {
    uint256 lp = _addStableLiquidity();
    _approveRouter(velo.stablePool, lp);

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    fund.execTransaction(velo.router, _removeLiquidityCalldata(velo.poolStable, daiData.asset, true, lp, manager));
  }
}
