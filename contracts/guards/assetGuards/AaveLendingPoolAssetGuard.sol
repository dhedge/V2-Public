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
// Copyright (c) 2024 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IAaveProtocolDataProvider} from "../../interfaces/aave/IAaveProtocolDataProvider.sol";
import {IAaveLendingPoolAssetGuard} from "../../interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import {ISlippageCheckingGuard} from "../../interfaces/guards/ISlippageCheckingGuard.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {ClosedAssetGuard} from "./ClosedAssetGuard.sol";

/// @title Aave lending pool asset guard
/// @dev Asset type 3 is for v2
///      Asset type 8 is for v3
contract AaveLendingPoolAssetGuard is ClosedAssetGuard, IAaveLendingPoolAssetGuard, ISlippageCheckingGuard {
  using SafeMath for uint256;

  struct AssetInAave {
    address asset;
    uint256 amount;
  }

  struct RepayData {
    address asset;
    uint256 amount;
    uint256 premium;
  }

  bool public override isSlippageCheckingGuard = true;

  IAaveProtocolDataProvider public immutable aaveProtocolDataProvider;

  address public immutable override aaveLendingPool;

  /// @param _aaveProtocolDataProvider Aave protocol data provider address
  /// @param _aaveLendingPool Aave lending pool address
  constructor(address _aaveProtocolDataProvider, address _aaveLendingPool) {
    require(_aaveProtocolDataProvider != address(0) && _aaveLendingPool != address(0), "invalid address");

    aaveProtocolDataProvider = IAaveProtocolDataProvider(_aaveProtocolDataProvider);
    aaveLendingPool = _aaveLendingPool;
  }

  /// @notice Returns the pool position of Aave lending pool
  /// @dev Returns the balance priced in USD
  /// @param _pool The pool logic address
  /// @return balance The total balance of the pool
  function getBalance(address _pool, address) public view override returns (uint256 balance) {
    (uint256 totalCollateralInUsd, uint256 totalDebtInUsd) = _getBalance(_pool);

    if (totalCollateralInUsd > totalDebtInUsd) {
      balance = totalCollateralInUsd.sub(totalDebtInUsd);
    }
  }

  /// @notice Returns decimals of the Aave lending pool asset
  /// @return decimals The decimals of the asset
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @param _pool The pool logic address
  /// @param _portion The portion of asset to be withdrawn
  /// @param _to The recipient address
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to depositor
  /// @return transactions are used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address _pool,
    address,
    uint256 _portion,
    address _to
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    AssetInAave memory borrowAsset = _calculateBorrowAsset(_pool, _portion);

    if (borrowAsset.asset == address(0)) {
      transactions = _withdrawAndTransfer(_pool, _to, _portion);
      // There is no asset to withdraw as the above executes the withdraw to the withdrawer(_to)
      return (address(0), 0, transactions);
    }

    // Changing the withdraw asset to borrow asset as this is the asset used for the remaining after flashloan repay
    withdrawAsset = borrowAsset.asset;
    // This adds a transaction that will initiate the flashloan flow from aave,
    // Aave will callback the higher level PoolLogic.executeOperation
    transactions = _prepareFlashLoan(_pool, _portion, borrowAsset);
    return (withdrawAsset, 0, transactions);
  }

  /// @notice Checks that asset can be removed from supported pool assets
  /// @dev Should not be abled to remove if pool has any collateral or debt in aave
  ///      This mitigates issue discovered by sherlock, that in theory when totalCollateralInUsd equals totalDebtInUsd,
  ///      aave position balance will be 0 and aave position asset could be removed, which should not happen
  /// @param _pool The pool logic address
  function removeAssetCheck(address _pool, address) public view override {
    (uint256 totalCollateralInUsd, uint256 totalDebtInUsd) = _getBalance(_pool);

    require(totalCollateralInUsd == 0 && totalDebtInUsd == 0, "cannot remove non-empty asset");
  }

  /// @notice process flash loan and return the transactions for execution
  /// @param _pool The pool logic address
  /// @param _repayAsset Asset to be repaid
  /// @param _repayAmount Amounts to be repaid
  /// @param _premium Premium to be paid for flash loan
  /// @param _params Arbitrary bytes-encoded params that will be passed to executeOperation() method of the receiver contract
  /// @return transactions Array of transactions to be executed
  function flashloanProcessing(
    address _pool,
    address _repayAsset,
    uint256 _repayAmount,
    uint256 _premium,
    bytes calldata _params
  ) external view virtual override returns (MultiTransaction[] memory transactions) {
    uint256 portion = abi.decode(_params, (uint256));
    RepayData memory repayData = RepayData({asset: _repayAsset, amount: _repayAmount, premium: _premium});

    // At this stage we have the flashloan
    // Repay the debt with the flashloan
    // This will unlock our portion of the collateral
    MultiTransaction[] memory repayDebtTransactions = _repayDebtTransactions(_pool, repayData);

    // Withdraw our collateral from aave and swap everything to repay asset
    MultiTransaction[] memory withdrawCollateralTransactions = _withdrawCollateralTransactions(
      _pool,
      portion,
      IHasGuardInfo(IPoolLogic(_pool).factory()).getAddress("swapRouter"),
      repayData.asset
    );

    transactions = new MultiTransaction[](repayDebtTransactions.length + withdrawCollateralTransactions.length);

    uint256 i;
    uint256 txCount;
    for (i = 0; i < repayDebtTransactions.length; i++) {
      transactions[txCount].to = repayDebtTransactions[i].to;
      transactions[txCount].txData = repayDebtTransactions[i].txData;
      txCount++;
    }
    for (i = 0; i < withdrawCollateralTransactions.length; i++) {
      transactions[txCount].to = withdrawCollateralTransactions[i].to;
      transactions[txCount].txData = withdrawCollateralTransactions[i].txData;
      txCount++;
    }
  }

  function _getBalance(address _pool) internal view returns (uint256 totalCollateralInUsd, uint256 totalDebtInUsd) {
    (IHasSupportedAsset.Asset[] memory supportedAssets, uint256 length) = _getPoolSupportedAssets(_pool);

    address asset;
    uint256 decimals;
    uint256 tokenPriceInUsd;
    uint256 collateralBalance;
    uint256 debtBalance;
    address factory = IPoolLogic(_pool).factory();

    for (uint256 i; i < length; ++i) {
      asset = supportedAssets[i].asset;

      // Lending/Borrowing enabled asset
      if (IHasAssetInfo(factory).getAssetType(asset) == 4 || IHasAssetInfo(factory).getAssetType(asset) == 14) {
        (collateralBalance, debtBalance, decimals) = _calculateAaveBalance(_pool, asset);

        if (collateralBalance != 0 || debtBalance != 0) {
          tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(asset);
          totalCollateralInUsd = totalCollateralInUsd.add(tokenPriceInUsd.mul(collateralBalance).div(10 ** decimals));
          totalDebtInUsd = totalDebtInUsd.add(tokenPriceInUsd.mul(debtBalance).div(10 ** decimals));
        }
      }
    }
  }

  function _calculateAaveBalance(
    address _pool,
    address _asset
  ) internal view returns (uint256 collateralBalance, uint256 debtBalance, uint256 decimals) {
    (address aToken, address variableDebtToken) = _getReserveTokensAddresses(_asset);
    if (aToken != address(0)) {
      collateralBalance = IERC20Extended(aToken).balanceOf(_pool);
      debtBalance = IERC20Extended(variableDebtToken).balanceOf(_pool);
    }

    decimals = IERC20Extended(_asset).decimals();
  }

  function _calculateCollateralAssets(
    address _pool,
    uint256 _portion
  ) internal view returns (AssetInAave[] memory collateralAssets, uint256 length) {
    (IHasSupportedAsset.Asset[] memory supportedAssets, uint256 supportedAssetsLength) = _getPoolSupportedAssets(_pool);

    collateralAssets = new AssetInAave[](supportedAssetsLength);

    address aToken;
    for (uint256 i; i < supportedAssetsLength; ++i) {
      (aToken, ) = _getReserveTokensAddresses(supportedAssets[i].asset);

      if (aToken != address(0)) {
        collateralAssets[length].amount = IERC20Extended(aToken).balanceOf(_pool);
        if (collateralAssets[length].amount != 0) {
          collateralAssets[length].amount = collateralAssets[length].amount.mul(_portion).div(10 ** 18);
          if (collateralAssets[length].amount == 0) continue; // sherlock issue: skip if the amount got rounded down to 0, which will cause revert
          collateralAssets[length].asset = supportedAssets[i].asset;
          length++;
        }
      }
    }

    // Reduce length the empty items
    uint256 reduceLength = supportedAssetsLength.sub(length);
    assembly {
      mstore(collateralAssets, sub(mload(collateralAssets), reduceLength))
    }
  }

  function _calculateBorrowAsset(
    address _pool,
    uint256 _portion
  ) internal view returns (AssetInAave memory borrowAsset) {
    (IHasSupportedAsset.Asset[] memory supportedAssets, uint256 length) = _getPoolSupportedAssets(_pool);

    address variableDebtToken;
    for (uint256 i; i < length; ++i) {
      // returns address(0) if it's not supported in aave
      (, variableDebtToken) = _getReserveTokensAddresses(supportedAssets[i].asset);

      if (variableDebtToken != address(0)) {
        borrowAsset.amount = IERC20Extended(variableDebtToken).balanceOf(_pool);
        if (borrowAsset.amount != 0) {
          borrowAsset.amount = borrowAsset.amount.mul(_portion).div(10 ** 18);
          if (borrowAsset.amount == 0) continue; // sherlock issue: skip if the amount got rounded down to 0, which will cause revert
          borrowAsset.asset = supportedAssets[i].asset;
          break;
        }
      }
    }
  }

  function _getPoolSupportedAssets(
    address _pool
  ) internal view returns (IHasSupportedAsset.Asset[] memory supportedAssets, uint256 length) {
    supportedAssets = IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic()).getSupportedAssets();
    length = supportedAssets.length;
  }

  function _getReserveTokensAddresses(
    address _asset
  ) internal view returns (address aToken, address variableDebtToken) {
    (aToken, , variableDebtToken) = aaveProtocolDataProvider.getReserveTokensAddresses(_asset);
  }

  function _prepareFlashLoan(
    address _pool,
    uint256 _portion,
    AssetInAave memory _borrowAsset
  ) internal view returns (MultiTransaction[] memory transactions) {
    address[] memory borrowAssets = new address[](1);
    borrowAssets[0] = _borrowAsset.asset;

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = _borrowAsset.amount;

    uint256[] memory modes = new uint256[](1); // 0 mode - no debt

    transactions = new MultiTransaction[](1);

    transactions[0].to = aaveLendingPool;
    transactions[0].txData = abi.encodeWithSelector(
      bytes4(keccak256("flashLoan(address,address[],uint256[],uint256[],address,bytes,uint16)")),
      _pool, // receiverAddress
      borrowAssets,
      amounts,
      modes,
      _pool,
      abi.encode(_portion), // arbitrary bytes-encoded params that will be passed to executeOperation() method of the receiver contract
      196 // referralCode
    );
  }

  function _withdrawAndTransfer(
    address _pool,
    address _to,
    uint256 _portion
  ) internal view returns (MultiTransaction[] memory transactions) {
    (AssetInAave[] memory collateralAssets, uint256 collateralAssetsLength) = _calculateCollateralAssets(
      _pool,
      _portion
    );
    transactions = new MultiTransaction[](collateralAssetsLength * 2);

    uint256 txCount;
    for (uint256 i; i < collateralAssetsLength; ++i) {
      transactions[txCount].to = aaveLendingPool;
      transactions[txCount].txData = abi.encodeWithSelector(
        bytes4(keccak256("withdraw(address,uint256,address)")),
        collateralAssets[i].asset,
        collateralAssets[i].amount,
        _pool // onBehalfOf
      );
      txCount++;

      transactions[txCount].to = collateralAssets[i].asset;
      transactions[txCount].txData = abi.encodeWithSelector(
        bytes4(keccak256("transfer(address,uint256)")),
        _to, // recipient
        collateralAssets[i].amount
      );
      txCount++;
    }
  }

  function _repayDebtTransactions(
    address _pool,
    RepayData memory _repayData
  ) internal view returns (MultiTransaction[] memory transactions) {
    transactions = new MultiTransaction[](2);

    // Repay amount is multiplied by 2, because approving lending pool contract happens single time here,
    // but available allowance is required for transactions to repay debt (_repayDebtTransactions),
    // as well as downstream during repaying flashloan which requires allowance for _repayData.amount + _repayData.premium
    (bool result, uint256 newAllowance) = IERC20Extended(_repayData.asset).allowance(_pool, aaveLendingPool).tryAdd(
      _repayData.amount.mul(2).add(_repayData.premium)
    );

    transactions[0].to = _repayData.asset;
    transactions[0].txData = abi.encodeWithSelector(
      bytes4(keccak256("approve(address,uint256)")),
      aaveLendingPool,
      result ? newAllowance : type(uint256).max
    );

    transactions[1].to = aaveLendingPool;
    transactions[1].txData = abi.encodeWithSelector(
      bytes4(keccak256("repay(address,uint256,uint256,address)")),
      _repayData.asset,
      _repayData.amount,
      2, // Interest rate mode for variable borrowing
      _pool // onBehalfOf
    );
  }

  function _withdrawCollateralTransactions(
    address _pool,
    uint256 _portion,
    address _swapRouter,
    address _repayAsset
  ) internal view returns (MultiTransaction[] memory transactions) {
    (AssetInAave[] memory collateralAssets, uint256 collateralAssetsLength) = _calculateCollateralAssets(
      _pool,
      _portion
    );

    // We have 3 transactions for each collateral asset:
    // 1. Withdraw collateral asset from aave
    // 2. Approve collateral asset for swap router
    // 3. Swap collateral asset to repay asset
    uint256 length = collateralAssetsLength.mul(3);
    transactions = new MultiTransaction[](length);

    address[] memory path = new address[](2);
    path[1] = _repayAsset;

    uint256 txCount;
    for (uint256 i; i < collateralAssetsLength; ++i) {
      transactions[txCount].to = aaveLendingPool;
      transactions[txCount].txData = abi.encodeWithSelector(
        bytes4(keccak256("withdraw(address,uint256,address)")),
        collateralAssets[i].asset,
        collateralAssets[i].amount,
        _pool
      );
      txCount++;

      if (collateralAssets[i].asset != _repayAsset) {
        transactions[txCount].to = collateralAssets[i].asset;
        transactions[txCount].txData = abi.encodeWithSelector(
          bytes4(keccak256("approve(address,uint256)")),
          _swapRouter,
          collateralAssets[i].amount
        );
        txCount++;

        path[0] = collateralAssets[i].asset;
        transactions[txCount].to = _swapRouter;
        transactions[txCount].txData = abi.encodeWithSelector(
          bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)")),
          collateralAssets[i].amount,
          0,
          path,
          _pool,
          uint256(-1)
        );
        txCount++;
      }
    }

    // Reduce length the empty items
    uint256 reduceLength = length.sub(txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }
  }
}
