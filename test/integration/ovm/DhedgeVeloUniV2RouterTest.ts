import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";

import { ovmChainData } from "../../../config/chainData/ovmData";
import { DhedgeVeloUniV2Router, DhedgeVeloV2UniV2Router, IERC20 } from "../../../types";
import { units } from "../../testHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { utils } from "../utils/utils";

const { assets, assetsBalanceOfSlot, velodrome, velodromeV2 } = ovmChainData;

type IDhedgeVeloRouter = DhedgeVeloUniV2Router | DhedgeVeloV2UniV2Router;
type ITestParam = {
  routerContractName: "DhedgeVeloUniV2Router" | "DhedgeVeloV2UniV2Router";
  args: string[];
};

const runTests = ({ routerContractName, args }: ITestParam) => {
  describe(`${routerContractName}Test`, () => {
    let logicOwner: SignerWithAddress;
    let DAI: IERC20, USDC: IERC20, WETH: IERC20;
    let dhedgeVeloUniV2Router: IDhedgeVeloRouter;

    utils.beforeAfterReset(before, after);
    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      [logicOwner] = await ethers.getSigners();
      DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
      USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
      WETH = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.weth);

      const DhedgeVeloUniV2Router = await ethers.getContractFactory(routerContractName);
      dhedgeVeloUniV2Router = <IDhedgeVeloRouter>await DhedgeVeloUniV2Router.deploy(...args);
      await dhedgeVeloUniV2Router.deployed();
    });

    describe("swapExactTokensForTokens", () => {
      it("handles 1 hop route", async () => {
        const usdcAmount = units(100, 6);
        await getAccountToken(usdcAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
        await USDC.approve(dhedgeVeloUniV2Router.address, usdcAmount);
        const path = [assets.usdc, assets.dai];

        const amountOuts = await dhedgeVeloUniV2Router.getAmountsOut(usdcAmount, path);

        await dhedgeVeloUniV2Router.swapExactTokensForTokens(
          usdcAmount,
          0,
          path,
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        );

        const daiBalance = await DAI.balanceOf(logicOwner.address);

        expect(daiBalance).to.be.equal(amountOuts[1]);

        await DAI.approve(dhedgeVeloUniV2Router.address, daiBalance);
        path.reverse();
        await dhedgeVeloUniV2Router.swapExactTokensForTokens(
          daiBalance,
          0,
          path,
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        );
        expect(await USDC.balanceOf(logicOwner.address)).to.be.closeTo(usdcAmount, usdcAmount.div(1000)); // 0.1%s
      });

      it("handles 2 hop route", async () => {
        const wethAmount = units(1);
        await getAccountToken(wethAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
        await WETH.approve(dhedgeVeloUniV2Router.address, wethAmount);

        const path = [assets.weth, assets.usdc, assets.dai];

        const amountOuts = await dhedgeVeloUniV2Router.getAmountsOut(wethAmount, path);

        await dhedgeVeloUniV2Router.swapExactTokensForTokens(
          wethAmount,
          0,
          path,
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        );

        const daiBalance = await DAI.balanceOf(logicOwner.address);
        expect(daiBalance).to.be.equal(amountOuts[2]);
        await DAI.approve(dhedgeVeloUniV2Router.address, daiBalance);
        path.reverse();
        await dhedgeVeloUniV2Router.swapExactTokensForTokens(
          daiBalance,
          0,
          path,
          logicOwner.address,
          Math.floor(Date.now() / 1000 + 100000000),
        );
        expect(await WETH.balanceOf(logicOwner.address)).to.be.closeTo(wethAmount, wethAmount.div(100)); // 1%
      });

      it("reverts on > 2 hops", async () => {
        const path = [assets.weth, assets.usdc, assets.op, assets.dai];
        await expect(
          dhedgeVeloUniV2Router.swapExactTokensForTokens(
            1,
            0,
            path,
            logicOwner.address,
            Math.floor(Date.now() / 1000 + 100000000),
          ),
        ).to.be.revertedWith("too many hops");
      });
    });
  });
};

[
  {
    routerContractName: "DhedgeVeloUniV2Router" as const,
    args: [velodrome.router],
  },
  {
    routerContractName: "DhedgeVeloV2UniV2Router" as const,
    args: [velodromeV2.router, velodromeV2.factory],
  },
].forEach(runTests);
