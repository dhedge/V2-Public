import axios from "axios";
import { BigNumber } from "ethers";
import { ChainIds } from "./utils";

interface IParams {
  src: string;
  dst: string;
  amount: BigNumber;
  from: string;
  receiver: string;
  chainId: ChainIds;
  version?: "5.2" | "6.0";
}

export const getOneInchSwapTransaction = async ({
  src,
  dst,
  amount,
  from,
  receiver,
  chainId,
  version = "5.2",
}: IParams): Promise<string> => {
  try {
    const apiUrl = `https://api.1inch.dev/swap/v${version}/${chainId}/swap`;
    const params = {
      src,
      dst,
      amount: amount.toString(),
      from,
      receiver,
      slippage: 1, // 1%
      disableEstimate: true,
      usePermit2: false,
    };
    const { data } = await axios.get<{ tx: { data: string } }>(apiUrl, {
      params,
      headers: { Authorization: `Bearer ${process.env.ONE_INCH_API_KEY}` },
    });
    return data.tx.data;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } catch (error: any) {
    console.log(error?.response?.data);
    throw new Error("Failed to get oneInch swap transaction data");
  }
};
