// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {DytmParamStructs} from "../../utils/dytm/DytmParamStructs.sol";

interface IDytmOffice {
  function delegationCall(
    DytmParamStructs.DelegationCallParams calldata params
  ) external returns (bytes memory returnData);
  function supply(DytmParamStructs.SupplyParams calldata params) external returns (uint256 shares);
  function switchCollateral(
    DytmParamStructs.SwitchCollateralParams calldata params
  ) external returns (uint256 assets, uint256 shares);
  function withdraw(DytmParamStructs.WithdrawParams calldata params) external returns (uint256 assets);
  function borrow(DytmParamStructs.BorrowParams calldata params) external returns (uint256 debtShares);
  function repay(DytmParamStructs.RepayParams calldata params) external returns (uint256 assetsRepaid);
  function transfer(address receiver, uint256 tokenId, uint256 amount) external returns (bool success);
  function isHealthyAccount(uint256 account, uint88 market) external returns (bool isHealthy);
  function callerContext() external view returns (address);
  function getAccountCount() external view returns (uint96 accountCount);
  function createMarket(address officer, address marketConfig) external returns (uint88 marketId);
  function accrueInterest(uint248 key) external returns (uint256 interest);
  function getAllCollateralIds(uint256 account, uint88 market) external view returns (uint256[] memory);
  function getDebtId(uint256 account, uint88 market) external view returns (uint256);
}
