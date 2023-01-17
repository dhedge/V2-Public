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
      // TODO: AaveLendingPoolAssetGuard in versions file include "V2" and "V3".
      // Ideally it should just be a single guard for both (not deployed twice)
      if (name.includes("AaveLendingPoolAssetGuard")) continue;
      let guardFound = false;

      for (const csvAssetGuard of csvAssetGuards) {
        if (csvAssetGuard.guardName == name) {
          guardFound = true;
          const deployedGuard = contracts[name as keyof IContracts];
          const governanceAssetGuard = await governance.assetGuards(csvAssetGuard.assetType);
          const versionsAssetGuard = contracts[csvAssetGuard.guardName as keyof IContracts] as string;

          assert(
            deployedGuard == governanceAssetGuard,
            `Asset guard ${name} deployment doesn't match Governance setting. Governance contract: ${governanceAssetGuard}, Versions deployment: ${deployedGuard}, Asset Type should be ${csvAssetGuard.assetType}`,
          );
          assert(
            governanceAssetGuard === versionsAssetGuard,
            `Asset guard ${name} type ${csvAssetGuard.assetType} deployment mismatch with the versions file. Governance contract: ${governanceAssetGuard}, Versions address: ${versionsAssetGuard}`,
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
          const guardDescription = csvContractGuard.description;
          const versionsContractGuard = contracts[csvContractGuard.guardName as keyof IContracts] as string;

          assert(
            deployedGuard == governanceContractGuard,
            `Contract guard ${guardDescription} deployment doesn't match Governance setting. Governance contract: ${governanceContractGuard}, Versions deployment: ${deployedGuard}`,
          );
          assert(
            governanceContractGuard == versionsContractGuard,
            `Contract guard ${guardDescription} deployment mismatch with the versions file. Governance contract: ${governanceContractGuard}, Versions address: ${versionsContractGuard}`,
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
