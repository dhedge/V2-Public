import axios from "axios";

export const getTokenPriceFromCoingecko = async (
  tokenAddress: string,
  chainId: "arbitrum-one" | "optimistic-ethereum" | "base",
) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/${chainId}?contract_addresses=${tokenAddress}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddress.toLocaleLowerCase()].usd;
};

export const getTokenPriceFromCoingeckoIds = async (ids: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/price?ids=${ids}&vs_currencies=usd&precision=18`;
  const response = await axios.get(apiUrl);
  return response.data[ids].usd;
};
