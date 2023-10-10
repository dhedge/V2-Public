import { smock, MockContract } from "@defi-wonderland/smock";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";

import { units } from "../../testHelpers";
import {
  ERC20Asset,
  PoolFactory,
  PoolFactory__factory,
  PoolLogic,
  PoolLogic__factory,
  PoolManagerLogic,
  PoolManagerLogic__factory,
  RewardDistribution,
} from "../../../types";

const REWARD_AMOUNT_PER_SECOND = units(2, 17); // 0.2 token
const POOL_VALUE = units(1_000_000);

const prepareMockedWhitelistedPools = async (
  pools: boolean[], // true if reward token supported, false otherwise
  poolValue: BigNumber,
  rewardTokenPrice = units(1), // 1$,
) => {
  const PoolFactoryFactory = await smock.mock<PoolFactory__factory>("PoolFactory");
  const PoolManagerLogicFactory = await smock.mock<PoolManagerLogic__factory>("PoolManagerLogic");
  const PoolLogicFactory = await smock.mock<PoolLogic__factory>("PoolLogic");
  const mockedPoolFactory: MockContract<PoolFactory> = await PoolFactoryFactory.deploy();
  mockedPoolFactory.getAssetPrice.returns(rewardTokenPrice);
  return Promise.all(
    Array.from(Array(pools.length).keys(), async (element) => {
      const mockedPoolManagerLogic: MockContract<PoolManagerLogic> = await PoolManagerLogicFactory.deploy();
      mockedPoolManagerLogic.totalFundValue.returns(poolValue);
      mockedPoolManagerLogic.isSupportedAsset.returns(pools[element]);
      const mockedPoolLogic: MockContract<PoolLogic> = await PoolLogicFactory.deploy();
      mockedPoolLogic.poolManagerLogic.returns(mockedPoolManagerLogic.address);
      mockedPoolLogic.factory.returns(mockedPoolFactory.address);
      return mockedPoolLogic.address;
    }),
  );
};

