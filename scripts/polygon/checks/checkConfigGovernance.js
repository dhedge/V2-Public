const { assert, use } = require("chai");
const chaiAlmost = require("chai-almost");
const csv = require("csvtojson");

use(chaiAlmost());

const { toBytes32 } = require("../../Helpers");

const main = async (initializeData) => {
  const { namesFileName, assetGuardsFileName, contractGuardsFileName, contracts, governance } = initializeData;

  // Check Governance settings
  console.log("Checking Governance settings..");

  const csvNames = await csv().fromFile(namesFileName);

  // Check governance guard mappings match the CSV
  const csvAssetGuards = await csv().fromFile(assetGuardsFileName);
  const csvContractGuards = await csv().fromFile(contractGuardsFileName);

  const names = Object.keys(contracts);
  for (const name of names) {
    if (name.includes("AssetGuard") || name == "ERC20Guard") {
      let guardFound = false;

      for (const csvAssetGuard of csvAssetGuards) {
        if (csvAssetGuard.GuardName == name) {
          guardFound = true;
          const deployedGuard = contracts[name];
          const governanceAssetGuard = await governance.assetGuards(csvAssetGuard.AssetType);

          assert(
            deployedGuard == governanceAssetGuard,
            `Asset guard ${name} deployment doesn't match Governance setting. Governance contract: ${governanceAssetGuard}, Versions deployment: ${deployedGuard}, Asset Type should be ${csvAssetGuard.AssetType}`,
          );
          console.log("Asset guard", name, "ok");
        }
      }

      assert(guardFound, `Asset guard ${name} couldn't be found in the Asset Guard CSV config file.`);
    } else if (name.includes("Guard")) {
      let guardFound = false;

      for (const csvContractGuard of csvContractGuards) {
        if (csvContractGuard.GuardName == name) {
          guardFound = true;
          const deployedGuard = contracts[name];
          const governanceContractGuard = await governance.contractGuards(csvContractGuard.ContractAddress);

          assert(
            deployedGuard == governanceContractGuard,
            `Contract guard ${name} deployment doesn't match Governance setting. Governance contract: ${governanceContractGuard}, Versions deployment: ${deployedGuard}`,
          );
          console.log("Contract guard", name, "ok");
        }
      }

      assert(guardFound, `Contract guard ${name} couldn't be found in the Contract Guard CSV config file.`);
    }
  }

  // Check Governance nameToDestination mappings match the CSV
  for (const csvName of csvNames) {
    const destinationAddress = await governance.nameToDestination(toBytes32(csvName.Name));

    assert(
      csvName.Destination.toLowerCase() == destinationAddress.toLowerCase(),
      `${
        csvName.Name
      } Governance namesToDestination mapping doesn't match Names CSV. Governance contract: ${destinationAddress.toLowerCase()}, CSV: ${csvName.Destination.toLowerCase()}`,
    );

    console.log(`nameToDestination ${csvName.Name} mapping ok`);
  }

  console.log("Governance checks complete!");
  console.log("_________________________________________");
};

module.exports = { main };
