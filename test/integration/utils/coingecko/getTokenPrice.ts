import axios from "axios";

export const getTokenPriceFromCoingecko = async (tokenAddress: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/optimistic-ethereum?contract_addresses=${tokenAddress}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddress.toLocaleLowerCase()].usd;
};
