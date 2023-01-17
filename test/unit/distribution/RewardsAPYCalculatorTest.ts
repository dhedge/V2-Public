import { expect } from "chai";
import { ethers } from "hardhat";

import { units } from "../../TestHelpers";
import { RewardsAPYCalculatorTest } from "../../../types";

describe("RewardsAPYCalculator Tests", () => {
  let rewardsAPYCalculator: RewardsAPYCalculatorTest;

  beforeEach(async () => {
    const RewardsAPYCalculator = await ethers.getContractFactory("RewardsAPYCalculatorTest");
    rewardsAPYCalculator = await RewardsAPYCalculator.deploy();
  });

  it("should calculate apy correctly with simple inputs", async () => {
    const apy = 1; // 100%
    const totalValue = units(315_360_000); // 315,360,000.00$
    const totalRewards = totalValue.mul(apy); // 315,360,000.00$
    const yearInSeconds = 60 * 60 * 24 * 365; // 31,536,000 seconds
    const rewardsPerSecond = totalRewards.div(yearInSeconds); // 1 token
    const rewardTokenPrice = units(1); // 1$
    expect(await rewardsAPYCalculator.calculateAPY(totalValue, rewardsPerSecond, rewardTokenPrice)).to.equal(
      units(apy, 18), // 1 or 100%
    );
  });

  it("should calculate apy correctly with roughly close to live inputs", async () => {
    // inputs taken roughly from Mat's Proposal https://forum.dhedge.org/t/dcp-11-op-incentives-for-dhedge-pools/398
    const totalValue = units(2_700_000); // 2,700,000.00$
    const rewardsPerSecond = units(1274, 13); // 0.01274 token
    const rewardTokenPrice = units(94, 16); // 0.94$
    expect(await rewardsAPYCalculator.calculateAPY(totalValue, rewardsPerSecond, rewardTokenPrice)).to.equal(
      units(139875008, 9), // ~13.99%
    );
  });

  it("should calculate apy correctly with corner case inputs", async () => {
    const totalValue = 0;
    const rewardsPerSecond = 0;
    const rewardTokenPrice = 0;
    expect(await rewardsAPYCalculator.calculateAPY(totalValue, rewardsPerSecond, rewardTokenPrice)).to.equal(0);
  });
});
