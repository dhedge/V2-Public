import { InitType } from "./initialize";
import assert from "assert";

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

  assert.strictEqual(await proxyAdmin.owner(), proxyAdminOwner);
  console.log("proxyAdmin owned by proxyAdminOwner");

  assert.strictEqual(await poolFactoryProxy.owner(), protocolDao);
  console.log("poolFactoryProxy owned by pDAO");

  assert.strictEqual(await governance.owner(), protocolDao);
  console.log("governance owned by pDAO");

  assert.strictEqual(await assetHandlerProxy.owner(), protocolDao);
  console.log("assetHandlerProxy owned by pDAO");

  if (sushiLPAssetGuard) {
    assert.strictEqual(await sushiLPAssetGuard.owner(), protocolDao);
    console.log("sushiLPAssetGuard owned by pDAO");
  }

  if (quickLPAssetGuard) {
    assert.strictEqual(await quickLPAssetGuard.owner(), protocolDao);
    console.log("quickLPAssetGuard owned by pDAO");
  }

  if (openAssetGuard) {
    assert.strictEqual(await openAssetGuard.owner(), protocolDao);
    console.log("openAssetGuard owned by pDAO");
  }

  if (balancerV2Guard) {
    assert.strictEqual(await balancerV2Guard.owner(), protocolDao);
    console.log("balancerV2Guard owned by pDAO");
  }

  console.log("Ownership checks complete!");
  console.log("_________________________________________");
};
