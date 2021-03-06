import { InitType } from "./initialize";
import { assert } from "chai";
import csv from "csvtojson";

import { toBytes32 } from "../Helpers";
import { IContracts } from "../types";

export const checkGovernance = async (initializeData: InitType) => {
  const { namesFileName, assetGuardsFileName, contractGuardsFileName, contracts, governance } = initializeData;

  // Check Governance settings
  console.log("Checking Governance settings..");

  const csvNames = (namesFileName && (await csv().fromFile(namesFileName))) || [];

  // Check governance guard mappings match the CSV
  const csvAssetGuards = await csv().fromFile(assetGuardsFileName);
  const csvContractGuards = await csv().fromFile(contractGuardsFileName);

  const names = Object.keys(contracts);
  for (const name of names) {
    if (name.includes("AssetGuard") || name == "ERC20Guard") {
      if (name == "OpenAssetGuard") continue; // OpenAssetGuard is not on the asset guard list
      let guardFound = false;

      for (const csvAssetGuard of csvAssetGuards) {
        if (csvAssetGuard.guardName == name) {
          guardFound = true;
          const deployedGuard = contracts[name as keyof IContracts];
          const governanceAssetGuard = await governance.assetGuards(csvAssetGuard.assetType);
          const csvAssetGuardAddress = csvAssetGuard.guardAddress;

          assert(
            deployedGuard == governanceAssetGuard,
            `Asset guard ${name} deployment doesn't match Governance setting. Governance contract: ${governanceAssetGuard}, Versions deployment: ${deployedGuard}, Asset Type should be ${csvAssetGuard.assetType}`,
          );
          assert(
            governanceAssetGuard == csvAssetGuardAddress,
            `Asset guard ${name} deployment doesn't match Asset Guard CSV. Governance contract: ${governanceAssetGuard}, CSV Asset Guards: ${csvAssetGuardAddress}`,
          );
          console.log("Asset guard", name, "ok");
        }
      }

      assert(guardFound, `Asset guard ${name} couldn't be found in the Asset Guard CSV config file.`);
    } else if (name.includes("Guard")) {
      let guardFound = false;

      for (const csvContractGuard of csvContractGuards) {
        if (csvContractGuard.guardName == name) {
          guardFound = true;
          const deployedGuard = contracts[name as keyof IContracts];
          const governanceContractGuard = await governance.contractGuards(csvContractGuard.contractAddress);
          const csvContractGuardAddress = csvContractGuard.guardAddress;
          const guardDescription = csvContractGuard.description;

          assert(
            deployedGuard == governanceContractGuard,
            `Contract guard ${guardDescription} deployment doesn't match Governance setting. Governance contract: ${governanceContractGuard}, Versions deployment: ${deployedGuard}`,
          );
          assert(
            governanceContractGuard == csvContractGuardAddress,
            `Contract guard ${guardDescription} deployment doesn't match Contract Guard CSV. Governance contract: ${governanceContractGuard}, CSV Contract Guards: ${csvContractGuardAddress}`,
          );
          console.log("Contract guard", guardDescription, "ok");
        }
      }

      assert(guardFound, `Contract guard ${name} couldn't be found in the Contract Guard CSV config file.`);
    }
  }

  // Check Governance nameToDestination mappings match the CSV
  for (const csvName of csvNames) {
    const destinationAddress = await governance.nameToDestination(toBytes32(csvName.name));

    assert(
      csvName.destination.toLowerCase() == destinationAddress.toLowerCase(),
      `${
        csvName.name
      } Governance namesToDestination mapping doesn't match Names CSV. Governance contract: ${destinationAddress.toLowerCase()}, CSV: ${csvName.destination.toLowerCase()}`,
    );

    console.log(`nameToDestination ${csvName.name} mapping ok`);
  }

  console.log("Governance checks complete!");
  console.log("_________________________________________");
};
