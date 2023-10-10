import { assert } from "chai";
import { IBalancerWeightedPool } from "../../../../types";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { deployBalancerAssets } from "../balancer/deploymentTestHelpers";

describe("BalancerV2LPAggregator Test", () => {
  let deployments: IBackboneDeployments;
  let wstETH_USDC_WEIGHTED_POOL: IBalancerWeightedPool;

  before(async () => {
    deployments = await deployBackboneContracts(arbitrumChainData);
    const balancerAssets = await deployBalancerAssets(deployments);
    wstETH_USDC_WEIGHTED_POOL = balancerAssets.wstETH_USDC_WEIGHTED_POOL;
  });

  it("should be able to price weighted balancer pool", async () => {
    const result = await deployments.poolFactory.getAssetPrice(wstETH_USDC_WEIGHTED_POOL.address);
    assert(result);
  });
});
