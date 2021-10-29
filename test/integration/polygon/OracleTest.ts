const { ethers, upgrades } = require("hardhat");
import { Contract, ContractFactory } from "ethers";
const { use, expect } = require("chai");
import { solidity } from "ethereum-waffle";

use(solidity);

const poolAddress = "0xe3528a438b94e64669def9b875c381c46ef713bf";
const deceimals = 6;

describe("DHedgePoolPriceOracle", function () {
  let dhedgePoolPriceOracle: Contract;
  let poolLogic: Contract;

  beforeEach(async function () {
    const DhedgePoolPriceOracle: ContractFactory = await ethers.getContractFactory("DHedgePoolPriceOracle");
    dhedgePoolPriceOracle = await upgrades.deployProxy(DhedgePoolPriceOracle, [poolAddress, 6]);
    await dhedgePoolPriceOracle.deployed();
    const PoolLogic: ContractFactory = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.attach(poolAddress);
  });

  // Checks id pool address is set
  it("price should almost be the same as token price", async () => {
    const priceFromOracle = await dhedgePoolPriceOracle.getPrice();
    console.log("price from oracle ", priceFromOracle.toString());
    const tokenPrice = await poolLogic.tokenPrice();
    console.log("token Price ", tokenPrice.toString());

    //not differ more than 10% to token price reduced to decimals
    expect(
      priceFromOracle.gte(
        tokenPrice
          .mul(9)
          .div(10)
          .div(10 ** (18 - deceimals)),
      ),
    ).to.be.true;
    expect(
      priceFromOracle.lte(
        tokenPrice
          .mul(11)
          .div(10)
          .div(10 ** (18 - deceimals)),
      ),
    ).to.be.true;
  });
});
