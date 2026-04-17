// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {HyperliquidCoreWriterContractGuard} from "contracts/guards/contractGuards/hyperliquid/HyperliquidCoreWriterContractGuard.sol";
import {IHyperliquidCoreWriterContractGuard} from "contracts/interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";
import {ISafe} from "contracts/interfaces/ISafe.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";

interface IProxyAdmin {
  function upgrade(address proxy, address implementation) external;
  function owner() external view returns (address);
}

contract SafeSignerAccessTest is Test {
  address public constant GUARD_PROXY = 0x69bAd630798814588Ed024F9DFf3Aac1bC3533D2;

  IHyperliquidCoreWriterContractGuard public guard;
  address public safeOwner;
  address public safeMultisig;

  function setUp() public {
    vm.createSelectFork("hyperevm", 32341732);

    guard = IHyperliquidCoreWriterContractGuard(GUARD_PROXY);

    // The guard's owner is the Safe multisig.
    safeMultisig = HyperliquidCoreWriterContractGuard(GUARD_PROXY).owner();
    require(safeMultisig != address(0), "owner is zero");

    // Get an actual Safe owner.
    address[] memory owners = ISafe(safeMultisig).getOwners();
    require(owners.length > 0, "no Safe owners");
    safeOwner = owners[0];

    // Deploy new implementation with SafeSignerAccess and upgrade.
    HyperliquidCoreWriterContractGuard newImpl = new HyperliquidCoreWriterContractGuard();

    address proxyAdminOwner = IProxyAdmin(HyperEVMConfig.PROXY_ADMIN).owner();
    vm.prank(proxyAdminOwner);
    IProxyAdmin(HyperEVMConfig.PROXY_ADMIN).upgrade(GUARD_PROXY, address(newImpl));
  }

  function test_safe_owner_can_call_setDhedgePoolsWhitelist() public {
    address testPool = makeAddr("testPool");

    // Safe owner (not the Safe itself) should be able to call.
    vm.prank(safeOwner);
    IHyperliquidCoreWriterContractGuard.WhitelistSetting[]
      memory settings = new IHyperliquidCoreWriterContractGuard.WhitelistSetting[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.WhitelistSetting({poolLogic: testPool, whitelisted: true});
    guard.setDhedgePoolsWhitelist(settings);

    assertTrue(guard.dHedgePoolsWhitelist(testPool));
  }

  function test_safe_multisig_can_call_setDhedgePoolsWhitelist() public {
    address testPool = makeAddr("testPool");

    // The Safe itself (contract owner) should also be able to call.
    vm.prank(safeMultisig);
    IHyperliquidCoreWriterContractGuard.WhitelistSetting[]
      memory settings = new IHyperliquidCoreWriterContractGuard.WhitelistSetting[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.WhitelistSetting({poolLogic: testPool, whitelisted: true});
    guard.setDhedgePoolsWhitelist(settings);

    assertTrue(guard.dHedgePoolsWhitelist(testPool));
  }

  function test_revert_random_address_cannot_call_setDhedgePoolsWhitelist() public {
    address randomCaller = makeAddr("randomCaller");
    address testPool = makeAddr("testPool");

    // Ensure the random address is NOT a Safe owner.
    assertFalse(ISafe(safeMultisig).isOwner(randomCaller));

    IHyperliquidCoreWriterContractGuard.WhitelistSetting[]
      memory settings = new IHyperliquidCoreWriterContractGuard.WhitelistSetting[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.WhitelistSetting({poolLogic: testPool, whitelisted: true});

    vm.prank(randomCaller);
    vm.expectRevert("not owner or Safe owner");
    guard.setDhedgePoolsWhitelist(settings);
  }
}
