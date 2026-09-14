// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice `PoolFactory` registry duties: tracking the pools it spawned, who manages and who is
/// invested in each, the custom cooldown whitelist, and the per-pool minimum deposit.
contract PoolFactoryTest is PoolUnitTestSetup {
  address internal otherManager = makeAddr("otherManager");

  /* ========== IMPLEMENTATION LOGIC ========== */

  function test_owner_can_point_the_factory_at_new_implementations() public {
    address newPoolLogic = address(new PoolLogic());
    address newPoolManagerLogic = address(new PoolManagerLogic());

    vm.prank(owner);
    poolFactoryProxy.setLogic(newPoolLogic, newPoolManagerLogic);

    assertEq(poolFactoryProxy.getLogic(1), newPoolManagerLogic);
    assertEq(poolFactoryProxy.getLogic(2), newPoolLogic);
  }

  function test_revert_setLogic_when_not_owner() public {
    // Deployed up front: `new` in argument position would consume the prank.
    address newPoolLogic = address(new PoolLogic());
    address newPoolManagerLogic = address(new PoolManagerLogic());

    vm.prank(manager);
    vm.expectRevert("Ownable: caller is not the owner");
    poolFactoryProxy.setLogic(newPoolLogic, newPoolManagerLogic);
  }

  /* ========== CREATE FUND VALIDATION ========== */

  function test_revert_createFund_with_a_manager_fee_above_the_cap() public {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});

    // The factory caps the performance fee at 50%.
    vm.prank(otherManager);
    vm.expectRevert("invalid manager fee");
    poolFactoryProxy.createFund({
      _privatePool: false,
      _manager: otherManager,
      _managerName: "Other Manager",
      _fundName: "Too Greedy",
      _fundSymbol: "GREED",
      _performanceFeeNumerator: 6_000,
      _managerFeeNumerator: 200,
      _entryFeeNumerator: 0,
      _exitFeeNum: 0,
      _supportedAssets: supportedAssets
    });
  }

  function test_created_fund_reports_its_manager_and_fees() public {
    address newPool = _createFund(otherManager);
    PoolManagerLogic newPoolManagerLogic = PoolManagerLogic(PoolLogic(newPool).poolManagerLogic());

    assertEq(newPoolManagerLogic.manager(), otherManager);
    assertEq(newPoolManagerLogic.poolLogic(), newPool);
    assertEq(PoolLogic(newPool).factory(), address(poolFactoryProxy));
  }

  /* ========== POOL REGISTRY ========== */

  function test_factory_tracks_the_pools_it_deploys() public {
    address[] memory deployedBefore = poolFactoryProxy.getDeployedFunds();

    address newPool = _createFund(otherManager);

    address[] memory deployedAfter = poolFactoryProxy.getDeployedFunds();
    assertEq(deployedAfter.length, deployedBefore.length + 1);
    assertEq(deployedAfter[deployedAfter.length - 1], newPool);
    assertTrue(poolFactoryProxy.isPool(newPool));
  }

  function test_an_arbitrary_address_is_not_a_pool() public view {
    assertFalse(poolFactoryProxy.isPool(investor));
  }

  function test_managed_pools_are_listed_per_manager() public {
    address newPool = _createFund(otherManager);

    address[] memory managedByManager = poolFactoryProxy.getManagedPools(manager);
    assertEq(managedByManager.length, 1);
    assertEq(managedByManager[0], address(fund));

    address[] memory managedByOther = poolFactoryProxy.getManagedPools(otherManager);
    assertEq(managedByOther.length, 1);
    assertEq(managedByOther[0], newPool);
  }

  function test_invested_pools_follow_the_depositor() public {
    assertEq(poolFactoryProxy.getInvestedPools(investor).length, 0);

    _deposit(investor, address(usdc), 100e6);

    address[] memory invested = poolFactoryProxy.getInvestedPools(investor);
    assertEq(invested.length, 1);
    assertEq(invested[0], address(fund));
  }

  /* ========== CUSTOM COOLDOWN WHITELIST ========== */

  function test_revert_addCustomCooldownWhitelist_when_not_owner() public {
    vm.prank(manager);
    vm.expectRevert("Ownable: caller is not the owner");
    poolFactoryProxy.addCustomCooldownWhitelist(investor);
  }

  function test_revert_removeCustomCooldownWhitelist_when_not_owner() public {
    vm.prank(manager);
    vm.expectRevert("Ownable: caller is not the owner");
    poolFactoryProxy.removeCustomCooldownWhitelist(investor);
  }

  function test_owner_can_add_and_remove_from_the_custom_cooldown_whitelist() public {
    vm.startPrank(owner);

    poolFactoryProxy.addCustomCooldownWhitelist(investor);
    assertTrue(poolFactoryProxy.customCooldownWhitelist(investor));

    poolFactoryProxy.removeCustomCooldownWhitelist(investor);
    assertFalse(poolFactoryProxy.customCooldownWhitelist(investor));

    vm.stopPrank();
  }

  /* ========== MINIMUM DEPOSIT ========== */

  function test_revert_setMinDepositUSD_when_not_manager() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.setMinDepositUSD(100e18);
  }

  function test_revert_deposit_below_the_minimum() public {
    vm.prank(manager);
    fundManagerLogic.setMinDepositUSD(100e18); // $100

    // USDC is priced at $1, so $99 worth is under the floor.
    vm.prank(investor);
    vm.expectRevert(bytes("dh25"));
    fund.deposit(address(usdc), 99e6);
  }

  function test_deposit_at_or_above_the_minimum_is_accepted() public {
    vm.prank(manager);
    fundManagerLogic.setMinDepositUSD(100e18);

    uint256 shares = _deposit(investor, address(usdc), 100e6);

    assertGt(shares, 0);
  }

  function test_minimum_deposit_is_measured_in_usd_not_token_amount() public {
    vm.prank(manager);
    fundManagerLogic.setMinDepositUSD(100e18);

    // WETH is priced at $2000, so a twentieth of one clears a $100 floor.
    uint256 shares = _deposit(investor, address(weth), 0.05e18);

    assertGt(shares, 0);
  }

  /* ========== HELPERS ========== */

  function _createFund(address _manager) internal returns (address newPool) {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});

    vm.prank(_manager);
    newPool = poolFactoryProxy.createFund({
      _privatePool: false,
      _manager: _manager,
      _managerName: "Other Manager",
      _fundName: "Other Fund",
      _fundSymbol: "OTH",
      _performanceFeeNumerator: 0,
      _managerFeeNumerator: 0,
      _entryFeeNumerator: 0,
      _exitFeeNum: 0,
      _supportedAssets: supportedAssets
    });
  }
}
