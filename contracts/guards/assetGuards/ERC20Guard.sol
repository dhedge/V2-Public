//
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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TxDataUtils} from "../../utils/TxDataUtils.sol";
import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {IAaveLendingPoolAssetGuard} from "../../interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import {IGovernance} from "../../interfaces/IGovernance.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {IAaveV3Pool} from "../../interfaces/aave/v3/IAaveV3Pool.sol";

/// @title Generic ERC20 asset guard
/// @dev Asset type = 0
contract ERC20Guard is TxDataUtils, IGuard, IAssetGuard, ITransactionTypes {
  using SafeMath for uint256;

  /// @notice Transaction guard for approving assets
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param poolManagerLogic PoolManagerLogic address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in ITransactionTypes
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address /* to */,
    bytes calldata data
  ) external view override returns (uint16 txType, bool) {
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("approve(address,uint256)"))) {
      address spender = convert32toAddress(getInput(data, 0));

      address factory = IPoolManagerLogic(poolManagerLogic).factory();
      address spenderGuard = IHasGuardInfo(factory).getContractGuard(spender);
      require(spenderGuard != address(0) && spenderGuard != address(this), "unsupported spender approval"); // checks that the spender is an approved address

      txType = uint16(TransactionType.Approve);
    }

    return (txType, false);
  }

  /// @notice Withdraw processing for ERC20 asset
  /// @param pool Address of the pool
  /// @param asset Address of the managed asset
  /// @param portion Portion of the asset balance to withdraw, in 10^18 scale
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to depositor
  /// @return transactions are used to execute the withdrawal transactions in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address /* to */
  )
    external
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    withdrawAsset = asset;
    uint256 totalAssetBalance = getBalance(pool, asset);
    withdrawBalance = totalAssetBalance.mul(portion).div(10 ** 18);
    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns the balance of the managed asset
  /// @param pool Address of the pool
  /// @param asset Address of the managed asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view virtual override returns (uint256 balance) {
    // The base ERC20 guard has no externally staked tokens
    balance = IERC20(asset).balanceOf(pool);
  }

  /// @notice Returns the decimal of the managed asset
  /// @param asset Address of the managed asset
  /// @return decimals The decimal of given asset
  function getDecimals(address asset) external view virtual override returns (uint256 decimals) {
    decimals = IERC20Extended(asset).decimals();
  }

  /// @notice Necessary check for remove asset.
  ///         In AaveLendingPoolAssetGuard, when calculating getBalance, the function loops through all the supported assets.
  ///         Supported asset balance can be 0, but aave collateral or debt can be > 0. If it was able to remove the asset,
  ///         the value of Aave lending pool position would become lower. Having this asset guard with removeAssetCheck prevents this.
  ///         If there is any collateral or debt of a particular asset in Aave, it's not possible to remove that asset.
  /// @param pool Address of the pool
  /// @param asset Address of the remove asset
  function removeAssetCheck(address pool, address asset) public view virtual override {
    require(getBalance(pool, asset) == 0, "cannot remove non-empty asset");

    address factory = IPoolLogic(pool).factory();
    address governance = IPoolFactory(factory).governanceAddress();
    // Magic number 8 is Aave lending pool "asset" asset type
    address aaveLendingPoolAssetGuard = IGovernance(governance).assetGuards(8);

    if (aaveLendingPoolAssetGuard == address(0)) {
      // If Aave lending pool asset guard is not set, skip the check
      return;
    }

    address aaveLendingPool = IAaveLendingPoolAssetGuard(aaveLendingPoolAssetGuard).aaveLendingPool();

    if (!IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(aaveLendingPool)) {
      // If Aave lending pool asset is not supported, skip the check
      return;
    }

    // Returns address(0) if it's not supported in Aave
    address variableDebtToken = IAaveV3Pool(aaveLendingPool).getReserveVariableDebtToken(asset);

    if (variableDebtToken != address(0))
      require(IERC20(variableDebtToken).balanceOf(pool) == 0, "repay Aave debt first");

    // Returns address(0) if it's not supported in Aave
    address aToken = IAaveV3Pool(aaveLendingPool).getReserveAToken(asset);
    if (aToken != address(0)) require(IERC20(aToken).balanceOf(pool) == 0, "withdraw Aave collateral first");
  }
}
