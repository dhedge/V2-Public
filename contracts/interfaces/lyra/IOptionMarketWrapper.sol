// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IOptionMarket.sol";
import "./IOptionToken.sol";

interface IOptionMarketWrapper {
  struct OptionMarketContracts {
    IERC20 quoteAsset;
    IERC20 baseAsset;
    IOptionToken optionToken;
  }

  struct OptionPositionParams {
    IOptionMarket optionMarket;
    uint256 strikeId; // The id of the relevant OptionListing
    uint256 positionId;
    uint256 iterations;
    uint256 setCollateralTo;
    uint256 currentCollateral;
    IOptionMarket.OptionType optionType; // Is the trade a long/short & call/put?
    uint256 amount; // The amount the user has requested to close
    uint256 minCost; // Min amount for the cost of the trade
    uint256 maxCost; // Max amount for the cost of the trade
    uint256 inputAmount; // Amount of stable coins the user can use
    IERC20 inputAsset; // Address of coin user wants to open with
  }

  struct ReturnDetails {
    address market;
    uint256 positionId;
    address owner;
    uint256 amount;
    uint256 totalCost;
    uint256 totalFee;
    int256 swapFee;
    address token;
  }

  function openPosition(OptionPositionParams memory params) external returns (ReturnDetails memory returnDetails);

  function closePosition(OptionPositionParams memory params) external returns (ReturnDetails memory returnDetails);

  function forceClosePosition(OptionPositionParams memory params) external returns (ReturnDetails memory returnDetails);

  function marketContracts(IOptionMarket market) external view returns (OptionMarketContracts memory);

  function idToMarket(uint8 id) external view returns (address optionMarket);

  function idToERC(uint8 id) external view returns (address token);

  function openLong(uint256 params) external returns (uint256 totalCost);

  function addLong(uint256 params) external returns (uint256 totalCost);

  function reduceLong(uint256 params) external returns (uint256 totalReceived);

  function closeLong(uint256 params) external returns (uint256 totalReceived);

  function openShort(uint256 params) external returns (uint256 totalReceived);

  function addShort(uint256 params) external returns (uint256 totalReceived);

  function reduceShort(uint256 params) external returns (uint256 totalCost);

  function closeShort(uint256 params) external returns (uint256 totalCost);
}
