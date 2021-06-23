// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ILendingPool {
  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external;

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external returns (uint256);

  function borrow(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    uint16 referralCode,
    address onBehalfOf
  ) external;

  function repay(
    address asset,
    uint256 amount,
    uint256 rateMode,
    address onBehalfOf
  ) external returns (uint256);

  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

  function rebalanceStableBorrowRate(address asset, address user) external;

  function swapBorrowRateMode(address asset, uint256 rateMode) external;
}
