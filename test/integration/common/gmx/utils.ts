import axios from "axios";
import { ethers } from "hardhat";
import { hashString, IGmxTestsParams } from "./gmxTestHelpers";
import { BigNumber } from "ethers";

type TokenPrice = { tokenAddress: string; minPrice: string; maxPrice: string };

export type MarketInfo = {
  indexToken: string;
  longToken: string;
  shortToken: string;
};

export type MarketPrices = {
  indexTokenPrice: { min: string; max: string };
  longTokenPrice: { min: string; max: string };
  shortTokenPrice: { min: string; max: string };
};

export const getTokenPrices = async (): Promise<TokenPrice[]> => {
  return (await axios.get("https://arbitrum-api.gmxinfra.io/prices/tickers")).data;
};

export const getMarketInfo = async (testParams: IGmxTestsParams): Promise<MarketInfo> => {
  const syntheticsReader = await ethers.getContractAt("IGmxReader", testParams.reader);
  const marketInfo = await syntheticsReader.callStatic.getMarket(testParams.dataStore, testParams.market);
  return marketInfo as unknown as MarketInfo;
};

export const getMarketPriceInfo = async (
  testParams: IGmxTestsParams,
): Promise<{ marketInfo: MarketInfo; marketPrices: MarketPrices }> => {
  const [marketInfo, tokenPrices] = await Promise.all([getMarketInfo(testParams), getTokenPrices()]);

  const findTokenPrice = (tokenAddress: string): { min: string; max: string } => {
    const price = tokenPrices.find((tp) => tp.tokenAddress === tokenAddress);
    if (price) {
      return {
        min: price.minPrice,
        max: price.maxPrice,
      };
    } else {
      throw new Error(`Token price not found for address: ${tokenAddress}`);
    }
  };

  const indexTokenPrice = findTokenPrice(marketInfo.indexToken);
  const longTokenPrice = findTokenPrice(marketInfo.longToken);
  const shortTokenPrice = findTokenPrice(marketInfo.shortToken);

  return {
    marketInfo,
    marketPrices: { indexTokenPrice, longTokenPrice, shortTokenPrice },
  };
};

export const getMarketTokenPrice = async (testParams: IGmxTestsParams): Promise<BigNumber> => {
  const { marketPrices, marketInfo } = await getMarketPriceInfo(testParams);
  const syntheticsReader = await ethers.getContractAt("IGmxReader", testParams.reader);
  const prices = await syntheticsReader.getMarketTokenPrice(
    testParams.dataStore,
    {
      ...marketInfo,
      marketToken: testParams.market,
    },
    marketPrices.indexTokenPrice,
    marketPrices.longTokenPrice,
    marketPrices.shortTokenPrice,
    hashString("MAX_PNL_FACTOR_FOR_WITHDRAWALS"),
    false,
  );

  return prices[0].div(ethers.BigNumber.from(10).pow(18));
};

type WithdrawalAmountOutReturnObj = {
  longTokenAmountOut: BigNumber;
  shortTokenAmountOut: BigNumber;
  marketPrices: MarketPrices;
  marketTokenPrice: BigNumber;
  inputValueD30: BigNumber;
  outputValueD30: BigNumber;
};

export const getWithdrawalAmountOut = async (
  testParams: IGmxTestsParams,
  {
    marketTokenAmount,
  }: {
    marketTokenAmount: BigNumber;
  },
): Promise<WithdrawalAmountOutReturnObj> => {
  const { marketPrices, marketInfo } = await getMarketPriceInfo(testParams);
  const marketTokenPrice = await getMarketTokenPrice(testParams);
  const syntheticsReader = await ethers.getContractAt("IGmxReader", testParams.reader);
  const [longTokenAmountOut, shortTokenAmountOut] = await syntheticsReader.getWithdrawalAmountOut(
    testParams.dataStore,
    {
      ...marketInfo,
      marketToken: testParams.market,
    },
    marketPrices,
    marketTokenAmount,
    testParams.uiFeeReceiver,
    4,
  );

  const inputValueD30 = marketTokenAmount.mul(marketTokenPrice);

  const outputValueD30 = longTokenAmountOut
    .mul(marketPrices.longTokenPrice.min)
    .add(shortTokenAmountOut.mul(marketPrices.shortTokenPrice.min));

  return {
    longTokenAmountOut,
    shortTokenAmountOut,
    marketPrices,
    marketTokenPrice,
    inputValueD30,
    outputValueD30,
  };
};

type DepositAmountOutReturnObj = {
  mintAmount: BigNumber;
  marketPrices: MarketPrices;
  marketTokenPrice: BigNumber;
  inputValueD30: BigNumber;
  outputValueD30: BigNumber;
};

