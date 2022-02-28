const { ethers, upgrades } = require("hardhat");
import { Contract, ContractFactory } from "ethers";
const { use, expect } = require("chai");
import { solidity } from "ethereum-waffle";

use(solidity);

const poolAddress = "0x3deeba9ca29e2dd98d32eed8dd559dac55014615";
const decimals = 6;

describe("DHedgePoolPriceOracle", function () {
  let dhedgePoolPriceOracle: Contract;
  let poolLogic: Contract;

  beforeEach(async function () {
    const BalancerDHedgePoolPriceOracle: ContractFactory = await ethers.getContractFactory(
      "BalancerDHedgePoolPriceOracle",
    );
    dhedgePoolPriceOracle = await BalancerDHedgePoolPriceOracle.deploy(poolAddress, decimals);
    await dhedgePoolPriceOracle.deployed();
    const PoolLogic: ContractFactory = await ethers.getContractFactory("PoolLogic");
    // TODO: deploy a new pool and seed it with funds. Can be done after Integration test refactor.
    poolLogic = await PoolLogic.attach(poolAddress);
  });

  // Checks id pool address is set
  it("price should  be the same as token price", async () => {
    const priceFromOracle = await dhedgePoolPriceOracle.getRate();
    console.log("price from oracle ", priceFromOracle.toString());
    const tokenPrice = await poolLogic.tokenPrice();
    console.log("token Price ", tokenPrice.toString());

    expect(priceFromOracle).to.equal(tokenPrice.div(10 ** (18 - decimals)));
  });
});
