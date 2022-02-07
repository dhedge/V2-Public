import { expect } from "chai";
import { ethers } from "hardhat";
import { assets, assetsBalanceOfSlot, curvePools, quickswap, sushi } from "../../../config/chainData/polygon-data";
import { DhedgeSwapRouter__factory } from "../../../types";
import { IERC20 } from "../../../types/IERC20.d";
import { SwapRouter } from "../../../types/SwapRouter";
import { units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";

describe("DhedgeSwapRouter", () => {
  const swapAmount = units(100, 6);
  let USDC: IERC20, WETH: IERC20;
  let SwapRouter: DhedgeSwapRouter__factory;

  before(async () => {
    USDC = await ethers.getContractAt("IERC20", assets.usdc);
    WETH = await ethers.getContractAt("IERC20", assets.weth);
    SwapRouter = await ethers.getContractFactory("DhedgeSwapRouter");
  });

  beforeEach(async () => {
    const [logicOwner] = await ethers.getSigners();
    await getAccountToken(swapAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });

  describe("swapExactTokensForTokens", () => {
    it("via quickswap", async () => {
      const swapRouter: SwapRouter = await SwapRouter.deploy([quickswap.router], []);
      await swapRouter.deployed();

      const swapEventListener = new Promise((res) => {
        swapRouter.on("Swap", async (router: string) => {
          expect(router).to.equal(quickswap.router);
          res(undefined);
        });
      });

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        [assets.usdc, assets.weth],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await WETH.balanceOf(receiver)).gt(0)).to.be.true;
      await swapEventListener;
    });

    it("via curve", async () => {
      const swapRouter: SwapRouter = await SwapRouter.deploy([], [curvePools[0]]);
      await swapRouter.deployed();

      const swapEventListener = new Promise((res) => {
        swapRouter.on("Swap", async (router: string) => {
          expect(router).to.equal(curvePools[0]);
          res(undefined);
        });
      });

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        [assets.usdc, assets.weth],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await WETH.balanceOf(receiver)).gt(0)).to.be.true;
      await swapEventListener;
    });

    it("via all", async () => {
      const swapRouter: SwapRouter = await SwapRouter.deploy([quickswap.router, sushi.router], curvePools);
      await swapRouter.deployed();

      const swapEventListener = new Promise((res) => {
        swapRouter.on("Swap", async () => {
          res(undefined);
        });
      });

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapExactTokensForTokens(
        swapAmount,
        0,
        [assets.usdc, assets.weth],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await WETH.balanceOf(receiver)).gt(0)).to.be.true;
      await swapEventListener;
    });
  });

  describe("swapTokensForExactTokens", () => {
    it("via quickswap", async () => {
      const swapRouter: SwapRouter = await SwapRouter.deploy([quickswap.router], []);
      await swapRouter.deployed();

      const swapEventListener = new Promise((res) => {
        swapRouter.on("Swap", async (router: string) => {
          expect(router).to.equal(quickswap.router);
          res(undefined);
        });
      });

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapTokensForExactTokens(
        0,
        swapAmount,
        [assets.usdc, assets.weth],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await WETH.balanceOf(receiver)).gt(0)).to.be.true;
      await swapEventListener;
    });

    it("via curve", async () => {
      const swapRouter: SwapRouter = await SwapRouter.deploy([], [curvePools[0]]);
      await swapRouter.deployed();

      const swapEventListener = new Promise((res) => {
        swapRouter.on("Swap", async (router: string) => {
          expect(router).to.equal(curvePools[0]);
          res(undefined);
        });
      });

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapTokensForExactTokens(
        0,
        swapAmount,
        [assets.usdc, assets.weth],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await WETH.balanceOf(receiver)).gt(0)).to.be.true;
      await swapEventListener;
    });

    it("via all", async () => {
      const swapRouter: SwapRouter = await SwapRouter.deploy([quickswap.router, sushi.router], curvePools);
      await swapRouter.deployed();

      const swapEventListener = new Promise((res) => {
        swapRouter.on("Swap", async () => {
          res(undefined);
        });
      });

      await USDC.approve(swapRouter.address, swapAmount);
      const receiver = ethers.Wallet.createRandom().address;
      await swapRouter.swapTokensForExactTokens(
        0,
        swapAmount,
        [assets.usdc, assets.weth],
        receiver,
        Math.floor(Date.now() / 1000 + 100000000),
      );
      expect((await WETH.balanceOf(receiver)).gt(0)).to.be.true;
      await swapEventListener;
    });
  });
});
