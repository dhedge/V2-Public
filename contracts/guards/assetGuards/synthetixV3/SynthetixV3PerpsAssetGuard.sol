//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2023 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {ISynthetixV3PerpsMarketContractGuard} from "../../../interfaces/synthetixV3/ISynthetixV3PerpsMarketContractGuard.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {ClosedAssetGuard} from "../ClosedAssetGuard.sol";
import {OutsidePositionWithdrawalHelper} from "../OutsidePositionWithdrawalHelper.sol";
import {IPerpsAccountModule} from "../../../interfaces/synthetixV3/IPerpsAccountModule.sol";

contract SynthetixV3PerpsAssetGuard is OutsidePositionWithdrawalHelper, ClosedAssetGuard {
  using SafeMath for uint256;
  using SafeCast for int256;

  address public immutable withdrawalAsset;

  constructor(address _withdrawalAsset) {
    require(_withdrawalAsset != address(0), "invalid withdrawAsset");

    withdrawalAsset = _withdrawalAsset;
  }

  /// @notice Returns the balance of Synthetix V3 Perps Market position
  /// @dev Returns the balance to be priced in USD
  /// @param _pool Pool address
  /// @param _asset Asset address (Basically Synthetix V3 Perps Market address)
  /// @return balance Synthetix V3 perps balance of the pool
  function getBalance(
    address _pool,
    address _asset
  ) public view override(ClosedAssetGuard, OutsidePositionWithdrawalHelper) returns (uint256) {
    ISynthetixV3PerpsMarketContractGuard contractGuard = ISynthetixV3PerpsMarketContractGuard(
      IHasGuardInfo(IPoolLogic(_pool).factory()).getContractGuard(_asset)
    );
    uint128 accountId = contractGuard.getAccountNftTokenId(_pool, _asset);
    int256 availableMargin = IPerpsAccountModule(_asset).getAvailableMargin(accountId);
    if (accountId == 0 || availableMargin <= 0) {
      return 0;
    }
    return availableMargin.toUint256();
  }

  /// @notice Creates transaction data for withdrawing from Synthetix V3 position
  /// @dev Current version is the simplest workaround for unwinding perp positions
  /// @dev Assumes that the pool always holds some amount of collateral outside of perp margin account
  /// @dev That implies limitations on the size of the withdrawal
  /// @param _pool Pool address
  /// @param _asset Asset address (Basically Synthetix V3 perps market address)
  /// @param _withdrawPortion Portion of the asset to withdraw
  /// @return withdrawAsset Asset address to withdraw (Basically zero address)
  /// @return withdrawBalance Amount to withdraw (Basically zero amount)
  /// @return transactions Transactions to be executed (These is where actual token transfer happens)
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
    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(
      _pool,
      _asset,
      _withdrawPortion,
      withdrawalAsset
    );
  }

  /// @notice Returns the decimals of Synthetix V3 Perps Market position
  /// @return decimals Decimals of the asset
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }
}
