// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IOptionToken.sol";
import "./IOptionMarket.sol";
import "./IOptionGreekCache.sol";

interface IOptionMarketViewer {
  struct MarketOptionPositions {
    address market;
    IOptionToken.OptionPosition[] positions;
  }

  struct OptionMarketAddresses {
    address liquidityPool;
    address liquidityTokens;
    IOptionGreekCache greekCache;
    IOptionMarket optionMarket;
    address optionMarketPricer;
    IOptionToken optionToken;
    address shortCollateral;
    address poolHedger;
    IERC20 quoteAsset;
    IERC20 baseAsset;
  }

  function synthetixAdapter() external view returns (address);

  function getOwnerPositions(address owner) external view returns (IOptionToken.OptionPosition[] memory);

  function getMarketAddresses() external view returns (OptionMarketAddresses[] memory);

  function marketAddresses(address market) external view returns (OptionMarketAddresses memory);
}
