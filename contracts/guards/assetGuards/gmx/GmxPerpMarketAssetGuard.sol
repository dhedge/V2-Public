// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxExchangeRouterContractGuard} from "../../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IAccountedTokenAssetGuard} from "../../../interfaces/guards/IAccountedTokenAssetGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {OutsidePositionWithdrawalHelper} from "../OutsidePositionWithdrawalHelper.sol";
import {ERC20Guard} from "../ERC20Guard.sol";
import {NonDepositAssetGuard} from "../shared/NonDepositAssetGuard.sol";
import {GmxStructs} from "../../../utils/gmx/GmxStructs.sol";
import {GmxPerpMarketAssetGuardLib} from "../../../utils/gmx/GmxPerpMarketAssetGuardLib.sol";

/// @notice AssetType = 105
contract GmxPerpMarketAssetGuard is
  OutsidePositionWithdrawalHelper,
  ERC20Guard,
  IAccountedTokenAssetGuard,
  NonDepositAssetGuard
{
  address public immutable gmxExchangeRouter;

  /// @inheritdoc IAccountedTokenAssetGuard
  // solhint-disable-next-line const-name-snakecase
  bool public constant override isAccountedTokenAssetGuard = true;

  constructor(address _gmxExchangeRouter) {
    gmxExchangeRouter = _gmxExchangeRouter;
  }

  function _addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _asset) internal view override {
    super._addAssetCheck(_poolLogic, _asset);

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

  /// @inheritdoc IAccountedTokenAssetGuard
  /// @dev The asset's $1 oracle prices the composite USD value returned by `getBalance`, not raw GMX market
  ///      token units. Generic swap guards therefore cannot value a market token source correctly; market
  ///      tokens must be unwound through the guarded GMX withdrawal flow.
  function isAccountedToken(address, address _asset, address _token) external pure override returns (bool accounted) {
    accounted = _asset == _token;
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
