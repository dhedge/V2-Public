// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {PoolFactory} from "contracts/PoolFactory.sol";
import {ISafe} from "contracts/interfaces/ISafe.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import {DeploymentDryRunTest} from "test/integration/utils/foundry/DeploymentDryRunTest.t.sol";

abstract contract SafeSignerPauseTest is DeploymentDryRunTest {
  address public safeMultisig;
  address public safeSigner;

  function setUp() public virtual override {
    super.setUp();

    safeMultisig = poolFactory.owner();
    require(safeMultisig != address(0), "owner is zero");

    // Get an actual Safe signer from the production multisig.
    address[] memory owners = ISafe(safeMultisig).getOwners();
    require(owners.length > 0, "no Safe owners");
    safeSigner = owners[0];

    // Deploy new PoolFactory implementation with SafeSignerAccess and upgrade.
    PoolFactory newImpl = new PoolFactory();
    address proxyAdminOwner = proxyAdmin.owner();
    vm.prank(proxyAdminOwner);
    proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(poolFactory))), address(newImpl));
  }

  function _getPool() internal returns (address) {
    address[] memory funds = poolFactory.getDeployedFunds();
    if (funds.length == 0) {
      vm.skip(true);
    }
    return funds[0];
  }

  // --- pause() ---

  function test_safe_signer_can_pause() public {
    vm.prank(safeSigner);
    poolFactory.pause();
    assertTrue(poolFactory.isPaused());
  }

  function test_owner_can_pause() public {
    vm.prank(safeMultisig);
    poolFactory.pause();
    assertTrue(poolFactory.isPaused());
  }

  function test_random_address_cannot_pause() public {
    address random = makeAddr("random");
    assertFalse(ISafe(safeMultisig).isOwner(random));

    vm.prank(random);
    vm.expectRevert("not owner or Safe owner");
    poolFactory.pause();
  }

  // --- unpause() ---

  function test_safe_signer_cannot_unpause() public {
    vm.prank(safeMultisig);
    poolFactory.pause();
    assertTrue(poolFactory.isPaused());

    vm.prank(safeSigner);
    vm.expectRevert("Ownable: caller is not the owner");
    poolFactory.unpause();
  }

  function test_owner_can_unpause() public {
    vm.prank(safeMultisig);
    poolFactory.pause();
    assertTrue(poolFactory.isPaused());

    vm.prank(safeMultisig);
    poolFactory.unpause();
    assertFalse(poolFactory.isPaused());
  }

  // --- setPoolsPaused() ---

  function test_safe_signer_can_setPoolsPaused_pause_only() public {
    address pool = _getPool();

    PoolFactory.PoolPausedInput[] memory inputs = new PoolFactory.PoolPausedInput[](1);
    inputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: true, pauseTrading: true});

    vm.prank(safeSigner);
    poolFactory.setPoolsPaused(inputs);

    assertTrue(poolFactory.pausedPools(pool));
    assertTrue(poolFactory.tradingPausedPools(pool));
  }

  function test_safe_signer_cannot_setPoolsPaused_unpause_shares() public {
    address pool = _getPool();

    // First, pause the pool via owner.
    PoolFactory.PoolPausedInput[] memory pauseInputs = new PoolFactory.PoolPausedInput[](1);
    pauseInputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: true, pauseTrading: true});
    vm.prank(safeMultisig);
    poolFactory.setPoolsPaused(pauseInputs);

    // Signer tries to unpause shares -> should revert.
    PoolFactory.PoolPausedInput[] memory unpauseInputs = new PoolFactory.PoolPausedInput[](1);
    unpauseInputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: false, pauseTrading: true});
    vm.prank(safeSigner);
    vm.expectRevert("signers can only pause");
    poolFactory.setPoolsPaused(unpauseInputs);
  }

  function test_safe_signer_cannot_setPoolsPaused_unpause_trading() public {
    address pool = _getPool();

    // First, pause the pool via owner.
    PoolFactory.PoolPausedInput[] memory pauseInputs = new PoolFactory.PoolPausedInput[](1);
    pauseInputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: true, pauseTrading: true});
    vm.prank(safeMultisig);
    poolFactory.setPoolsPaused(pauseInputs);

    // Signer tries to unpause trading -> should revert.
    PoolFactory.PoolPausedInput[] memory unpauseInputs = new PoolFactory.PoolPausedInput[](1);
    unpauseInputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: true, pauseTrading: false});
    vm.prank(safeSigner);
    vm.expectRevert("signers can only pause");
    poolFactory.setPoolsPaused(unpauseInputs);
  }

  function test_owner_can_setPoolsPaused_unpause() public {
    address pool = _getPool();

    // Pause the pool via owner.
    PoolFactory.PoolPausedInput[] memory pauseInputs = new PoolFactory.PoolPausedInput[](1);
    pauseInputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: true, pauseTrading: true});
    vm.prank(safeMultisig);
    poolFactory.setPoolsPaused(pauseInputs);
    assertTrue(poolFactory.pausedPools(pool));

    // Owner can unpause.
    PoolFactory.PoolPausedInput[] memory unpauseInputs = new PoolFactory.PoolPausedInput[](1);
    unpauseInputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: false, pauseTrading: false});
    vm.prank(safeMultisig);
    poolFactory.setPoolsPaused(unpauseInputs);
    assertFalse(poolFactory.pausedPools(pool));
    assertFalse(poolFactory.tradingPausedPools(pool));
  }

  function test_random_address_cannot_setPoolsPaused() public {
    address pool = _getPool();
    address random = makeAddr("random");

    PoolFactory.PoolPausedInput[] memory inputs = new PoolFactory.PoolPausedInput[](1);
    inputs[0] = PoolFactory.PoolPausedInput({pool: pool, pauseShares: true, pauseTrading: true});

    vm.prank(random);
    vm.expectRevert("not owner or Safe owner");
    poolFactory.setPoolsPaused(inputs);
  }
}
