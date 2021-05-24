require('dotenv').config();
require('@eth-optimism/plugins/hardhat/compiler');
require('@eth-optimism/plugins/hardhat/ethers');
require('hardhat-gas-reporter');
require('hardhat-abi-exporter');
require('@nomiclabs/hardhat-waffle');
require('solidity-coverage');

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  defaultNetwork: 'kovan-optimism',
  gasReporter: {
    showTimeSpent: true,
    currency: 'USD',
  },
  networks: {
    'kovan-optimism': {
      url: process.env.KOVAN_OVM_URL || 'https://kovan.optimism.io',
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 0
    },
    localhost: {
      chainId: 31337,
      url: "http://127.0.0.1:8545",
      timeout: 1000000,
    },
    polygon: {
      chainId: 137,
      url: "https://rpc-mainnet.maticvigil.com/",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    mumbai: {
      chainId: 80001,
      url: "https://rpc-mumbai.maticvigil.com/",
      accounts: process.env.TEST_PRIVATE_KEY1 && process.env.TEST_PRIVATE_KEY2 && process.env.TEST_PRIVATE_KEY3 ? [process.env.TEST_PRIVATE_KEY1, process.env.TEST_PRIVATE_KEY2, process.env.TEST_PRIVATE_KEY3] : [],
    },
  },
  ovm: {
    solcVersion: '0.6.12',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  solidity: {
    version: '0.6.12',
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
  abiExporter: {
    path: './abi',
    clear: true,
    flat: true,
    only: ['PoolFactory', 'PoolLogic', 'PoolManagerLogic', 'AssetHandler'],
    spacing: 2
  }
};
