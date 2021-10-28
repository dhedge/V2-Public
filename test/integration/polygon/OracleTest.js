const { ethers } = require("hardhat");
const chaiAlmost = require("chai-almost");
const { use, expect } = require("chai");

use(chaiAlmost());

const oracleAddress = "0xE749cD67F9e6727b868bB2480195ee301aA4BA33";

describe("DHedgePoolPriceOracle", function () {
  let dhedgePoolPriceOracle;
  let poolLogic;

  beforeEach(async function () {
    const DhedgePoolPriceOracle = await ethers.getContractFactory("DHedgePoolPriceOracle");
    dhedgePoolPriceOracle = await DhedgePoolPriceOracle.attach(oracleAddress);
    const poolAddress = await dhedgePoolPriceOracle.poolAddress();
    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.attach(poolAddress);
  });

  // Checks id pool address is set
  it("price should almost be the same as token price", async () => {
    const priceFromOracle = await dhedgePoolPriceOracle.getPrice();
    console.log("price from oracle ", priceFromOracle.toString());
    const tokenPrice = await poolLogic.tokenPrice();
    console.log("token Price ", tokenPrice.toString());

    //not differ more than 10%
    expect(priceFromOracle.gte(tokenPrice.mul(9).div(10))).to.be.true;
    expect(priceFromOracle.lte(tokenPrice.mul(11).div(10))).to.be.true;
  });
});
