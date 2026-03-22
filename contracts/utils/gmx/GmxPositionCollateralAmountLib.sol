// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {IGmxPosition} from "../../interfaces/gmx/IGmxPosition.sol";

library GmxPositionCollateralAmountLib {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SafeCast for uint256;

  /**
   * @dev Returns the ceiling of the division of two numbers.
   *
   * This differs from standard division with `/` in that it rounds up instead
   * of rounding down.
   */
  function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
    return a == 0 ? 0 : (a.sub(1)).div(b).add(1);
  }

  function getPositionCollateralAmount(
    IGmxPosition.PositionInfo memory positionInfo
  ) internal pure returns (uint256 collateralAmount) {
    collateralAmount = positionInfo.position.numbers.collateralAmount;

    int256 basePnlCollateralAmount;
    if (positionInfo.basePnlUsd > 0) {
      basePnlCollateralAmount = positionInfo.basePnlUsd.div((positionInfo.fees.collateralTokenPrice.max).toInt256());
    } else if (positionInfo.basePnlUsd < 0) {
      basePnlCollateralAmount = ceilDiv(
        uint256(positionInfo.basePnlUsd.mul(-1)),
        (positionInfo.fees.collateralTokenPrice.min)
      ).toInt256().mul(-1);
    }

    int256 totalImpactCollateralAmount;
    if (positionInfo.executionPriceResult.totalImpactUsd > 0) {
      totalImpactCollateralAmount = positionInfo.executionPriceResult.totalImpactUsd.div(
        (positionInfo.fees.collateralTokenPrice.max).toInt256()
      );
    } else if (positionInfo.executionPriceResult.totalImpactUsd < 0) {
      totalImpactCollateralAmount = (
        ceilDiv(
          uint256(positionInfo.executionPriceResult.totalImpactUsd.mul(-1)),
          (positionInfo.fees.collateralTokenPrice.min)
        )
      ).toInt256().mul(-1);
    }

    int256 pnlAfterTotalImpactCollateralAmount = totalImpactCollateralAmount.add(basePnlCollateralAmount);
    if (pnlAfterTotalImpactCollateralAmount > 0) {
      collateralAmount = collateralAmount.add(uint256(pnlAfterTotalImpactCollateralAmount));
    } else {
      uint256 lossCollateralAmount = uint256(pnlAfterTotalImpactCollateralAmount.mul(-1));
      // loss can be greater than collateral amount, then we don't include it all.
      // Debt is per position, not per account. That is why negative value is not included in the getDebtAssets() as only the deposited collateral can be recovered by the GMXV2 protocol.
      if (lossCollateralAmount < collateralAmount) {
        collateralAmount = collateralAmount.sub(lossCollateralAmount);
      } else {
        collateralAmount = 0;
      }
    }
    // Subtract the fees incurred by the position from the total collateral
    if (positionInfo.fees.totalCostAmount < collateralAmount) {
      collateralAmount = collateralAmount.sub(positionInfo.fees.totalCostAmount);
    } else {
      collateralAmount = 0;
    }
  }
}
