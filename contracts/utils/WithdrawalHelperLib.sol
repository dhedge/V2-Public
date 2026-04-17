// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IPoolLogic} from "../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../interfaces/IPoolManagerLogic.sol";
import {IERC20Extended} from "../interfaces/IERC20Extended.sol";

/// @title Shared helpers for withdrawal processing in asset guards
library WithdrawalHelperLib {
  using SafeMath for uint256;

  /// @notice Mints manager fee, applies exit fee, and calculates withdrawal portion
  /// @param _pool The pool (or vault token) address
  /// @param _tokenAmount The amount of pool tokens to be withdrawn
  /// @return portion The portion of totalSupply being withdrawn (scaled by 1e18)
  /// @return poolManagerLogic The pool manager logic address
  function calculateWithdrawalPortion(
    address _pool,
    uint256 _tokenAmount
  ) internal returns (uint256 portion, address poolManagerLogic) {
    // Mint manager fee to update totalSupply for accurate portion calculation
    IPoolLogic(_pool).mintManagerFee();

    poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();

    // If the pool has exit fee set, token amount processed for withdrawal will be reduced by the exit fee
    (uint256 exitFeeNumerator, , uint256 denominator) = IPoolManagerLogic(poolManagerLogic).getExitFeeInfo();
    if (exitFeeNumerator > 0) {
      _tokenAmount = _tokenAmount.sub(_tokenAmount.mul(exitFeeNumerator).div(denominator));
    }

    // Calculate what portion of pool tokens is intended for withdrawal
    portion = _tokenAmount.mul(1e18).div(IERC20Extended(_pool).totalSupply());
  }
}