export const getDepositAmountOut = async (
  testParams: IGmxTestsParams,
  {
    longTokenAmount,
    shortTokenAmount,
  }: {
    longTokenAmount: BigNumber;
    shortTokenAmount: BigNumber;
  },
): Promise<DepositAmountOutReturnObj> => {
  const { marketPrices, marketInfo } = await getMarketPriceInfo(testParams);
  const marketTokenPrice = await getMarketTokenPrice(testParams);
  const syntheticsReader = await ethers.getContractAt("IGmxReader", testParams.reader);
  const mintAmount = await syntheticsReader.getDepositAmountOut(
    testParams.dataStore,
    {
      ...marketInfo,
      marketToken: testParams.market,
    },
    marketPrices,
    longTokenAmount,
    shortTokenAmount,
    testParams.uiFeeReceiver,
    3,
    true, // includeVirtualInventoryImpact
  );

  const inputValueD30 = longTokenAmount
    .mul(marketPrices.longTokenPrice.max)
    .add(shortTokenAmount.mul(marketPrices.shortTokenPrice.max));

  const outputValueD30 = mintAmount.mul(marketTokenPrice);

  console.log("marketTokenPrice", marketTokenPrice.toString());
  console.log("mintAmount", mintAmount.toString());
  console.log("longTokenPrice.max", marketPrices.longTokenPrice.max.toString());
  console.log("shortTokenPrice.max", marketPrices.shortTokenPrice.max.toString());

  return {
    mintAmount,
    marketPrices,
    marketTokenPrice,
    inputValueD30,
    outputValueD30,
  };
};

const adjustSlippage = (bn: BigNumber, slippage: number) => bn.sub(bn.mul(Math.round(slippage * 100)).div(100_00));
const formatBN = (bn: BigNumber, decimals = 30) => parseFloat(ethers.utils.formatUnits(bn, decimals)).toFixed(2);

const calculateAndFormatRealSlippage = (inputValue: BigNumber, outputValue: BigNumber): string => {
  const difference = inputValue.sub(outputValue);
  const slippageInBasisPoints = difference.mul(10_000).div(inputValue);

  // Format slippage as a percentage with two decimal places
  const slippagePercentage = slippageInBasisPoints.toString();
  // Format slippage as a percentage with two decimal places
  return `${(parseFloat(slippagePercentage) / 100).toFixed(2)}%`; // Divide by 100 to convert bps to percentage
};

export const getEstimateDepositAmountOut = async (
  testParams: IGmxTestsParams,
  {
    longTokenAmount,
    shortTokenAmount,
    slippage = 0.5,
    isToLog = false,
  }: {
    longTokenAmount: BigNumber;
    shortTokenAmount: BigNumber;
    isToLog: boolean;
    slippage?: number; // 0.5 is 0.5%
  },
) => {
  const { mintAmount, inputValueD30, outputValueD30 } = await getDepositAmountOut(testParams, {
    longTokenAmount,
    shortTokenAmount,
  });

  const adjustMintAmountOut = adjustSlippage(mintAmount, slippage);
  if (isToLog) {
    console.log(
      `inputValue ($${formatBN(inputValueD30)}) => outputValue ($${formatBN(adjustSlippage(outputValueD30, slippage))}) with slippage, ${calculateAndFormatRealSlippage(inputValueD30, adjustSlippage(outputValueD30, slippage))} `,
    );
  }

  return {
    adjustMintAmountOut,
  };
};

export const getEstimateWithdrawAmountOut = async (
  testParams: IGmxTestsParams,
  {
    marketTokenAmount,
    slippage = 0.5,
    isToLog = false,
  }: {
    marketTokenAmount: BigNumber;
    slippage?: number; // 0.5 is 0.5%
    isToLog: boolean;
  },
) => {
  // Fetch withdrawal data
  const { longTokenAmountOut, shortTokenAmountOut, inputValueD30, outputValueD30 } = await getWithdrawalAmountOut(
    testParams,
    { marketTokenAmount },
  );

  // Adjust the output values based on slippage
  const adjustLongTokenAmountOut = adjustSlippage(longTokenAmountOut, slippage);
  const adjustShortTokenAmountOut = adjustSlippage(shortTokenAmountOut, slippage);

  // If logging is enabled, print the slippage and amounts
  if (isToLog) {
    console.log(
      `inputValue ($${formatBN(inputValueD30)}) => outputValue ($${formatBN(
        adjustSlippage(outputValueD30, slippage),
      )}) with slippage, ${calculateAndFormatRealSlippage(inputValueD30, adjustSlippage(outputValueD30, slippage))} `,
    );
    console.log(
      `Adjusted Token Outputs - Long: ${formatBN(adjustLongTokenAmountOut, 18)}, Short: ${formatBN(
        adjustShortTokenAmountOut,
        6,
      )}`,
    );
  }

  // Return the adjusted token amounts and related data
  return {
    adjustLongTokenAmountOut,
    adjustShortTokenAmountOut,
  };
};
