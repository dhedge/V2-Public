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
// Copyright (c) 2024 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IEasySwapperV2} from "../../swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "../../swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {ClosedAssetGuard} from "./ClosedAssetGuard.sol";

contract EasySwapperV2UnrolledAssetsGuard is ClosedAssetGuard {
  using SafeMath for uint256;

  function getBalance(address _pool, address _asset) public view override returns (uint256 balance) {
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = IEasySwapperV2(_asset).getTrackedAssets(_pool);
    address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();

    for (uint256 i; i < trackedAssets.length; ++i) {
      balance = balance.add(
        IPoolManagerLogic(poolManagerLogic).assetValue(trackedAssets[i].token, trackedAssets[i].balance)
      );
    }
  }

  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address _to
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    uint256 balance = getBalance(_pool, _asset);

    if (balance == 0) {
      return (withdrawAsset, withdrawBalance, transactions);
    }

    transactions = new MultiTransaction[](1);
    transactions[0] = MultiTransaction({
      to: _asset,
      txData: abi.encodeWithSelector(IEasySwapperV2.partialWithdraw.selector, _withdrawPortion, _to)
    });

    return (withdrawAsset, withdrawBalance, transactions);
  }
}
