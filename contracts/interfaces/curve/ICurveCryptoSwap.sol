// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ICurveCryptoSwap {
  // solhint-disable-next-line func-name-mixedcase
  function underlying_coins(uint256 i) external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function get_dy_underlying(uint256 i, uint256 j, uint256 dx) external view returns (uint256);

  // solhint-disable-next-line func-name-mixedcase
  function exchange_underlying(
    uint256 i,
    uint256 j,
    uint256 dx,
    // solhint-disable-next-line var-name-mixedcase
    uint256 min_dy,
    address receipient
  ) external;
}
