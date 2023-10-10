import axios from "axios";
import { ethers } from "ethers";

interface IParams {
  baseURL: string;
  sellToken: string;
  buyToken: string;
  sellAmount: string;
}

export const getZeroExSwapTransactionQuote = async ({ baseURL, sellToken, buyToken, sellAmount }: IParams) => {
  try {
    const { data } = await axios({
      method: "GET",
      url: "/swap/v1/quote",
      baseURL,
      // free api key created from my personal account for integration testing purposes
      headers: { "0x-api-key": "f1ef01e4-e9c3-49e9-a5a5-3d129b5b7f55" },
      params: {
        sellToken,
        buyToken,
        sellAmount,
        affiliateAddress: ethers.constants.AddressZero,
        slippagePercentage: 0.001, // 0.1%
      },
    });
    return data;
  } catch (err) {
    console.log(err);
    return null;
  }
};
