// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {VelodromeV2TestSetup} from "test/integration/common/velodromeV2/VelodromeV2TestSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";

/// @notice Optimism's live Velodrome V2 deployment, shared by the guard test leaves.
library VelodromeV2OptimismConfig {
  uint256 internal constant FORK_BLOCK_NUMBER = 128000000;

  address internal constant VOTER = 0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C;

  function config() internal pure returns (VelodromeV2TestSetup.VelodromeV2Config memory) {
    return
      VelodromeV2TestSetup.VelodromeV2Config({
        router: OptimismConfig.VELODROME_V2_ROUTER,
        voter: VOTER,
        // The live pools are quoted in bridged USDC.e, not native USDC.
        poolStable: OptimismConfig.USDCe,
        poolStableOracle: OptimismConfig.USDC_CHAINLINK_ORACLE,
        stablePool: OptimismConfig.VELODROME_V2_STABLE_USDC_DAI_POOL,
        variablePool: OptimismConfig.VELODROME_V2_VARIABLE_WETH_USDC_POOL
      });
  }
}
