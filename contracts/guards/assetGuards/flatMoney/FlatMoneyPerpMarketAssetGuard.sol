// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {FlatMoneyDelayedOrderContractGuard} from "../../../guards/contractGuards/flatMoney/FlatMoneyDelayedOrderContractGuard.sol";
import {ILeverageModule} from "../../../interfaces/flatMoney/ILeverageModule.sol";
import {IOracleModule} from "../../../interfaces/flatMoney/IOracleModule.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {FlatcoinModuleKeys} from "../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {ClosedAssetGuard} from "../ClosedAssetGuard.sol";
import {OutsidePositionWithdrawalHelper} from "../OutsidePositionWithdrawalHelper.sol";
import {FlatMoneyOrderHelperGuard} from "./FlatMoneyOrderHelperGuard.sol";

/// @notice AssetType = 27
contract FlatMoneyPerpMarketAssetGuard is OutsidePositionWithdrawalHelper, FlatMoneyOrderHelperGuard, ClosedAssetGuard {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SafeCast for int256;

  /// @notice Returns the balance of Flat Money leverage positions
  /// @dev Returns the balance to be priced in USD
  /// @param _pool PoolLogic address
  /// @param _asset Asset address (LeverageModule address)
  /// @return balance Flat Money leverage positions balance of the pool
  function getBalance(
    address _pool,
    address _asset
  ) public view override(ClosedAssetGuard, OutsidePositionWithdrawalHelper) returns (uint256 balance) {
    require(_hasNoBlockingOrder(_pool, _asset), "order in progress");

    uint256[] memory tokenIds = _useContractGuard(_pool, _asset).getOwnedTokenIds(_pool);
    int256 totalMarginAfterSettlement;
    for (uint256 i; i < tokenIds.length; ++i) {
      totalMarginAfterSettlement = totalMarginAfterSettlement.add(
        ILeverageModule(_asset).getPositionSummary(tokenIds[i]).marginAfterSettlement
      );
    }

    address oracleModule = ILeverageModule(_asset).vault().moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY);
    (uint256 price, ) = IOracleModule(oracleModule).getPrice();

    balance = totalMarginAfterSettlement.toUint256().mul(price).div(1e18);
  }

  /// @notice Returns the decimals of Flat Money leverage positions
  /// @return decimals Decimals of the asset
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing from Flat Money leverage positions
  /// @dev Leverage position portion is being withdrawn using specially configured asset sitting in the pool outside
  /// @param _pool PoolLogic address
  /// @param _asset Asset address (LeverageModule address)
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
    (, address withdrawalAsset) = _useContractGuard(_pool, _asset).dHedgePoolsWhitelist(_pool);

    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(
      _pool,
      _asset,
      _withdrawPortion,
      withdrawalAsset
    );
  }

  function _useContractGuard(
    address _pool,
    address _moduleAddress
  ) internal view returns (FlatMoneyDelayedOrderContractGuard delayedOrderGuard) {
    address delayedOrder = ILeverageModule(_moduleAddress).vault().moduleAddress(FlatcoinModuleKeys._DELAYED_ORDER_KEY);
    delayedOrderGuard = FlatMoneyDelayedOrderContractGuard(
      IHasGuardInfo(IPoolLogic(_pool).factory()).getContractGuard(delayedOrder)
    );
  }
}
