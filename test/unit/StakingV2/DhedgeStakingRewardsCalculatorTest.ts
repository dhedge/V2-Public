import { expect } from "chai";
import { ethers } from "hardhat";
import { DhedgeStakingV2RewardsCalculator } from "../../../types";
import { units } from "../../TestHelpers";
import { BigNumber } from "ethers";

const OneDayInSeconds = 24 * 60 * 60;

describe("DhedgeStakingRewardsCalculatorTest", () => {
  let dhedgeStakingRewardsCalculator: DhedgeStakingV2RewardsCalculator;

  const rewardParams: {
    stakeDurationDelaySeconds: BigNumber;
    maxDurationBoostSeconds: BigNumber;
    maxPerformanceBoostNumerator: BigNumber;
    maxPerformanceBoostDenominator: BigNumber;
    stakingRatio: BigNumber;
    emissionsRate: BigNumber;
    emissionsRateDenominator: BigNumber;
  } = {
    stakeDurationDelaySeconds: BigNumber.from(30 * OneDayInSeconds),
    maxDurationBoostSeconds: BigNumber.from(182 * OneDayInSeconds),
    maxPerformanceBoostNumerator: BigNumber.from(500), // 50%
    maxPerformanceBoostDenominator: BigNumber.from(1000),
    stakingRatio: BigNumber.from(6),
    emissionsRate: BigNumber.from(1000),
    emissionsRateDenominator: BigNumber.from(1000),
  };
  beforeEach(async () => {
    const DhedgeStakingRewardsCalculator = await ethers.getContractFactory("DhedgeStakingV2RewardsCalculator");
    dhedgeStakingRewardsCalculator = await DhedgeStakingRewardsCalculator.deploy();
  });

  describe("calculateMaxVDHTAllowed", () => {
    it("perfect vdht ratio", async () => {
      const vDHTAmount = 6000;
      const totalValue = 1000;
      const stakingRatio = 6;

      const result = await dhedgeStakingRewardsCalculator.calculateMaxVDHTAllowed(vDHTAmount, totalValue, stakingRatio);
      expect(result).to.equal(vDHTAmount);
    });

    it("totalValue over max vdht ratio", async () => {
      const vDHTAmount = 6000;
      const totalValue = 2000;
      const stakingRatio = 6;

      const result = await dhedgeStakingRewardsCalculator.calculateMaxVDHTAllowed(vDHTAmount, totalValue, stakingRatio);
      expect(result).to.equal(vDHTAmount);
    });

    it("totalValue under max vdht ratio", async () => {
      const vDHTAmount = 6000;
      const totalValue = 500;
      const stakingRatio = 6;

      const result = await dhedgeStakingRewardsCalculator.calculateMaxVDHTAllowed(vDHTAmount, totalValue, stakingRatio);
      expect(result).to.equal(vDHTAmount / 2);
    });

    it("totalValue way under max vdht ratio", async () => {
      const vDHTAmount = 6000;
      const totalValue = 1;
      const stakingRatio = 6;

      const result = await dhedgeStakingRewardsCalculator.calculateMaxVDHTAllowed(vDHTAmount, totalValue, stakingRatio);
      expect(result).to.equal(6);
    });
  });

  describe("calculateStakeDurationFactor", () => {
    it("basic test no duration", async () => {
      const stakeStartTime = 0;
      const stakeFinishTime = 0;
      const maxDurationBoost = 365;

      const result = await dhedgeStakingRewardsCalculator.calculateStakeDurationFactor(
        stakeStartTime,
        stakeFinishTime,
        maxDurationBoost,
      );
      expect(result).to.equal(0);
    });

    it("basic test max duration", async () => {
      const stakeStartTime = 0;
      const stakeFinishTime = 365;
      const maxDurationBoost = 365;
      const unit = await dhedgeStakingRewardsCalculator.UNIT();

      const result = await dhedgeStakingRewardsCalculator.calculateStakeDurationFactor(
        stakeStartTime,
        stakeFinishTime,
        maxDurationBoost,
      );

      expect(result).to.equal(unit);
    });

    it("double max duration", async () => {
      const stakeStartTime = 0;
      const stakeFinishTime = 365 * 2;
      const maxDurationBoost = 365;
      const unit = await dhedgeStakingRewardsCalculator.UNIT();

      const result = await dhedgeStakingRewardsCalculator.calculateStakeDurationFactor(
        stakeStartTime,
        stakeFinishTime,
        maxDurationBoost,
      );

      expect(result).to.equal(unit);
    });

    it("half max duration", async () => {
      const stakeStartTime = 0;
      const stakeFinishTime = 3650 / 2;
      const maxDurationBoost = 3650;
      const unit = await dhedgeStakingRewardsCalculator.UNIT();

      const result = await dhedgeStakingRewardsCalculator.calculateStakeDurationFactor(
        stakeStartTime,
        stakeFinishTime,
        maxDurationBoost,
      );

      expect(result).to.equal(unit.div(2));
    });
  });

  describe("calculatePerformanceFactor", () => {
    it("basic test no token price increase", async () => {
      const maxPerformance = 1000;
      const maxPerformanceDenominator = 1000;
      const tokenStartPrice = units(1);
      const tokenFinishPrice = 0;

      const result = await dhedgeStakingRewardsCalculator.calculatePerformanceFactor(
        tokenStartPrice,
        tokenFinishPrice,
        maxPerformance,
        maxPerformanceDenominator,
      );
      expect(result).to.equal(0);
    });

    it("basic test max token price increase 50% max", async () => {
      const maxPerformance = 500;
      const maxPerformanceDenominator = 1000;
      const tokenStartPrice = units(1);
      const tokenFinishPrice = units(1)
        .mul(maxPerformance + maxPerformanceDenominator)
        .div(maxPerformanceDenominator);

      const unit = await dhedgeStakingRewardsCalculator.UNIT();

      const result = await dhedgeStakingRewardsCalculator.calculatePerformanceFactor(
        tokenStartPrice,
        tokenFinishPrice,
        maxPerformance,
        maxPerformanceDenominator,
      );
      expect(result).to.equal(unit);
    });

    it("basic test max token price increase 200%", async () => {
      const maxPerformance = 2000;
      const maxPerformanceDenominator = 1000;
      const tokenStartPrice = units(1);
      const tokenFinishPrice = units(1)
        .mul(maxPerformance + maxPerformanceDenominator)
        .div(maxPerformanceDenominator);
      const unit = await dhedgeStakingRewardsCalculator.UNIT();

      const result = await dhedgeStakingRewardsCalculator.calculatePerformanceFactor(
        tokenStartPrice,
        tokenFinishPrice,
        maxPerformance,
        maxPerformanceDenominator,
      );
      expect(result).to.equal(unit);
    });

    it("50% token price increase", async () => {
      const maxPerformance = 1000;
      const maxPerformanceDenominator = 1000;
      const tokenStartPrice = units(1);
      const tokenFinishPrice = units(1)
        .mul(maxPerformance / 2 + maxPerformanceDenominator)
        .div(maxPerformanceDenominator);

      const unit = await dhedgeStakingRewardsCalculator.UNIT();

      const result = await dhedgeStakingRewardsCalculator.calculatePerformanceFactor(
        tokenStartPrice,
        tokenFinishPrice,
        maxPerformance,
        maxPerformanceDenominator,
      );
      expect(result).to.equal(unit.div(2));
    });

    it("200% token price increase, returns max", async () => {
      const maxPerformance = 1000;
      const maxPerformanceDenominator = 1000;
      const tokenStartPrice = units(1);
      const tokenFinishPrice = units(1)
        .mul(maxPerformance * 2 + maxPerformanceDenominator)
        .div(maxPerformanceDenominator);

      const unit = await dhedgeStakingRewardsCalculator.UNIT();

      const result = await dhedgeStakingRewardsCalculator.calculatePerformanceFactor(
        tokenStartPrice,
        tokenFinishPrice,
        maxPerformance,
        maxPerformanceDenominator,
      );
      expect(result).to.equal(unit);
    });
  });

  describe("calculateDhtRewardAmount", () => {
    it("basic test nothing", async () => {
      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        0,
        0,
        0,
        0,
        0,
        0,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(0);
    });

    // N.B. poolTokensStaked * tokenStartPrice == totalValueStaked
    it("perfect ratio, max duration, max performance", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(10);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);

      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds;

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(vDHTAmount);
    });

    it("perfect ratio, max duration, max performance, 1.5x emissions rate", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(10);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);

      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds;

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate.add(rewardParams.emissionsRate.div(2)),
        rewardParams,
      );
      expect(result).to.equal(vDHTAmount * 1.5);
    });

    it("perfect ratio, max duration, max performance, 0.5x emissions rate", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(10);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);

      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds;

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate.div(2),
        rewardParams,
      );
      expect(result).to.equal(vDHTAmount / 2);
    });

    it("perfect ratio, max duration, half performance", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(10);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.div(2).add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);
      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds;

      console.log(tokenPriceFinish);

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(vDHTAmount / 2);
    });

    it("perfect ratio, max performance, half duration", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(10);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);
      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds.div(2);

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(vDHTAmount / 2);
    });

    it("perfect ratio, half performance, half duration", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(10);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.div(2).add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);
      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds.div(2);

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(vDHTAmount / 2 / 2);
    });

    it("half ratio, half performance, half duration", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(5);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.div(2).add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);
      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds.div(2);

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(vDHTAmount / 2 / 4);
    });

    it("perfect ratio, 0 performance, full duration", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = 10;
      const tokenPriceStart = 100;
      const tokenPriceFinish = 100;
      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds;

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(0);
    });

    it("perfect ratio, full performance, 0 duration", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = units(10);
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);
      const stakeStartTime = 0;
      const stakeFinishTime = 0;

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(0);
    });

    it("no ratio, full performance, 0 duration", async () => {
      const vDHTAmount = 6000;
      const poolTokensStaked = 0;
      const tokenPriceStart = 100;
      const tokenPriceFinish = BigNumber.from(tokenPriceStart)
        .mul(rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator))
        .div(rewardParams.maxPerformanceBoostDenominator);
      const stakeStartTime = 0;
      const stakeFinishTime = rewardParams.maxDurationBoostSeconds;

      const result = await dhedgeStakingRewardsCalculator.calculateDhtRewardAmount(
        vDHTAmount,
        poolTokensStaked,
        tokenPriceStart,
        tokenPriceFinish,
        stakeStartTime,
        stakeFinishTime,
        rewardParams.emissionsRate,
        rewardParams,
      );
      expect(result).to.equal(0);
    });
  });
});
