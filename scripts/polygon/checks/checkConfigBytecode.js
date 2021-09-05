const { ethers } = require("hardhat");
const { assert, use } = require("chai");
const chaiAlmost = require("chai-almost");

use(chaiAlmost());

const { isSameBytecode } = require("../../Helpers");

const main = async (initializeData) => {
  const { contracts, contractsArray } = initializeData;

  // Check latest contract bytecodes (what needs to be upgraded on next release)
  console.log("Checking latest bytecodes against last deployment..");

  const bytecodeErrors = [];
  for (const contract of contractsArray) {
    const creationBytecode = contract.contract.bytecode;
    const runtimeBytecode = await ethers.provider.getCode(contracts[contract.name]);
    const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
    if (runtimeBytecode.length < 10) bytecodeErrors.push(`Missing bytecode in deployed address for ${contract.name}`);
    if (!bytecodeCheck) bytecodeErrors.push(`Bytecode difference found for ${contract.name}`);
  }

  for (const bytecodeError of bytecodeErrors) {
    console.log(bytecodeError);
  }

  assert(!bytecodeErrors.length, "Bytecode differences or errors found.");

  console.log("Bytecode checks complete!");
  console.log("_________________________________________");
};

module.exports = { main };
