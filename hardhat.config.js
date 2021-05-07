require("dotenv").config();
require("@eth-optimism/plugins/hardhat/compiler");
require("@eth-optimism/plugins/hardhat/ethers");
require("hardhat-gas-reporter");
require("@nomiclabs/hardhat-waffle");
require("solidity-coverage");

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "kovan-optimism",
  gasReporter: {
    showTimeSpent: true,
    currency: "USD",
  },
  networks: {
    "kovan-optimism": {
      url: process.env.KOVAN_OVM_URL || "https://kovan.optimism.io",
      // accounts: [process.env.PRIVATE_KEY],
      gasPrice: 0,
    },
  },
  ovm: {
    solcVersion: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: false,
  },
};
