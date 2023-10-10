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

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";

import "../../contractGuards/synthetixV3/SynthetixV3ContractGuard.sol";
import "../../../interfaces/guards/IMutableBalanceAssetGuard.sol";
import "../../../interfaces/synthetixV3/ICollateralModule.sol";
import "../../../interfaces/synthetixV3/ILiquidationModule.sol";
import "../../../interfaces/synthetixV3/IVaultModule.sol";
import "../../../interfaces/IPoolLogic.sol";
import "../../../interfaces/IHasAssetInfo.sol";
import "../../../interfaces/IHasGuardInfo.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../ClosedAssetGuard.sol";

contract SynthetixV3AssetGuard is ClosedAssetGuard, IMutableBalanceAssetGuard {
  using SafeMath for uint256;
  using SafeCast for int256;

  struct DebtRecord {
    int256 debt;
    uint256 timestamp;
  }

  bool public override isStateMutatingGuard = true;

  mapping(address => DebtRecord) public latestDebtRecords;

  /// @notice Returns the balance of Synthetix V3 position, accurate balance is not guaranteed
  /// @dev Returns the balance to be priced in USD
  /// @param _pool Pool address
  /// @param _asset Asset address (Basically Synthetix V3 core address)
  /// @return balance Synthetix V3 balance of the pool
  function getBalance(address _pool, address _asset) public view override returns (uint256) {
    (uint128 accountId, address collateralType, , address debtAsset) = _getPoolPositionDetails(_pool, _asset);

    // Using latest stored debt record to calculate balance
    return _calculateBalance(_pool, _asset, accountId, collateralType, debtAsset, latestDebtRecords[_pool].debt);
  }

  /// @notice Returns the balance of Synthetix V3 position in a mutable way
  /// @dev This is required due to getPositionDebt is a non-view function
  /// @dev Returns the balance to be priced in USD
  /// @param _pool Pool address
  /// @param _asset Asset address (Basically Synthetix V3 core address)
  /// @return balance Synthetix V3 balance of the pool
  function getBalanceMutable(address _pool, address _asset) public override returns (uint256) {
    (uint128 accountId, address collateralType, uint128 poolId, address debtAsset) = _getPoolPositionDetails(
      _pool,
      _asset
    );

    if (ILiquidationModule(_asset).isPositionLiquidatable(accountId, poolId, collateralType)) {
      ILiquidationModule(_asset).liquidate(accountId, poolId, collateralType, accountId);
    }

    // Getting position debt from Synthetix V3 system
    int256 debt = IVaultModule(_asset).getPositionDebt(accountId, poolId, collateralType);
    // Storing latest debt record to be used in classic getBalance
    latestDebtRecords[_pool] = DebtRecord({debt: debt, timestamp: block.timestamp});

    return _calculateBalance(_pool, _asset, accountId, collateralType, debtAsset, debt);
  }

  /// @notice Returns the decimals of Synthetix V3 position
  /// @return decimals Decimals of the asset
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing from Synthetix V3 position
  /// @dev Current version is the simplest workaround of lockup issue
  /// @dev Assumes that the pool always holds some amount of undelegated collateral that can be withdrawn
  /// @dev That implies limitations on the size of the withdrawal
  /// @param _pool Pool address
  /// @param _asset Asset address (Basically Synthetix V3 core address)
  /// @param _withdrawPortion Portion of the asset to withdraw
  /// @param _to Investor address to withdraw to
  /// @return withdrawAsset Asset address to withdraw (Basically zero address)
  /// @return withdrawBalance Amount to withdraw (Basically zero amount)
  /// @return transactions Transactions to be executed (These is where actual token transfer happens)
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address _to
  )
    external
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      MultiTransaction[] memory transactions
    )
  {
    // Collecting data to perform withdrawal
    (uint128 accountId, address collateralType, , ) = _getPoolPositionDetails(_pool, _asset);
    uint256 balance = getBalanceMutable(_pool, _asset);

    // My thinking this check is needed for the cases when pool enabled Synthetix V3 position, but never interacted with it or has nothing in it
    if (accountId == 0 || balance == 0) {
      return (address(0), 0, transactions);
    }

    // Getting total amount of collateral token available for withdrawal
    uint256 availableCollateral = ICollateralModule(_asset).getAccountAvailableCollateral(accountId, collateralType);
    // Calculating total value of collateral token available for withdrawal using factory oracles for that collateral
    uint256 availableWithdrawValue = _assetValue(_pool, collateralType, availableCollateral);
    // Getting balance of investor's portion in Synthetix V3 position and then calculating its value
    uint256 portionBalance = balance.mul(_withdrawPortion).div(10**18);
    uint256 withdrawValue = _assetValue(_pool, _asset, portionBalance);

    // Guard to prevent division by zero and to check if there is enough available collateral to perform withdrawal
    require(availableWithdrawValue >= withdrawValue && availableWithdrawValue > 0, "not enough available balance");
    // Calculating how much collateral token should be withdrawn to get investor's portion
    uint256 collateralAmountToWithdraw = availableCollateral.mul(withdrawValue).div(availableWithdrawValue);

    transactions = new MultiTransaction[](2);

    // Withdrawing collateral token from Synthetix V3 position to the pool
    transactions[0].to = _asset;
    transactions[0].txData = abi.encodeWithSelector(
      ICollateralModule.withdraw.selector,
      accountId,
      collateralType,
      collateralAmountToWithdraw
    );

    // Transferring collateral token from the pool to the investor
    transactions[1].to = collateralType;
    transactions[1].txData = abi.encodeWithSelector(IERC20.transfer.selector, _to, collateralAmountToWithdraw);

    return (address(0), 0, transactions);
  }

  /// @dev Helper function to calculate value of the asset using factory oracles
  /// @dev Returns zero if the asset is not supported by the factory
  /// @param _pool Pool address (to get factory address)
  /// @param _asset Asset address
  /// @param _amount Amount of the asset
  /// @return assetValue Value of the asset
  function _assetValue(
    address _pool,
    address _asset,
    uint256 _amount
  ) internal view returns (uint256 assetValue) {
    if (IHasAssetInfo(IPoolLogic(_pool).factory()).isValidAsset(_asset)) {
      address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();
      assetValue = IPoolManagerLogic(poolManagerLogic).assetValue(_asset, _amount);
    } else {
      assetValue = 0;
    }
  }

  /// @dev Helper function to get Synthetix V3 position details
  /// @dev Uses Synthetix V3 contract guard to get the data not to store anything in asset guard
  /// @param _pool Pool address
  /// @param _synthetixV3Core Synthetix V3 core address
  /// @return accountId Synthetix V3 NFT token ID associated with the pool
  /// @return collateralType Collateral token address
  /// @return poolId Liquidity Pool ID from Synthetix V3 system
  /// @return debtAsset Debt token address in Synthetix V3 system
  function _getPoolPositionDetails(address _pool, address _synthetixV3Core)
    internal
    view
    returns (
      uint128 accountId,
      address collateralType,
      uint128 poolId,
      address debtAsset
    )
  {
    SynthetixV3ContractGuard contractGuard = SynthetixV3ContractGuard(
      IHasGuardInfo(IPoolLogic(_pool).factory()).getContractGuard(_synthetixV3Core)
    );
    accountId = contractGuard.getAccountNftTokenId(_pool, _synthetixV3Core);
    collateralType = contractGuard.collateral();
    poolId = contractGuard.allowedLiquidityPoolId();
    debtAsset = contractGuard.debtAsset();
  }

  /// @dev Helper function to calculate balance of the Synthetix V3 position
  /// @param _pool Pool address
  /// @param _asset Asset address (Basically Synthetix V3 core address)
  /// @param _accountId Synthetix V3 NFT token ID associated with the pool
  /// @param _collateralType Collateral token address
  /// @param _debtAsset Debt token address
  /// @param _debt Amount of position debt
  /// @return balance Balance of the Synthetix V3 position
  function _calculateBalance(
    address _pool,
    address _asset,
    uint128 _accountId,
    address _collateralType,
    address _debtAsset,
    int256 _debt
  ) internal view returns (uint256 balance) {
    // If there is no Synthetix V3 NFT stored in our system associated with the pool, then balance is zero
    if (_accountId == 0) {
      return 0;
    }

    // Getting value of collateral that can be withdrawn or delegated to pools (it's not affected by debt)
    balance = _assetValue(
      _pool,
      _collateralType,
      ICollateralModule(_asset).getAccountAvailableCollateral(_accountId, _collateralType)
    );
    // Adding value of collateral that is snxUSD tokens minted
    balance = balance.add(
      _assetValue(_pool, _debtAsset, ICollateralModule(_asset).getAccountAvailableCollateral(_accountId, _debtAsset))
    );
    // Getting amount of collateral that is delegated to pools (this collateral is affected by debt)
    (, uint256 totalAssigned, ) = ICollateralModule(_asset).getAccountCollateral(_accountId, _collateralType);
    uint256 assignedCollateralValue = _assetValue(_pool, _collateralType, totalAssigned);

    if (_debt < 0) {
      // Negative debt means credit. With this in mind, we calculate debt value in USD and add it to assigned collateral value
      balance = balance.add(assignedCollateralValue.add(_assetValue(_pool, _debtAsset, -_debt.toUint256())));
    } else {
      // When debt is zero or positive, we calculate position's USD balance by subtracting value of the debt from value of the collateral
      // Debt's value which is bigger than collateral value would mean that position can be liquidated
      // trySub will return 0 result in that case
      (, uint256 result) = assignedCollateralValue.trySub((_assetValue(_pool, _debtAsset, _debt.toUint256())));
      balance = balance.add(result);
    }
  }
}
