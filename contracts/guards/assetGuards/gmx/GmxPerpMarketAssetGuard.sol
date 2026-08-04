// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxExchangeRouterContractGuard} from "../../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {OutsidePositionWithdrawalHelper} from "../OutsidePositionWithdrawalHelper.sol";
import {ERC20Guard} from "../ERC20Guard.sol";
import {GmxStructs} from "../../../utils/gmx/GmxStructs.sol";
import {GmxPerpMarketAssetGuardLib} from "../../../utils/gmx/GmxPerpMarketAssetGuardLib.sol";

/// @notice AssetType = 105
contract GmxPerpMarketAssetGuard is OutsidePositionWithdrawalHelper, ERC20Guard, IAddAssetCheckGuard {
  address public immutable gmxExchangeRouter;
  bool public override isAddAssetCheckGuard = true;

  constructor(address _gmxExchangeRouter) {
    gmxExchangeRouter = _gmxExchangeRouter;
  }

  function addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _asset) external view override {
    require(!_asset.isDeposit, "deposit not supported");
    GmxStructs.PoolSetting memory poolSetting = _useContractGuard(IPoolLogic(_poolLogic).factory())
      .dHedgePoolsWhitelist(_poolLogic);
    require(poolSetting.poolLogic == _poolLogic, "not gmx whitelisted");
  }

  /// @notice Returns the balance of GMX perp leverage positions
  /// @dev Returns the balance to be priced in USD
  /// @param _pool PoolLogic address
  /// @param _asset Asset address (GMX perp market address)
  /// @return balance GMX perp market balance of the pool
  function getBalance(
    address _pool,
    address _asset
  ) public view override(OutsidePositionWithdrawalHelper, ERC20Guard) returns (uint256 balance) {
    balance = GmxPerpMarketAssetGuardLib.getBalance(gmxExchangeRouter, _pool, _asset);
  }

  /// @notice Returns the decimals of Flat Money leverage positions
  /// @return decimals Decimals of the asset
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing from GMX leverage positions
  /// @dev Leverage position portion is being withdrawn using specially configured asset sitting in the pool outside
  /// @param _pool PoolLogic address
  /// @param _asset Asset address (GMX perp market address)
  /// @param _withdrawPortion Portion to withdraw
  /// @return withdrawAsset Asset address to withdraw
  /// @return withdrawBalance Amount to withdraw
  /// @return transactions Transactions to be executed
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    GmxStructs.PoolSetting memory poolSetting = _useContractGuard(IPoolLogic(_pool).factory()).dHedgePoolsWhitelist(
      _pool
    );

    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(
      _pool,
      _asset,
      _withdrawPortion,
      poolSetting.withdrawalAsset
    );
  }

  function _useContractGuard(
    address _poolFactory
  ) internal view returns (IGmxExchangeRouterContractGuard contractguard) {
    contractguard = IGmxExchangeRouterContractGuard(IHasGuardInfo(_poolFactory).getContractGuard(gmxExchangeRouter));
  }
}
