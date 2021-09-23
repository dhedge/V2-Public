const { ethers } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { units } = require("../../TestHelpers");
const { sushi, assets } = require("../polygon-data");

use(chaiAlmost());

describe("DhedgeSwap Test", function () {
  let WMATIC, WETH, USDC, USDT, DAI;
  let owner;
  let dhedgeSwapTest;

  before(async function () {
    [owner] = await ethers.getSigners();

    const DhedgeSwapTest = await ethers.getContractFactory("DhedgeSwapTest");
    dhedgeSwapTest = await DhedgeSwapTest.deploy(sushi.router, assets.weth);
    dhedgeSwapTest.deployed();
  });

  it("Should be able to get WMATIC", async function () {
    const IWETH = await hre.artifacts.readArtifact("IWETH");
    WMATIC = await ethers.getContractAt(IWETH.abi, assets.wmatic);

    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    USDT = await ethers.getContractAt(IERC20.abi, assets.usdt);
    DAI = await ethers.getContractAt(IERC20.abi, assets.dai);
    USDC = await ethers.getContractAt(IERC20.abi, assets.usdc);
    WETH = await ethers.getContractAt(IERC20.abi, assets.weth);

    // deposit Matic -> WMATIC
    await WMATIC.deposit({ value: units(500) });
  });

  it("Should be able to swap exact token to token", async function () {
    expect(await WMATIC.balanceOf(dhedgeSwapTest.address)).to.be.equal(0);
    await WMATIC.transfer(dhedgeSwapTest.address, units(500));
    expect(await WMATIC.balanceOf(dhedgeSwapTest.address)).to.be.equal(units(500));

    await dhedgeSwapTest.swapTokensIn(assets.wmatic, assets.usdc, units(200));
    expect(await WMATIC.balanceOf(dhedgeSwapTest.address)).to.be.equal(units(300));
  });

  it("Should be able to swap token to exact token", async function () {
    await dhedgeSwapTest.swapTokensOut(assets.usdc, assets.usdt, (50e6).toString());
    expect(await USDT.balanceOf(dhedgeSwapTest.address)).to.be.equal((50e6).toString());
  });
});
