import { expect } from "chai";
import { ethers } from "hardhat";

import { ovmChainData } from "../../../config/chainData/ovmData";
import versionsUntyped from "../../../publish/ovm/prod/versions.json";
import { IVersions } from "../../../deployment/types";
import { utils } from "../utils/utils";
import { IERC20 } from "../../../types";
import { units } from "../../testHelpers";
import { IERC20Path } from "../utils/deployContracts/deployBackboneContracts";

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const POOL_TO_TEST = "0x49bf093277bf4dde49c48c6aa55a3bda3eedef68"; // USDmny
const INVESTOR = "0x253956aedc059947e700071bc6d74bd8e34fe2ab";

describe("USDmny withdraw simulation", () => {
  utils.beforeAfterReset(beforeEach, afterEach);

  it("should demo investor loss during withdraw", async () => {
    /* Start of upgrading contracts to get the local fixes in */
    const DhedgeSuperSwapper = await ethers.getContractFactory("DhedgeSuperSwapper");
    const v2Routers: string[] = [];

    // Use only existing velodrome V2 swap router (not v1)
    if (versions[latestVersion].contracts.DhedgeVeloV2UniV2Router) {
      v2Routers.push(versions[latestVersion].contracts.DhedgeVeloV2UniV2Router);
    }

    // Deploy new DhedgeUniV3V2Router
    const DhedgeUniV3V2Router = await ethers.getContractFactory("DhedgeUniV3V2Router");
    const dhedgeUniV3V2Router = await DhedgeUniV3V2Router.deploy(
      ovmChainData.uniswapV3.factory,
      ovmChainData.uniswapV3.router,
    );
    await dhedgeUniV3V2Router.deployed();
    v2Routers.push(dhedgeUniV3V2Router.address);

    // Deploy new SwapRouter
    const dhedgeSwapRouter = await DhedgeSuperSwapper.deploy(...[v2Routers, ovmChainData.routeHints]);
    await dhedgeSwapRouter.deployed();

    // Set new SwapRouter in EasySwapper
    const easySwapper = await ethers.getContractAt(
      "DhedgeEasySwapper",
      versions[latestVersion].contracts.DhedgeEasySwapperProxy,
    );
    const easySwapperOwner = await utils.impersonateAccount(await easySwapper.owner());
    await easySwapper.connect(easySwapperOwner).setSwapRouter(dhedgeSwapRouter.address);
    /* End of upgrading to latest changes */

    const poolLogic = await ethers.getContractAt("PoolLogic", POOL_TO_TEST);
    const poolManagerLogicAddress = await poolLogic.poolManagerLogic();
    const poolManagerLogic = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);

    const investor = await utils.impersonateAccount(INVESTOR);
    const investorBalanceBefore = await poolLogic.balanceOf(investor.address);
    const tokenPrice = await poolLogic.tokenPrice();
    const investorValueBefore = investorBalanceBefore.mul(tokenPrice).div(units(1));

    console.log("investorValueBefore", investorValueBefore.div(units(1)));

    const WETH = <IERC20>await ethers.getContractAt(IERC20Path, ovmChainData.assets.weth);
    const investorWETHBalanceBefore = await WETH.balanceOf(investor.address);

    // Using EasySwapper to withdraw for the sake of easier accounting before and after withdraw
    await easySwapper.connect(investor).withdraw(poolLogic.address, investorBalanceBefore, ovmChainData.assets.weth, 0); // should be zero, otherwise it will fail on Withdraw Slippage detected

    expect(await poolLogic.balanceOf(investor.address)).to.be.eq(0);

    const investorWETHBalanceAfter = await WETH.balanceOf(investor.address);
    const wethReceived = investorWETHBalanceAfter.sub(investorWETHBalanceBefore);
    const wethPrice = await poolManagerLogic["assetValue(address,uint256)"](ovmChainData.assets.weth, units(1));
    const investorValueAfter = wethReceived.mul(wethPrice).div(units(1));

    console.log("investorValueAfter", investorValueAfter.div(units(1)));

    expect(investorValueBefore).to.be.closeTo(investorValueAfter, investorValueBefore.div(100)); // accepts slippage 1%
  });
});
