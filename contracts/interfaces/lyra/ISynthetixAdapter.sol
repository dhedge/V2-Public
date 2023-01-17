// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IOptionMarket.sol";
import "../synthetix/IExchanger.sol";

interface ISynthetixAdapter {
  function synthetix() external view returns (address);

  function exchanger() external view returns (IExchanger);

  function addressResolver() external view returns (address);

  function quoteKey(address) external view returns (bytes32);

  function baseKey(address) external view returns (bytes32);

  function getSpotPriceForMarket(address) external view returns (uint256);
}
