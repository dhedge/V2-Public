import dotenv from "dotenv";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "solidity-coverage";
import "@typechain/hardhat";
import { HardhatUserConfig } from "hardhat/config";

import "./scripts/polygon/upgrade-polygon";
import "./scripts/polygon/verify";
import "./scripts/ovm/explorer-verify";
import "./scripts/polygon/dhedgeEasySwapper";
import "./scripts/checks/checkConfig";
import "./scripts/compileOne";
import "./scripts/dynamicBonds";

dotenv.config();

import HardHatConfig from "./hardhat.config-common";

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

export default HardHatConfig;
