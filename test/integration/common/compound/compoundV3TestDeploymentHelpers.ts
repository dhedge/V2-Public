import { ethers } from "hardhat";

import { IBackboneDeployments, IBackboneDeploymentsParams } from "../../utils/deployContracts/deployBackboneContracts";

import { IERC20__factory, ICompoundV3Comet__factory, ICompoundV3CometRewards__factory } from "../../../../types";
import { BigNumber } from "ethers";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

export type ICompoundV3TestParams = IBackboneDeploymentsParams & {
  assetName: string;
  cAsset: string;
  baseAsset: string;
  baseAssetSlot: number;
  baseAssetAmount: BigNumber;
  cAssetPriceFeed: string;
  rewards: string;
  easySwapperV2: {
    swapper: string;
    wrappedNativeToken: string;
  };
};

export const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

export const iCompoundV3Comet = new ethers.utils.Interface(ICompoundV3Comet__factory.abi);

export const iCompoundV3CometRewards = new ethers.utils.Interface(ICompoundV3CometRewards__factory.abi);

export const deployCompoundV3Infrastructure = async (
  deployments: IBackboneDeployments,
  testParams: ICompoundV3TestParams,
) => {
  const CompoundV3CometContractGuard = await ethers.getContractFactory("CompoundV3CometContractGuard");
  const compoundV3CometContractGuard = await CompoundV3CometContractGuard.deploy({});
  await compoundV3CometContractGuard.deployed();

  const CompoundV3CometRewardsContractGuard = await ethers.getContractFactory("CompoundV3CometRewardsContractGuard");
  const compoundV3CometRewardsContractGuard = await CompoundV3CometRewardsContractGuard.deploy({});
  await compoundV3CometRewardsContractGuard.deployed();

  await deployments.governance.setContractGuard(testParams.cAsset, compoundV3CometContractGuard.address);

  await deployments.governance.setContractGuard(testParams.rewards, compoundV3CometRewardsContractGuard.address);

  const CompoundV3CometAssetGuard = await ethers.getContractFactory("CompoundV3CometAssetGuard");
  const compoundV3CometAssetGuard = await CompoundV3CometAssetGuard.deploy();
  await compoundV3CometAssetGuard.deployed();

  await deployments.governance.setAssetGuard(AssetType["Compound V3 Comet Asset"], compoundV3CometAssetGuard.address);

  await deployments.assetHandler.addAssets([
    assetSetting(testParams.cAsset, AssetType["Compound V3 Comet Asset"], testParams.cAssetPriceFeed),
    assetSetting(
      testParams.baseAsset,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      testParams.cAssetPriceFeed,
    ),
  ]);

  await deployments.assetHandler.setChainlinkTimeout(86400 * 365); // 365 days expiry
};
