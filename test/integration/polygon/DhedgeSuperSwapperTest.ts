import { expect } from "chai";
import { ethers } from "hardhat";

import { DhedgeSuperSwapper, DhedgeSuperSwapper__factory } from "../../../types";
import { IERC20 } from "../../../types";
import { units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { polygonChainData } from "../../../config/chainData/polygon-data";
import { utils } from "../utils/utils";
const { assets, assetsBalanceOfSlot, curvePools, quickswap, sushi } = polygonChainData;

describe("DhedgeSuperSwapper", () => {
  const swapAmount = units(100, 6);
  let USDC: IERC20, DAI: IERC20;
  let SwapRouter: DhedgeSuperSwapper__factory;

  before(async () => {
    USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
    DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
    SwapRouter = await ethers.getContractFactory("DhedgeSuperSwapper");
  });

  let snapId: string;
  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();
    const [logicOwner] = await ethers.getSigners();
    await getAccountToken(swapAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });

  describe("swapExactTokensForTokens", () => {
    it("via quickswap", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([quickswap.router], []);
      await swapRouter.deployed();

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        [assets.usdc, assets.dai],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await DAI.balanceOf(receiver)).gt(0)).to.be.true;
    });

    // Curve is consistently broken because aaveIncentivesController keeps running out of matic rewards
    it.skip("via curve", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([], [curvePools[0]]);
      await swapRouter.deployed();

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        [assets.usdc, assets.dai],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await DAI.balanceOf(receiver)).gt(0)).to.be.true;
    });

    it("via all", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([quickswap.router, sushi.router], []);
      await swapRouter.deployed();

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        [assets.usdc, assets.dai],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await DAI.balanceOf(receiver)).gt(0)).to.be.true;
    });
  });

  // Note: Curve is not used for swapTokensForExactTokens
  describe("swapTokensForExactTokens", () => {
    it("via quickswap", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([quickswap.router], []);
      await swapRouter.deployed();

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapTokensForExactTokens(
        swapAmount.div(100).mul(99),
        swapAmount,
        [assets.usdc, assets.dai],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await DAI.balanceOf(receiver)).gt(0)).to.be.true;
    });

    it("via all", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([quickswap.router, sushi.router], []);
      await swapRouter.deployed();

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapTokensForExactTokens(
        swapAmount.div(100).mul(99),
        swapAmount,
        [assets.usdc, assets.dai],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await DAI.balanceOf(receiver)).gt(0)).to.be.true;
    });
  });
});
