// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {FlatMoneyBasisContractGuard} from "../../../../../guards/contractGuards/flatMoney/shared/FlatMoneyBasisContractGuard.sol";
import {ILeverageModuleV2} from "../../../../../interfaces/flatMoney/v2/ILeverageModuleV2.sol";
import {IFlatcoinVaultV2} from "../../../../../interfaces/flatMoney/v2/IFlatcoinVaultV2.sol";
import {IOracleModuleV2} from "../../../../../interfaces/flatMoney/v2/IOracleModuleV2.sol";
import {IHasGuardInfo} from "../../../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../../../interfaces/IPoolLogic.sol";
import {IERC20Extended} from "../../../../../interfaces/IERC20Extended.sol";
import {FlatcoinModuleKeys} from "../../../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {ClosedAssetGuard} from "../../../ClosedAssetGuard.sol";
import {OutsidePositionWithdrawalHelper} from "../../../OutsidePositionWithdrawalHelper.sol";
import {FlatMoneyV2OrderHelperGuard} from "../FlatMoneyV2OrderHelperGuard.sol";

abstract contract FlatMoneyV2BasisAssetGuard is
  OutsidePositionWithdrawalHelper,
  FlatMoneyV2OrderHelperGuard,
  ClosedAssetGuard
{
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SafeCast for int256;

  function getBalance(
    address _pool,
    address _asset
  ) public view override(ClosedAssetGuard, OutsidePositionWithdrawalHelper) returns (uint256 balanceD18) {
    require(_hasNoBlockingOrder(_pool, _asset), "order in progress");

    uint256[] memory tokenIds = _useContractGuard(_pool, _asset).getOwnedTokenIds(_pool);
    int256 totalMarginAfterSettlement;
    for (uint256 i; i < tokenIds.length; ++i) {
      totalMarginAfterSettlement = totalMarginAfterSettlement.add(
        ILeverageModuleV2(_asset).getPositionSummary(tokenIds[i]).marginAfterSettlement
      );
    }

    IFlatcoinVaultV2 vault = ILeverageModuleV2(_asset).vault();
    address collateral = vault.collateral();

    (uint256 priceD18, ) = IOracleModuleV2(vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY)).getPrice(
      collateral
    );

    balanceD18 = totalMarginAfterSettlement.toUint256().mul(priceD18).div(
      10 ** (IERC20Extended(collateral).decimals())
    );
  }

  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  function _useContractGuard(
    address _pool,
    address _moduleAddress
  ) internal view returns (FlatMoneyBasisContractGuard contractGuard) {
    address orderAnnouncementModule = ILeverageModuleV2(_moduleAddress).vault().moduleAddress(
      FlatcoinModuleKeys._ORDER_ANNOUNCEMENT_MODULE_KEY
    );
    contractGuard = FlatMoneyBasisContractGuard(
      IHasGuardInfo(IPoolLogic(_pool).factory()).getContractGuard(orderAnnouncementModule)
    );
  }
}
