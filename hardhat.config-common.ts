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
      timeout: 0,
    },
    ovm: {
      chainId: 10,
      url: process.env.OPTIMISM_URL || "https://opt-mainnet.g.alchemy.com/v2/",
      accounts: process.env.OVM_PRIVATE_KEY ? [process.env.OVM_PRIVATE_KEY] : [],
    },
    polygon: {
      chainId: 137,
      url: process.env.POLYGON_URL || "https://polygon-mainnet.g.alchemy.com/v2/",
      accounts: process.env.POLYGON_PRIVATE_KEY ? [process.env.POLYGON_PRIVATE_KEY] : [],
      gasPrice: 400e9,
      timeout: 600000,
    },
    arbitrum: {
      chainId: 42161,
      url: process.env.ARBITRUM_URL || "https://arb-mainnet.g.alchemy.com/v2/",
      accounts: process.env.ARBITRUM_PRIVATE_KEY ? [process.env.ARBITRUM_PRIVATE_KEY] : [],
    },
    base: {
      chainId: 8453,
      url: process.env.BASE_URL || "https://base-mainnet.g.alchemy.com/v2/",
      accounts: process.env.BASE_PRIVATE_KEY ? [process.env.BASE_PRIVATE_KEY] : [],
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
          optimizer: {
            enabled: true,
            runs: 20,
          },
        },
      },
      {
        version: "0.8.10",
        settings: {
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
          optimizer: {
            enabled: true,
            runs: 20,
          },
        },
      },
    ],
    overrides: {
      "@uniswap/lib/contracts/libraries/BitMath.sol": {
        version: "0.7.6",
      },
      "@uniswap/lib/contracts/libraries/FullMath.sol": {
        version: "0.7.6",
      },
      "@uniswap/lib/contracts/libraries/FixedPoint.sol": {
        version: "0.7.6",
      },
      "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol": {
        version: "0.7.6",
      },
      "contracts/test/SonneFinancePriceAggregatorMock.sol": {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: false,
          },
        },
      },
    },
  },
  mocha: {
    timeout: 0,
    // Jake: During integration tests we sometimes get
    // ProviderError: Errors encountered in param 1: Invalid value "0x02e5dda5c51be531e95b2e5b22389b23cd39a929c1a594052162ebe432d897e9" supplied to : QUANTITY
    // Usually retrying the test works.
    // Chinmay: If the tests fail and it turns out they are being run multiple times and the state being used
    // is persistent, comment this out and re-run the tests. You will probably find the reason the
    // tests were failing.
    retries: process.env.TEST_RETRIES !== undefined ? process.env.TEST_RETRIES : 3,
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true,
    only: [
      "PoolFactory",
      "PoolLogic",
      "PoolManagerLogic",
      "AssetHandler",
      "DynamicBonds",
      "DhedgeStakingV2",
      "DhedgeEasySwapper",
      "RewardDistribution",
      "contracts/swappers/poolTokenSwapper/PoolTokenSwapper",
    ],
    except: ["contracts/interfaces", "contracts/test", "contracts/v2.4.1", "contracts/stakingv2/interfaces"],
    spacing: 2,
  },
  etherscan: {
    // https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html#multiple-api-keys-and-alternative-block-explorers
    apiKey: {
      optimisticEthereum: process.env.OPTIMISTICSCAN_API_KEY,
      polygon: process.env.POLYGONSCAN_API_KEY,
      arbitrumOne: process.env.ARBISCAN_API_KEY,
      base: process.env.BASESCAN_API_KEY,
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org/",
        },
      },
    ],
  },
  typechain: {
    outDir: "./types",
    target: "ethers-v5",
  },
};

// Hack console to just print bigNumbers as normal numbers not as an object
const log = console.log.bind(console);
console.log = (...args) => {
  args = args.map((arg) => {
    if (arg && arg._isBigNumber) {
      return arg.toString();
    }
    return arg;
  });
  log(...args);
};
