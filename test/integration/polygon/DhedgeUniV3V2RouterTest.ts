import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { DhedgeUniV3V2Router } from "../../../types";
import { IERC20 } from "../../../types";
import { checkAlmostSame, units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";

import { polygonChainData } from "../../../config/chainData/polygon-data";
import { utils } from "../utils/utils";
const { assets, assetsBalanceOfSlot, uniswapV3 } = polygonChainData;

describe("DhedgeUniV3V2Router", () => {
  const swapUSDC = units(100, 6);
  const swapDAI = units(100);
  let logicOwner: SignerWithAddress;
  let USDC: IERC20, DAI: IERC20;
  let swapRouter: DhedgeUniV3V2Router;

  before(async () => {
    USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
    DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
  });

  let snapId: string;
  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();

    [logicOwner] = await ethers.getSigners();
    await getAccountToken(swapUSDC.mul(10), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    const SwapRouter = await ethers.getContractFactory("DhedgeUniV3V2Router");
    swapRouter = await SwapRouter.deploy(uniswapV3.factory, uniswapV3.router);
    await swapRouter.deployed();
  });

  it("getAmountsOut", async () => {
    checkAlmostSame((await swapRouter.getAmountsOut(swapUSDC, [assets.usdc, assets.weth, assets.dai]))[2], swapDAI);
  });

  it("swapExactTokensForTokens", async () => {
    await USDC.approve(swapRouter.address, swapUSDC);
    const receiver = ethers.Wallet.createRandom().address;
    await swapRouter.swapExactTokensForTokens(
      swapUSDC,
      0,
      [assets.usdc, assets.weth, assets.dai],
      receiver,
      Math.floor(Date.now() / 1000 + 100000000),
    );
    checkAlmostSame(await DAI.balanceOf(receiver), swapDAI);
  });

  it("getAmountsIn", async () => {
    checkAlmostSame((await swapRouter.getAmountsIn(swapDAI, [assets.usdc, assets.weth, assets.dai]))[0], swapUSDC);
  });

  it("swapTokensForExactTokens", async () => {
    await USDC.approve(swapRouter.address, swapUSDC.mul(2));

    const usdcBalanceBefore = await USDC.balanceOf(logicOwner.address);

    const receiver = ethers.Wallet.createRandom().address;
    await swapRouter.swapTokensForExactTokens(
      swapDAI,
      swapUSDC.mul(2),
      [assets.usdc, assets.weth, assets.dai],
      receiver,
      Math.floor(Date.now() / 1000 + 100000000),
    );

    expect(await DAI.balanceOf(receiver)).to.equal(swapDAI);
    checkAlmostSame((await usdcBalanceBefore).sub(await USDC.balanceOf(logicOwner.address)), swapUSDC);
  });
});
