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

import "./scripts/upgrade";
import "./scripts/verify";
import "./scripts/dynamicBonds";
import "./scripts/polygon/checks/checkConfig";
import "./scripts/compileOne";

dotenv.config();

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

export default {
  gasReporter: {
    enabled: true,
    currency: "ETH",
    showTimeSpent: true,
  },
  networks: {
    localhost: {
      chainId: 31337,
      url: "http://127.0.0.1:8545",
      timeout: 600000,
    },
    ovm: {
      chainId: 10,
      url: process.env.ALCHEMY_OPTIMISM_URL || "https://opt-mainnet.g.alchemy.com/v2/",
      accounts: process.env.OVM_PRIVATE_KEY ? [process.env.OVM_PRIVATE_KEY] : [],
    },
    polygon: {
      chainId: 137,
      url: process.env.POLYGON_RPC
        ? process.env.POLYGON_RPC
        : "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_POLYGON_KEY,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 100e9,
      timeout: 600000,
    },
    mumbai: {
      chainId: 80001,
      url: process.env.MUMBAI_URL
        ? process.env.MUMBAI_URL
        : "https://rpc-mumbai.maticvigil.com/v1/" + process.env.MATIC_KEY,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },

  solidity: {
    version: "0.7.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 0,
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true,
    only: [
      "PoolPerformance",
      "PoolFactory",
      "PoolLogic",
      "PoolManagerLogic",
      "AssetHandler",
      "UniswapV3SwapGuard",
      "ERC20Guard",
      "SynthetixGuard",
      "AaveLendingPoolGuard",
      "UniswapV2RouterGuard",
      "UniswapV3SwapGuard",
      "SushiMiniChefV2Guard",
      "QuickStakingRewardsGuard",
      "Managed",
      "Governance",
      "DynamicBonds",
      "BalancerV2Guard",
      "DhedgeEasySwapper",
    ],
    spacing: 2,
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY,
  },
  typechain: {
    outDir: "./types",
    target: "ethers-v5",
  },
} as HardhatUserConfig;
