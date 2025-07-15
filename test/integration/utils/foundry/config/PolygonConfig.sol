// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

library PolygonConfig {
  uint256 public constant CHAIN_ID = 137;

  address public constant PROXY_ADMIN = 0x0C0a10C9785a73018077dBC74B2A006695849252;

  // dHEDGE Contracts
  address public constant POOL_FACTORY_PROD = 0xfdc7b8bFe0DD3513Cc669bB8d601Cb83e2F69cB0;
  address public constant NFT_TRACKER_PROD = 0x195AFA2ef88b0A52DFE561E12Fac30F28860A489;
  address public constant SLIPPAGE_ACCUMULATOR_PROD = 0xb23D4ccFaD52bB632a85c9a5d64c334B90B60E61;
  address public constant USD_PRICE_AGGREGATOR_PROD = 0xE4831972d8E78A947051BCfe9658Cdf4BEFF9c51;

  // Tokens
  address public constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
  address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
  address public constant WBTC = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
  address public constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

  // Oracles
  address public constant WETH_CHAINLINK_ORACLE = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
  address public constant USDC_CHAINLINK_ORACLE = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
  address public constant DAI_CHAINLINK_ORACLE = 0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D;

  // Toros Vaults
  address public constant BTCBULL3X = 0xdB88AB5b485b38EDbEEf866314F9E49d095BCe39;
  address public constant ETHBULL3X = 0x460b60565cb73845d56564384ab84BF84c13e47D;

  // Auxiliary Contracts
  address public constant SWAPPER = 0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D;
  address public constant AAVE_V3_LENDING_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
  address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  address public constant UNISWAP_V3_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
  address public constant UNISWAP_V2_ROUTER = 0xedf6066a2b290C185783862C7F4776A2C8077AD1;
  address public constant QUICKSWAP_V2_ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
  address public constant SUSHISWAP_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
}
