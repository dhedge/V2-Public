//
// We need to be able to run typechain standalone
// Otherwise we can't use the generated types in the files imported into hardhat.config.ts
//

import dotenv from "dotenv";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "solidity-coverage";
import "@typechain/hardhat";
import "hardhat-dependency-compiler";
import { lyraContractPaths } from "@lyrafinance/protocol/dist/test/utils/package/index-paths";

import HardHatConfig from "./hardhat.config-common";

dotenv.config();

export default {
  ...HardHatConfig,
  solidity: {
    ...HardHatConfig.solidity,

    overrides: {
      ...[
        ...lyraContractPaths,
        "@lyrafinance/protocol/contracts/interfaces/IExchangeRates.sol",
        "@lyrafinance/protocol/contracts/interfaces/ICollateralShort.sol",
        "@lyrafinance/protocol/contracts/interfaces/IFeeCounter.sol",
        "@lyrafinance/protocol/contracts/interfaces/ICurve.sol",
        "@lyrafinance/protocol/contracts/test-helpers/ITestERC20.sol",
        "openzeppelin-contracts-4.4.1/utils/math/SafeCast.sol",
        "@lyrafinance/protocol/contracts/OptionMarketPricer.sol",
        "openzeppelin-contracts-4.4.1/token/ERC20/IERC20.sol",
        "@lyrafinance/protocol/contracts/interfaces/ISynthetix.sol",
        "@lyrafinance/protocol/contracts/interfaces/ISwapRouter.sol",
        "openzeppelin-contracts-4.4.1/token/ERC20/extensions/IERC20Metadata.sol",
        "@lyrafinance/protocol/contracts/interfaces/ILiquidityTracker.sol",
        "@lyrafinance/protocol/contracts/test-helpers/OldBlackScholesMath.sol",
        "openzeppelin-contracts-4.4.1/token/ERC721/extensions/IERC721Enumerable.sol",
        "openzeppelin-contracts-4.4.1/token/ERC721/IERC721.sol",
        "openzeppelin-contracts-4.4.1/token/ERC721/extensions/IERC721Metadata.sol",
        "openzeppelin-contracts-4.4.1/token/ERC721/ERC721.sol",
        "openzeppelin-contracts-4.4.1/utils/introspection/ERC165.sol",
        "openzeppelin-contracts-4.4.1/utils/introspection/IERC165.sol",
        "openzeppelin-contracts-4.4.1/utils/Strings.sol",
        "openzeppelin-contracts-4.4.1/utils/Context.sol",
        "openzeppelin-contracts-4.4.1/utils/Address.sol",
        "openzeppelin-contracts-4.4.1/token/ERC721/IERC721Receiver.sol",
        "@lyrafinance/protocol/contracts/interfaces/IDelegateApprovals.sol",
        "@lyrafinance/protocol/contracts/interfaces/IExchanger.sol",
        "@lyrafinance/protocol/contracts/interfaces/IAddressResolver.sol",
        "openzeppelin-contracts-upgradeable-4.5.1/proxy/utils/Initializable.sol",
        "openzeppelin-contracts-upgradeable-4.5.1/utils/ContextUpgradeable.sol",
        "openzeppelin-contracts-upgradeable-4.5.1/utils/AddressUpgradeable.sol",
      ].reduce(
        (a, v) => ({
          ...a,
          [`contracts/hardhat-dependency-compiler/${v}`]: {
            version: "0.8.9",
            settings: {
              outputSelection: {
                "*": {
                  "*": ["storageLayout"],
                },
              },
              optimizer: {
                enabled: true,
                runs: 10000,
              },
            },
          },
          [v]: {
            version: "0.8.9",
            settings: {
              outputSelection: {
                "*": {
                  "*": ["storageLayout"],
                },
              },
              optimizer: {
                enabled: true,
                runs: 10000,
              },
            },
          },
        }),
        {},
      ),
    },
  },
  dependencyCompiler: {
    paths: lyraContractPaths,
  },
};
