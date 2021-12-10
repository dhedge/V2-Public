import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { units } from "../../TestHelpers";
import { assets, sushi } from "../polygon-data";
import { DhedgeSwapTest, IERC20, IWETH } from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

use(solidity);

describe("DhedgeSwap Test", function () {
  let WMATIC: IWETH, WETH: IERC20, USDC: IERC20, USDT: IERC20, DAI: IERC20;
  let owner: SignerWithAddress;
  let dhedgeSwapTest: DhedgeSwapTest;

  before(async function () {
    [owner] = await ethers.getSigners();

    const DhedgeSwapTest = await ethers.getContractFactory("DhedgeSwapTest");
    dhedgeSwapTest = await DhedgeSwapTest.deploy(sushi.router, assets.weth);
    dhedgeSwapTest.deployed();
  });

  it("Should be able to get WMATIC", async function () {
    WMATIC = await ethers.getContractAt("IWETH", assets.wmatic);
    USDT = await ethers.getContractAt("IERC20", assets.usdt);
    DAI = await ethers.getContractAt("IERC20", assets.dai);
    USDC = await ethers.getContractAt("IERC20", assets.usdc);
    WETH = await ethers.getContractAt("IERC20", assets.weth);

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
