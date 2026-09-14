// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {SlippageAccumulator} from "contracts/utils/SlippageAccumulator.sol";
import {IHasGuardInfo} from "contracts/interfaces/IHasGuardInfo.sol";
import {IHasAssetInfo} from "contracts/interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";

/// @notice `SlippageAccumulator` caps how much value a manager may lose to slippage within a
/// rolling window. Guards report every swap to it; it accumulates the shortfall, decays it
/// linearly over `decayTime`, and reverts once the running total reaches the cap.
/// Exercised directly here with a stand-in guard, so the rules hold for every guard that uses it.
contract SlippageAccumulatorTest is Test {
  uint128 internal constant SCALING_FACTOR = 1e6; // 1e6 == 100% slippage
  uint64 internal constant DECAY_TIME = 6 hours;
  uint128 internal constant MAX_CUMULATIVE_SLIPPAGE = 5e4; // 5%
  uint256 internal constant ONE_PERCENT = uint256(SCALING_FACTOR) / 100;

  SlippageAccumulator internal slippageAccumulator;

  address internal poolFactory = makeAddr("poolFactory");
  address internal poolManagerLogic = makeAddr("poolManagerLogic");
  address internal router = makeAddr("router");
  address internal guard = makeAddr("guard");
  address internal impostor = makeAddr("impostor");

  address internal srcAsset = makeAddr("srcAsset");
  address internal dstAsset = makeAddr("dstAsset");

  function setUp() public {
    slippageAccumulator = new SlippageAccumulator(poolFactory, DECAY_TIME, MAX_CUMULATIVE_SLIPPAGE);

    // Only the guard registered for the router may report swaps.
    vm.mockCall(
      poolFactory,
      abi.encodeWithSelector(IHasGuardInfo.getContractGuard.selector, router),
      abi.encode(guard)
    );

    // Both assets are 18 decimals and worth $1, so a swap's slippage is just the amount shortfall.
    _mockAsset(srcAsset, 18, 1e18);
    _mockAsset(dstAsset, 18, 1e18);
    _setSrcAssetSupported(true);

    // Leave room to rewind the clock when testing decay.
    vm.warp(DECAY_TIME * 10);
  }

  /* ========== ACCESS CONTROL ========== */

  function test_revert_when_caller_is_not_the_routers_guard() public {
    vm.prank(impostor);
    vm.expectRevert("Not authorised guard");
    slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(100e18, 90e18));
  }

  function test_revert_on_zero_source_amount() public {
    vm.prank(guard);
    vm.expectRevert("0 src amount");
    slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(0, 0));
  }

  /* ========== WHAT COUNTS AS SLIPPAGE ========== */

  function test_slippage_is_ignored_when_source_asset_is_not_supported() public {
    // Swapping out of something the vault does not hold is not the manager losing vault value.
    _setSrcAssetSupported(false);

    _reportSwap(100e18, 50e18);

    assertEq(_cumulative(poolManagerLogic), 0);
  }

  function test_profitable_swap_accumulates_nothing() public {
    _reportSwap(100e18, 110e18);

    assertEq(_cumulative(poolManagerLogic), 0);
  }

  function test_even_swap_accumulates_nothing() public {
    _reportSwap(100e18, 100e18);

    assertEq(_cumulative(poolManagerLogic), 0);
  }

  function test_loss_accumulates_as_a_fraction_of_the_amount_sent() public {
    // Sending $100 and receiving $99 is 1% slippage.
    _reportSwap(100e18, 99e18);

    assertEq(_cumulative(poolManagerLogic), ONE_PERCENT);
  }

  function test_slippage_is_measured_in_value_not_token_amounts() public {
    // Destination token is worth $2, so 50 of them repay $100 exactly - no slippage.
    _mockAsset(dstAsset, 18, 2e18);

    _reportSwap(100e18, 50e18);

    assertEq(_cumulative(poolManagerLogic), 0);
  }

  /* ========== ACCUMULATION AND THE CAP ========== */

  function test_consecutive_swaps_accumulate() public {
    _reportSwap(100e18, 99e18); // 1%
    _reportSwap(100e18, 99e18); // 1%

    assertEq(_cumulative(poolManagerLogic), (ONE_PERCENT) * 2);
  }

  function test_revert_when_a_single_swap_exceeds_the_cap() public {
    // 10% in one trade, against a 5% cap.
    vm.prank(guard);
    vm.expectRevert("slippage impact exceeded");
    slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(100e18, 90e18));
  }

  function test_revert_when_accumulated_swaps_exceed_the_cap() public {
    // Four 1% trades sit under the 5% cap; the fifth would reach it.
    for (uint256 i; i < 4; ++i) {
      _reportSwap(100e18, 99e18);
    }
    assertEq(_cumulative(poolManagerLogic), (ONE_PERCENT) * 4);

    vm.prank(guard);
    vm.expectRevert("slippage impact exceeded");
    slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(100e18, 99e18));
  }

  function test_accumulated_slippage_is_tracked_per_pool_manager() public {
    address otherPoolManagerLogic = makeAddr("otherPoolManagerLogic");
    vm.mockCall(
      otherPoolManagerLogic,
      abi.encodeWithSelector(IHasSupportedAsset.isSupportedAsset.selector, srcAsset),
      abi.encode(true)
    );

    _reportSwap(100e18, 99e18);

    // One manager burning through its budget must not constrain another.
    assertEq(_cumulative(otherPoolManagerLogic), 0);
  }

  /* ========== DECAY ========== */

  function test_slippage_decays_linearly_and_fully_expires() public {
    _reportSwap(100e18, 99e18);
    uint256 accumulated = ONE_PERCENT;

    vm.warp(block.timestamp + DECAY_TIME / 2);
    assertEq(_cumulative(poolManagerLogic), accumulated / 2);

    vm.warp(block.timestamp + DECAY_TIME / 2);
    assertEq(_cumulative(poolManagerLogic), 0);
  }

  function test_a_swap_blocked_by_the_cap_succeeds_once_slippage_has_decayed() public {
    for (uint256 i; i < 4; ++i) {
      _reportSwap(100e18, 99e18);
    }

    vm.prank(guard);
    vm.expectRevert("slippage impact exceeded");
    slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(100e18, 99e18));

    vm.warp(block.timestamp + DECAY_TIME);

    _reportSwap(100e18, 99e18);
    assertEq(_cumulative(poolManagerLogic), ONE_PERCENT);
  }

  /* ========== OWNER SETTINGS ========== */

  function test_revert_setDecayTime_when_not_owner() public {
    vm.prank(impostor);
    vm.expectRevert("Ownable: caller is not the owner");
    slippageAccumulator.setDecayTime(1 hours);
  }

  function test_revert_setMaxCumulativeSlippage_when_not_owner() public {
    vm.prank(impostor);
    vm.expectRevert("Ownable: caller is not the owner");
    slippageAccumulator.setMaxCumulativeSlippage(1e5);
  }

  function test_owner_can_retune_the_cap_to_unblock_a_manager() public {
    for (uint256 i; i < 4; ++i) {
      _reportSwap(100e18, 99e18);
    }

    vm.prank(guard);
    vm.expectRevert("slippage impact exceeded");
    slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(100e18, 99e18));

    slippageAccumulator.setMaxCumulativeSlippage(1e5); // 10%

    _reportSwap(100e18, 99e18);
    assertEq(_cumulative(poolManagerLogic), (ONE_PERCENT) * 5);
  }

  /* ========== INVARIANTS ========== */

  /// @dev However a manager splits their trades, the running total can never reach the cap.
  function test_fuzz_accumulated_slippage_never_reaches_the_cap(
    uint256 _srcAmount,
    uint256 _dstAmount,
    uint256 _swapCount
  ) public {
    _srcAmount = bound(_srcAmount, 1e18, 1e24);
    _dstAmount = bound(_dstAmount, 0, _srcAmount);
    _swapCount = bound(_swapCount, 1, 10);

    uint256 accepted;
    uint256 rejected;

    for (uint256 i; i < _swapCount; ++i) {
      vm.prank(guard);
      // A trade that would breach the cap reverts; the accumulated total is what survives.
      try slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(_srcAmount, _dstAmount)) {
        ++accepted;
      } catch {
        ++rejected;
      }
    }

    assertEq(accepted + rejected, _swapCount);
    assertLt(_cumulative(poolManagerLogic), uint256(MAX_CUMULATIVE_SLIPPAGE));
  }

  function test_fuzz_slippage_only_decays_as_time_passes(uint256 _elapsed) public {
    _elapsed = bound(_elapsed, 0, DECAY_TIME);

    _reportSwap(100e18, 99e18);
    uint256 before = _cumulative(poolManagerLogic);

    vm.warp(block.timestamp + _elapsed);

    assertLe(_cumulative(poolManagerLogic), before);
  }

  /* ========== HELPERS ========== */

  function _cumulative(address _poolManagerLogic) internal view returns (uint256 cumulativeSlippage) {
    cumulativeSlippage = uint256(slippageAccumulator.getCumulativeSlippageImpact(_poolManagerLogic));
  }

  function _reportSwap(uint256 _srcAmount, uint256 _dstAmount) internal {
    vm.prank(guard);
    slippageAccumulator.updateSlippageImpact(poolManagerLogic, router, _swap(_srcAmount, _dstAmount));
  }

  function _swap(
    uint256 _srcAmount,
    uint256 _dstAmount
  ) internal view returns (SlippageAccumulator.SwapData memory swapData) {
    swapData = SlippageAccumulator.SwapData({
      srcAsset: srcAsset,
      dstAsset: dstAsset,
      srcAmount: _srcAmount,
      dstAmount: _dstAmount
    });
  }

  function _mockAsset(address _asset, uint8 _decimals, uint256 _price) internal {
    vm.mockCall(_asset, abi.encodeWithSelector(IERC20Extended.decimals.selector), abi.encode(_decimals));
    vm.mockCall(poolFactory, abi.encodeWithSelector(IHasAssetInfo.getAssetPrice.selector, _asset), abi.encode(_price));
  }

  function _setSrcAssetSupported(bool _supported) internal {
    vm.mockCall(
      poolManagerLogic,
      abi.encodeWithSelector(IHasSupportedAsset.isSupportedAsset.selector, srcAsset),
      abi.encode(_supported)
    );
  }
}
