const { expect, assert } = require("chai");

const main = async (initializeData) => {
  const { protocolTreasury, poolFactoryProxy, assetHandlerProxy, governance, poolFactory } = initializeData;

  // Check Factory settings
  console.log("Checking Factory settings..");

  try {
    await poolFactory.implInitializer();
    assert(false, "poolFactory implementation Should be already initialized");
  } catch (e) {
    assert(e.error.message.includes("contract is already initialized"));
    console.log("Pool Factory Implementation is initialized.");
  }

  const protocolTreasurySetting = await poolFactoryProxy.daoAddress();
  expect(protocolTreasurySetting).to.equal(protocolTreasury);
  console.log("Protocol Treasury address:", protocolTreasury);

  const governanceSetting = await poolFactoryProxy.governanceAddress();
  expect(governanceSetting).to.equal(governance.address);
  console.log("Governance address:", governance.address);

  const assetHandlerSetting = await poolFactoryProxy.getAssetHandler();
  expect(assetHandlerSetting).to.equal(assetHandlerProxy.address);
  console.log("Asset Handler address:", assetHandlerProxy.address);

  console.log("Factory settings checks complete!");
  console.log("_________________________________________");
};

module.exports = { main };
