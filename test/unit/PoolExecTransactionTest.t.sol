// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {ERC20Asset} from "contracts/test/TestAssets.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice How `execTransaction` decides whether a manager's call is allowed: who may call it at
/// all, and - with no contract guard registered for the destination - the fallback to the asset
/// guard, which only lets a vault approve a spender the protocol knows.
contract PoolExecTransactionTest is PoolUnitTestSetup {
  address internal trader = makeAddr("trader");
  address internal guardedSpender = makeAddr("guardedSpender");
  address internal unknownSpender = makeAddr("unknownSpender");
  address internal someGuard = makeAddr("someGuard");

  /// @dev Known to the protocol but not on this vault's supported list.
  ERC20Asset internal unsupportedAsset;

  function setUp() public override {
    super.setUp();

    unsupportedAsset = new ERC20Asset("Unsupported", "UNS");

    vm.prank(owner);
    assetHandlerProxy.addAsset({asset: address(unsupportedAsset), assetType: 0, aggregator: usdcPriceFeed});
  }

  /* ========== WHO MAY TRADE ========== */

  function test_revert_execTransaction_when_caller_is_neither_manager_nor_trader() public {
    // Otherwise-valid call, so the caller check is what rejects it.
    _registerGuardFor(guardedSpender);

    vm.prank(investor);
    vm.expectRevert(bytes("dh24"));
    fund.execTransaction(address(usdc), _approveCalldata(guardedSpender));
  }

  function test_trader_may_trade_once_appointed() public {
    _registerGuardFor(guardedSpender);

    vm.prank(manager);
    fundManagerLogic.setTrader(trader);

    vm.prank(trader);
    fund.execTransaction(address(usdc), _approveCalldata(guardedSpender));

    assertEq(usdc.allowance(address(fund), guardedSpender), 1e6);
  }

  /* ========== DESTINATION RESOLUTION ========== */

  function test_revert_when_the_destination_is_an_asset_the_vault_does_not_support() public {
    // The approve itself is fine; the destination is the problem - a manager may only act on
    // assets their vault actually supports.
    _registerGuardFor(guardedSpender);

    vm.prank(manager);
    vm.expectRevert(bytes("dh22"));
    fund.execTransaction(address(unsupportedAsset), _approveCalldata(guardedSpender));
  }

  /* ========== APPROVALS ========== */

  function test_vault_can_approve_a_spender_the_protocol_guards() public {
    _registerGuardFor(guardedSpender);

    vm.prank(manager);
    fund.execTransaction(address(usdc), _approveCalldata(guardedSpender));

    assertEq(usdc.allowance(address(fund), guardedSpender), 1e6);
  }

  /// @dev Approving an unguarded spender would hand vault funds to something the protocol cannot
  /// constrain, so it is refused.
  function test_revert_approving_a_spender_with_no_guard() public {
    vm.prank(manager);
    vm.expectRevert("unsupported spender approval");
    fund.execTransaction(address(usdc), _approveCalldata(unknownSpender));
  }

  /* ========== HELPERS ========== */

  function _registerGuardFor(address _spender) internal {
    vm.prank(owner);
    governance.setContractGuard({extContract: _spender, guardAddress: someGuard});
  }

  function _approveCalldata(address _spender) internal pure returns (bytes memory data) {
    data = abi.encodeWithSelector(IERC20.approve.selector, _spender, 1e6);
  }
}
