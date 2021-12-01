const { expect, assert, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const main = async (initializeData) => {
  const {
    protocolDao,
    proxyAdmin,
    proxyAdminOwner,
    poolFactoryProxy,
    assetHandlerProxy,
    governance,
    sushiLPAssetGuard,
    quickLPAssetGuard,
    balancerV2Guard,
    openAssetGuard,
  } = initializeData;

  // Check ownership
  console.log("Checking ownership..");
  console.log("Protocol DAO address:", protocolDao);
  console.log("ProxyAdmin owner address:", proxyAdminOwner);

  let owner = {};
  owner.proxyAdmin = await proxyAdmin.owner();
  owner.poolFactoryProxy = await poolFactoryProxy.owner();
  owner.governance = await governance.owner();
  owner.assetHandlerProxy = await assetHandlerProxy.owner();

  if (sushiLPAssetGuard) {
    owner.sushiLPAssetGuard = await sushiLPAssetGuard.owner();
  }
  if (quickLPAssetGuard) {
    owner.quickLPAssetGuard = await quickLPAssetGuard.owner();
    qq;
  }
  if (openAssetGuard) {
    owner.openAssetGuard = await openAssetGuard.owner();
  }
  if (balancerV2Guard) {
    owner.balancerV2Guard = await balancerV2Guard.owner();
  }

  expect(owner.proxyAdmin).to.equal(proxyAdminOwner);
  console.log("proxyAdmin owned by proxyAdminOwner");
  expect(owner.poolFactoryProxy).to.equal(protocolDao);
  console.log("poolFactoryProxy owned by pDAO");
  expect(owner.governance).to.equal(protocolDao);
  console.log("governance owned by pDAO");
  expect(owner.assetHandlerProxy).to.equal(protocolDao);
  console.log("assetHandlerProxy owned by pDAO");
  if (sushiLPAssetGuard) {
    expect(owner.sushiLPAssetGuard).to.equal(protocolDao);
    console.log("sushiLPAssetGuard owned by pDAO");
  }
  if (quickLPAssetGuard) {
    expect(owner.quickLPAssetGuard).to.equal(protocolDao);
    console.log("quickLPAssetGuard owned by pDAO");
  }
  if (openAssetGuard) {
    expect(owner.openAssetGuard).to.equal(protocolDao);
    console.log("openAssetGuard owned by pDAO");
  }
  if (balancerV2Guard) {
    expect(owner.balancerV2Guard).to.equal(protocolDao);
    console.log("balancerV2Guard owned by pDAO");
  }

  console.log("Ownership checks complete!");
  console.log("_________________________________________");
};

module.exports = { main };
