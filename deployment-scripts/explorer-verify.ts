import { task, types } from "hardhat/config";
import { ovmChainData } from "../config/chainData/ovm-data";

import { getTag, tryVerify } from "./Helpers";
import { getDeploymentData } from "./upgrade/getDeploymentData";

task("explorerVerify", "Verify contracts")
  .addOptionalParam("production", "run against production environment", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const network = await hre.ethers.provider.getNetwork();
    const { addresses, filenames } = getDeploymentData(network.chainId, taskArgs.production ? "production" : "staging");

    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const versions = require(filenames.versionsFileName);
    const currentTag = await getTag();
    console.log("currentTag:", currentTag);
    const contracts = versions[currentTag].contracts;
    const provider = hre.ethers.provider;

    if (contracts.SynthetixGuard) {
      await tryVerify(
        hre,
        contracts.SynthetixGuard,
        "contracts/guards/contractGuards/SynthetixGuard.sol:SynthetixGuard",
        [ovmChainData.synthetix.addressResolver],
      );
    }
    if (contracts.Governance) {
      await tryVerify(hre, contracts.Governance, "contracts/Governance.sol:Governance", []);
    }

    if (contracts.PoolFactory && contracts.PoolFactory.proxy) {
      const implementation = await provider.getStorageAt(
        contracts.PoolFactory.proxy,
        addresses.implementationStorageAddress,
      );
      const address = hre.ethers.utils.hexValue(implementation);
      console.log("PoolFactory: ", address);
      await tryVerify(hre, contracts.PoolFactory.implementation, "contracts/PoolFactory.sol:PoolFactory", []);
    }

    if (contracts.PoolLogic) {
      await tryVerify(hre, contracts.PoolLogic.implementation, "contracts/PoolLogic.sol:PoolLogic", []);
    }

    if (contracts.PoolManagerLogic) {
      await tryVerify(
        hre,
        contracts.PoolManagerLogic.implementation,
        "contracts/PoolManagerLogic.sol:PoolManagerLogic",
        [],
      );
    }

    if (contracts.AssetHandler && contracts.AssetHandler.proxy) {
      const implementation = await provider.getStorageAt(
        contracts.AssetHandler.proxy,
        addresses.implementationStorageAddress,
      );
      const address = hre.ethers.utils.hexValue(implementation);
      console.log("AssetHandler: ", address);
      await tryVerify(hre, address, "contracts/priceAggregators/AssetHandler.sol:AssetHandler", []);
    }

    if (contracts.ERC20Guard) {
      await tryVerify(hre, contracts.ERC20Guard, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);
    }

    if (contracts.PoolPerformance && contracts.PoolPerformance.proxy) {
      const implementation = await provider.getStorageAt(
        contracts.PoolPerformance.proxy,
        addresses.implementationStorageAddress,
      );
      const address = hre.ethers.utils.hexValue(implementation);
      console.log("PoolPerformance: ", address);
      await tryVerify(hre, address, "contracts/PoolPerformance.sol:PoolPerformance", []);
    }
  });
