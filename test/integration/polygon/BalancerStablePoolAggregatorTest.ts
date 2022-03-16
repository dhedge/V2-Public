import { ethers } from "hardhat";
import { expect } from "chai";

import { units } from "../../TestHelpers";
import { balancer } from "../../../config/chainData/polygon-data";
import { BalancerStablePoolAggregator, PoolFactory } from "../../../types";
import { deployContracts } from "../utils/deployContracts";

describe("Balancer Stable Pool Aggregator Test", function () {
  let balancerStablePoolAggregator: BalancerStablePoolAggregator;
  let poolFactory: PoolFactory;

  before(async function () {
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
  });

  it("Stable Pool - USDC, TUSD, DAI, USDT", async function () {
    const BalancerStablePoolAggregator = await ethers.getContractFactory("BalancerStablePoolAggregator");
    balancerStablePoolAggregator = await BalancerStablePoolAggregator.deploy(
      poolFactory.address,
      balancer.stablePools.BPSP_TUSD,
    );
    await balancerStablePoolAggregator.deployed();

    expect((await balancerStablePoolAggregator.latestRoundData())[1]).to.closeTo(units(1, 8), 3000000); // 3% changes
  });
});
