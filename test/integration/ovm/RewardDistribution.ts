import { ethers } from "hardhat";
import { IDeployments, deployContracts } from "../utils/deployContracts/deployContracts";
import { ovmChainData } from "../../../config/chainData/ovmData";
import { BigNumber } from "ethers";
import { RewardDistribution } from "../../../types";
import { getAccountToken } from "../utils/getAccountTokens";
import { units } from "../../testHelpers";
import { expect } from "chai";
import { createFund } from "../utils/createFund";

describe("RewardDistribution", () => {
  let deployments: IDeployments;
  let rewardDistribution: RewardDistribution;

  before(async () => {
    deployments = await deployContracts("ovm");
    const RewardDistribution = await ethers.getContractFactory("RewardDistribution");
    rewardDistribution = await RewardDistribution.deploy(
      ovmChainData.assets.op,
      BigNumber.from(210000)
        .mul(BigNumber.from(10).pow(18))
        .div(180 * 24 * 60 * 60),
    );
    await rewardDistribution.deployed();

    const amountToFund = units(1000000);
    await getAccountToken(
      amountToFund,
      deployments.logicOwner.address,
      ovmChainData.assets.op,
      ovmChainData.assetsBalanceOfSlot.op,
    );
    expect(await deployments.assets.OP?.balanceOf(deployments.logicOwner.address)).to.be.equal(amountToFund);

    const numOfPoolsToDistribute = 8;
    const poolsForRewardDistribution: string[] = [];
    while (poolsForRewardDistribution.length < numOfPoolsToDistribute) {
      const { poolLogicProxy } = await createFund(
        deployments.poolFactory,
        deployments.logicOwner,
        deployments.manager,
        [{ isDeposit: true, asset: ovmChainData.assets.op }],
      );
      await deployments.assets.OP?.approve(poolLogicProxy.address, units(1000));
      await poolLogicProxy.deposit(ovmChainData.assets.op, units(1000));
      poolsForRewardDistribution.push(poolLogicProxy.address);
    }

    await rewardDistribution.setWhitelistedPools(poolsForRewardDistribution);

    const amount = units(210000);
    await deployments.assets.OP?.transfer(rewardDistribution.address, amount);
    expect(await deployments.assets.OP?.balanceOf(rewardDistribution.address)).to.be.equal(amount);

    await ethers.provider.send("evm_increaseTime", [86400]);
    await ethers.provider.send("evm_mine", []);
  });

  it("should distribute rewards", async () => {
    await rewardDistribution.distributeRewards();
  });
});
