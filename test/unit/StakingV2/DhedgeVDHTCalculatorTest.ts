import { expect } from "chai";
import { ethers } from "hardhat";
import { DhedgeStakingV2VDHTCalculator } from "../../../types";
import { units } from "../../TestHelpers";

const DAY_IN_SECONDS = 24 * 60 * 60;

const dhtAmount = units(100);
const maxVDurationTime = ethers.BigNumber.from(365 * DAY_IN_SECONDS);

describe("Dhedge DHT Staking V2", () => {
  let dhedgeVDHTCalculator: DhedgeStakingV2VDHTCalculator;
  beforeEach(async () => {
    const DhedgeVDHTCalculator = await ethers.getContractFactory("DhedgeStakingV2VDHTCalculator");
    dhedgeVDHTCalculator = await DhedgeVDHTCalculator.deploy();
  });

  describe("calculateVDHT", () => {
    describe("calculates the correct balance", () => {
      it("0 if not time has elapsed", async () => {
        const result = await dhedgeVDHTCalculator.calculateVDHT(0, dhtAmount, 0, maxVDurationTime);
        expect(result).to.equal(0);
      });

      it("Correct amount after quarter of maxVDuration", async () => {
        const result = await dhedgeVDHTCalculator.calculateVDHT(
          0,
          dhtAmount,
          maxVDurationTime.div(4),
          maxVDurationTime,
        );
        expect(result).to.equal(dhtAmount.div(4));
      });

      it("100% after maxVDurationTime", async () => {
        const result = await dhedgeVDHTCalculator.calculateVDHT(0, dhtAmount, maxVDurationTime, maxVDurationTime);
        expect(result).to.equal(dhtAmount);
      });
    });
  });
});
