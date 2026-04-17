// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

library PlasmaConfig {
  uint256 public constant CHAIN_ID = 9745;

  address public constant PROXY_ADMIN = 0x80B668bD5dB79F633CAFeC9032825d51dc9943f8;

  // dHEDGE Contracts
  address public constant POOL_FACTORY_PROD = 0xAec4975Fc8ad911464D2948D771488b30F6eEE87;
  address public constant USD_PRICE_AGGREGATOR_PROD = 0x6516866B3695f21dA7aE23CF9a95b3a2A41b2AA3;
  address public constant SLIPPAGE_ACCUMULATOR_PROD = 0xAD463cC407576C25DD9cfE911b8348Bf551548B8;

  // Tokens
  address public constant USDT = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
  address public constant WETH = 0x9895D81bB462A195b4922ED7De0e3ACD007c32CB;
  address public constant USDe = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
  address public constant sUSDe = 0x211Cc4DD073734dA055fbF44a2b4667d5E5fE5d2;

  // Oracles
  address public constant USDT_CHAINLINK_ORACLE = 0x70b77FcdbE2293423e41AdD2FB599808396807BC;
  address public constant WETH_CHAINLINK_ORACLE = 0x43A7dd2125266c5c4c26EB86cd61241132426Fe7;
  address public constant USDe_CHAINLINK_ORACLE = 0x0DFdCF9AF39Be41E40a52A80fa86e23A69a69C3B;
  address public constant sUSDe_CHAINLINK_ORACLE = 0x0ca32ed285ADDf84E8491f5EDB835E10635945A2;

  // Toros Vaults

  // Auxiliary Contracts
  address public constant SWAPPER = 0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D;
  address public constant AAVE_V3_LENDING_POOL = 0x925a2A7214Ed92428B5b1B090F80b25700095e12;
  address public constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;
}
