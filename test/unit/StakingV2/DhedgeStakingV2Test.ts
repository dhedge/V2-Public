import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { DhedgeStakingV2, ERC20Asset, PoolLogic__factory, PoolLogic, PoolFactory__factory } from "../../../types";
import { utils } from "../../integration/utils/utils";
import { checkDelta, units } from "../../TestHelpers";
import { smock, MockContract } from "@defi-wonderland/smock";
import { BigNumber } from "ethers";

const START_MOCK_TOKEN_PRICE = units(1);

describe("Dhedge DHT Staking V2", () => {
  let owner: SignerWithAddress, staker: SignerWithAddress, other: SignerWithAddress;
  let dht: ERC20Asset;
  let dhtStaking: DhedgeStakingV2;
  let dhtAmountToStake: BigNumber;
  let AMOUNT_TO_STAKE;
  let MAX_V_DURATION_TIME: BigNumber;

  let rewardParams: {
    stakeDurationDelaySeconds: BigNumber;
    maxDurationBoostSeconds: BigNumber;
    maxPerformanceBoostNumerator: BigNumber;
    maxPerformanceBoostDenominator: BigNumber;
    stakingRatio: BigNumber;
    emissionsRate: BigNumber;
    emissionsRateDenominator: BigNumber;
  };

  beforeEach(async () => {
    [owner, staker, other] = await ethers.getSigners();

    const DHT = await ethers.getContractFactory("ERC20Asset");
    dht = await DHT.deploy("DHT", "DHT");
    await dht.deployed();

    const DHTStaking = await ethers.getContractFactory("DhedgeStakingV2");
    dhtStaking = await DHTStaking.deploy();
    await dhtStaking.deployed();
    await dhtStaking.initialize(dht.address);

    // For even math set to number divisible by stakingRatio(6)
    const dhtCap = units(120);
    await dhtStaking.setDHTCap(dhtCap);
    dhtAmountToStake = dhtCap;
    rewardParams = await dhtStaking.rewardParams();
    // Set the emissions rate to 1:1 by default, easier to reason about
    await dhtStaking.setEmissionsRate(rewardParams.emissionsRateDenominator);
    // Reload rewards params because it changes from above call
    rewardParams = await dhtStaking.rewardParams();
    // We calculate the correct amount of DHPT to stake to max out the dhtCap
    AMOUNT_TO_STAKE = dhtCap.div(rewardParams.stakingRatio).mul(units(1)).div(START_MOCK_TOKEN_PRICE);
    MAX_V_DURATION_TIME = await dhtStaking.maxVDurationTimeSeconds();

    await dht.transfer(dhtStaking.address, dhtCap);
    await dht.transfer(staker.address, dhtAmountToStake);
    await dht.connect(staker).approve(dhtStaking.address, dhtAmountToStake);
  });

  describe("No Transferability", () => {
    it("Stakes ownership not transferable", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      await expect(dhtStaking.connect(staker).transferFrom(staker.address, other.address, tokenId)).to.be.revertedWith(
        "Token is soulbound",
      );
    });
  });

  it("setDHTCap + maxStakingValue", async () => {
    const newAmount = units(1);
    const newEmissionsRate = rewardParams.emissionsRate.mul(2);
    await dhtStaking.connect(owner).setDHTCap(newAmount);
    await dhtStaking.connect(owner).setEmissionsRate(newEmissionsRate);
    expect(await dhtStaking.maxStakingValue()).to.equal(
      newAmount.div(rewardParams.stakingRatio).mul(rewardParams.emissionsRateDenominator).div(newEmissionsRate),
    );
  });

  describe("newStake", () => {
    it("Can create a stake with 0 DHT", async () => {
      await dhtStaking.connect(staker).newStake(0);
      expect(await dhtStaking.balanceOf(staker.address)).to.equal(1);
    });

    it("Current emissions rate is stored correctly against Stake", async () => {
      const newEmissionsRate = BigNumber.from(2999);
      await dhtStaking.setEmissionsRate(newEmissionsRate);
      await dhtStaking.connect(staker).newStake(0);
      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      const stake = await dhtStaking.stakes(tokenId);
      expect(stake.rewardParamsEmissionsRate).to.equal(newEmissionsRate);
    });

    it("Staking contract receives dht", async () => {
      const balanceBefore = await dht.balanceOf(dhtStaking.address);
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      expect(await dht.balanceOf(dhtStaking.address)).to.equal(balanceBefore.add(dhtAmountToStake.div(2)));
      const balanceBeforeSecondStake = await dht.balanceOf(dhtStaking.address);
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      expect(await dht.balanceOf(dhtStaking.address)).to.equal(balanceBeforeSecondStake.add(dhtAmountToStake.div(2)));
    });

    it("Staker receives nft", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake);
      expect(await dhtStaking.balanceOf(staker.address)).to.equal(1);
    });

    it("global dhtBeingStaked is updated", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      expect(await dhtStaking.dhtStaked()).to.equal(dhtAmountToStake.div(2));
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      expect(await dhtStaking.dhtStaked()).to.equal(dhtAmountToStake);
    });
  });

  describe("Global vDHT", () => {
    it("single staker", async () => {
      expect(await dhtStaking.globalVDHT()).to.equal(0);
      const smallAmountToStake = dhtAmountToStake.div(10);
      await dhtStaking.connect(staker).newStake(smallAmountToStake);
      await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber());

      expect(await dhtStaking.dhtStaked()).to.equal(smallAmountToStake);
      expect(await dhtStaking.globalVDHT()).to.equal(await dhtStaking.vDHTBalanceOf(staker.address));

      await dhtStaking.connect(staker).newStake(smallAmountToStake);
      await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());

      expect(await dhtStaking.dhtStaked()).to.equal(smallAmountToStake.add(smallAmountToStake));
      expect(await dhtStaking.globalVDHT()).to.equal(smallAmountToStake.add(smallAmountToStake));
      expect(await dhtStaking.globalVDHT()).to.equal(await dhtStaking.vDHTBalanceOf(staker.address));
    });

    it("single staker + unstake", async () => {
      expect(await dhtStaking.globalVDHT()).to.equal(0);
      const smallAmountToStake = dhtAmountToStake.div(10);
      await dhtStaking.connect(staker).newStake(smallAmountToStake);
      await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber());

      expect(await dhtStaking.globalVDHT()).to.equal(await dhtStaking.vDHTBalanceOf(staker.address));

      await dhtStaking.connect(staker).newStake(smallAmountToStake);
      await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber());

      expect(await dhtStaking.globalVDHT()).to.equal(await dhtStaking.vDHTBalanceOf(staker.address));
      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      await dhtStaking.connect(staker).unstakeDHT(tokenId, smallAmountToStake);
      expect(await dhtStaking.globalVDHT()).to.equal(await dhtStaking.vDHTBalanceOf(staker.address));
    });

    it("two stakers + unstake + stake", async () => {
      expect(await dhtStaking.globalVDHT()).to.equal(0);
      // Setup `other` to be able to stake
      await dht.transfer(other.address, dhtAmountToStake);
      await dht.connect(other).approve(dhtStaking.address, dhtAmountToStake);
      // OtherStaker Stakes
      await dhtStaking.connect(other).newStake(dhtAmountToStake);
      await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber());
      // Usual Staker Stakes
      await dhtStaking.connect(staker).newStake(dhtAmountToStake);
      await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber());

      const staker1VDHT = await dhtStaking.vDHTBalanceOf(staker.address);
      const staker2VDHT = await dhtStaking.vDHTBalanceOf(other.address);
      expect(await dhtStaking.globalVDHT()).to.equal(staker1VDHT.add(staker2VDHT));

      // Usual Staker Unstakes
      await dhtStaking
        .connect(staker)
        .unstakeDHT(await dhtStaking.tokenOfOwnerByIndex(staker.address, 0), dhtAmountToStake);
      expect(await dhtStaking.globalVDHT()).to.equal(await dhtStaking.vDHTBalanceOf(other.address));
      await dhtStaking
        .connect(other)
        .unstakeDHT(await dhtStaking.tokenOfOwnerByIndex(other.address, 0), dhtAmountToStake);
      expect(await dhtStaking.globalVDHT()).to.equal(0);

      // Usual Staker Stakes again
      await dht.connect(staker).approve(dhtStaking.address, dhtAmountToStake);
      await dhtStaking.connect(staker).newStake(dhtAmountToStake);
      expect(await dhtStaking.globalVDHT()).to.equal(0);
    });
  });

  describe("addDhtToStake", () => {
    it("Must be owner or approved", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      await expect(dhtStaking.connect(other).addDhtToStake(tokenId, dhtAmountToStake.div(2))).to.be.revertedWith(
        "Must be approved or owner.",
      );
    });

    it("Can increase stake", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      expect(await dhtStaking.dhtBalanceOf(staker.address)).to.equal(dhtAmountToStake.div(2));

      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      await dhtStaking.connect(staker).addDhtToStake(tokenId, dhtAmountToStake.div(2));
      expect(await dhtStaking.dhtBalanceOf(staker.address)).to.equal(dhtAmountToStake);
    });

    it("Does not create new nft", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      await dhtStaking.connect(staker).addDhtToStake(tokenId, dhtAmountToStake.div(2));
      expect(await dhtStaking.balanceOf(staker.address)).to.equal(1);
    });

    it("vDHT is not manipulated", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      // Fastforward two month's to accrue vDHT
      await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber()); // 6months
      const vDHT = await dhtStaking.vDHTBalanceOf(staker.address);
      expect(vDHT).to.be.closeTo(dhtAmountToStake.div(2).div(2), dhtAmountToStake.div(1000));
      // Increase the amount of DHT being staked
      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      // This will make it as though dhtAmount has been staked for 3 months
      await dhtStaking.connect(staker).addDhtToStake(tokenId, dhtAmountToStake.div(2));
      // Check it doesn't immediately increase vDHT (one block may have passed so we have very small delta)
      expect(await dhtStaking.vDHTBalanceOf(staker.address)).to.be.closeTo(vDHT, vDHT.div(1000000));

      await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber()); // 12 months but really only staking for 9 months
      expect(await dhtStaking.vDHTBalanceOf(staker.address)).to.be.closeTo(
        dhtAmountToStake.div(4).mul(3),
        dhtAmountToStake.div(1000),
      );
      // Another 3 months
      await utils.increaseTime(MAX_V_DURATION_TIME.div(4).toNumber()); // 15 months -but really 12 months
      expect(await dhtStaking.vDHTBalanceOf(staker.address)).to.equal(dhtAmountToStake);
    });
  });

  describe("unstakeDHT", () => {
    let tokenId: BigNumber;
    beforeEach(async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake);
      tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
    });

    it("Must be owner or approved", async () => {
      // Note we connect here as the `other`
      await expect(dhtStaking.connect(other).unstakeDHT(tokenId, dhtAmountToStake)).to.be.revertedWith(
        "Must be approved or owner.",
      );
    });

    it("Stake must have enough DHT", async () => {
      // Note we are trying to unstake more than we staked
      await expect(dhtStaking.connect(staker).unstakeDHT(tokenId, dhtAmountToStake.mul(2))).to.be.revertedWith(
        "Not enough staked dht.",
      );
    });

    it("Unstakers dht is returned", async () => {
      const dhtBalanceBefore = await dht.balanceOf(staker.address);
      await dhtStaking.connect(staker).unstakeDHT(tokenId, dhtAmountToStake);
      expect(await dht.balanceOf(staker.address)).to.equal(dhtBalanceBefore.add(dhtAmountToStake));
    });

    it("dht balance after unstaking is correct", async () => {
      await dhtStaking.connect(staker).unstakeDHT(tokenId, dhtAmountToStake);
      expect(await dhtStaking.dhtBalanceOf(staker.address)).to.equal(0);
    });

    it("can unstake partial", async () => {
      const dhtBalanceBefore = await dht.balanceOf(staker.address);
      await dhtStaking.connect(staker).unstakeDHT(tokenId, dhtAmountToStake.div(2));
      expect(await dht.balanceOf(staker.address)).to.equal(dhtBalanceBefore.add(dhtAmountToStake.div(2)));
      expect(await dhtStaking.dhtBalanceOf(staker.address)).to.equal(dhtAmountToStake.div(2));
    });

    it("global dhtBeingStaked is updated", async () => {
      await dhtStaking.connect(staker).unstakeDHT(tokenId, dhtAmountToStake.div(2));
      expect(await dhtStaking.dhtStaked()).to.equal(dhtAmountToStake.div(2));
    });
  });

  describe("Staking Pool Tokens", () => {
    let mockPool: MockContract<PoolLogic>;
    let tokenId: BigNumber;

    beforeEach(async () => {
      // https://smock.readthedocs.io/en/latest/mocks.html
      // Create a fake pool
      const PoolFactoryFactory = await smock.mock<PoolFactory__factory>("PoolFactory");
      const poolFactory = await PoolFactoryFactory.deploy();
      const PoolLogicFactory = await smock.mock<PoolLogic__factory>("PoolLogic");
      mockPool = await PoolLogicFactory.deploy();
      // We need to set the factory for _beforeTokenTransfer
      await mockPool.setVariable("factory", poolFactory.address);
      // Give some pool tokens to the staker
      await mockPool.setVariable("_balances", {
        [staker.address]: AMOUNT_TO_STAKE,
      });
      // Set the pools token price to return $1
      mockPool.tokenPrice.returns(START_MOCK_TOKEN_PRICE);
      // Enabled the Pool for staking and set the cap to what where staking
      await dhtStaking.configurePool(mockPool.address, AMOUNT_TO_STAKE.mul(START_MOCK_TOKEN_PRICE).div(units(1)));
      // Approve staking contract to take pool tokens
      await mockPool.connect(staker).approve(dhtStaking.address, AMOUNT_TO_STAKE);

      await dhtStaking.connect(staker).newStake(dhtAmountToStake);
      tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
    });

    describe("stakePoolTokens", () => {
      it("Must be owner or approved", async () => {
        await expect(
          dhtStaking.connect(other).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE),
        ).to.be.revertedWith("Must be approved or owner.");
      });

      it("Contract receives poolTokens", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        expect(await mockPool.balanceOf(dhtStaking.address)).to.equal(AMOUNT_TO_STAKE);
      });

      it("Stake data is recorded correctly", async () => {
        mockPool.getExitRemainingCooldown.returns(84600);
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        const stake = await dhtStaking.stakes(tokenId);
        expect(stake.dhedgePoolAddress).to.equal(mockPool.address);
        expect(stake.dhedgePoolAmount).to.equal(AMOUNT_TO_STAKE);
        expect(stake.stakeStartTokenPrice).to.equal(START_MOCK_TOKEN_PRICE);
        expect(stake.dhedgePoolStakeStartTime).to.equal(await utils.currentBlockTimestamp());
        expect(stake.dhedgePoolRemainingExitCooldownAtStakeTime).to.equal(84600);
      });

      it("Can only stake whitelisted pool", async () => {
        const randomAddress = "0xb79fad4ca981472442f53d16365fdf0305ffd8e9";
        await expect(
          dhtStaking.connect(staker).stakePoolTokens(tokenId, randomAddress, AMOUNT_TO_STAKE),
        ).to.be.revertedWith("Pool not allowed.");
      });

      it("Can only stake upto the pool cap configure", async () => {
        // Reduce the staking cap for the mockPool to half
        await dhtStaking.configurePool(mockPool.address, AMOUNT_TO_STAKE.div(2));
        await expect(
          dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE),
        ).to.be.revertedWith("Cap for pool will be exceeded.");
      });

      it("Can only stake upto the global maxStakingValue", async () => {
        await dhtStaking.setDHTCap(AMOUNT_TO_STAKE.mul(rewardParams.stakingRatio).div(2));
        await expect(
          dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE),
        ).to.be.revertedWith("Staking cap will be exceeded.");
      });

      it("maxStakingValue is updated", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        expect(await dhtStaking.totalStakingValue()).to.equal(
          AMOUNT_TO_STAKE.mul(START_MOCK_TOKEN_PRICE).div(units(1)),
        );
      });

      it("poolConfiguration stakedSoFar is updated", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE.div(2));
        expect((await dhtStaking.getPoolConfiguration(mockPool.address)).stakedSoFar).to.equal(
          AMOUNT_TO_STAKE.mul(START_MOCK_TOKEN_PRICE).div(units(1)).div(2),
        );
        // Setup `other` to be able to stake
        await dht.transfer(other.address, dhtAmountToStake);
        await dht.connect(other).approve(dhtStaking.address, dhtAmountToStake);
        await dhtStaking.connect(other).newStake(dhtAmountToStake);
        await mockPool.setVariable("_balances", {
          [other.address]: AMOUNT_TO_STAKE,
        });
        await mockPool.connect(other).approve(dhtStaking.address, AMOUNT_TO_STAKE);
        // ^ Finish setup
        const tokenIdOfOther = await dhtStaking.tokenOfOwnerByIndex(other.address, 0);
        await dhtStaking.connect(other).stakePoolTokens(tokenIdOfOther, mockPool.address, AMOUNT_TO_STAKE.div(2));
        expect((await dhtStaking.getPoolConfiguration(mockPool.address)).stakedSoFar).to.equal(
          AMOUNT_TO_STAKE.mul(START_MOCK_TOKEN_PRICE).div(units(1)),
        );
      });

      it("Cannot restake", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE.div(2));
        await expect(
          dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE.div(2)),
        ).to.be.revertedWith("Pool Tokens already staked.");
      });
    });

    describe("unstakePoolTokens", () => {
      it("cannot unstake if no pool tokens staked", async () => {
        await expect(dhtStaking.connect(staker).unstakePoolTokens(tokenId)).to.be.revertedWith("No pool tokens staked");
      });

      it("Must be owner or approved", async () => {
        await expect(dhtStaking.connect(other).unstakePoolTokens(tokenId)).to.be.revertedWith(
          "Must be approved or owner.",
        );
      });

      it("Cannot unstake if tokens are under lockup (receiverWhitelist)", async () => {
        mockPool.getExitRemainingCooldown.returns(84600);
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        await expect(dhtStaking.connect(staker).unstakePoolTokens(tokenId)).to.be.revertedWith("cooldown active");
      });

      it("Unstake parameters are recorded correctly", async () => {
        await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber());
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        const vdht = await dhtStaking.vDHTBalanceOfStake(tokenId);
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        const stake = await dhtStaking.stakes(tokenId);
        expect(stake.dhtAmount).to.equal(0);
        expect(stake.unstaked).to.equal(true);
        expect(stake.unstakeTime).to.equal(await utils.currentBlockTimestamp());
        expect(stake.reward).to.equal(0);
        expect(stake.claimedReward).to.equal(0);
        expect(stake.vdhtAccruedAtUnstake).to.closeTo(vdht, vdht.div(1000));
        expect(stake.stakeFinishTokenPrice).to.equal(START_MOCK_TOKEN_PRICE);
      });

      it("Cannot unstake if already unstaked", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        await expect(dhtStaking.connect(staker).unstakePoolTokens(tokenId)).to.be.revertedWith("Already unstaked");
      });

      it("Reward is recorded correctly: perfect ratio, full performance, full stake duration", async () => {
        // Need staker to have max VDHT, so fastforward before staking DHPT
        await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());

        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        // Increase the tokenPrice to get the max multiplier
        const newTokenPrice = START_MOCK_TOKEN_PRICE.mul(
          rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator),
        ).div(rewardParams.maxPerformanceBoostDenominator);
        mockPool.tokenPrice.returns(newTokenPrice);
        // Fastforward time to get max multiplier and increase vDHT
        await utils.increaseTime(rewardParams.maxDurationBoostSeconds.toNumber());
        const vdhtAccrued = await dhtStaking.vDHTBalanceOfStake(tokenId);
        expect(vdhtAccrued).to.equal(dhtAmountToStake);
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        const stake = await dhtStaking.stakes(tokenId);
        expect(stake.unstakeTime).to.equal(await utils.currentBlockTimestamp());
        expect(stake.reward).to.equal(vdhtAccrued);
        expect(stake.vdhtAccruedAtUnstake).to.equal(vdhtAccrued);
        expect(stake.stakeFinishTokenPrice).to.equal(newTokenPrice);
      });

      it("No reward if unstaking during stakeDurationDelay", async () => {
        // Need staker to have max VDHT, so fastforward before staking DHPT
        await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());

        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        // Increase the tokenPrice to get the max multiplier
        const newTokenPrice = START_MOCK_TOKEN_PRICE.mul(
          rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator),
        ).div(rewardParams.maxPerformanceBoostDenominator);
        mockPool.tokenPrice.returns(newTokenPrice);
        // Fastforward time until 90% way through the stakeDurationDelay
        await utils.increaseTime(
          rewardParams.stakeDurationDelaySeconds.sub(rewardParams.stakeDurationDelaySeconds.div(10)).toNumber(),
        );
        const vdhtAccrued = await dhtStaking.vDHTBalanceOfStake(tokenId);
        expect(vdhtAccrued).to.equal(dhtAmountToStake);
        // Check they have rewards
        const rewards = await dhtStaking.currentRewardsForStake(tokenId);
        expect(rewards.gt(0)).to.be.true;
        // They're unstaking during the stakeDurationDelay so forfeit rewards
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        const stake = await dhtStaking.stakes(tokenId);
        expect(stake.unstakeTime).to.equal(await utils.currentBlockTimestamp());
        expect(stake.reward).to.equal(0);
        expect(stake.vdhtAccruedAtUnstake).to.equal(vdhtAccrued);
        expect(stake.stakeFinishTokenPrice).to.equal(newTokenPrice);
      });

      describe("canClaimAmount", () => {
        beforeEach(async () => {
          // We want the staker to 100% vDHT, so fastforward
          await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());
          await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
          // Increase the tokenPrice to get the max multiplier
          mockPool.tokenPrice.returns(
            START_MOCK_TOKEN_PRICE.mul(
              rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator),
            ).div(rewardParams.maxPerformanceBoostDenominator),
          );
          // Fastforward time to get max multiplier and increase vDHT
          await utils.increaseTime(rewardParams.maxDurationBoostSeconds.toNumber());
          await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
          const stake = await dhtStaking.stakes(tokenId);
          expect(stake.reward).to.equal(dhtAmountToStake);
        });

        describe("Calculates the correct amount", () => {
          it("At start of rewardStreamingTime", async () => {
            expect(await dhtStaking.canClaimAmount(tokenId)).to.equal(0);
          });
          it("At middle of rewardStreamingTime", async () => {
            await utils.increaseTime((await dhtStaking.rewardStreamingTime()).toNumber() / 2);
            expect(await dhtStaking.canClaimAmount(tokenId)).to.be.closeTo(
              dhtAmountToStake.div(2),
              dhtAmountToStake.div(10000),
            );
          });
          it("At end of rewardStreamingTime", async () => {
            await utils.increaseTime((await dhtStaking.rewardStreamingTime()).toNumber());
            await network.provider.send("evm_mine", []); // Just mines to the next block
            expect(await dhtStaking.canClaimAmount(tokenId)).to.equal(dhtAmountToStake);
          });
        });

        it("Adjusts for amount already claimed", async () => {
          const stake = await dhtStaking.stakes(tokenId);
          // Give the staking contract enough rewards
          await dht.transfer(dhtStaking.address, stake.reward);
          // Fastforward half the streaming time
          await utils.increaseTime((await dhtStaking.rewardStreamingTime()).toNumber() / 2);
          const claimAmount = await dhtStaking.canClaimAmount(tokenId);
          expect(claimAmount).to.be.closeTo(dhtAmountToStake.div(2), dhtAmountToStake.div(10000));
          // Claim rewards released so far
          await dhtStaking.connect(staker).claim(tokenId);
          const stakeAfterClaim = await dhtStaking.stakes(tokenId);
          // Check the claimedRewards is set
          expect(await stakeAfterClaim.claimedReward).to.be.closeTo(claimAmount, dhtAmountToStake.div(10000));
          // Check canClaimAmount is adjusted for already claimed portion
          expect(await dhtStaking.canClaimAmount(tokenId)).to.equal(0);
          // Fastforward for rest of streaming time
          await utils.increaseTime((await dhtStaking.rewardStreamingTime()).toNumber() / 2);
          // Check canClaimAmount includes residual
          expect(await dhtStaking.canClaimAmount(tokenId)).to.be.closeTo(
            dhtAmountToStake.div(2),
            dhtAmountToStake.div(10000),
          );
        });
      });

      // At the moment this is NOT possible, the stake is `finalised` when pool tokens are unstaked
      it.skip("Can partially unstake");
      // At the moment this is NOT possible, for reasons discussed we would need to record the token price at each new stake interval
      it.skip("Can add additional DHPT to stake");

      it("DHT Stake is teleported to new stake", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        const stake1BeforeUnstaking = await dhtStaking.stakes(tokenId);
        expect(await dhtStaking.balanceOf(staker.address)).to.equal(1);
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        // Assert 2 nft's
        expect(await dhtStaking.balanceOf(staker.address)).to.equal(2);
        // Assert DHT is nulled in original stake
        const stake1AfterUnstaking = await dhtStaking.stakes(tokenId);
        expect(stake1AfterUnstaking.dhtAmount).to.equal(0);

        // Note were getting the tokenId of the second nft for the user
        const stake2 = await dhtStaking.stakes(await dhtStaking.tokenOfOwnerByIndex(staker.address, 1));
        expect(stake2.dhtAmount).to.equal(stake1BeforeUnstaking.dhtAmount);
        expect(stake2.dhtStakeStartTime).to.equal(stake1BeforeUnstaking.dhtStakeStartTime);
        expect(stake2.dhedgePoolAddress).to.equal(ethers.constants.AddressZero);
      });

      it("totalStakingValue is updated", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        const totalStakingValueBefore = await dhtStaking.totalStakingValue();
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        expect(await dhtStaking.totalStakingValue()).to.equal(
          totalStakingValueBefore.sub(AMOUNT_TO_STAKE.mul(START_MOCK_TOKEN_PRICE).div(units(1))),
        );
      });

      it("poolConfiguration stakedSoFar is updated", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        const stakedBefore = (await dhtStaking.getPoolConfiguration(mockPool.address)).stakedSoFar;
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        const stakedAfter = (await dhtStaking.getPoolConfiguration(mockPool.address)).stakedSoFar;
        expect(stakedAfter).to.equal(stakedBefore.sub(AMOUNT_TO_STAKE.mul(START_MOCK_TOKEN_PRICE).div(units(1))));
      });

      it("Cannot increase stake if unstaked", async () => {
        // Unstake half dht to stake later
        await dhtStaking.connect(staker).unstakeDHT(tokenId, dhtAmountToStake.div(2));
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        // Try and stake more dht after unstaking pool tokens
        await dht.connect(staker).approve(dhtStaking.address, dhtAmountToStake);
        await expect(dhtStaking.connect(staker).addDhtToStake(tokenId, dhtAmountToStake.div(2))).to.be.revertedWith(
          "Already unstaked",
        );
      });
    });

    describe("claim", () => {
      it("Cannot claim until unstaked", async () => {
        await expect(dhtStaking.connect(staker).claim(tokenId)).to.be.revertedWith("Not Unstaked.");
      });

      it("Reverts with message if not enough dht", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);

        await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());
        // Increase the tokenPrice by 100%
        mockPool.tokenPrice.returns(START_MOCK_TOKEN_PRICE.mul(2));
        expect(await mockPool.tokenPrice()).to.equal(START_MOCK_TOKEN_PRICE.mul(2));
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        // Fast forward to the end of the escrow time
        const streamingTime = await dhtStaking.rewardStreamingTime();
        await utils.increaseTime(streamingTime.toNumber());

        // In the test setup we seed the dhtStaking contract with DHT
        // We need to get rid of it for this test, except for the amount being staked
        dht.burnAll(dhtStaking.address);
        dht.transfer(dhtStaking.address, await dhtStaking.dhtStaked());

        await expect(dhtStaking.connect(staker).claim(tokenId)).to.be.revertedWith("Rewards depleted.");
      });

      it("Claimer receives correct amount of dht", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);

        await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());
        // Increase the tokenPrice by 100%
        mockPool.tokenPrice.returns(START_MOCK_TOKEN_PRICE.mul(2));
        expect(await mockPool.tokenPrice()).to.equal(START_MOCK_TOKEN_PRICE.mul(2));
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        // Fast forward to the end of the escrow time
        const streamingTime = await dhtStaking.rewardStreamingTime();
        await utils.increaseTime(streamingTime.toNumber());
        const stake = await dhtStaking.stakes(tokenId);

        const dhtBalanceBeforeClaim = await dht.balanceOf(staker.address);
        await dhtStaking.connect(staker).claim(tokenId);
        const dhtBalanceAfterClaim = await dht.balanceOf(staker.address);
        expect(dhtBalanceAfterClaim).to.equal(dhtBalanceBeforeClaim.add(stake.reward));
      });

      it("If staker has received all rewards, can't claim anymore", async () => {
        await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, AMOUNT_TO_STAKE);

        await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());
        // Increase the tokenPrice by 100%
        mockPool.tokenPrice.returns(START_MOCK_TOKEN_PRICE.mul(2));
        expect(await mockPool.tokenPrice()).to.equal(START_MOCK_TOKEN_PRICE.mul(2));
        await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
        // Fast forward to the end of the escrow time
        const streamingTime = await dhtStaking.rewardStreamingTime();
        await utils.increaseTime(streamingTime.toNumber());

        await dhtStaking.connect(staker).claim(tokenId);
      });
    });

    it.skip(
      "Stake 1 dht, and DHPT, wait for dhpt staking duration, short term massive DHT buy to boost vDHT, claim, sell DHT",
    );

    // In this test we have one staker that stakes and then claims.
    // He receives half the dhtCap of rewards. This means that the next staker
    // Should not be able to stake more DHPT than remaining dhtCap / rewardParams.stakingRatio
    // Restricting staking using this methodology is extremly crude but will give us peace of mind
    it("DHT Emissions are controlled to and upper maximum", async () => {
      // Only stake enough DHT to consume half the dhtCap at full performance, full stake duration
      await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());
      const amountToStake = AMOUNT_TO_STAKE.div(2);
      const expectedDhtRewards = dhtAmountToStake.div(2);
      await dhtStaking.connect(staker).stakePoolTokens(tokenId, mockPool.address, amountToStake);
      // Increase the tokenPrice to get the max multiplier
      mockPool.tokenPrice.returns(
        START_MOCK_TOKEN_PRICE.mul(
          rewardParams.maxPerformanceBoostNumerator.add(rewardParams.maxPerformanceBoostDenominator),
        ).div(rewardParams.maxPerformanceBoostDenominator),
      );
      // Fastforward time to get max multiplier and increase vDHT
      await utils.increaseTime(rewardParams.maxDurationBoostSeconds.toNumber());

      await dhtStaking.connect(staker).unstakePoolTokens(tokenId);
      // Assert that first staker has received rewards and dhtRewarded is updated
      expect((await dhtStaking.stakes(tokenId)).reward).to.be.closeTo(
        expectedDhtRewards,
        expectedDhtRewards.div(10000) as unknown as number,
      );
      expect(await dhtStaking.dhtRewarded()).to.equal((await dhtStaking.stakes(tokenId)).reward);

      // Setup `other` to be able to stake
      // Reset the mockToken price to the OG Price
      mockPool.tokenPrice.returns(START_MOCK_TOKEN_PRICE);
      await dht.transfer(other.address, dhtAmountToStake);
      await dht.connect(other).approve(dhtStaking.address, dhtAmountToStake);
      await dhtStaking.connect(other).newStake(dhtAmountToStake);
      await mockPool.setVariable("_balances", {
        [other.address]: AMOUNT_TO_STAKE,
      });
      await mockPool.connect(other).approve(dhtStaking.address, AMOUNT_TO_STAKE);
      // ^ Finish setup
      const tokenIdOfOther = await dhtStaking.tokenOfOwnerByIndex(other.address, 0);

      await expect(
        dhtStaking.connect(other).stakePoolTokens(tokenIdOfOther, mockPool.address, AMOUNT_TO_STAKE),
      ).to.be.revertedWith("Staking cap will be exceeded.");

      await dhtStaking.connect(other).stakePoolTokens(tokenIdOfOther, mockPool.address, amountToStake);
    });
  });

  describe("dhtBalanceOf", () => {
    it("returns aggregate dht balance across all stakes", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      expect(await dhtStaking.dhtBalanceOf(staker.address)).to.equal(dhtAmountToStake.div(2));
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      expect(await dhtStaking.dhtBalanceOf(staker.address)).to.equal(dhtAmountToStake);
    });
  });

  describe("vDHTBalanceOfStake", () => {
    it("returns vDHT balance for given stake", async () => {
      expect(await dhtStaking.vDHTBalanceOf(staker.address)).to.equal(0);
      await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
      await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());
      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      expect(await dhtStaking.vDHTBalanceOfStake(tokenId)).to.equal(dhtAmountToStake.div(2));
    });
  });

  describe("vDHTBalanceOf", () => {
    describe("returns aggregate vDHT balance across all stakes", () => {
      it("returns the same amount as calculateVDHT for period", async () => {
        expect(await dhtStaking.vDHTBalanceOf(staker.address)).to.equal(0);
        await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
        await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
        checkDelta(await dhtStaking.vDHTBalanceOf(staker.address), 0, dhtAmountToStake.div(1000));
        expect(await dhtStaking.balanceOf(staker.address)).to.equal(2);

        await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());
        expect(await dhtStaking.vDHTBalanceOf(staker.address)).to.equal(dhtAmountToStake);
      });
      it("returns the same amount as calculateVDHT half MAX_V_DURATION_TIME", async () => {
        expect(await dhtStaking.vDHTBalanceOf(staker.address)).to.equal(0);
        await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
        await dhtStaking.connect(staker).newStake(dhtAmountToStake.div(2));
        checkDelta(await dhtStaking.vDHTBalanceOf(staker.address), 0, dhtAmountToStake.div(10000));
        expect(await dhtStaking.balanceOf(staker.address)).to.equal(2);

        await utils.increaseTime(MAX_V_DURATION_TIME.div(2).toNumber());
        checkDelta(
          await dhtStaking.vDHTBalanceOf(staker.address),
          dhtAmountToStake.div(2),
          dhtAmountToStake.div(10000),
        );
      });
    });
  });

  describe("checkEnoughDht", () => {
    it("Reverts if contract doesn't have enough dht", async () => {
      await expect(dhtStaking.checkEnoughDht(units(1).add(await dht.balanceOf(dhtStaking.address)))).to.be.revertedWith(
        "Rewards depleted.",
      );
    });
    it("Reverts if contract doesn't have enough dht after staking", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake);
      await expect(dhtStaking.checkEnoughDht(units(1).add(await dht.balanceOf(dhtStaking.address)))).to.be.revertedWith(
        "Rewards depleted.",
      );
    });
  });

  describe("configurePool", () => {
    it("Can configure a pool with a cap", async () => {
      const poolAddress = ethers.Wallet.createRandom().address;
      const poolConfigInitial = await dhtStaking.getPoolConfiguration(poolAddress);
      const numOfPoolsConfiguredInitial = await dhtStaking.numberOfPoolsConfigured();
      expect(poolConfigInitial.stakeCap).to.equal(0);
      expect(poolConfigInitial.configured).to.be.false;
      expect(numOfPoolsConfiguredInitial).to.equal(0);
      const cap = units(1);
      await dhtStaking.connect(owner).configurePool(poolAddress, cap);
      const poolConfigAfter = await dhtStaking.getPoolConfiguration(poolAddress);
      const numOfPoolsConfiguredAfter = await dhtStaking.numberOfPoolsConfigured();
      expect(numOfPoolsConfiguredAfter).to.equal(1);
      expect(poolConfigAfter.stakeCap).to.equal(cap);
      expect(poolConfigAfter.configured).to.be.true;
    });
    it("Can reconfigure a pool with a different cap", async () => {
      const poolAddress = ethers.Wallet.createRandom().address;
      const cap = units(1);
      await dhtStaking.connect(owner).configurePool(poolAddress, cap);
      expect((await dhtStaking.getPoolConfiguration(poolAddress)).stakeCap).to.equal(cap);
      const newCap = units(2);
      await dhtStaking.connect(owner).configurePool(poolAddress, newCap);
      expect((await dhtStaking.getPoolConfiguration(poolAddress)).stakeCap).to.equal(newCap);
    });
    it("Can configure more than 1 pool", async () => {
      const poolAddress = ethers.Wallet.createRandom().address;
      expect((await dhtStaking.getPoolConfiguration(poolAddress)).configured).to.be.false;
      const cap = units(1);
      await dhtStaking.connect(owner).configurePool(poolAddress, cap);
      expect(await dhtStaking.numberOfPoolsConfigured()).to.equal(1);
      expect((await dhtStaking.getPoolConfiguration(poolAddress)).configured).to.be.true;
      const anotherPoolAddress = ethers.Wallet.createRandom().address;
      expect((await dhtStaking.getPoolConfiguration(anotherPoolAddress)).configured).to.be.false;
      await dhtStaking.connect(owner).configurePool(anotherPoolAddress, cap);
      expect((await dhtStaking.getPoolConfiguration(anotherPoolAddress)).configured).to.be.true;
      expect(await dhtStaking.numberOfPoolsConfigured()).to.equal(2);
    });
  });

  describe.skip("tokenURI", () => {
    // https://github.com/Uniswap/v3-periphery/blob/de4e437ae97ba21d71a856167968ea05a05853fe/contracts/libraries/NFTSVG.sol
    // https://github.com/Uniswap/v3-periphery/blob/de4e437ae97ba21d71a856167968ea05a05853fe/contracts/NonfungibleTokenPositionDescriptor.sol
    // https://github.com/Uniswap/v3-periphery/blob/de4e437ae97ba21d71a856167968ea05a05853fe/contracts/libraries/NFTDescriptor.sol
    it("Returns correct metadata", async () => {
      await dhtStaking.connect(staker).newStake(dhtAmountToStake);
      await utils.increaseTime(MAX_V_DURATION_TIME.toNumber());

      const tokenId = await dhtStaking.tokenOfOwnerByIndex(staker.address, 0);
      const tokenURI = await dhtStaking.tokenURI(tokenId);

      expect(tokenURI.includes("data:application/json;base64,")).to.be.true;
      const buff = Buffer.from(tokenURI.replace("data:application/json;base64,", ""), "base64");
      const jsonRaw = buff.toString("ascii");
      console.log(jsonRaw);
      const meta = JSON.parse(jsonRaw);
      expect(meta["name"]).to.equal("DHT Stake: " + tokenId);
      expect(meta["description"]).to.equal("vDHT Accruing DHT stake");
      expect(meta["attributes"]).to.deep.equals([
        { trait_type: "Staked DHT", value: 100000000000000000000 },
        { trait_type: "vDHT", value: 100000000000000000000 },
      ]);
      expect(meta["image_data"]).to.equal(
        "<svg viewBox='0 0 350 350' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'><style>.a { fill: #00a0d0; font-size: 12px; }</style><text x='0' y='12' class='a'>Token #0</text><text x='0' y='30' class='a'>DHT:100000000000000000000</text><text x='0' y='50' class='a'>DHT Stake Time:365Days </text><text x='0' y='70' class='a'>vDHT:100000000000000000000</text><text x='0' y='70' class='a'>Pool:</text><text x='0' y='70' class='a'>Value Staked:100000000000000000000</text><text x='0' y='50' class='a'>Rewards:0</text></svg>",
      );
    });
  });
});
