const { expect } = require("chai");
// const { ethers, upgrades } = require("hardhat");
let governance;

describe("Governance", async () => {
  before(async () => {
    [signer] = await ethers.getSigners();
    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy();
  });

  it("should be able to set and get guards", async () => {
    let contract = "0x1111111111111111111111111111111111111111";
    let contractGuard = "0x2222222222222222222222222222222222222222";
    let assetGuard = "0x3333333333333333333333333333333333333333";
    await governance.setContractGuard(contract, contractGuard);
    await governance.setAssetGuard("0", assetGuard);
    let newContractGuard = await governance.contractGuards(contract);
    let newAssetGuard = await governance.assetGuards("0");
    expect(newContractGuard).to.equal(contractGuard);
    expect(newAssetGuard).to.equal(assetGuard);
  });
});
