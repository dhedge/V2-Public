require('dotenv').config();
// require('@eth-optimism/plugins/hardhat/compiler');
// require('@eth-optimism/plugins/hardhat/ethers');
require("@eth-optimism/hardhat-ovm");
require('hardhat-gas-reporter');
require('hardhat-abi-exporter');
require('@nomiclabs/hardhat-waffle');
require('solidity-coverage');
require('@openzeppelin/hardhat-upgrades');
require('./scripts/upgrade.js');

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
      gasPrice: 0,
      ovm: true,
    },
    localhost: {
      chainId: 31337,
      url: "http://127.0.0.1:8545",
      timeout: 1000000,
    },
    polygon: {
      chainId: 137,
      url: "https://rpc-mainnet.maticvigil.com/v1/" + process.env.MATIC_KEY,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    mumbai: {
      chainId: 80001,
      url: process.env.MUMBAI_URL ? process.env.MUMBAI_URL : "https://rpc-mumbai.maticvigil.com/v1/" + process.env.MATIC_KEY,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  ovm: {
    solcVersion: '0.7.6',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  solidity: {
    version: '0.7.6',
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
    only: ['PoolFactory', 'PoolLogic', 'PoolManagerLogic', 'AssetHandler', 'UniswapV3SwapGuard', 'ERC20Guard', 'SynthetixGuard', 'UniswapV2RouterGuard'],
    spacing: 2
  }
};
