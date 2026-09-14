// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice Who may call `PoolManagerLogic.changeAssets`: the owner, the manager and - unless the
/// manager has switched it off - the trader.
contract PoolChangeAssetsTest is PoolUnitTestSetup {
  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;

  address private trader = makeAddr("trader");

  function setUp() public override {
    super.setUp();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: address(weth), isDeposit: false});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "ChangeAssetsTest",
        _fundSymbol: "CAT",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());
  }

  function test_revert_changeAssets_when_unauthorized() public {
    _assertSupportedAssets(2);

    vm.prank(trader); // not set as the fund's trader
    vm.expectRevert("only manager, owner or trader enabled");
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(weth)));

    _assertSupportedAssets(2);
  }

  function test_owner_can_changeAssets() public {
    vm.prank(owner);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(weth)));

    _assertSupportedAssets(1);
  }

  function test_manager_can_changeAssets() public {
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(weth)));

    _assertSupportedAssets(1);
  }

  function test_trader_can_changeAssets_by_default() public {
    vm.prank(manager);
    testPoolManagerLogic.setTrader(trader);

    vm.prank(trader);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(weth)));

    _assertSupportedAssets(1);
  }

  function test_revert_trader_changeAssets_when_disabled_by_manager() public {
    vm.startPrank(manager);
    testPoolManagerLogic.setTrader(trader);
    testPoolManagerLogic.setTraderAssetChangeDisabled(true);
    vm.stopPrank();

    vm.prank(trader);
    vm.expectRevert("only manager, owner or trader enabled");
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(weth)));

    _assertSupportedAssets(2);
  }

  function test_revert_setTraderAssetChangeDisabled_when_not_manager() public {
    vm.prank(manager);
    testPoolManagerLogic.setTrader(trader);

    // Owner is allowed to change assets but not to change the trader's rights.
    vm.prank(owner);
    vm.expectRevert(bytes("dh4"));
    testPoolManagerLogic.setTraderAssetChangeDisabled(true);
  }

  function _assertSupportedAssets(uint256 _expectedCount) internal view {
    IHasSupportedAsset.Asset[] memory supportedAssets = testPoolManagerLogic.getSupportedAssets();
    assertEq(supportedAssets.length, _expectedCount);
    assertEq(supportedAssets[0].asset, address(usdc));
    if (_expectedCount == 2) {
      assertEq(supportedAssets[1].asset, address(weth));
    }
  }
}
