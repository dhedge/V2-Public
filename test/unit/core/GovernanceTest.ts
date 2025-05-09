import { expect } from "chai";
import { ethers } from "hardhat";
import { Governance } from "../../../types";
import { toBytes32 } from "../../testHelpers";

describe("Governance", async () => {
  let governance: Governance;

  before(async () => {
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
    const contractGuardCheck = await governance.contractGuards(contract);
    expect(contractGuardCheck).to.equal(contractGuard);
    const assetGuardCheck = await governance.assetGuards(0);
    expect(assetGuardCheck).to.equal(assetGuard);
  });

  it("should be able to set and get addresses", async () => {
    const name1 = "Name1";
    const name2 = "Name2";
    const name3 = "Name3";
    const namesBytes = [toBytes32(name1), toBytes32(name2), toBytes32(name3)];
    const address1 = "0x1111111111111111111111111111111111111111";
    const address2 = "0x2222222222222222222222222222222222222222";
    const address3 = "0x3333333333333333333333333333333333333333";
    const addresses = [address1, address2, address3];
    const setAddressesTuple = [
      {
        name: toBytes32(name1),
        destination: address1,
      },
      {
        name: toBytes32(name2),
        destination: address2,
      },
      {
        name: toBytes32(name3),
        destination: address3,
      },
    ];

    await governance.setAddresses(setAddressesTuple);

    // Check set is successful
    const destinationCheck = await governance.nameToDestination(namesBytes[0]);
    expect(destinationCheck).to.equal(addresses[0]);

    // Check correct mappings
    const address1Mapping = await governance.nameToDestination(namesBytes[0]);
    const address2Mapping = await governance.nameToDestination(namesBytes[1]);
    const address3Mapping = await governance.nameToDestination(namesBytes[2]);
    expect(address1).to.equal(address1Mapping);
    expect(address2).to.equal(address2Mapping);
    expect(address3).to.equal(address3Mapping);

    // Check 0x0 return on bad name call
    const zeroAddress = await governance.nameToDestination(toBytes32("badName"));
    expect(zeroAddress).to.equal("0x0000000000000000000000000000000000000000");
  });
});
