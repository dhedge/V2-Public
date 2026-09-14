// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {VelodromeCLPositionGuardTestSetup} from "test/integration/common/velodromeCL/VelodromeCLPositionGuardTestSetup.t.sol";
import {VelodromeCLGaugeGuardTestSetup} from "test/integration/common/velodromeCL/VelodromeCLGaugeGuardTestSetup.t.sol";
import {VelodromeCLAssetGuardTestSetup} from "test/integration/common/velodromeCL/VelodromeCLAssetGuardTestSetup.t.sol";
import {VelodromeCLTestSetup} from "test/integration/common/velodromeCL/VelodromeCLTestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {VelodromeCLOptimismConfig} from "test/integration/ovm/velodromeCL/VelodromeCLOptimismConfig.sol";

/// @notice Runs the position, gauge and asset guard suites for Velodrome CL against one Optimism
/// fork - they share a single fixture, so they compose into one runner.
contract VelodromeCLTestOptimism is
  VelodromeCLPositionGuardTestSetup,
  VelodromeCLGaugeGuardTestSetup,
  VelodromeCLAssetGuardTestSetup,
  OptimismSetup
{
  constructor()
    VelodromeCLTestSetup(VelodromeCLOptimismConfig.config())
    OptimismSetup(VelodromeCLOptimismConfig.FORK_BLOCK_NUMBER)
  {}

  function setUp() public override(VelodromeCLTestSetup, OptimismSetup) {
    super.setUp();
  }
}
