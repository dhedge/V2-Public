import axios from "axios";
import { BigNumber } from "ethers";

export const getOneInchSwapTransaction = async ({
  srcAsset,
  dstAsset,
  srcAmount,
  fromAddress,
  toAddress,
  chainId,
  version = 5,
}: {
  srcAsset: string;
  dstAsset: string;
  srcAmount: BigNumber;
  fromAddress: string;
  toAddress: string;
  chainId: 137 | 10;
  version?: number;
}) => {
  const apiUrl = `https://api.1inch.exchange/v${version}.0/${chainId}/swap?fromTokenAddress=${srcAsset}&toTokenAddress=${dstAsset}&amount=${srcAmount.toString()}&fromAddress=${fromAddress}&destReceiver=${toAddress}&referrerAddress=&slippage=1&disableEstimate=true`;
  const response = await axios.get(apiUrl);
  return response.data.tx?.data;
};
