import { InitType } from "./initialize";
import { expect } from "chai";

export const checkOwnership = async (initializeData: InitType) => {
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

  expect(await proxyAdmin.owner()).to.equal(proxyAdminOwner);
  console.log("proxyAdmin owned by proxyAdminOwner");

  expect(await poolFactoryProxy.owner()).to.equal(protocolDao);
  console.log("poolFactoryProxy owned by pDAO");

  expect(await governance.owner()).to.equal(protocolDao);
  console.log("governance owned by pDAO");

  expect(await assetHandlerProxy.owner()).to.equal(protocolDao);
  console.log("assetHandlerProxy owned by pDAO");

  if (sushiLPAssetGuard) {
    expect(await sushiLPAssetGuard.owner()).to.equal(protocolDao);
    console.log("sushiLPAssetGuard owned by pDAO");
  }

  if (quickLPAssetGuard) {
    expect(await quickLPAssetGuard.owner()).to.equal(protocolDao);
    console.log("quickLPAssetGuard owned by pDAO");
  }

  if (openAssetGuard) {
    expect(await openAssetGuard.owner()).to.equal(protocolDao);
    console.log("openAssetGuard owned by pDAO");
  }

  if (balancerV2Guard) {
    expect(await balancerV2Guard.owner()).to.equal(protocolDao);
    console.log("balancerV2Guard owned by pDAO");
  }

  console.log("Ownership checks complete!");
  console.log("_________________________________________");
};
