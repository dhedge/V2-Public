// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice A pool can be paused along two independent axes. Pausing shares freezes everything that
/// moves value in or out (deposits, withdrawals, transfers, fee mints) while leaving the manager
/// able to trade; pausing trading does the opposite. Who may pause is covered by
/// `SafeSignerPauseTest` - this covers what each pause actually stops.
contract PoolPausingTest is PoolUnitTestSetup {
  uint256 internal constant DEPOSIT_AMOUNT = 42e6;

  /* ========== TOGGLING ========== */

  function test_shares_pause_can_be_turned_on_and_off() public {
    assertFalse(poolFactoryProxy.pausedPools(address(fund)));

    _setPaused({_pauseShares: true, _pauseTrading: false});
    assertTrue(poolFactoryProxy.pausedPools(address(fund)));

    _setPaused({_pauseShares: false, _pauseTrading: false});
    assertFalse(poolFactoryProxy.pausedPools(address(fund)));
  }

  function test_trading_pause_can_be_turned_on_and_off() public {
    assertFalse(poolFactoryProxy.tradingPausedPools(address(fund)));

    _setPaused({_pauseShares: false, _pauseTrading: true});
    assertTrue(poolFactoryProxy.tradingPausedPools(address(fund)));

    _setPaused({_pauseShares: false, _pauseTrading: false});
    assertFalse(poolFactoryProxy.tradingPausedPools(address(fund)));
  }

  function test_the_two_pauses_are_independent() public {
    _setPaused({_pauseShares: true, _pauseTrading: false});
    assertTrue(poolFactoryProxy.pausedPools(address(fund)));
    assertFalse(poolFactoryProxy.tradingPausedPools(address(fund)));

    _setPaused({_pauseShares: false, _pauseTrading: true});
    assertFalse(poolFactoryProxy.pausedPools(address(fund)));
    assertTrue(poolFactoryProxy.tradingPausedPools(address(fund)));
  }

  /* ========== SHARES PAUSED ========== */

  function test_revert_deposit_when_shares_are_paused() public {
    _setPaused({_pauseShares: true, _pauseTrading: false});

    vm.prank(investor);
    vm.expectRevert(bytes("dh2"));
    fund.deposit(address(usdc), DEPOSIT_AMOUNT);
  }

  function test_revert_withdraw_when_shares_are_paused() public {
    uint256 shares = _depositAndClearLockup();
    _setPaused({_pauseShares: true, _pauseTrading: false});

    vm.prank(investor);
    vm.expectRevert(bytes("dh2"));
    fund.withdraw(shares);
  }

  function test_revert_withdrawTo_when_shares_are_paused() public {
    uint256 shares = _depositAndClearLockup();
    _setPaused({_pauseShares: true, _pauseTrading: false});

    vm.prank(investor);
    vm.expectRevert(bytes("dh2"));
    fund.withdrawTo(investor, shares);
  }

  function test_revert_transfer_when_shares_are_paused() public {
    uint256 shares = _depositAndClearLockup();
    _setPaused({_pauseShares: true, _pauseTrading: false});

    vm.prank(investor);
    vm.expectRevert(bytes("dh2"));
    fund.transfer(otherInvestor, shares);
  }

  function test_revert_transferFrom_when_shares_are_paused() public {
    uint256 shares = _depositAndClearLockup();
    vm.prank(investor);
    fund.approve(address(this), shares);

    _setPaused({_pauseShares: true, _pauseTrading: false});

    vm.expectRevert(bytes("dh2"));
    fund.transferFrom(investor, otherInvestor, shares);
  }

  function test_revert_mintManagerFee_when_shares_are_paused() public {
    _setPaused({_pauseShares: true, _pauseTrading: false});

    vm.expectRevert(bytes("dh2"));
    fund.mintManagerFee();
  }

  function test_trading_still_reaches_the_guards_when_shares_are_paused() public {
    _setPaused({_pauseShares: true, _pauseTrading: false});

    // "dh23" is the guard declining the call, not the pause rejecting it - a trading pause would
    // have stopped the transaction earlier with "dh20".
    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    fund.execTransaction(address(usdc), abi.encodeWithSelector(IERC20.transfer.selector, address(fund), 1));
  }

  /* ========== TRADING PAUSED ========== */

  function test_revert_execTransaction_when_trading_is_paused() public {
    _setPaused({_pauseShares: false, _pauseTrading: true});

    vm.prank(manager);
    vm.expectRevert(bytes("dh20"));
    fund.execTransaction(address(0), "");
  }

  function test_revert_execTransactions_when_trading_is_paused() public {
    _setPaused({_pauseShares: false, _pauseTrading: true});

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](1);
    txs[0] = PoolLogic.TxToExecute({to: address(0), data: ""});

    vm.prank(manager);
    vm.expectRevert(bytes("dh20"));
    fund.execTransactions(txs);
  }

  function test_deposit_is_allowed_when_only_trading_is_paused() public {
    _setPaused({_pauseShares: false, _pauseTrading: true});

    uint256 shares = _deposit(investor, address(usdc), DEPOSIT_AMOUNT);

    assertGt(shares, 0);
    assertEq(fund.balanceOf(investor), shares);
  }

  function test_withdraw_is_allowed_when_only_trading_is_paused() public {
    uint256 shares = _depositAndClearLockup();
    _setPaused({_pauseShares: false, _pauseTrading: true});

    _withdraw(investor, shares);

    assertEq(fund.balanceOf(investor), 0);
  }

  function test_transfer_is_allowed_when_only_trading_is_paused() public {
    uint256 shares = _depositAndClearLockup();
    _setPaused({_pauseShares: false, _pauseTrading: true});

    vm.prank(investor);
    fund.transfer(otherInvestor, shares);

    assertEq(fund.balanceOf(otherInvestor), shares);
  }

  function test_mintManagerFee_is_allowed_when_only_trading_is_paused() public {
    _setPaused({_pauseShares: false, _pauseTrading: true});

    fund.mintManagerFee();
  }

  /* ========== HELPERS ========== */

  function _setPaused(bool _pauseShares, bool _pauseTrading) internal {
    PoolFactory.PoolPausedInput[] memory pools = new PoolFactory.PoolPausedInput[](1);
    pools[0] = PoolFactory.PoolPausedInput({
      pool: address(fund),
      pauseShares: _pauseShares,
      pauseTrading: _pauseTrading
    });

    vm.prank(owner);
    poolFactoryProxy.setPoolsPaused(pools);
  }

  function _depositAndClearLockup() internal returns (uint256 shares) {
    shares = _deposit(investor, address(usdc), DEPOSIT_AMOUNT);
    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);
  }
}
