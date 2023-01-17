// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IOptionToken.sol";
import "./IOptionMarket.sol";
import "./IOptionGreekCache.sol";

interface ILyraRegistry {
  struct OptionMarketAddresses {
    address liquidityPool;
    address liquidityToken;
    IOptionGreekCache greekCache;
    IOptionMarket optionMarket;
    address optionMarketPricer;
    IOptionToken optionToken;
    address poolHedger;
    address shortCollateral;
    address gwavOracle;
    IERC20 quoteAsset;
    IERC20 baseAsset;
  }

  function getMarketAddresses(address market) external view returns (OptionMarketAddresses memory);

  function getGlobalAddress(bytes32 contractName) external view returns (address globalContract);

  function optionMarkets(uint256 index) external view returns (address);
}
