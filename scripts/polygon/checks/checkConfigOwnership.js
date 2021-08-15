const { expect, assert, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const main = async (initializeData) => {
  const {
    protocolDao,
    proxyAdmin,
    poolFactoryProxy,
    assetHandlerProxy,
    governance,
    sushiLPAssetGuard,
  } = initializeData;

  // Check ownership
  console.log("Checking ownership..");

  let owner = {};
  owner.proxyAdmin = await proxyAdmin.owner();
  owner.poolFactoryProxy = await poolFactoryProxy.owner();
  owner.governance = await governance.owner();
  owner.assetHandlerProxy = await assetHandlerProxy.owner();
  owner.sushiLPAssetGuard = await sushiLPAssetGuard.owner();

  console.log("Protocol DAO address:", protocolDao);

  expect(owner.proxyAdmin).to.equal(protocolDao);
  console.log("proxyAdmin owned by pDAO");
  expect(owner.poolFactoryProxy).to.equal(protocolDao);
  console.log("poolFactoryProxy 0wned by pDAO");
  expect(owner.governance).to.equal(protocolDao);
  console.log("governance owned by pDAO");
  expect(owner.assetHandlerProxy).to.equal(protocolDao);
  console.log("assetHandlerProxy owned by pDAO");
  expect(owner.sushiLPAssetGuard).to.equal(protocolDao);
  console.log("sushiLPAssetGuard owned by pDAO");

  console.log("Ownership checks complete!");
  console.log("_________________________________________");
};

module.exports = { main };
