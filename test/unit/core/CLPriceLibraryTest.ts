import { ethers } from "hardhat";
import { parseEther } from "ethers/lib/utils";

const calculatePairs: IV3PairForCalculateSqrtPrice[] = [
  // use parseEther to format in 1e18

  {
    token0Price: parseEther("3800").toString(),
    token1Price: parseEther("1").toString(),
    token0Decimals: "18",
    token1Decimals: "6",
    desc: "weth/usdc",
  },
  {
    token0Price: parseEther("4500").toString(),
    token1Price: parseEther("2").toString(),
    token0Decimals: "18",
    token1Decimals: "18",
    desc: "weth/op",
  },
  {
    token0Price: parseEther("3700").toString(),
    token1Price: parseEther("65000").toString(),
    token0Decimals: "18",
    token1Decimals: "8",
    desc: "weth/wbtc",
  },
  {
    token0Price: parseEther("0.5").toString(),
    token1Price: parseEther("68000").toString(),
    token0Decimals: "18",
    token1Decimals: "8",
    desc: "wmatic/wbtc",
  },
  {
    token0Price: parseEther("1").toString(),
    token1Price: parseEther("68000").toString(),
    token0Decimals: "6",
    token1Decimals: "8",
    desc: "usdc/wbtc",
  },
  {
    token0Price: parseEther("1").toString(),
    token1Price: parseEther("1").toString(),
    token0Decimals: "18",
    token1Decimals: "6",
    desc: "dai/usdc",
  },
  {
    token0Price: parseEther("1").toString(),
    token1Price: parseEther("1").toString(),
    token0Decimals: "18",
    token1Decimals: "6",
    desc: "dai/usdc",
  },
  {
    token0Price: parseEther("0.13").toString(),
    token1Price: parseEther("1").toString(),
    token0Decimals: "18",
    token1Decimals: "6",
    desc: "dht/usdc",
  },
  {
    token0Price: parseEther("0.002").toString(),
    token1Price: parseEther("80000").toString(),
    token0Decimals: "18",
    token1Decimals: "6",
    desc: "wbtc-big/coin-small",
  },
  {
    token0Price: parseEther("1.5").toString(),
    token1Price: parseEther("1").toString(),
    token0Decimals: "18",
    token1Decimals: "6",
    desc: "arb/usdc",
  },
  {
    token0Price: parseEther("0.98").toString(),
    token1Price: parseEther("1.01").toString(),
    token0Decimals: "18",
    token1Decimals: "6",
    desc: "susd/usdc",
  },
];

export interface IV3PairForCalculateSqrtPrice {
  token0Price: string;
  token1Price: string;
  token0Decimals: string;
  token1Decimals: string;
  desc: string; // for display
}
let uniswapV3PriceLibraryTest;

describe("CLPriceLibraryTest", function () {
  before(async () => {
    const UniswapV3PriceLibraryTest = await ethers.getContractFactory("UniswapV3PriceLibraryTest");
    uniswapV3PriceLibraryTest = await UniswapV3PriceLibraryTest.deploy();
    await uniswapV3PriceLibraryTest.deployed();
  });

  calculatePairs.forEach((calculatePair) => {
    it(`calculateSqrtPrice: ${JSON.stringify(calculatePair)}`, async () => {
      const { token0Price, token1Price, token0Decimals, token1Decimals } = calculatePair;
      const sqrtprice1 = await uniswapV3PriceLibraryTest.calculateSqrtPrice(
        token0Price,
        token1Price,
        token0Decimals,
        token1Decimals,
      );
      console.log(
        `pair ${calculatePair.desc} normal order, sqrtprice1: ${sqrtprice1}. price: ${Number(sqrtprice1) ** 2 / 2 ** 192}`,
      );
      //
      const sqrtprice2 = await uniswapV3PriceLibraryTest.calculateSqrtPrice(
        token1Price,
        token0Price,
        token1Decimals,
        token0Decimals,
      );
      console.log(
        `pair ${calculatePair.desc} reversed order, sqrtprice2: ${sqrtprice2}. price: ${Number(sqrtprice2) ** 2 / 2 ** 192}`,
      );
    });
  });
});
