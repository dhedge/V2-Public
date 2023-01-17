import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { expect } from "chai";
import { Contract, ContractFactory } from "ethers";
import { ethers, upgrades } from "hardhat";
import * as versions from "../../../publish/ovm/prod/versions.json";

const isSameBytecode = (creationBytecode: string, runtimeBytecode: string) => {
  const bytecodeB = runtimeBytecode.substring(39);
  const bytecodeSnippet = bytecodeB.substring(0, 100);
  const indexOfSnippet = creationBytecode.indexOf(bytecodeSnippet);

  if (indexOfSnippet < 0) return false;
  const bytecodeA = creationBytecode.substring(indexOfSnippet);
  if (bytecodeA.length !== bytecodeB.length) return false;

  // Ignore the bytecode metadata https://docs.soliditylang.org/en/v0.7.6/metadata.html
  const metadataString = "a264"; // Note: this string might change in future compiler versions
  if (
    bytecodeA.substring(0, bytecodeA.indexOf(metadataString)) !==
    bytecodeB.substring(0, bytecodeB.indexOf(metadataString))
  )
    return false;

  return true;
};

describe("Bytecode Test", function () {
  let PoolFactory: ContractFactory, PoolLogic: ContractFactory, PoolManagerLogic: ContractFactory;
  let poolFactory: Contract, poolLogic: Contract, poolManagerLogic: Contract;

  before(async function () {
    const [, , dao] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [[]]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year

    PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = await upgrades.deployProxy(PoolFactory, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ]);
    await poolFactory.deployed();
  });

  it("PoolFactory Should have matching byte code", async function () {
    const creationBytecode = PoolFactory.bytecode;
    const implementation = await getImplementationAddress(ethers.provider, poolFactory.address);
    const runtimeBytecode = await ethers.provider.getCode(implementation);

    const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
    expect(bytecodeCheck).to.be.true;
  });

  it("PoolLogic Should have matching byte code", async function () {
    const creationBytecode = PoolLogic.bytecode;

    const runtimeBytecode = await ethers.provider.getCode(poolLogic.address);

    const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
    expect(bytecodeCheck).to.be.true;
  });

  it("PoolFactory Real Should have matching byte code", async function () {
    const creationBytecode = PoolFactory.bytecode;

    const runtimeBytecode = await ethers.provider.getCode(versions["v2.12.0"].contracts.PoolFactory);

    const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
    expect(bytecodeCheck).to.be.true;
  });

  it("PoolLogic Real Should have matching byte code", async function () {
    const creationBytecode = PoolLogic.bytecode;

    const runtimeBytecode = await ethers.provider.getCode(versions["v2.12.0"].contracts.PoolLogic);

    const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
    expect(bytecodeCheck).to.be.true;
  });
});
