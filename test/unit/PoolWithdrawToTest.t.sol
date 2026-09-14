// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice `PoolLogic.withdrawTo` burns the caller's shares but routes the proceeds to a third
/// party. A single-asset $1 vault makes the payout exact.
contract PoolWithdrawToTest is PoolUnitTestSetup {
  uint256 internal constant DEPOSIT_AMOUNT = 1_000e6;

  address internal recipient = makeAddr("withdrawToRecipient");

  function test_withdrawTo_sends_proceeds_to_recipient() public {
    uint256 shares = _deposit(investor, address(usdc), DEPOSIT_AMOUNT);
    skip(EXIT_COOLDOWN + 1);

    uint256 sharesToBurn = shares / 4;
    uint256 expectedUsdcOut = (usdc.balanceOf(address(fund)) * sharesToBurn) / fund.totalSupply();
    uint256 investorUsdcBefore = usdc.balanceOf(investor);

    vm.prank(investor);
    fund.withdrawTo(recipient, sharesToBurn);

    // Shares come out of the caller; the underlying goes to the recipient, not the caller.
    assertEq(fund.balanceOf(investor), shares - sharesToBurn);
    assertEq(usdc.balanceOf(investor), investorUsdcBefore, "caller must not receive the proceeds");
    assertEq(usdc.balanceOf(recipient), expectedUsdcOut);
    assertEq(fund.balanceOf(recipient), 0, "recipient receives underlying, not shares");
  }

  function test_revert_withdrawTo_more_shares_than_owned() public {
    uint256 shares = _deposit(investor, address(usdc), DEPOSIT_AMOUNT);
    skip(EXIT_COOLDOWN + 1);

    vm.prank(investor);
    vm.expectRevert(bytes("dh12"));
    fund.withdrawTo(recipient, shares + 1);
  }
}
