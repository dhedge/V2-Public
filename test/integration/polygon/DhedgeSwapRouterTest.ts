import { expect } from "chai";
import { ethers } from "hardhat";
import { assets, assetsBalanceOfSlot, curvePools, quickswap, sushi } from "../../../config/chainData/polygon-data";
import { DhedgeSwapRouter, DhedgeSwapRouter__factory } from "../../../types";
import { IERC20 } from "../../../types/IERC20.d";
import { units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";

describe("DhedgeSwapRouter", () => {
  const swapAmount = units(100, 6);
  let USDC: IERC20, DAI: IERC20;
  let SwapRouter: DhedgeSwapRouter__factory;
  let snapshot: any;

  before(async () => {
    USDC = await ethers.getContractAt("IERC20", assets.usdc);
    DAI = await ethers.getContractAt("IERC20", assets.dai);
    SwapRouter = await ethers.getContractFactory("DhedgeSwapRouter");
  });

  beforeEach(async () => {
    snapshot = await ethers.provider.send("evm_snapshot", []);
    const [logicOwner] = await ethers.getSigners();
    await getAccountToken(swapAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });

  afterEach(async () => {
    await ethers.provider.send("evm_revert", [snapshot]);
  });

  describe("swapExactTokensForTokens", () => {
    it("via quickswap", async () => {
      const swapRouter: DhedgeSwapRouter = await SwapRouter.deploy([quickswap.router], []);
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

    it("via curve", async () => {
      const swapRouter: DhedgeSwapRouter = await SwapRouter.deploy([], [curvePools[0]]);
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
      const swapRouter: DhedgeSwapRouter = await SwapRouter.deploy([quickswap.router, sushi.router], curvePools);
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
      const swapRouter: DhedgeSwapRouter = await SwapRouter.deploy([quickswap.router], []);
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
      const swapRouter: DhedgeSwapRouter = await SwapRouter.deploy([quickswap.router, sushi.router], curvePools);
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
