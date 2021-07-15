const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, toBytes32 } = require("../../TestHelpers");

use(chaiAlmost());

const units = (value) => ethers.utils.parseUnits(value.toString());

// sushiswap
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";

// For mainnet
const wmatic = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const weth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdt = "0xc2132D05D31c914a87C6611C10748AEb04B58e8F";
const dai = "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

describe("DhedgeSwap Test", function () {
  let WMATIC, WETH, USDC, USDT, DAI;
  let owner;
  let dhedgeSwapTest;

  before(async function () {
    [owner] = await ethers.getSigners();

    const DhedgeSwapTest = await ethers.getContractFactory("DhedgeSwapTest");
    dhedgeSwapTest = await DhedgeSwapTest.deploy(sushiswapV2Router, weth);
    dhedgeSwapTest.deployed();
  });

  it("Should be able to get WMATIC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMATIC = await ethers.getContractAt(IWETH.abi, wmatic);

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, usdt);
    DAI = await ethers.getContractAt(IERC20.abi, dai);
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    WETH = await ethers.getContractAt(IERC20.abi, weth);

    // deposit Matic -> WMATIC
    await WMATIC.deposit({ value: units(500) });
  });

  it("Should be able to swap exact token to token", async function () {
    expect(await WMATIC.balanceOf(dhedgeSwapTest.address)).to.be.equal(0);
    await WMATIC.transfer(dhedgeSwapTest.address, units(500));
    expect(await WMATIC.balanceOf(dhedgeSwapTest.address)).to.be.equal(units(500));

    await dhedgeSwapTest.swapTokensIn(wmatic, usdc, units(200));
    expect(await WMATIC.balanceOf(dhedgeSwapTest.address)).to.be.equal(units(300));
  });

  it("Should be able to swap token to exact token", async function () {
    await dhedgeSwapTest.swapTokensOut(usdc, usdt, (50e6).toString());
    expect(await USDT.balanceOf(dhedgeSwapTest.address)).to.be.equal((50e6).toString());
  });
});
