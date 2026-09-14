// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {VelodromeCLTestSetup} from "test/integration/common/velodromeCL/VelodromeCLTestSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";

/// @notice Optimism's live Velodrome CL deployment, shared by the CL guard test leaves.
library VelodromeCLOptimismConfig {
  uint256 internal constant FORK_BLOCK_NUMBER = 128000000;

  address internal constant NFT_POSITION_MANAGER = 0x416b433906b1B72FA758e166e239c43d68dC6F29;
  address internal constant CL_FACTORY = 0xCc0bDDB707055e04e497aB22a59c2aF4391cd12F;
  /// @dev USDC/WETH tick spacing 100.
  address internal constant USDC_WETH_GAUGE = 0xa75127121d28a9BF848F3B70e7Eea26570aa7700;

  function config() internal pure returns (VelodromeCLTestSetup.VelodromeCLConfig memory) {
    return
      VelodromeCLTestSetup.VelodromeCLConfig({
        nonfungiblePositionManager: NFT_POSITION_MANAGER,
        clFactory: CL_FACTORY,
        protocolToken: OptimismConfig.VELO,
        protocolTokenOracle: OptimismConfig.VELO_CHAINLINK_ORACLE,
        token0: OptimismConfig.USDC,
        token1: OptimismConfig.WETH,
        token0Oracle: OptimismConfig.USDC_CHAINLINK_ORACLE,
        token1Oracle: OptimismConfig.WETH_CHAINLINK_ORACLE,
        tickSpacing: 100,
        gauge: USDC_WETH_GAUGE,
        amount0: 2_000e6,
        amount1: 1e18
      });
  }
}
