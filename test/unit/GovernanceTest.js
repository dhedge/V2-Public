const { expect } = require("chai");
const { toBytes32 } = require("./TestHelpers");
let governance;

describe("Governance", async () => {
  before(async () => {
    [signer] = await ethers.getSigners();
    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy();
  });

  it("should be able to set and get guards", async () => {
    const contract = "0x1111111111111111111111111111111111111111";
    const contractGuard = "0x2222222222222222222222222222222222222222";
    const assetGuard = "0x3333333333333333333333333333333333333333";

    await governance.setContractGuard(contract, contractGuard);
    await governance.setAssetGuard("0", assetGuard);
    const newContractGuard = await governance.contractGuards(contract);
    const newAssetGuard = await governance.assetGuards("0");
    expect(newContractGuard).to.equal(contractGuard);
    expect(newAssetGuard).to.equal(assetGuard);

    // Check guard sets are successful
    const areContractGuardsSet = await governance.areContractGuardsSet([contract], [contractGuard]);
    expect(areContractGuardsSet).to.equal(true);
    const areAssetGuardsSet = await governance.areAssetGuardsSet([0], [assetGuard]);
    expect(areAssetGuardsSet).to.equal(true);
  });

  it("should be able to set and get addresses", async () => {
    const name1 = "Name1";
    const name2 = "Name2";
    const name3 = "Name3";
    let namesBytes = [toBytes32(name1), toBytes32(name2), toBytes32(name3)];
    const address1 = "0x1111111111111111111111111111111111111111";
    const address2 = "0x2222222222222222222222222222222222222222";
    const address3 = "0x3333333333333333333333333333333333333333";
    let addresses = [address1, address2, address3];

    await governance.setAddresses(namesBytes, addresses);

    // Check set is successful
    let areAddressesSet = await governance.areAddressesSet(namesBytes, addresses);
    expect(areAddressesSet).to.equal(true);

    // Check that it throws on bad checks
    areAddressesSet = await governance.areAddressesSet(namesBytes, addresses.reverse());
    expect(areAddressesSet).to.equal(false);

    namesBytes.push(toBytes32("badName"));
    await expect(governance.areAddressesSet(namesBytes, addresses)).to.be.revertedWith("input lengths must match");

    addresses.push(address1);
    areAddressesSet = await governance.areAddressesSet(namesBytes, addresses);
    expect(areAddressesSet).to.equal(false);

    // Check correct mappings
    const address1Mapping = await governance.nameToDestination(toBytes32(name1));
    const address2Mapping = await governance.nameToDestination(toBytes32(name2));
    const address3Mapping = await governance.nameToDestination(toBytes32(name3));
    expect(address1).to.equal(address1Mapping);
    expect(address2).to.equal(address2Mapping);
    expect(address3).to.equal(address3Mapping);

    // Check 0x0 return on bad name call
    const zeroAddress = await governance.nameToDestination(toBytes32("badName"));
    expect(zeroAddress).to.equal("0x0000000000000000000000000000000000000000");
  });
});
