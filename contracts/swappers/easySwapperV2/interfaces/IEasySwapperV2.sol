// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {ISwapper} from "../../../interfaces/flatMoney/swapper/ISwapper.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IWithdrawalVault} from "./IWithdrawalVault.sol";

interface IEasySwapperV2 {
  // ============ Types ============

  enum WithdrawalVaultType {
    SINGLE_ASSET_WITHDRAWAL,
    LIMIT_ORDER
  }

  // ============ State Variable Getters ============

  function swapper() external view returns (ISwapper swapper_);

  function withdrawalContracts(address _depositor) external view returns (address withdrawalVault_);

  function limitOrderContracts(address _depositor) external view returns (address limitOrderVault_);

  function customCooldown() external view returns (uint256 cooldown_);

  function customCooldownDepositsWhitelist(address _vault) external view returns (bool isWhitelisted_);

  // ============ View Functions ============

  function isdHedgeVault(address _dHedgeVault) external view returns (bool isVault_);

  function depositQuote(
    address _dHedgeVault,
    address _vaultDepositToken,
    uint256 _depositAmount
  ) external view returns (uint256 expectedAmountReceived_);

  function getTrackedAssets(
    address _depositor
  ) external view returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets_);

  function getTrackedAssetsFromLimitOrders(
    address _depositor
  ) external view returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets_);

  // ============ Mutating Functions ============

  function partialWithdraw(uint256 _portion, address _to, WithdrawalVaultType _vaultType) external;

  function dHedgePoolFactory() external view returns (address);

  function initLimitOrderWithdrawalFor(
    address _user,
    address _dHedgeVault,
    uint256 _amountIn,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) external returns (IWithdrawalVault.TrackedAsset[] memory trackedAssets_, address vault_);

  function completeLimitOrderWithdrawalFor(
    address _user,
    IWithdrawalVault.MultiInSingleOutData calldata _swapData,
    uint256 _expectedDestTokenAmount
  ) external returns (uint256 destTokenAmount_);
}
