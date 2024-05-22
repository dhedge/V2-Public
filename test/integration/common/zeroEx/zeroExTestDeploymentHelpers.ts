import { ethers } from "hardhat";

import { IBackboneDeployments, IERC20Path } from "../../utils/deployContracts/deployBackboneContracts";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { IERC20 } from "../../../../types";

interface IChainAddresses {
  zeroExExchangeProxy: string;
  usdtAddress: string;
  usdtPriceFeed: string;
}

export const deployZeroExContractGuard = async (deployments: IBackboneDeployments, addresses: IChainAddresses) => {
  const ZeroExContractGuard = await ethers.getContractFactory("ZeroExContractGuard");
  const zeroExContractGuard = await ZeroExContractGuard.deploy(deployments.slippageAccumulator.address);
  await zeroExContractGuard.deployed();
  await deployments.governance.setContractGuard(addresses.zeroExExchangeProxy, zeroExContractGuard.address);
  await deployments.assetHandler.addAsset(
    addresses.usdtAddress,
    AssetType["Lending Enable Asset"],
    addresses.usdtPriceFeed,
  );
  const tether = <IERC20>await ethers.getContractAt(IERC20Path, addresses.usdtAddress);
  return { tether };
};
