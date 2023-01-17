import { InitType } from "./initialize";
import { expect, assert } from "chai";

export const checkFactory = async (initializeData: InitType) => {
  const { protocolTreasury, poolFactoryProxy, assetHandlerProxy, governance, poolFactory } = initializeData;

  // Check Factory settings
  console.log("Checking Factory settings..");

  try {
    await poolFactory.implInitializer();
    assert(false, "poolFactory implementation Should be already initialized");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (e: any) {
    console.error(e.error.message);
    assert(e.error.message.includes("already initialized"), "PoolFactory implementation should be initialised");
    console.log("PoolFactory Implementation is initialized.");
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
