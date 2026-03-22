// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract MaxSupplyCapTestSetup is BackboneSetup {
  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;

  function setUp() public virtual override {
    super.setUp();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Test Vault",
        _fundSymbol: "TV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());
  }

  function test_can_set_max_supply_cap() public {
    uint256 supplyCap = 1000e18; // 1000 tokens

    assertEq(testPoolManagerLogic.maxSupplyCap(), 0);

    vm.expectEmit(false, false, false, true);
    emit MaxSupplyCapSet(supplyCap);

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    assertEq(testPoolManagerLogic.maxSupplyCap(), supplyCap);
  }

  function test_trader_can_set_max_supply_cap() public {
    uint256 supplyCap = 1000e18; // 1000 tokens

    address trader = makeAddr("trader");

    vm.prank(manager);
    testPoolManagerLogic.setTrader(trader);

    vm.prank(trader);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    assertEq(testPoolManagerLogic.maxSupplyCap(), supplyCap);
  }

  function test_revert_set_max_supply_cap_when_below_total_supply() public {
    uint256 depositAmount = 1000e6; // 1000 USDC

    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 capBelowSupply = 500e18; // 500 tokens

    vm.prank(manager);
    vm.expectRevert(bytes("invalid supply cap"));
    testPoolManagerLogic.setMaxSupplyCap(capBelowSupply);
  }

  function test_revert_set_max_supply_cap_when_not_manager() public {
    uint256 supplyCap = 1000e18;

    vm.prank(investor);
    vm.expectRevert(bytes("only manager or trader"));
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    assertEq(testPoolManagerLogic.maxSupplyCap(), 0);
  }

  function test_deposit_with_no_cap_set() public {
    uint256 depositAmount = 1000e6; // 1000 USDC

    assertEq(testPoolManagerLogic.maxSupplyCap(), 0);

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    assertGt(liquidityMinted, 0);
    assertEq(testPool.balanceOf(investor), liquidityMinted);
  }

  function test_deposit_within_cap() public {
    uint256 supplyCap = 1000e18; // 1000 tokens cap
    uint256 depositAmount = 100e6; // 100 USDC (much smaller deposit)

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    assertGt(liquidityMinted, 0);
    assertEq(testPool.balanceOf(investor), liquidityMinted);
    assertLt(testPool.totalSupply(), supplyCap);
  }

  function test_deposit_exceeding_cap() public {
    uint256 supplyCap = 100e18; // Small supply cap: 100 tokens
    uint256 largeDepositAmount = 10000e6; // Very large deposit: 10,000 USDC

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    deal(usdcData.asset, investor, largeDepositAmount);

    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), largeDepositAmount);

    vm.expectRevert(bytes("dh32"));
    testPool.deposit(usdcData.asset, largeDepositAmount);

    vm.stopPrank();

    assertEq(testPool.balanceOf(investor), 0);
  }

  function test_multiple_deposits_reaching_cap() public {
    uint256 supplyCap = 500e18; // 500 tokens cap
    uint256 depositAmount = 200e6; // 200 USDC each

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    // First deposit - should succeed
    uint256 liquidity1 = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);
    assertGt(liquidity1, 0);
    assertLt(testPool.totalSupply(), supplyCap);

    // Second deposit - should succeed
    uint256 liquidity2 = _makeDeposit(testPool, owner, usdcData.asset, depositAmount);
    assertGt(liquidity2, 0);
    assertLt(testPool.totalSupply(), supplyCap);

    // Third deposit - exceed cap
    deal(usdcData.asset, manager, depositAmount);
    vm.startPrank(manager);
    IERC20(usdcData.asset).approve(address(testPool), depositAmount);

    vm.expectRevert(bytes("dh32"));
    testPool.deposit(usdcData.asset, depositAmount);

    vm.stopPrank();

    assertLe(testPool.totalSupply(), supplyCap);
  }

  function test_withdraw_ignores_supply_cap_when_fees_set() public {
    vm.startPrank(manager);
    testPoolManagerLogic.announceFeeIncrease(1000, 300, 100, 100); // 10% performance, 3% management, 1% entry/exit
    skip(15 days);
    testPoolManagerLogic.commitFeeIncrease();
    vm.stopPrank();

    uint256 depositAmount = 1000e6; // 1000 USDC

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    // Wait for management fees to accrue
    skip(365 days);

    uint256 capEqualToSupply = testPool.totalSupply();

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(capEqualToSupply);

    vm.startPrank(investor);
    testPool.withdrawSafe(liquidityMinted, _getEmptyPoolComplexAssetsData(address(testPool)));
  }

  function test_manager_fee_minting_ignores_supply_cap() public {
    vm.startPrank(manager);
    testPoolManagerLogic.announceFeeIncrease(1000, 300, 0, 0); // 10% performance, 3% management
    skip(15 days);
    testPoolManagerLogic.commitFeeIncrease();
    vm.stopPrank();

    uint256 depositAmount = 1000e6; // 1000 USDC

    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    // Set supply cap equal to current total supply
    uint256 currentSupply = testPool.totalSupply();
    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(currentSupply);

    // Wait for management fees to accrue
    skip(365 days);

    // Add some more assets to the pool to create performance fees
    // This simulates the pool's assets appreciating in value
    deal(usdcData.asset, address(testPool), 100e6);

    // Manager fee minting should work despite supply cap
    testPool.mintManagerFee();

    uint256 supplyAfterFeeMint = testPool.totalSupply();

    // Once fees were minted, they should exceed the cap
    assertGt(supplyAfterFeeMint, currentSupply);
  }

  function test_deposit_with_entry_fees_respects_supply_cap() public {
    uint256 supplyCap = 200e18;

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    vm.startPrank(manager);
    testPoolManagerLogic.announceFeeIncrease(0, 0, 50, 0); // 0.5% entry
    skip(15 days);
    testPoolManagerLogic.commitFeeIncrease();
    vm.stopPrank();

    uint256 depositAmount = 1000e6; // 1000 USDC

    deal(usdcData.asset, investor, depositAmount);

    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), depositAmount);

    vm.expectRevert(bytes("dh32"));
    testPool.deposit(usdcData.asset, depositAmount);

    vm.stopPrank();
  }

  function test_can_increase_supply_cap_after_deposits() public {
    uint256 initialCap = 500e18;
    uint256 newCap = 1000e18;
    uint256 depositAmount = 200e6; // 200 USDC

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(initialCap);

    // Make some deposits
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    // Increase the cap
    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(newCap);

    // Should be able to make more deposits now
    _makeDeposit(testPool, owner, usdcData.asset, depositAmount);
  }

  function test_can_decrease_supply_cap_to_current_supply() public {
    uint256 supplyCap = 2000e18; // 2000 tokens

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    uint256 depositAmount = 1000e6; // 1000 USDC

    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    // Set cap equal to current supply
    uint256 currentSupply = testPool.totalSupply();
    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(currentSupply);

    // New deposits should now fail
    deal(usdcData.asset, owner, depositAmount);
    vm.startPrank(owner);
    IERC20(usdcData.asset).approve(address(testPool), depositAmount);

    vm.expectRevert(bytes("dh32"));
    testPool.deposit(usdcData.asset, depositAmount);

    vm.stopPrank();
  }

  function test_deposit_exactly_at_supply_cap_limit() public {
    uint256 depositAmount = 1000e6; // 1000 USDC

    // Make initial deposit to establish baseline
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);
    uint256 currentSupply = testPool.totalSupply();

    // Set supply cap to allow for a small additional amount (50 tokens)
    uint256 supplyCap = currentSupply + 50e18;

    vm.prank(manager);
    testPoolManagerLogic.setMaxSupplyCap(supplyCap);

    // Make a deposit that should fit within the cap
    uint256 smallDepositAmount = 50e6;
    uint256 liquidityMinted = _makeDeposit(testPool, owner, usdcData.asset, smallDepositAmount);

    assertGt(liquidityMinted, 0);
    assertEq(testPool.totalSupply(), supplyCap);

    // Now any additional deposit should fail since we're at the cap
    uint256 largeAdditionalDeposit = 1000e6;
    deal(usdcData.asset, manager, largeAdditionalDeposit);
    vm.startPrank(manager);
    IERC20(usdcData.asset).approve(address(testPool), largeAdditionalDeposit);

    vm.expectRevert(bytes("dh32"));
    testPool.deposit(usdcData.asset, largeAdditionalDeposit);

    vm.stopPrank();
  }

  // Event definition for testing
  event MaxSupplyCapSet(uint256 maxSupplyCap);
}
