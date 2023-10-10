import { ethers } from "hardhat";
import { Address } from "../../../../deployment/types";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { IDeployments } from "../../utils/deployContracts/deployContracts";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";

export const deployMai = async (
  deployments: IDeployments,
  maiData: {
    maiAddress: Address;
    maiPriceFeed: Address;
    maiVaultAddress: Address;
    usdc: Address;
    aaveV3LendingPool: Address;
  },
) => {
  const { usdc, aaveV3LendingPool, maiVaultAddress, maiAddress, maiPriceFeed } = maiData;
  const MaiVaultAssetGuard = await ethers.getContractFactory("MaiVaultAssetGuard");
  const maiVaultAssetGuard = await MaiVaultAssetGuard.deploy(usdc, aaveV3LendingPool);
  await maiVaultAssetGuard.deployed();

  const MaiVaultContractGuard = await ethers.getContractFactory("MaiVaultContractGuard");
  const maiVaultContractGuard = await MaiVaultContractGuard.deploy(deployments.dhedgeNftTrackerStorage.address);
  await maiVaultContractGuard.deployed();

  await deployments.governance.setAssetGuard(AssetType["Mai Vault Asset"], maiVaultAssetGuard.address);
  await deployments.governance.setContractGuard(maiVaultAddress, maiVaultContractGuard.address);

  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  const maiVaultAsset = assetSetting(maiVaultAddress, AssetType["Mai Vault Asset"], usdPriceAggregator.address);
  const mai = assetSetting(maiAddress, AssetType["Chainlink direct USD price feed with 8 decimals"], maiPriceFeed);
  await deployments.assetHandler.addAssets([maiVaultAsset, mai]);
};
