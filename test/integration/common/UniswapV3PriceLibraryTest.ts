import { ethers } from "hardhat";
import { describe } from "mocha";
import { Address } from "../../../deployment-scripts/types";
import { deployContracts, IDeployments, NETWORK } from "../utils/deployContracts";

export interface IV3AssetPair {
  token0: Address;
  token1: Address;
  fee: number;
}

export const uniswapV3PriceLibraryTest = (testParams: {
  network: NETWORK;
  uniswapV3Factory: Address;
  assetPairs: IV3AssetPair[];
}) => {
  const { network, uniswapV3Factory, assetPairs } = testParams;
  let deployments: IDeployments;

  before(async () => {
    deployments = await deployContracts(network);
  });

  describe("UniswapV3PriceLibrary", function () {
    assetPairs.forEach((assetPair) => {
      it(JSON.stringify(assetPair), async () => {
        const UniswapV3PriceLibraryTest = await ethers.getContractFactory("UniswapV3PriceLibraryTest");
        const uniswapV3PriceLibraryTest = await UniswapV3PriceLibraryTest.deploy();
        await uniswapV3PriceLibraryTest.deployed();

        await uniswapV3PriceLibraryTest.assertFairPrice(
          deployments.poolFactory.address,
          uniswapV3Factory,
          assetPair.token0,
          assetPair.token1,
          assetPair.fee,
        );
      });
    });
  });
};
