// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {VelodromeAggregatorsTestSetup} from "test/integration/common/velodromeV2/VelodromeAggregatorsTestSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {VelodromeV2OptimismConfig} from "test/integration/ovm/velodromeV2/VelodromeV2OptimismConfig.sol";

contract VelodromeAggregatorsTestOptimism is VelodromeAggregatorsTestSetup {
  constructor()
    VelodromeAggregatorsTestSetup(
      VelodromeAggregatorsTestSetup.TestParams({
        router: OptimismConfig.VELODROME_V2_ROUTER,
        factory: OptimismConfig.VELODROME_V2_FACTORY,
        // The live factory already prices USDC.e, DAI and WETH.
        dhedgeFactory: OptimismConfig.POOL_FACTORY_PROD,
        stablePool: OptimismConfig.VELODROME_V2_STABLE_USDC_DAI_POOL,
        variablePool: OptimismConfig.VELODROME_V2_VARIABLE_WETH_USDC_POOL,
        // Both live pools are quoted in bridged USDC.e rather than native USDC.
        usdc: OptimismConfig.USDCe,
        dai: OptimismConfig.DAI,
        weth: OptimismConfig.WETH,
        usdcOracle: OptimismConfig.USDC_CHAINLINK_ORACLE
      })
    )
  {}

  function setUp() public override {
    vm.createSelectFork("optimism", VelodromeV2OptimismConfig.FORK_BLOCK_NUMBER);

    super.setUp();
  }
}
