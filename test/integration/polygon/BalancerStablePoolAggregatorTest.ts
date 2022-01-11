import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { units } from "../../TestHelpers";
import { balancer } from "../../../config/chainData/polygon-data";
import { BalancerStablePoolAggregator, PoolFactory } from "../../../types";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";

use(solidity);

describe("Balancer Stable Pool Aggregator Test", function () {
  let logicOwner: SignerWithAddress, other: SignerWithAddress;
  let balancerStablePoolAggregator: BalancerStablePoolAggregator;
  let poolFactory: PoolFactory;

  before(async function () {
    const deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
  });

  it("Stable Pool - USDC, TUSD, DAI, USDT", async function () {
    [logicOwner, other] = await ethers.getSigners();
    const BalancerStablePoolAggregator = await ethers.getContractFactory("BalancerStablePoolAggregator");
    balancerStablePoolAggregator = await BalancerStablePoolAggregator.deploy(
      poolFactory.address,
      balancer.v2Vault,
      balancer.stablePools.stablePool.pool,
      balancer.stablePools.stablePool.tokens,
      balancer.stablePools.stablePool.decimals,
    );
    await balancerStablePoolAggregator.deployed();

    expect((await balancerStablePoolAggregator.latestRoundData())[1]).to.closeTo(units(1, 8), 3000000); // 3% changes
  });
});
