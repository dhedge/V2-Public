import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { Address } from "../../../types";
import { TAssetConfig, TOracleDeployer } from "./oracleTypes";

export const deployUSDPriceAggregator: TOracleDeployer = async (
  hre: HardhatRuntimeEnvironment,
  _oracleConfig: TAssetConfig,
): Promise<Address> => {
  // Deploy USDPriceAggregator
  const USDPriceAggregator = await hre.ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  await usdPriceAggregator.deployed();
  const usdPriceAggregatorAddress = usdPriceAggregator.address;

  await tryVerify(
    hre,
    usdPriceAggregatorAddress,
    "contracts/priceAggregators/USDPriceAggregator.sol:USDPriceAggregator",
    [],
  );

  return usdPriceAggregatorAddress;
};
