import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { NETWORK } from "../../utils/deployContracts/deployContracts";
import { IDeployments } from "../../utils/deployContracts/deployContracts";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import {
  IERC20__factory,
  IStargateRouter__factory,
  IStargateLpStaking__factory,
  PoolLogic,
  StargateLPAssetGuard,
} from "../../../../types";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iStargateRouter = new ethers.utils.Interface(IStargateRouter__factory.abi);
const iStargateLpStaking = new ethers.utils.Interface(IStargateLpStaking__factory.abi);

interface StargateTestsChainData {
  stargate: {
    router: string;
    staking: string;
    stakingRewardToken: string;
    pools: {
      susdc: {
        address: string;
        poolId: number;
        stakingPoolId: number;
      };
      sdai: {
        address: string;
        poolId: number;
        stakingPoolId: number;
      };
      susdt?: {
        address: string;
        poolId: number;
        stakingPoolId: number;
      };
      ssusd?: {
        address: string;
        poolId: number;
        stakingPoolId: number;
      };
    };
  };
  price_feeds: {
    usdc: string;
    dai: string;
  };
}

export interface TxConfig {
  poolLogic: PoolLogic;
  manager: SignerWithAddress;
  stargate: StargateTestsChainData["stargate"];
}

export interface IStargateLpTestParameters {
  network: NETWORK;
  chainData: StargateTestsChainData;
  asset: {
    lpAssetName: string;
    address: string;
    balanceOfSlot: number;
  };
  depositAmount: BigNumber;
  testScope?: "minimum" | "all";
}

export const stargateTestHelpers = {
  setup: async (
    deployments: IDeployments,
    chainData: StargateTestsChainData,
    stakingRewardToken: string,
  ): Promise<StargateLPAssetGuard> => {
    const governance = deployments.governance;
    const assetHandler = deployments.assetHandler;
    const assetHandlerAssetType = AssetType["Stargate Lp"];
    const assets = [
      {
        asset: chainData.stargate.pools.susdc.address,
        assetType: assetHandlerAssetType,
        aggregator: chainData.price_feeds.usdc,
      },
      {
        asset: chainData.stargate.pools.sdai.address,
        assetType: assetHandlerAssetType,
        aggregator: chainData.price_feeds.dai,
      },
      {
        asset: stakingRewardToken,
        assetType: 0,
        aggregator: chainData.price_feeds.dai, // just make it $1
      },
    ];
    await assetHandler.addAssets(assets);

    const StargateLpStakingContractGuard = await ethers.getContractFactory("StargateLpStakingContractGuard");
    const stargateLpStakingContractGuard = await StargateLpStakingContractGuard.deploy();
    await stargateLpStakingContractGuard.deployed();

    const StargateRouterContractGuard = await ethers.getContractFactory("StargateRouterContractGuard");
    const stargateRouterContractGuard = await StargateRouterContractGuard.deploy();
    await stargateRouterContractGuard.deployed();

    const StargateLPAssetGuard = await ethers.getContractFactory("StargateLPAssetGuard");
    const stargateLPAssetGuard = await StargateLPAssetGuard.deploy(chainData.stargate.staking);
    await stargateLPAssetGuard.deployed();

    await governance.setContractGuard(chainData.stargate.router, stargateRouterContractGuard.address);
    await governance.setContractGuard(chainData.stargate.staking, stargateLpStakingContractGuard.address);
    await governance.setAssetGuard(16, stargateLPAssetGuard.address);

    return stargateLPAssetGuard;
  },

  addLiquidityToStargatePool: async (
    txConfig: TxConfig,
    amount: BigNumber,
    asset: string,
    poolId: number,
    receiver: string = txConfig.poolLogic.address,
  ) => {
    const { poolLogic, stargate, manager } = txConfig;
    const approveData = iERC20.encodeFunctionData("approve", [stargate.router, amount]);
    await poolLogic.connect(manager).execTransaction(asset, approveData);

    const addLiquidityData = iStargateRouter.encodeFunctionData("addLiquidity", [poolId, amount, receiver]);

    await poolLogic.connect(manager).execTransaction(stargate.router, addLiquidityData);
  },

  instantRedeemFromStargatePool: async (
    txConfig: TxConfig,
    amount: BigNumber,
    asset: string,
    poolId: number,
    receiver: string = txConfig.poolLogic.address,
  ) => {
    const { poolLogic, stargate, manager } = txConfig;
    const approveData = iERC20.encodeFunctionData("approve", [stargate.router, amount]);
    await poolLogic.connect(manager).execTransaction(asset, approveData);

    const instantRedeemLocalData = iStargateRouter.encodeFunctionData("instantRedeemLocal", [poolId, amount, receiver]);

    await poolLogic.connect(manager).execTransaction(stargate.router, instantRedeemLocalData);
  },

  stakeStargateLpToken: async (txConfig: TxConfig, amount: BigNumber, asset: string, stakingPoolId: number) => {
    const { poolLogic, stargate, manager } = txConfig;
    const approveData = iERC20.encodeFunctionData("approve", [stargate.staking, amount]);
    await poolLogic.connect(manager).execTransaction(asset, approveData);
    const stakeData = iStargateLpStaking.encodeFunctionData("deposit", [stakingPoolId, amount]);
    await poolLogic.connect(manager).execTransaction(stargate.staking, stakeData);
  },

  unstakeStargateLpToken: async (txConfig: TxConfig, amount: BigNumber, stakingPoolId: number) => {
    const { poolLogic, stargate, manager } = txConfig;
    const unstakeData = iStargateLpStaking.encodeFunctionData("withdraw", [stakingPoolId, amount]);
    await poolLogic.connect(manager).execTransaction(stargate.staking, unstakeData);
  },
};
