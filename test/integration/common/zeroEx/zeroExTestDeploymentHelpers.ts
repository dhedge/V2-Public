import { ethers } from "hardhat";

import { IBackboneDeployments } from "../../utils/deployContracts/deployBackboneContracts";

interface IChainAddresses {
  zeroExExchangeProxy: string;
}

export const deployZeroExContractGuard = async (deployments: IBackboneDeployments, addresses: IChainAddresses) => {
  const ZeroExContractGuard = await ethers.getContractFactory("ZeroExContractGuard");
  const zeroExContractGuard = await ZeroExContractGuard.deploy(deployments.slippageAccumulator.address);
  await zeroExContractGuard.deployed();
  await deployments.governance.setContractGuard(addresses.zeroExExchangeProxy, zeroExContractGuard.address);
};
