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
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ERC20Guard.sol";
import "./IAaveLendingPoolAssetGuard.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/aave/IAaveProtocolDataProvider.sol";
import "../../interfaces/aave/ILendingPoolAddressesProvider.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IUniswapV2Router.sol";

/// @title Aave lending pool asset guard
/// @dev Asset type = 3
contract AaveLendingPoolAssetGuard is TxDataUtils, ERC20Guard, IAaveLendingPoolAssetGuard {
  using SafeMathUpgradeable for uint256;

  // For Aave decimal calculation
  uint256 constant DECIMALS_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF;
  uint256 constant RESERVE_DECIMALS_START_BIT_POSITION = 48;

  IAaveProtocolDataProvider public aaveProtocolDataProvider;
  ILendingPoolAddressesProvider public aaveAddressProvider;
  ILendingPool public aaveLendingPool;

  constructor(address _aaveProtocolDataProvider) {
    aaveProtocolDataProvider = IAaveProtocolDataProvider(_aaveProtocolDataProvider);
    aaveAddressProvider = ILendingPoolAddressesProvider(aaveProtocolDataProvider.ADDRESSES_PROVIDER());
    aaveLendingPool = ILendingPool(aaveAddressProvider.getLendingPool());
  }

  /// @notice Returns the pool position of Aave lending pool
  /// @dev Returns the balance priced in ETH
  /// @param pool The pool logic address
  function getBalance(address pool, address) public view override returns (uint256 balance) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic());
    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();

    address asset;
    uint256 decimals;
    uint256 tokenPriceInUsd;
    uint256 collateralBalance;
    uint256 debtBalance;
    uint256 totalCollateralInUsd;
    uint256 totalDebtInUsd;
    address factory = IPoolLogic(pool).factory();

    uint256 length = supportedAssets.length;
    for (uint256 i = 0; i < length; i++) {
      asset = supportedAssets[i].asset;

      (collateralBalance, debtBalance, decimals) = _calculateAaveBalance(pool, asset);

      if (collateralBalance != 0 || debtBalance != 0) {
        tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(asset);
        totalCollateralInUsd = totalCollateralInUsd.add(tokenPriceInUsd.mul(collateralBalance).div(10**decimals));
        totalDebtInUsd = totalDebtInUsd.add(tokenPriceInUsd.mul(debtBalance).div(10**decimals));
      }
    }

    balance = totalCollateralInUsd.sub(totalDebtInUsd);
  }

  /// @notice Returns the decimal
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @dev Withdrawal processing is not applicable for this guard
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return withdrawContracts and
  /// @return txData are used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool, // pool
    address, // asset
    uint256 portion, // portion
    address to
  )
    external
    view
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      MultiTransactions memory transactions
    )
  {
    (address[] memory borrowAssets, uint256[] memory borrowAmounts, uint256[] memory interestRateModes) =
      _calculateBorrowAssets(pool, portion);

    if (borrowAssets.length > 0) {
      // set withdrawAsset as the last index of borrow assets
      address factory = IPoolLogic(pool).factory();
      withdrawAsset = IHasGuardInfo(factory).getAddress("weth");

      transactions = _prepareFlashLoan(pool, portion, borrowAssets, borrowAmounts, interestRateModes);
    } else {
      transactions = _withdrawAndTransfer(pool, to, portion);
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Prepare flashlan transaction data
  /// @param pool the PoolLogic address
  /// @param borrowAssets the borrowed assets list
  /// @param borrowAmounts the borrowed amount per each asset
  /// @param interestRateModes the interest rate mode per each asset
  /// @param portion the portion of assets to be withdrawn
  /// @return txData are used to execute the withdrawal transaction in PoolLogic
  function _prepareFlashLoan(
    address pool,
    uint256 portion,
    address[] memory borrowAssets,
    uint256[] memory borrowAmounts,
    uint256[] memory interestRateModes
  ) internal pure returns (MultiTransactions memory transactions) {
    transactions.contracts = new address[](1);
    transactions.txData = new bytes[](1);
    transactions.txCount = 1;

    transactions.contracts = address(aaveLendingPool);

    bytes memory params = abi.encode(interestRateModes, portion);
    uint256[] memory modes = new uint256[](borrowAssets.length);
    transactions.txData[0] = abi.encodeWithSelector(
      bytes4(keccak256("flashLoan(address,address[],uint256[],uint256[],address,bytes,uint16)")),
      pool, // receiverAddress
      borrowAssets,
      borrowAmounts,
      modes,
      pool, // onBehalfOf
      params,
      0 // referralCode
    );
  }

  /// @notice Prepare withdraw/transfer transacton data
  /// @param pool the PoolLogic address
  /// @param to the recipient address
  /// @param portion the portion of assets to be withdrawn
  /// @return withdrawAsset the asset to be withdrawn
  /// @return withdrawBalance the asset amount to be withdrawn
  /// @return withdrawContracts the contracts for transaction execution
  /// @return txData are used to execute the withdrawal transaction in PoolLogic
  function _withdrawAndTransfer(
    address pool,
    address to,
    uint256 portion
  ) internal view returns (MultiTransactions memory transactions) {
    (address[] memory collateralAssets, uint256[] memory amounts) = _calculateCollateralAssets(pool, portion);
    uint256 length = collateralAssets.length;
    transactions.contracts = new address[](length * 2);
    transactions.txData = new bytes[](length * 2);
    for (uint256 i = 0; i < length; i++) {
      transactions.contracts[transactions.txCount] = address(aaveLendingPool);
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("withdraw(address,uint256,address)")),
        collateralAssets[i], // receiverAddress
        amounts[i],
        pool // onBehalfOf
      );
      transactions.txCount++;

      transactions.contracts[transactions.txCount] = collateralAssets[i];
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("transfer(address,uint256)")),
        to, // recipient
        amounts[i]
      );
      transactions.txCount++;
    }
  }

  /// @notice Calculates AToken/DebtToken balances
  /// @param pool the PoolLogic address
  /// @param asset the asset address
  /// @return collateralBalance the AToken balance
  /// @return debtBalance the DebtToken balance
  /// @return decimals the asset decimals
  function _calculateAaveBalance(address pool, address asset)
    internal
    view
    returns (
      uint256 collateralBalance,
      uint256 debtBalance,
      uint256 decimals
    )
  {
    (address aToken, address stableDebtToken, address variableDebtToken) =
      aaveProtocolDataProvider.getReserveTokensAddresses(asset);
    if (aToken != address(0)) {
      collateralBalance = IERC20(aToken).balanceOf(pool);
      debtBalance = IERC20(stableDebtToken).balanceOf(pool).add(IERC20(variableDebtToken).balanceOf(pool));
    }

    ILendingPool.ReserveConfigurationMap memory configuration = aaveLendingPool.getConfiguration(asset);
    decimals = (configuration.data & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION;
  }

  /// @notice Calculates AToken balances
  /// @param pool the PoolLogic address
  /// @param portion the portion of assets to be withdrawn
  /// @return collateralAssets the collateral assets list
  /// @return amounts the asset balance per each collateral asset
  function _calculateCollateralAssets(address pool, uint256 portion)
    internal
    view
    returns (address[] memory collateralAssets, uint256[] memory amounts)
  {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic());
    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();

    uint256 length = supportedAssets.length;
    collateralAssets = new address[](length);
    amounts = new uint256[](length);

    address aToken;
    uint256 index;
    for (uint256 i = 0; i < length; i++) {
      (aToken, , ) = IAaveProtocolDataProvider(aaveProtocolDataProvider).getReserveTokensAddresses(
        supportedAssets[i].asset
      );

      if (aToken != address(0)) {
        amounts[index] = IERC20(aToken).balanceOf(pool);
        if (amounts[index] != 0) {
          collateralAssets[index] = supportedAssets[i].asset;
          amounts[index] = amounts[index].mul(portion).div(10**18);
          index++;
        }
      }
    }

    // Reduce length the empty items
    uint256 reduceLength = length.sub(index);
    assembly {
      mstore(collateralAssets, sub(mload(collateralAssets), reduceLength))
      mstore(amounts, sub(mload(amounts), reduceLength))
    }
  }

  /// @notice Calculates DebtToken balances
  /// @param pool the PoolLogic address
  /// @param portion the portion of assets to be withdrawn
  /// @return borrowAssets the borrow assets list
  /// @return amounts the asset balance per each borrow asset
  /// @return interestRateModes the interest rate modes per each borrow asset
  function _calculateBorrowAssets(address pool, uint256 portion)
    internal
    view
    returns (
      address[] memory borrowAssets,
      uint256[] memory amounts,
      uint256[] memory interestRateModes
    )
  {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic());
    IHasSupportedAsset.Asset[] memory supportedAssets = poolManagerLogicAssets.getSupportedAssets();
    uint256 length = supportedAssets.length;
    borrowAssets = new address[](length);
    amounts = new uint256[](length);
    interestRateModes = new uint256[](length);

    address stableDebtToken;
    address variableDebtToken;
    uint256 index;
    for (uint256 i = 0; i < length; i++) {
      // returns address(0) if it's not supported in aave
      (, stableDebtToken, variableDebtToken) = IAaveProtocolDataProvider(aaveProtocolDataProvider)
        .getReserveTokensAddresses(supportedAssets[i].asset);

      if (stableDebtToken != address(0)) {
        amounts[index] = IERC20(stableDebtToken).balanceOf(pool);
        if (amounts[index] != 0) {
          borrowAssets[index] = supportedAssets[i].asset;
          amounts[index] = amounts[index].mul(portion).div(10**18);
          interestRateModes[index] = 1;
          index++;
          continue;
        }
      }

      if (variableDebtToken != address(0)) {
        amounts[index] = IERC20(variableDebtToken).balanceOf(pool);
        if (amounts[index] != 0) {
          borrowAssets[index] = supportedAssets[i].asset;
          amounts[index] = amounts[index].mul(portion).div(10**18);
          interestRateModes[index] = 2;
          index++;
          continue;
        }
      }
    }

    // Reduce length the empty items
    uint256 reduceLength = length.sub(index);
    assembly {
      mstore(borrowAssets, sub(mload(borrowAssets), reduceLength))
      mstore(amounts, sub(mload(amounts), reduceLength))
      mstore(interestRateModes, sub(mload(interestRateModes), reduceLength))
    }
  }

  function flashloanProcessing(
    address pool,
    uint256 portion,
    address[] memory repayAssets,
    uint256[] memory repayAmounts,
    uint256[] memory premiums,
    uint256[] memory interestRateModes
  ) external view virtual override returns (MultiTransactions memory transactions) {
    address factory = IPoolLogic(pool).factory();
    address swapRouter = IHasGuardInfo(factory).getAddress("swapRouter");
    address weth = IHasGuardInfo(factory).getAddress("weth");

    MultiTransactions memory aaveRepayTransactions =
      _repayAaveTransactions(pool, repayAssets, repayAmounts, interestRateModes);
    MultiTransactions memory aaveWithdrawTransactions = _withdrawAaveTransactions(pool, portion, swapRouter, weth);
    MultiTransactions memory flashloanWithdrawTransactions =
      _repayFlashloanTransactions(pool, swapRouter, weth, repayAssets, repayAmounts, premiums);

    transactions.contracts = new address[](
      aaveRepayTransactions.txCount + aaveWithdrawTransactions.txCount + flashloanWithdrawTransactions.txCount
    );
    transactions.txData = new bytes[](
      aaveRepayTransactions.txCount + aaveWithdrawTransactions.txCount + flashloanWithdrawTransactions.txCount
    );

    uint256 i;
    for (i = 0; i < aaveRepayTransactions.txCount; i++) {
      transactions.contracts[transactions.txCount] = aaveRepayTransactions.contracts[i];
      transactions.txData[transactions.txCount] = aaveRepayTransactions.txData[i];
      transactions.txCount++;
    }
    for (i = 0; i < aaveWithdrawTransactions.txCount; i++) {
      transactions.contracts[transactions.txCount] = aaveWithdrawTransactions.contracts[i];
      transactions.txData[transactions.txCount] = aaveWithdrawTransactions.txData[i];
      transactions.txCount++;
    }
    for (i = 0; i < flashloanWithdrawTransactions.txCount; i++) {
      transactions.contracts[transactions.txCount] = flashloanWithdrawTransactions.contracts[i];
      transactions.txData[transactions.txCount] = flashloanWithdrawTransactions.txData[i];
      transactions.txCount++;
    }
  }

  function _repayAaveTransactions(
    address pool,
    address[] memory repayAssets,
    uint256[] memory repayAmounts,
    uint256[] memory interestRateModes
  ) internal view returns (MultiTransactions memory transactions) {
    transactions.contracts = new address[](repayAssets.length * 2);
    transactions.txData = new bytes[](repayAssets.length * 2);

    for (uint256 i = 0; i < repayAssets.length; i++) {
      transactions.contracts[transactions.txCount] = repayAssets[i];
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("approve(address,uint256)")),
        aaveLendingPool,
        repayAmounts[i]
      );
      transactions.txCount++;

      transactions.contracts[transactions.txCount] = address(aaveLendingPool);
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("repay(address,uint256,uint256,address)")),
        repayAssets[i],
        repayAmounts[i],
        interestRateModes[i],
        pool // onBehalfOf
      );
      transactions.txCount++;
    }
  }

  function _withdrawAaveTransactions(
    address pool,
    uint256 portion,
    address swapRouter,
    address weth
  ) internal view returns (MultiTransactions memory transactions) {
    (address[] memory collateralAssets, uint256[] memory amounts) = _calculateCollateralAssets(pool, portion);

    transactions.contracts = new address[](collateralAssets.length * 4);
    transactions.txData = new bytes[](collateralAssets.length * 4);

    address[] memory path = new address[](2);
    path[1] = weth;

    for (uint256 i = 0; i < collateralAssets.length; i++) {
      transactions.contracts[transactions.txCount] = address(aaveLendingPool);
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("withdraw(address,uint256,address)")),
        collateralAssets[i],
        amounts[i],
        pool
      );
      transactions.txCount++;

      transactions.contracts[transactions.txCount] = collateralAssets[i];
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("approve(address,uint256)")),
        swapRouter,
        amounts[i]
      );
      transactions.txCount++;

      path[0] = collateralAssets[i];
      transactions.contracts[transactions.txCount] = swapRouter;
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)")),
        amounts[i],
        0,
        path,
        pool,
        uint256(-1)
      );
      transactions.txCount++;

      transactions.contracts[transactions.txCount] = collateralAssets[i];
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("approve(address,uint256)")),
        swapRouter,
        0
      );
      transactions.txCount++;
    }
  }

  function _repayFlashloanTransactions(
    address pool,
    address swapRouter,
    address weth,
    address[] memory repayAssets,
    uint256[] memory repayAmounts,
    uint256[] memory premiums
  ) internal view returns (MultiTransactions memory transactions) {
    transactions.contracts = new address[](repayAssets.length * 4);
    transactions.txData = new bytes[](repayAssets.length * 4);

    address[] memory path = new address[](2);
    path[0] = weth;

    for (uint256 i = 0; i < repayAssets.length; i++) {
      uint256 amountOwing = repayAmounts[i].add(premiums[i]);

      transactions.contracts[transactions.txCount] = repayAssets[i];
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("approve(address,uint256)")),
        swapRouter,
        amountOwing
      );
      transactions.txCount++;

      path[1] = repayAssets[i];
      transactions.contracts[transactions.txCount] = swapRouter;
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("swapTokensForExactTokens(uint256,uint256,address[],address,uint256)")),
        amountOwing,
        uint256(-1),
        path,
        pool,
        uint256(-1)
      );
      transactions.txCount++;

      transactions.contracts[transactions.txCount] = repayAssets[i];
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("approve(address,uint256)")),
        address(aaveLendingPool),
        amountOwing
      );
      transactions.txCount++;

      transactions.contracts[transactions.txCount] = repayAssets[i];
      transactions.txData[transactions.txCount] = abi.encodeWithSelector(
        bytes4(keccak256("approve(address,uint256)")),
        swapRouter,
        0
      );
      transactions.txCount++;
    }
  }
}
