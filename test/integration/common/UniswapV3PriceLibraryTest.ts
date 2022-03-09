import { expect, use } from "chai";
import { ethers } from "hardhat";
import { describe } from "mocha";
import { Address } from "../../../deployment-scripts/types";
import { deployContracts, IDeployments, NETWORK } from "../utils/deployContracts";
import { getSqrtPrice } from "../utils/uniswapV3Utils";

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

        const uniSqrt = await getSqrtPrice(uniswapV3Factory, assetPair);
        console.log("uni", uniSqrt.toString());

        const fairSqrt = await uniswapV3PriceLibraryTest.getFairSqrtPriceX96(
          deployments.poolFactory.address,
          assetPair.token0,
          assetPair.token1,
        );
        console.log("far", fairSqrt.toString());

        // 0.25%
        expect(fairSqrt).to.be.closeTo(uniSqrt, uniSqrt.div(400) as unknown as number);

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
