import { expect } from "chai";
import { ethers } from "hardhat";
import { Governance } from "../../../types";

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
});
