import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";

import { polygonChainData } from "../../../config/chainData/polygonData";
import { IERC20, PoolManagerLogic } from "../../../types";
import { createFund } from "../utils/createFund";
import { IBackboneDeployments, deployBackboneContracts } from "../utils/deployContracts/deployBackboneContracts";
import { utils } from "../utils/utils";

describe("changeAssets", () => {
  let deployments: IBackboneDeployments;
  let poolManagerLogicProxy: PoolManagerLogic;
  let manager: SignerWithAddress, logicOwner: SignerWithAddress;
  let USDC: IERC20, DAI: IERC20;
  let usdcAddress: string;
  let daiAddress: string;

  utils.beforeAfterReset(beforeEach, afterEach);

  before(async () => {
    deployments = await deployBackboneContracts(polygonChainData);
    manager = deployments.manager;
    logicOwner = deployments.owner;
    USDC = deployments.assets.USDC;
    DAI = deployments.assets.DAI;
    usdcAddress = USDC.address;
    daiAddress = DAI.address;
    const supportedAssets = [
      {
        asset: usdcAddress,
        isDeposit: true,
      },
      {
        asset: daiAddress,
        isDeposit: false,
      },
    ];
    const poolProxies = await createFund(deployments.poolFactory, logicOwner, manager, supportedAssets);
    poolManagerLogicProxy = poolProxies.poolManagerLogicProxy;
  });

  it("should not allow unauthorized change assets in a vault", async () => {
    const [fundCompositionBefore] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionBefore.length).to.be.eq(2);
    expect(fundCompositionBefore.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress, daiAddress]);

    await expect(poolManagerLogicProxy.connect(deployments.user).changeAssets([], [daiAddress])).to.be.revertedWith(
      "only manager, trader or owner",
    );

    const [fundCompositionAfter] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionAfter.length).to.be.eq(2);
    expect(fundCompositionAfter.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress, daiAddress]);
  });

  it("should allow owner to change assets in a vault", async () => {
    const [fundCompositionBefore] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionBefore.length).to.be.eq(2);
    expect(fundCompositionBefore.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress, daiAddress]);

    await poolManagerLogicProxy.connect(logicOwner).changeAssets([], [daiAddress]);

    const [fundCompositionAfter] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionAfter.length).to.be.eq(1);
    expect(fundCompositionAfter.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress]);
  });

  it("should allow manager to change assets in a vault", async () => {
    const [fundCompositionBefore] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionBefore.length).to.be.eq(2);
    expect(fundCompositionBefore.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress, daiAddress]);

    await poolManagerLogicProxy.connect(manager).changeAssets([], [daiAddress]);

    const [fundCompositionAfter] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionAfter.length).to.be.eq(1);
    expect(fundCompositionAfter.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress]);
  });

  it("should allow trader to change assets in a vault", async () => {
    await poolManagerLogicProxy.connect(manager).setTrader(deployments.user.address);

    const [fundCompositionBefore] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionBefore.length).to.be.eq(2);
    expect(fundCompositionBefore.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress, daiAddress]);

    await poolManagerLogicProxy.connect(deployments.user).changeAssets([], [daiAddress]);

    const [fundCompositionAfter] = await poolManagerLogicProxy.getFundComposition();
    expect(fundCompositionAfter.length).to.be.eq(1);
    expect(fundCompositionAfter.map(({ asset }) => asset)).to.be.deep.eq([usdcAddress]);
  });
});
