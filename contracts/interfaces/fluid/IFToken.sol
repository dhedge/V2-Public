// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

interface IFToken {
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function asset() external view returns (address);
  function balanceOf(address account) external view returns (uint256);
  function convertToAssets(uint256 shares_) external view returns (uint256);
  function convertToShares(uint256 assets_) external view returns (uint256);
  function decimals() external view returns (uint8);
  function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
  function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);
  function getData()
    external
    view
    returns (
      address liquidity_,
      address lendingFactory_,
      address lendingRewardsRateModel_,
      address permit2_,
      address rebalancer_,
      bool rewardsActive_,
      uint256 liquidityBalance_,
      uint256 liquidityExchangePrice_,
      uint256 tokenExchangePrice_
    );
  function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
  function maxDeposit(address) external view returns (uint256);
  function maxRedeem(address owner_) external view returns (uint256);
  function maxWithdraw(address owner_) external view returns (uint256);
  function minDeposit() external view returns (uint256);
  function previewDeposit(uint256 assets_) external view returns (uint256);
  function previewRedeem(uint256 shares_) external view returns (uint256);
  function previewWithdraw(uint256 assets_) external view returns (uint256);
  function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);
  function totalAssets() external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function transfer(address to, uint256 amount) external returns (bool);
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
  function updateRates() external returns (uint256 tokenExchangePrice_, uint256 liquidityExchangePrice_);
  function withdraw(uint256 assets_, address receiver_, address owner_) external returns (uint256 shares_);
}
