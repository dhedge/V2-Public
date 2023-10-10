import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../testHelpers";
import { DhedgeSwapTest, IERC20, IWETH } from "../../../types";
import { polygonChainData } from "../../../config/chainData/polygonData";
import { utils } from "../utils/utils";
const { assets, sushi } = polygonChainData;

describe("DhedgeSwap Test", function () {
  let WMATIC: IWETH, USDT: IERC20;
  let dhedgeSwapTest: DhedgeSwapTest;

  let snapId: string;
  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  before(async () => {
    snapId = await utils.evmTakeSnap();
    const DhedgeSwapTest = await ethers.getContractFactory("DhedgeSwapTest");
    dhedgeSwapTest = await DhedgeSwapTest.deploy(sushi.router, assets.weth);
    dhedgeSwapTest.deployed();
  });

  it("Should be able to get WMATIC", async function () {
    WMATIC = await ethers.getContractAt("IWETH", assets.wmatic);
    USDT = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdt);

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
