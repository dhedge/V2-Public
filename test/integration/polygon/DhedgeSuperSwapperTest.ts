import { expect } from "chai";
import { ethers } from "hardhat";

import { DhedgeSuperSwapper, DhedgeSuperSwapper__factory, DhedgeUniV3V2Router } from "../../../types";
import { IERC20 } from "../../../types";
import { units } from "../../testHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { polygonChainData } from "../../../config/chainData/polygonData";
import { utils } from "../utils/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const { assets, assetsBalanceOfSlot, quickswap, sushi, routeHints } = polygonChainData;

describe("DhedgeSuperSwapper", () => {
  let logicOwner: SignerWithAddress;
  const swapAmount = units(100, 6);
  let USDC: IERC20, DAI: IERC20, WETH: IERC20, AGEUR: IERC20;
  let SwapRouter: DhedgeSuperSwapper__factory;
  let univ3v2Router: DhedgeUniV3V2Router;

  before(async () => {
    [logicOwner] = await ethers.getSigners();
    USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
    DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
    WETH = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.weth);
    AGEUR = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.agEur);
    SwapRouter = await ethers.getContractFactory("DhedgeSuperSwapper");
    const DhedgeUniV3V2Router = await ethers.getContractFactory("DhedgeUniV3V2Router");
    univ3v2Router = await DhedgeUniV3V2Router.deploy(
      polygonChainData.uniswapV3.factory,
      polygonChainData.uniswapV3.router,
    );
    await univ3v2Router.deployed();
    await getAccountToken(swapAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });

  utils.beforeAfterReset(before, after);
  utils.beforeAfterReset(beforeEach, afterEach);

  describe("swapExactTokensForTokens", () => {
    it("adds usdc multihop", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([univ3v2Router.address], routeHints);
      await swapRouter.deployed();

      const wethAmount = units(1);
      await getAccountToken(wethAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
      await WETH.approve(swapRouter.address, wethAmount);

      await expect(
        swapRouter.swapExactTokensForTokens(
          wethAmount,
          0,
          [assets.weth, assets.agEur],
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        ),
      ).to.emit(swapRouter, "Interpolate");

      const agEurBalance = await AGEUR.balanceOf(logicOwner.address);
      await AGEUR.approve(swapRouter.address, agEurBalance);

      // So we attempt to do the direct pair swap against univ3v2Router
      // this will fail because there is no direct pair we need the supper swapper to interpolate usdc
      await expect(
        univ3v2Router.swapExactTokensForTokens(
          agEurBalance,
          0,
          [assets.agEur, assets.weth],
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        ),
      ).to.be.reverted;

      await expect(
        swapRouter.swapExactTokensForTokens(
          agEurBalance,
          0,
          [assets.agEur, assets.weth],
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        ),
      ).to.emit(swapRouter, "Interpolate");

      expect(await WETH.balanceOf(logicOwner.address)).to.be.closeTo(wethAmount, wethAmount.div(100));
    });

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
    // Curve functionality has been removed from the SwapRouter as it wasn't being used
    it.skip("via curve", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([], []);
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
    it("adds usdc multihop", async () => {
      const swapRouter: DhedgeSuperSwapper = await SwapRouter.deploy([univ3v2Router.address], routeHints);
      await swapRouter.deployed();

      const wethAmount = units(1);
      await getAccountToken(wethAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
      await WETH.approve(swapRouter.address, wethAmount);

      const [, , amountExpected] = await swapRouter.getAmountsOut(wethAmount, [assets.weth, assets.usdc, assets.agEur]);
      await expect(
        swapRouter.swapTokensForExactTokens(
          amountExpected.mul(99).div(100),
          wethAmount,
          [assets.weth, assets.agEur],
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        ),
      ).to.emit(swapRouter, "Interpolate");

      expect(await AGEUR.balanceOf(logicOwner.address)).to.equal(amountExpected.mul(99).div(100));
    });

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

  // Note: getAmountsOut is a method used by EasySwapper to quote the amount of tokens that will be received during deposit
  describe("getAmountsOut", () => {
    it("ensures that quote amount matches actual swap amount when multihop is used", async () => {
      const swapRouter = await SwapRouter.deploy([univ3v2Router.address], routeHints);
      await swapRouter.deployed();

      const wethAmount = units(1);
      await getAccountToken(wethAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
      await WETH.approve(swapRouter.address, wethAmount);

      const path = [assets.weth, assets.agEur];
      const quote = await swapRouter.getAmountsOut(wethAmount, path);
      await swapRouter.swapExactTokensForTokens(wethAmount, 0, path, logicOwner.address, ethers.constants.MaxUint256);

      const agEurBalance = await AGEUR.balanceOf(logicOwner.address);
      expect(agEurBalance).to.equal(quote[quote.length - 1]);
    });

    it("ensures that quote amount matches actual swap amount when multihop is NOT used", async () => {
      const swapRouter = await SwapRouter.deploy([univ3v2Router.address], routeHints);
      await swapRouter.deployed();

      const usdcAmount = units(1000, 6);
      await getAccountToken(usdcAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await USDC.approve(swapRouter.address, usdcAmount);

      const path = [assets.usdc, assets.weth];
      const quote = await swapRouter.getAmountsOut(usdcAmount, path);
      await swapRouter.swapExactTokensForTokens(usdcAmount, 0, path, logicOwner.address, ethers.constants.MaxUint256);

      const wethBalance = await WETH.balanceOf(logicOwner.address);
      expect(wethBalance).to.equal(quote[quote.length - 1]);
    });
  });
});
