// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";

interface IPoolLimitOrderManager {
  struct LimitOrderInfo {
    uint256 amount;
    uint256 stopLossPriceD18;
    uint256 takeProfitPriceD18;
    address user;
    address pool;
    address pricingAsset;
  }

  struct LimitOrderExecution {
    bytes32 orderId;
    IPoolLogic.ComplexAsset[] complexAssetsData;
    uint256 amount;
  }

  struct SettlementOrderExecution {
    address user;
    IWithdrawalVault.MultiInSingleOutData swapData;
  }

  function createLimitOrder(LimitOrderInfo calldata limitOrderInfo_) external;

  function deleteLimitOrder(address pool_) external;

  function easySwapper() external view returns (address);

  function hasOpenLimitOrder(address user_) external view returns (bool hasOpenLimitOrder_);

  function getUserLimitOrderIds(address user_) external view returns (bytes32[] memory orderIds_);

  function hasSettlementOrder(address user_) external view returns (bool hasSettlementOrder_);

  function limitOrderSettlementToken() external view returns (address);

  function modifyLimitOrder(LimitOrderInfo calldata modificationInfo_) external;

  function executeLimitOrders(LimitOrderExecution[] calldata orders_) external;

  function executeSettlementOrders(SettlementOrderExecution[] calldata orders_) external;
}
