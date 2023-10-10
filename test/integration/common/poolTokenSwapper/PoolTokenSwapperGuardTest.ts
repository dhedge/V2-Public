import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

import {
  IBackboneDeployments,
  IBackboneDeploymentsParams,
  deployBackboneContracts,
} from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import {
  PoolLogic,
  IERC20,
  IERC20__factory,
  PoolManagerLogic,
  PoolTokenSwapper,
  PoolTokenSwapper__factory,
} from "../../../../types";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iPoolTokenSwapper = new ethers.utils.Interface(PoolTokenSwapper__factory.abi);

type IParams = IBackboneDeploymentsParams & {
  assetsBalanceOfSlot: {
    usdc: number;
  };
};

const deployPoolTokenSwapperInfrastructure = async (
  deployments: IBackboneDeployments,
  addresses: { swapWhitelistedPoolLogic: string; swapperEnabledPool: string },
) => {
  const PoolTokenSwapper = await ethers.getContractFactory("PoolTokenSwapper");
  const poolTokenSwapper = <PoolTokenSwapper>(
    await upgrades.deployProxy(PoolTokenSwapper, [
      deployments.poolFactory.address,
      deployments.user.address,
      [{ asset: deployments.assets.USDC.address, assetEnabled: true }],
      [{ pool: addresses.swapperEnabledPool, poolEnabled: true, poolSwapFee: 5 }],
      [{ status: true, sender: addresses.swapWhitelistedPoolLogic }],
    ])
  );
  await poolTokenSwapper.deployed();

  const PoolTokenSwapperGuard = await ethers.getContractFactory("PoolTokenSwapperGuard");
  const poolTokenSwapperGuard = await PoolTokenSwapperGuard.deploy();
  await poolTokenSwapperGuard.deployed();

  await deployments.governance.setContractGuard(poolTokenSwapper.address, poolTokenSwapperGuard.address);

  return poolTokenSwapper.address;
};

export const launchPoolTokenSwapperGuardSwapsTests = (chainData: IParams) => {
  describe("PoolTokenSwapperGuard Swaps Test", () => {
    let deployments: IBackboneDeployments;
    let poolTokenSwapperAddress: string;
    let swapWhitelistedPoolLogic: PoolLogic;
    let swapWhitelistedManagerLogic: PoolManagerLogic;
    let swapWhitelistedPoolAddress: string;
    let manager: SignerWithAddress, logicOwner: SignerWithAddress;
    let USDC: IERC20;
    let usdcAddress: string;
    let swapperEnabledPoolLogic: PoolLogic;
    let swapperEnabledPool: string;

    utils.beforeAfterReset(before, after);

    before(async () => {
      deployments = await deployBackboneContracts(chainData);
      manager = deployments.manager;
      logicOwner = deployments.owner;
      USDC = deployments.assets.USDC;
      usdcAddress = USDC.address;

      const swapperEnabledPoolProxies = await createFund(deployments.poolFactory, logicOwner, manager, [
        { asset: usdcAddress, isDeposit: true },
      ]);
      swapperEnabledPoolLogic = swapperEnabledPoolProxies.poolLogicProxy;
      swapperEnabledPool = swapperEnabledPoolProxies.poolLogicProxy.address;
      const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
      const dHedgePoolAggregator = await DHedgePoolAggregator.deploy(swapperEnabledPool);
      await dHedgePoolAggregator.deployed();
      await deployments.assetHandler.addAssets([
        assetSetting(
          swapperEnabledPool,
          AssetType["Chainlink direct USD price feed with 8 decimals"],
          dHedgePoolAggregator.address,
        ),
      ]);

      // Fund logic owner with 100_000 USDC
      await getAccountToken(units(100_000, 6), logicOwner.address, usdcAddress, chainData.assetsBalanceOfSlot.usdc);
      // Deposit 50_000 USDC into swapper enabled pool
      await USDC.approve(swapperEnabledPool, units(50_000, 6));
      await swapperEnabledPoolProxies.poolLogicProxy.deposit(usdcAddress, units(50_000, 6));

      const poolProxies = await createFund(deployments.poolFactory, logicOwner, manager, [
        {
          asset: usdcAddress,
          isDeposit: true,
        },
        {
          asset: swapperEnabledPool,
          isDeposit: true,
        },
      ]);
      swapWhitelistedPoolLogic = poolProxies.poolLogicProxy;
      swapWhitelistedManagerLogic = poolProxies.poolManagerLogicProxy;
      swapWhitelistedPoolAddress = swapWhitelistedPoolLogic.address;
      poolTokenSwapperAddress = await deployPoolTokenSwapperInfrastructure(deployments, {
        swapWhitelistedPoolLogic: swapWhitelistedPoolAddress,
        swapperEnabledPool: swapperEnabledPool,
      });

      // Deposit 10_000 USDC into swap whitelisted pool
      await USDC.approve(swapWhitelistedPoolAddress, units(10_000, 6));
      await swapWhitelistedPoolLogic.deposit(usdcAddress, units(10_000, 6));
      // Transfer 10_000 pool tokens to pool token swapper
      await deployments.poolFactory.addReceiverWhitelist(poolTokenSwapperAddress);
      await swapperEnabledPoolProxies.poolLogicProxy.transfer(poolTokenSwapperAddress, units(10_000));
      // Transfer 10_000 USDC to pool token swapper
      await USDC.transfer(poolTokenSwapperAddress, units(10_000, 6));
    });

    const approvePoolTokenSwapperAsSpender = async () => {
      await swapWhitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          usdcAddress,
          iERC20.encodeFunctionData("approve", [poolTokenSwapperAddress, units(10_000, 6)]),
        );
    };

    it("should be able to approve PoolTokenSwapper as spender", async () => {
      expect(await USDC.allowance(swapWhitelistedPoolAddress, poolTokenSwapperAddress)).to.be.equal(0);
      await approvePoolTokenSwapperAsSpender();
      expect(await USDC.allowance(swapWhitelistedPoolAddress, poolTokenSwapperAddress)).to.be.equal(units(10_000, 6));
    });

    it("should be able to rebalance pool via PoolTokenSwapper swap method", async () => {
      const totalFundValueBefore = await swapWhitelistedManagerLogic.totalFundValue();
      expect(await USDC.balanceOf(swapWhitelistedPoolAddress)).to.equal(units(10_000, 6));
      expect(await swapperEnabledPoolLogic.balanceOf(swapWhitelistedPoolAddress)).to.equal(0);

      await approvePoolTokenSwapperAsSpender();

      const swapTxData = iPoolTokenSwapper.encodeFunctionData("swap", [
        usdcAddress,
        swapperEnabledPool,
        units(10_000, 6),
        0,
      ]);
      await swapWhitelistedPoolLogic.connect(manager).execTransaction(poolTokenSwapperAddress, swapTxData);

      expect(await USDC.balanceOf(swapWhitelistedPoolAddress)).to.equal(0);
      expect(await swapperEnabledPoolLogic.balanceOf(swapWhitelistedPoolAddress)).to.be.gt(0);
      const totalFundValueAfter = await swapWhitelistedManagerLogic.totalFundValue();
      expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(1_000)); // this is 0.1% delta
    });

    it("should not be able to call different method on PoolTokenSwapper", async () => {
      await expect(
        swapWhitelistedPoolLogic
          .connect(manager)
          .execTransaction(poolTokenSwapperAddress, iPoolTokenSwapper.encodeFunctionData("pause", [])),
      ).to.be.revertedWith("invalid transaction");
    });
  });
};
