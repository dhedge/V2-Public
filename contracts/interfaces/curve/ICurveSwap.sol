// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ICurveSwap {
  // solhint-disable-next-line func-name-mixedcase
  function underlying_coins(uint256 i) external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function get_best_rate(
    address _from,
    address _to,
    uint256 amount
  ) external view returns (address, uint256);

  // solhint-disable-next-line func-name-mixedcase
  function exchange(
    address pool,
    address _from,
    address _to,
    uint256 amount,
    uint256 expected,
    address receiver
  ) external;
}
