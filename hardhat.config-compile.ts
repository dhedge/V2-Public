//
// We need to be able to run typechain standalone
// Otherwise we can't use the generated types in the files imported into hardhat.config.ts
//

import dotenv from "dotenv";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-waffle";
import "@nomicfoundation/hardhat-verify";
import "@nomiclabs/hardhat-ethers";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "solidity-coverage";
import "@typechain/hardhat";

import HardHatConfig from "./hardhat.config-common";

dotenv.config();

export default HardHatConfig;