describe("RewardDistribution Tests", () => {
  let rewardDistribution: RewardDistribution;
  let rewardToken: ERC20Asset;
  let owner: SignerWithAddress;
  let other: SignerWithAddress;

  beforeEach(async () => {
    [owner, other] = await ethers.getSigners();

    const OptimismToken = await ethers.getContractFactory("ERC20Asset");
    rewardToken = await OptimismToken.deploy("Optimism", "OP");

    const RewardDistribution = await ethers.getContractFactory("RewardDistribution");
    rewardDistribution = await RewardDistribution.deploy(rewardToken.address, REWARD_AMOUNT_PER_SECOND);
  });

  describe("calculatePoolRewardAmount returns correct rewards", () => {
    const ALL_POOLS_TVL = units(42000000);
    const TOTAL_REWARDS_TO_DISTRIBUTE = units(10);

    it("should return zero rewards when all pools tvl is zero (eligible pools not set)", async () => {
      expect(await rewardDistribution.calculatePoolRewardAmount(POOL_VALUE, 0, TOTAL_REWARDS_TO_DISTRIBUTE)).to.equal(
        0,
      );
    });

    it("should return zero rewards if total rewards for period is zero", async () => {
      expect(await rewardDistribution.calculatePoolRewardAmount(POOL_VALUE, ALL_POOLS_TVL, 0)).to.equal(0);
    });

    it("should return zero rewards when total tvl is less pool tvl", async () => {
      expect(
        await rewardDistribution.calculatePoolRewardAmount(units(10), units(1), REWARD_AMOUNT_PER_SECOND),
      ).to.equal(0);
    });

    it("should return total available rewards if only one pool is eligible", async () => {
      const poolTvl = ALL_POOLS_TVL;
      expect(
        await rewardDistribution.calculatePoolRewardAmount(poolTvl, ALL_POOLS_TVL, TOTAL_REWARDS_TO_DISTRIBUTE),
      ).to.equal(TOTAL_REWARDS_TO_DISTRIBUTE);
    });

    it("should return pro rata rewards", async () => {
      const allPoolsTvl = units(1000); // 1000$
      const coeff = 10;
      const poolTvl = allPoolsTvl.div(coeff); // 100$
      const rewardsToDistribute = units(100); // tokens
      expect(await rewardDistribution.calculatePoolRewardAmount(poolTvl, allPoolsTvl, rewardsToDistribute)).to.equal(
        units(10), // rewardsToDistribute * poolTvl / allPoolsTvl => (100 * 100 / 1000)
      );
    });
  });

  describe("calculateTotalRewardsForPeriod returns correct rewards", () => {
    const LAST_DISTRIBUTION_TIME = 0;
    const DAY_IN_SECONDS = 60 * 60 * 24;

    it("should return zero rewards if reward per second is zero (not set)", async () => {
      expect(
        await rewardDistribution.calculateTotalRewardsForPeriod(
          0,
          LAST_DISTRIBUTION_TIME,
          LAST_DISTRIBUTION_TIME + DAY_IN_SECONDS,
        ),
      ).to.equal(0);
    });

    it("should return zero rewards when blocktime is less than or equal last distribution date", async () => {
      expect(
        await rewardDistribution.calculateTotalRewardsForPeriod(
          REWARD_AMOUNT_PER_SECOND,
          LAST_DISTRIBUTION_TIME + DAY_IN_SECONDS * 2,
          LAST_DISTRIBUTION_TIME + DAY_IN_SECONDS,
        ),
      ).to.equal(0);
      expect(
        await rewardDistribution.calculateTotalRewardsForPeriod(
          REWARD_AMOUNT_PER_SECOND,
          LAST_DISTRIBUTION_TIME,
          LAST_DISTRIBUTION_TIME,
        ),
      ).to.equal(0);
    });

    it("should return correct rewards for period", async () => {
      const rewardAmountPerSecond = units(1); // 1 token
      expect(
        await rewardDistribution.calculateTotalRewardsForPeriod(
          rewardAmountPerSecond,
          LAST_DISTRIBUTION_TIME,
          LAST_DISTRIBUTION_TIME + DAY_IN_SECONDS,
        ),
      ).to.equal(units(86400)); // 1 * 86400 (day in seconds)
    });
  });

  describe("getEligiblePools returns correct pools", () => {
    it("returns empty list if whitelisted pools not set", async () => {
      const result = await rewardDistribution.getEligiblePoolsWithTvl();
      expect(result.eligiblePools).to.deep.equal([]);
      expect(result.tvl).to.be.equal(0);
    });

    it("returns empty list if no whitelited pools has reward token enabled", async () => {
      const pools = [false, false, false];
      const whitelistedPools = await prepareMockedWhitelistedPools(pools, POOL_VALUE);
      await rewardDistribution.setWhitelistedPools(whitelistedPools);
      const result = await rewardDistribution.getEligiblePoolsWithTvl();
      expect(result.eligiblePools).to.deep.equal([]);
      expect(result.tvl).to.be.equal(0);
    });

    it("returns filtered list if some of whitelisted pools have reward token disabled", async () => {
      const pools = [true, false, true];
      const whitelistedPools = await prepareMockedWhitelistedPools(pools, POOL_VALUE);
      await rewardDistribution.setWhitelistedPools(whitelistedPools);
      const result = await rewardDistribution.getEligiblePoolsWithTvl();
      expect(result.eligiblePools.map(({ pool }) => pool)).to.deep.equal([whitelistedPools[0], whitelistedPools[2]]);
      expect(result.tvl).to.be.equal(units(2_000_000));
    });

    it("returns whitelistedPools if all of whitelisted pools have reward token enabled", async () => {
      const pools = [true, true, true];
      const whitelistedPools = await prepareMockedWhitelistedPools(pools, POOL_VALUE);
      await rewardDistribution.setWhitelistedPools(whitelistedPools);
      const result = await rewardDistribution.getEligiblePoolsWithTvl();
      expect(result.eligiblePools.map(({ pool }) => pool)).to.deep.equal(whitelistedPools);
      expect(result.tvl).to.be.equal(units(3_000_000));
    });
  });

  describe("distributeRewards behaves as intended", () => {
    const REWARD_TOKEN_AMOUNT = units(1000);

    describe("each of whitelisted pools have reward token enabled", () => {
      const WHITELISTED_POOLS = [true, true];
      let pools: string[];

      before(async () => {
        pools = await prepareMockedWhitelistedPools(WHITELISTED_POOLS, POOL_VALUE);
      });

      it("prevents distribution when eligiblePools not set", async () => {
        await rewardToken.transfer(rewardDistribution.address, REWARD_TOKEN_AMOUNT);
        await expect(rewardDistribution.distributeRewards()).to.be.revertedWith("no eligible pools or not set");
      });

      it("prevents distribution when rewardAmountPerSecond equals zero", async () => {
        await rewardToken.transfer(rewardDistribution.address, REWARD_TOKEN_AMOUNT);
        await rewardDistribution.setWhitelistedPools(pools);
        await rewardDistribution.setRewardAmountPerSecond(0);
        await expect(rewardDistribution.distributeRewards()).to.be.revertedWith("nothing to distribute");
      });

      it("prevents distribution when contract needs to be topped-up with rewardToken", async () => {
        await rewardDistribution.setWhitelistedPools(pools);
        await expect(rewardDistribution.distributeRewards()).to.be.revertedWith("not enough reward token");
      });

      it("distributes rewards to eligible pools", async () => {
        await rewardToken.transfer(rewardDistribution.address, REWARD_TOKEN_AMOUNT);
        await rewardDistribution.setWhitelistedPools(pools);
        expect(await rewardToken.balanceOf(rewardDistribution.address)).to.equal(REWARD_TOKEN_AMOUNT);
        for (const eligiblePool of pools) {
          expect(await rewardToken.balanceOf(eligiblePool)).to.equal(0);
        }
        await rewardDistribution.distributeRewards();
        expect(await rewardToken.balanceOf(rewardDistribution.address)).to.be.lt(REWARD_TOKEN_AMOUNT);
        for (const eligiblePool of pools) {
          expect(await rewardToken.balanceOf(eligiblePool)).to.be.gt(0);
        }
      });

      it("resets lastDistributionTime after rewards distribution", async () => {
        await rewardToken.transfer(rewardDistribution.address, REWARD_TOKEN_AMOUNT);
        await rewardDistribution.setWhitelistedPools(pools);
        const lastDistributionTimeBeforeDistribution = await rewardDistribution.lastDistributionTime();
        await rewardDistribution.distributeRewards();
        const lastDistributionTimeAfterDistribution = await rewardDistribution.lastDistributionTime();
        expect(lastDistributionTimeAfterDistribution > lastDistributionTimeBeforeDistribution);
      });
    });

    describe("whitelisted pools can have reward token not enabled", () => {
      it("doesn't distribute rewards if none of whitelisted pools have reward token enabled", async () => {
        const pools = [false, false];
        const whitelistedPools = await prepareMockedWhitelistedPools(pools, POOL_VALUE);
        await rewardToken.transfer(rewardDistribution.address, REWARD_TOKEN_AMOUNT);
        await rewardDistribution.setWhitelistedPools(whitelistedPools);
        await expect(rewardDistribution.distributeRewards()).to.be.revertedWith("no eligible pools or not set");
      });

      it("distributes rewards only to pools which have reward token enabled", async () => {
        const pools = [false, true];
        const whitelistedPools = await prepareMockedWhitelistedPools(pools, POOL_VALUE);
        await rewardToken.transfer(rewardDistribution.address, REWARD_TOKEN_AMOUNT);
        await rewardDistribution.setWhitelistedPools(whitelistedPools);
        expect(await rewardToken.balanceOf(rewardDistribution.address)).to.equal(REWARD_TOKEN_AMOUNT);
        for (const whitelistedPool of whitelistedPools) {
          expect(await rewardToken.balanceOf(whitelistedPool)).to.equal(0);
        }
        await rewardDistribution.distributeRewards();
        expect(await rewardToken.balanceOf(rewardDistribution.address)).to.be.lt(REWARD_TOKEN_AMOUNT);
        expect(await rewardToken.balanceOf(whitelistedPools[0])).to.equal(0);
        expect(await rewardToken.balanceOf(whitelistedPools[1])).to.be.gt(0);
      });
    });
  });

  describe("only owner can call setters", () => {
    it("setRewardToken", async () => {
      await expect(rewardDistribution.connect(other).setRewardToken(owner.address)).to.be.reverted;
      await rewardDistribution.connect(owner).setRewardToken(rewardToken.address);
    });

    it("setRewardAmountPerSecond", async () => {
      await expect(rewardDistribution.connect(other).setRewardAmountPerSecond(0)).to.be.reverted;
      await rewardDistribution.connect(owner).setRewardAmountPerSecond(0);
    });

    it("setWhitelistedPools", async () => {
      await expect(rewardDistribution.connect(other).setWhitelistedPools([])).to.be.reverted;
      await rewardDistribution.connect(owner).setWhitelistedPools([]);
    });
  });

  describe("setters can change storage values", () => {
    it("setRewardToken", async () => {
      expect(await rewardDistribution.rewardToken()).to.equal(rewardToken.address);
      await rewardDistribution.setRewardToken(other.address);
      expect(await rewardDistribution.rewardToken()).to.equal(other.address);
    });

    it("setRewardAmountPerSecond", async () => {
      expect(await rewardDistribution.rewardAmountPerSecond()).to.equal(REWARD_AMOUNT_PER_SECOND);
      await rewardDistribution.setRewardAmountPerSecond(0);
      expect(await rewardDistribution.rewardAmountPerSecond()).to.equal(0);
    });

    it("setWhitelistedPools", async () => {
      expect(await rewardDistribution.getWhitelistedPools()).to.deep.equal([]);
      await rewardDistribution.setWhitelistedPools([other.address]);
      expect(await rewardDistribution.getWhitelistedPools()).to.deep.equal([other.address]);
    });
  });

  describe("apy calculations", () => {
    let pools: string[];
    const whitelistedPools = [true];
    const apy = 1; // 100%
    const totalValue = units(315_360_000); // 315,360,000.00$
    const totalRewards = totalValue.mul(apy); // 315,360,000.00$
    const yearInSeconds = 60 * 60 * 24 * 365; // 31,536,000 seconds
    const rewardsPerSecond = totalRewards.div(yearInSeconds); // 1 token
    const rewardTokenPrice = units(1); // 1$

    before(async () => {
      pools = await prepareMockedWhitelistedPools(whitelistedPools, totalValue, rewardTokenPrice);
    });

    it("returns correct apy when calling getRewardsAPY", async () => {
      await rewardDistribution.setWhitelistedPools(pools);
      await rewardDistribution.setRewardAmountPerSecond(rewardsPerSecond);
      expect(await rewardDistribution.getRewardsAPY()).to.equal(units(apy, 18)); // 1 or 100%
    });
  });
});
