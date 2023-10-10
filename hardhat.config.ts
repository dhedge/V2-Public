import dotenv from "dotenv";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "solidity-coverage";
import "@typechain/hardhat";
import "hardhat-contract-sizer";

import "./deployment/upgrade/upgrade";
import "./deployment/explorerVerify";
import "./deployment/checks/checkConfig";
import "./deployment/compileOne";
import "./deployment/polygon/dynamicBonds";
import "./deployment/polygon/privateTokenSwap";

dotenv.config();

import HardHatConfig from "./hardhat.config-common";

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

export default HardHatConfig;
