// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IAaveProtocolDataProvider {
  function ADDRESSES_PROVIDER() external view returns (address);

  function getReserveTokensAddresses(address asset)
    external
    view
    returns (
      address aTokenAddress,
      address stableDebtTokenAddress,
      address variableDebtTokenAddress
    );
}
