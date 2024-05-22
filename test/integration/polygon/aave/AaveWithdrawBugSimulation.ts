import { expect } from "chai";
import { ethers } from "hardhat";

import { polygonChainData } from "../../../../config/chainData/polygonData";
import versionsUntyped from "../../../../publish/polygon/prod/versions.json";
import { IVersions } from "../../../../deployment/types";
import { utils } from "../../utils/utils";
import { IERC20 } from "../../../../types";
import { units } from "../../../testHelpers";
import { IERC20Path } from "../../utils/deployContracts/deployBackboneContracts";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const POOL_TO_TEST = "0x46b1adc3b1ca80ae3c003649efae4039544f02e9"; // https://dhedge.org/vault/0x46b1adc3b1ca80ae3c003649efae4039544f02e9 AlgoTraveler MATIC
const INVESTOR = "0x0828114A8B78615F2F764C9EcF797BF819917aD2"; // https://polygonscan.com/address/0x0828114A8B78615F2F764C9EcF797BF819917aD2

/* To run this test, first fork the chain using `fork:polygon:aave-fix` script */
describe("AaveWithdrawBugSimulation", () => {
  utils.beforeAfterReset(beforeEach, afterEach);

  it("should demo investor lost more than 50% during withdraw", async () => {
    const poolLogic = await ethers.getContractAt("PoolLogic", POOL_TO_TEST);
    const poolManagerLogicAddress = await poolLogic.poolManagerLogic();
    const poolManagerLogic = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);

    const investor = await utils.impersonateAccount(INVESTOR);
    const investorBalanceBefore = await poolLogic.balanceOf(investor.address);
    const tokenPrice = await poolLogic.tokenPrice();
    const investorValueBefore = investorBalanceBefore.mul(tokenPrice).div(units(1));
    console.log("investorValueBefore", investorValueBefore.div(units(1)));
    const WETH = <IERC20>await ethers.getContractAt(IERC20Path, polygonChainData.assets.weth);
    const investorWETHBalanceBefore = await WETH.balanceOf(investor.address);

    // Using EasySwapper to withdraw just for the sake of easier accounting before and after withdraw
    const easySwapper = await ethers.getContractAt(
      "DhedgeEasySwapper",
      versions[latestVersion].contracts.DhedgeEasySwapperProxy,
    );
    await easySwapper
      .connect(investor)
      .withdraw(poolLogic.address, investorBalanceBefore, polygonChainData.assets.weth, 0); // should be zero, otherwise it will fail on Withdraw Slippage detected, but investor in fact did a normal withdraw

    expect(await poolLogic.balanceOf(investor.address)).to.be.eq(0);

    const investorWETHBalanceAfter = await WETH.balanceOf(investor.address);
    const wethReceived = investorWETHBalanceAfter.sub(investorWETHBalanceBefore);
    const wethPrice = await poolManagerLogic["assetValue(address,uint256)"](polygonChainData.assets.weth, units(1));
    const investorValueAfter = wethReceived.mul(wethPrice).div(units(1));
    console.log("investorValueAfter", investorValueAfter.div(units(1)));

    expect(investorValueBefore).to.be.gt(investorValueAfter.mul(15).div(10)); // investor lost more than 50% of his initial value
  });

  it("should demo the fix works and withdraw reverts due to high withdraw slippage", async () => {
    /* Start of upgrading PoolLogic to latest changes */
    const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
    const poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);
    const PoolFactory = await ethers.getContractFactory("PoolFactory");

    const proxyAdmin = await ethers.getContractAt("ProxyAdmin", polygonChainData.proxyAdmin);
    const poolFactoryOwner = await utils.impersonateAccount(await poolFactory.owner());
    await proxyAdmin.connect(poolFactoryOwner).upgrade(poolFactoryProxy, (await PoolFactory.deploy()).address);

    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    await poolFactory
      .connect(poolFactoryOwner)
      .setLogic((await PoolLogic.deploy()).address, (await PoolManagerLogic.deploy()).address);

    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
      polygonChainData.aaveV3.protocolDataProvider,
      polygonChainData.aaveV3.lendingPool,
    );
    await aaveLendingPoolAssetGuard.deployed();

    const governance = await ethers.getContractAt("Governance", versions[latestVersion].contracts.Governance);
    const governanceOwner = await utils.impersonateAccount(await governance.owner());
    await governance
      .connect(governanceOwner)
      .setAssetGuard(AssetType["Aave V3 Lending Pool Asset"], aaveLendingPoolAssetGuard.address);
    /* End of upgrading PoolLogic to latest changes */

    const poolLogic = await ethers.getContractAt("PoolLogic", POOL_TO_TEST);
    const investor = await utils.impersonateAccount(INVESTOR);
    const investorBalanceBefore = await poolLogic.balanceOf(investor.address);

    await expect(poolLogic.connect(investor).withdrawSafe(investorBalanceBefore, 5_000)).to.be.revertedWith(
      "high withdraw slippage",
    ); // reverts even when 50% slippage is allowed
  });
});
