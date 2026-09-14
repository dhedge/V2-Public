// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {VelodromeV2RouterGuardTestSetup} from "test/integration/common/velodromeV2/VelodromeV2RouterGuardTestSetup.t.sol";
// solhint-disable-next-line max-line-length
import {VelodromeV2GaugeGuardTestSetup} from "test/integration/common/velodromeV2/VelodromeV2GaugeGuardTestSetup.t.sol";
// solhint-disable-next-line max-line-length
import {VelodromeV2LPAssetGuardTestSetup} from "test/integration/common/velodromeV2/VelodromeV2LPAssetGuardTestSetup.t.sol";
import {VelodromeV2TestSetup} from "test/integration/common/velodromeV2/VelodromeV2TestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {VelodromeV2OptimismConfig} from "test/integration/ovm/velodromeV2/VelodromeV2OptimismConfig.sol";

/// @notice Runs the router, gauge and LP asset guard suites for Velodrome V2 against one Optimism
/// fork - they share a single fixture, so they compose into one runner.
contract VelodromeV2TestOptimism is
  VelodromeV2RouterGuardTestSetup,
  VelodromeV2GaugeGuardTestSetup,
  VelodromeV2LPAssetGuardTestSetup,
  OptimismSetup
{
  constructor()
    VelodromeV2TestSetup(VelodromeV2OptimismConfig.config())
    OptimismSetup(VelodromeV2OptimismConfig.FORK_BLOCK_NUMBER)
  {}

  function setUp() public override(VelodromeV2TestSetup, OptimismSetup) {
    super.setUp();
  }
}
