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

import {IAaveV3Pool} from "../../interfaces/aave/v3/IAaveV3Pool.sol";
import {ISwapper} from "../../interfaces/flatMoney/swapper/ISwapper.sol";
import {IAaveLendingPoolAssetGuard} from "../../interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import {IComplexAssetGuard} from "../../interfaces/guards/IComplexAssetGuard.sol";
import {ISwapDataConsumingGuard} from "../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {IUniswapV2RouterSwapOnly} from "../../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";
import {IERC20Extended} from "../../interfaces/IERC20Extended.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {ClosedAssetGuard} from "./ClosedAssetGuard.sol";
import {PendlePTHandlerLib} from "../../utils/pendle/PendlePTHandlerLib.sol";

/// @title Aave lending pool asset guard
/// @dev Asset type 3 is for v2
///      Asset type 8 is for v3
contract AaveLendingPoolAssetGuard is ClosedAssetGuard, IAaveLendingPoolAssetGuard, ISwapDataConsumingGuard {
  using SafeMath for uint256;
  using PendlePTHandlerLib for AssetStructure;

  struct RepayData {
    address asset;
    uint256 amount;
    uint256 premium;
  }

  struct WithdrawCollateralExecution {
    uint256 srcTokensLength;
    uint256 txCount;
    uint256 srcAssetsCount;
    uint256 possibleTransactionsLength;
  }

  address private constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

  address public immutable override aaveLendingPool;

  address public immutable swapper;

  address public immutable onchainSwapRouter;

  address public immutable pendleYieldContractFactory;

  address public immutable pendleRouterStatic;

  /// @dev Used to calculate tolerance for mismatch between the amounts passed in swap data and the amounts calculated at the moment of execution
  uint256 private immutable mismatchDeltaNumerator;

  /// @dev Normally set to 10_000 (100%)
  uint256 private immutable mismatchDeltaDenominator;

  /// @dev Normally set to 10_000 (100%)
  uint256 private immutable slippageToleranceDenominator;

  /// @param _aaveLendingPool Aave lending pool address
  /// @param _swapper Swapper contract address
  /// @param _onchainSwapRouter DhedgeSuperSwapper contract address
  /// @param _mismatchDelta Numerator for mismatch delta
  /// @param _mismatchDeltaDenominator Denominator for mismatch delta
  /// @param _slippageToleranceDenominator Denominator for slippage tolerance
  constructor(
    address _aaveLendingPool,
    address _swapper,
    address _onchainSwapRouter,
    address _pendleYieldContractFactory,
    address _pendleRouterStatic,
    uint256 _mismatchDelta,
    uint256 _mismatchDeltaDenominator,
    uint256 _slippageToleranceDenominator
  ) {
    require(
      _aaveLendingPool != address(0) && _swapper != address(0) && _onchainSwapRouter != address(0),
      "invalid address"
    );
    require(_mismatchDeltaDenominator > 0 && _mismatchDelta <= _mismatchDeltaDenominator, "numerator must be less");

    aaveLendingPool = _aaveLendingPool;
    swapper = _swapper;
    onchainSwapRouter = _onchainSwapRouter;
    pendleYieldContractFactory = _pendleYieldContractFactory;
    pendleRouterStatic = _pendleRouterStatic;

    mismatchDeltaNumerator = _mismatchDelta;
    mismatchDeltaDenominator = _mismatchDeltaDenominator;
    slippageToleranceDenominator = _slippageToleranceDenominator;
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

  /// @inheritdoc IComplexAssetGuard
  function withdrawProcessing(
    address _pool,
    address,
    uint256 _portion,
    address _to,
    bytes memory _swapData
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    return _withdrawProcessing(_pool, _portion, _to, _validateSwapData(_pool, _portion, _swapData), false);
  }

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
    ISwapDataConsumingGuard.ComplexAssetSwapData memory swapData; // Empty struct
    return _withdrawProcessing(_pool, _portion, _to, swapData, true);
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
  ) external view override returns (MultiTransaction[] memory transactions) {
    (uint256 portion, ISwapDataConsumingGuard.ComplexAssetSwapData memory swapData, bool _swapType) = abi.decode(
      _params,
      (uint256, ISwapDataConsumingGuard.ComplexAssetSwapData, bool)
    );
    RepayData memory repayData = RepayData({asset: _repayAsset, amount: _repayAmount, premium: _premium});

    // At this stage we have the flashloan
    // Repay the debt with the flashloan
    // This will unlock our portion of the collateral
    MultiTransaction[] memory repayDebtTransactions = _repayDebtTransactions(_pool, repayData);

    // Withdraw collateral from aave and swap everything to repay asset, type of swap depends on `_swapType`. 0 - offchain, 1 - onchain
    MultiTransaction[] memory withdrawCollateralTransactions = _swapType
      ? _withdrawCollateralTransactions(_pool, portion, repayData.asset) // onchain swap
      : _withdrawCollateralTransactions(_pool, portion, swapData); // offchain swap

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

  /// @inheritdoc ISwapDataConsumingGuard
  function calculateSwapDataParams(
    address _pool,
    uint256 _poolTokenAmount,
    uint256 _slippageTolerance
  ) public override returns (SwapDataParams memory swapDataParams) {
    // This is required to update totalSupply of pool token and have portion calculated correctly
    IPoolLogic(_pool).mintManagerFee();

    // If the pool has exit fee set, pool token amount processed for withdrawal will be reduced by the exit fee
    (, , , uint256 exitFeeNumerator, uint256 denominator) = IPoolManagerLogic(IPoolLogic(_pool).poolManagerLogic())
      .getFee();

    if (exitFeeNumerator > 0) {
      _poolTokenAmount = _poolTokenAmount.sub(_poolTokenAmount.mul(exitFeeNumerator).div(denominator));
    }

    // Calculate what is the current portion of pool tokens intended for withdrawal
    uint256 portion = _poolTokenAmount.mul(1e18).div(IERC20Extended(_pool).totalSupply());

    swapDataParams = _calculateSwapDataParams(_pool, portion, _slippageTolerance);

    // Lower quote amounts intentionally by 0.01% for cases when management fee is set to avoid 'amount too high' revert
    for (uint256 i; i < swapDataParams.srcData.length; ++i) {
      swapDataParams.srcData[i].amount = swapDataParams.srcData[i].amount.mul(mismatchDeltaDenominator.sub(1)).div(
        mismatchDeltaDenominator
      );
    }
  }

  function _calculateSwapDataParams(
    address _pool,
    uint256 _portion,
    uint256 _slippageTolerance
  ) internal view returns (SwapDataParams memory swapDataParams) {
    require(_slippageTolerance <= slippageToleranceDenominator, "invalid slippage tolerance");

    // Based on the portion we calculate the borrow asset and the collateral assets
    AssetStructure memory borrowAsset = _calculateBorrowAsset(_pool, _portion);
    // If vault has no debt positions in aave (no borrow asset), then there is no need for offchain swap data
    if (borrowAsset.asset == address(0)) {
      return swapDataParams;
    }

    uint256 counter;
    {
      (AssetStructure[] memory collateralAssets, uint256 collateralAssetsLength) = _calculateCollateralAssets(
        _pool,
        _portion
      );
      // It is possible that borrow asset is the same as one of the collateral assets, that's the reason why
      // we do not assign `collateralAssets` as `swapDataParams.srcData`, we need to filter out the borrow asset first.
      // If collateral asset is the same as borrow asset, we don't need to swap it
      AssetStructure[] memory filteredSrcData = new AssetStructure[](collateralAssetsLength);
      for (uint256 i; i < collateralAssetsLength; ++i) {
        if (collateralAssets[i].asset != borrowAsset.asset) {
          filteredSrcData[counter] = collateralAssets[i];
          counter++;
        }
      }
      uint256 reduceLength = collateralAssetsLength.sub(counter);
      assembly {
        mstore(filteredSrcData, sub(mload(filteredSrcData), reduceLength))
      }

      // Assign the filtered collateral assets to swapDataParams.srcData
      swapDataParams.srcData = filteredSrcData;
    }

    // Calculate the $ value of all collateral assets to be swapped. This can be used to calculate the minDstAmount
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(IPoolLogic(_pool).poolManagerLogic());
    uint256 assetsToSwapFromValueD18;
    for (uint256 i; i < counter; ++i) {
      assetsToSwapFromValueD18 = assetsToSwapFromValueD18.add(
        poolManagerLogic.assetValue(swapDataParams.srcData[i].asset, swapDataParams.srcData[i].amount)
      );
      // Mutates AssetStructure in place only during this last loop, so that minDstAmount downstream is calculated based on PTs value,
      // and not the value of underlying after conversion
      if (swapDataParams.srcData[i].detectPendlePT(pendleYieldContractFactory)) {
        swapDataParams.srcData[i].convertPendlePTToUnderlying(_pool, pendleRouterStatic);
      }
    }

    // Calculate the minDstAmount based on the borrow asset price and the $ value of all collateral assets to be swapped
    uint256 dstAssetPriceD18 = IHasAssetInfo(IPoolLogic(_pool).factory()).getAssetPrice(borrowAsset.asset);
    uint256 dstAssetDecimals = 10 ** IERC20Extended(borrowAsset.asset).decimals();
    uint256 minDstAmount = assetsToSwapFromValueD18
      .mul(dstAssetDecimals)
      .div(dstAssetPriceD18)
      .mul(slippageToleranceDenominator.sub(_slippageTolerance))
      .div(slippageToleranceDenominator); // slippage tolerance correction happens here

    swapDataParams.dstData.asset = borrowAsset.asset;
    swapDataParams.dstData.amount = minDstAmount;
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

      (collateralBalance, debtBalance) = _calculateAaveBalance(_pool, asset);

      if (collateralBalance != 0 || debtBalance != 0) {
        tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(asset);
        decimals = IERC20Extended(asset).decimals();
        totalCollateralInUsd = totalCollateralInUsd.add(tokenPriceInUsd.mul(collateralBalance).div(10 ** decimals));
        totalDebtInUsd = totalDebtInUsd.add(tokenPriceInUsd.mul(debtBalance).div(10 ** decimals));
      }
    }
  }

  function _withdrawProcessing(
    address _pool,
    uint256 _portion,
    address _to,
    ISwapDataConsumingGuard.ComplexAssetSwapData memory _swapData,
    bool _swapType
  ) internal view returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions) {
    AssetStructure memory borrowAsset = _calculateBorrowAsset(_pool, _portion);

    if (borrowAsset.asset == address(0)) {
      transactions = _withdrawAndTransfer(_pool, _to, _portion);
      // There is no asset to withdraw as the above executes the withdraw to the withdrawer(_to)
      return (address(0), 0, transactions);
    }

    // This adds a transaction that will initiate the flashloan flow from aave,
    // Aave will callback the higher level PoolLogic.executeOperation
    transactions = _prepareFlashLoan(_pool, _portion, borrowAsset, _swapData, _swapType);
    // Changing the withdraw asset to borrow asset as this is the asset used for the remaining after flashloan repay
    withdrawAsset = borrowAsset.asset;
  }

  function _calculateAaveBalance(
    address _pool,
    address _asset
  ) internal view returns (uint256 collateralBalance, uint256 debtBalance) {
    address aToken = IAaveV3Pool(aaveLendingPool).getReserveAToken(_asset);
    address variableDebtToken = IAaveV3Pool(aaveLendingPool).getReserveVariableDebtToken(_asset);

    if (aToken != address(0)) {
      collateralBalance = IERC20Extended(aToken).balanceOf(_pool);
    }

    if (variableDebtToken != address(0)) {
      debtBalance = IERC20Extended(variableDebtToken).balanceOf(_pool);
    }
  }

  function _calculateCollateralAssets(
    address _pool,
    uint256 _portion
  ) internal view returns (AssetStructure[] memory collateralAssets, uint256 length) {
    (IHasSupportedAsset.Asset[] memory supportedAssets, uint256 supportedAssetsLength) = _getPoolSupportedAssets(_pool);

    collateralAssets = new AssetStructure[](supportedAssetsLength);

    address aToken;
    for (uint256 i; i < supportedAssetsLength; ++i) {
      aToken = IAaveV3Pool(aaveLendingPool).getReserveAToken(supportedAssets[i].asset);

      if (aToken != address(0)) {
        collateralAssets[length].amount = IERC20Extended(aToken).balanceOf(_pool);
        if (collateralAssets[length].amount != 0) {
          collateralAssets[length].amount = collateralAssets[length].amount.mul(_portion).div(1e18);
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
  ) internal view returns (AssetStructure memory borrowAsset) {
    (IHasSupportedAsset.Asset[] memory supportedAssets, uint256 length) = _getPoolSupportedAssets(_pool);

    address variableDebtToken;
    for (uint256 i; i < length; ++i) {
      // returns address(0) if it's not supported in aave
      variableDebtToken = IAaveV3Pool(aaveLendingPool).getReserveVariableDebtToken(supportedAssets[i].asset);

      if (variableDebtToken != address(0)) {
        borrowAsset.amount = IERC20Extended(variableDebtToken).balanceOf(_pool);
        if (borrowAsset.amount != 0) {
          // used to round the amount up instead of down. allows to repay rounded up debt amount downstream
          uint256 roundingUpFactor = uint256(1e18).sub(1);
          borrowAsset.amount = borrowAsset.amount.mul(_portion).add(roundingUpFactor).div(1e18);
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

  function _validateSwapData(
    address _pool,
    uint256 _portion,
    bytes memory _swapData
  ) internal view returns (ISwapDataConsumingGuard.ComplexAssetSwapData memory swapData) {
    swapData = abi.decode(_swapData, (ISwapDataConsumingGuard.ComplexAssetSwapData));

    SwapDataParams memory currentStateParams = _calculateSwapDataParams(_pool, _portion, swapData.slippageTolerance);
    ISwapper.SrcTokenSwapDetails[] memory srcData = abi.decode(swapData.srcData, (ISwapper.SrcTokenSwapDetails[]));

    uint256 srcDataLength = currentStateParams.srcData.length;
    require(srcDataLength == srcData.length, "swap data length mismatch");

    for (uint256 i; i < srcDataLength; i++) {
      _validateSrcToken(srcData[i], currentStateParams.srcData[i]);
    }

    _validateDstToken(swapData.destData, currentStateParams.dstData);
  }

  function _validateSrcToken(
    ISwapper.SrcTokenSwapDetails memory _swapSrcData,
    AssetStructure memory _currentSrcData
  ) internal view {
    require(address(_swapSrcData.token) == _currentSrcData.asset, "src asset mismatch");

    // If the amount to swap from in swap data is higher than the amount that is going to be withdrawn from aave, there will be not enough tokens to swap from
    require(_swapSrcData.amount <= _currentSrcData.amount, "amount too high");

    // Amount from swap data can't be less than current amount minus the mismatch delta
    require(
      _currentSrcData.amount.sub(_swapSrcData.amount) <=
        _currentSrcData.amount.mul(mismatchDeltaNumerator).div(mismatchDeltaDenominator),
      "src amount mismatch"
    );
  }

  function _validateDstToken(
    ISwapper.DestData memory _swapDestData,
    AssetStructure memory _currentDestData
  ) internal view {
    require(address(_swapDestData.destToken) == _currentDestData.asset, "dst asset mismatch");

    uint256 delta = _currentDestData.amount.mul(mismatchDeltaNumerator).div(mismatchDeltaDenominator);

    // Accept minDestAmount deviation by the delta to both sides
    require(
      _swapDestData.minDestAmount <= _currentDestData.amount.add(delta) &&
        _swapDestData.minDestAmount >= _currentDestData.amount.sub(delta),
      "dst amount mismatch"
    );
  }

  function _prepareFlashLoan(
    address _pool,
    uint256 _portion,
    AssetStructure memory _borrowAsset,
    ISwapDataConsumingGuard.ComplexAssetSwapData memory _swapData,
    bool _swapType // 0 - offchain, 1 - onchain
  ) internal view returns (MultiTransaction[] memory transactions) {
    address[] memory borrowAssets = new address[](1);
    borrowAssets[0] = _borrowAsset.asset;

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = _borrowAsset.amount;

    uint256[] memory modes = new uint256[](1); // 0 mode - no debt

    transactions = new MultiTransaction[](1);

    transactions[0].to = aaveLendingPool;
    transactions[0].txData = abi.encodeWithSelector(
      IAaveV3Pool.flashLoan.selector,
      _pool, // receiverAddress
      borrowAssets,
      amounts,
      modes,
      _pool,
      abi.encode(_portion, _swapData, _swapType), // arbitrary bytes-encoded params that will be passed to executeOperation() method of the receiver contract
      196 // referralCode
    );
  }

  function _withdrawAndTransfer(
    address _pool,
    address _to,
    uint256 _portion
  ) internal view returns (MultiTransaction[] memory transactions) {
    (AssetStructure[] memory collateralAssets, uint256 collateralAssetsLength) = _calculateCollateralAssets(
      _pool,
      _portion
    );
    transactions = new MultiTransaction[](collateralAssetsLength * 2);

    uint256 txCount;
    for (uint256 i; i < collateralAssetsLength; ++i) {
      transactions[txCount].to = aaveLendingPool;
      transactions[txCount].txData = abi.encodeWithSelector(
        IAaveV3Pool.withdraw.selector,
        collateralAssets[i].asset,
        collateralAssets[i].amount,
        _pool // onBehalfOf
      );
      txCount++;

      transactions[txCount].to = collateralAssets[i].asset;
      transactions[txCount].txData = abi.encodeWithSelector(
        IERC20Extended.transfer.selector,
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
    // USDT on Mainnet does not allow approving an amount M > 0 when an existing amount N > 0 is already approved.
    // To change the approve amount first have to reduce the addresses allowance to zero.
    if (_repayData.asset == USDT_MAINNET) {
      transactions = new MultiTransaction[](3);

      transactions[0].to = _repayData.asset;
      transactions[0].txData = abi.encodeWithSelector(IERC20Extended.approve.selector, aaveLendingPool, 0);
    } else {
      transactions = new MultiTransaction[](2);
    }

    uint256 txLength = transactions.length;

    // Repay amount is multiplied by 2, because approving lending pool contract happens single time here,
    // but available allowance is required for transactions to repay debt (_repayDebtTransactions),
    // as well as downstream during repaying flashloan which requires allowance for _repayData.amount + _repayData.premium
    (bool result, uint256 newAllowance) = IERC20Extended(_repayData.asset).allowance(_pool, aaveLendingPool).tryAdd(
      _repayData.amount.mul(2).add(_repayData.premium)
    );

    transactions[txLength - 2].to = _repayData.asset;
    transactions[txLength - 2].txData = abi.encodeWithSelector(
      IERC20Extended.approve.selector,
      aaveLendingPool,
      result ? newAllowance : type(uint256).max
    );

    transactions[txLength - 1].to = aaveLendingPool;
    transactions[txLength - 1].txData = abi.encodeWithSelector(
      IAaveV3Pool.repay.selector,
      _repayData.asset,
      _repayData.amount,
      2, // Interest rate mode for variable borrowing
      _pool // onBehalfOf
    );
  }

  /// @dev For swap processing with the help of offchain swap data
  function _withdrawCollateralTransactions(
    address _pool,
    uint256 _portion,
    ISwapDataConsumingGuard.ComplexAssetSwapData memory _swapData
  ) internal view returns (MultiTransaction[] memory transactions) {
    // Get the collateral assets corresponding to the portion to withdraw them from aave
    (AssetStructure[] memory collateralAssets, uint256 collateralAssetsLength) = _calculateCollateralAssets(
      _pool,
      _portion
    );

    // Get the swap props for the swapper contract
    ISwapper.InOutData memory swapProps;
    ISwapper.SrcData[] memory srcData = new ISwapper.SrcData[](1);
    srcData[0].srcTokenSwapDetails = abi.decode(_swapData.srcData, (ISwapper.SrcTokenSwapDetails[]));
    srcData[0].transferMethodData.method = ISwapper.TransferMethod.ALLOWANCE;
    swapProps.srcData = srcData;
    swapProps.destData = _swapData.destData;

    WithdrawCollateralExecution memory executionData;
    executionData.srcTokensLength = swapProps.srcData[0].srcTokenSwapDetails.length;

    // Going to have 3 types of transactions:
    // 1. Withdraw collateral asset from aave (If all collateral assets are pendle PTs, there might be triple more transactions per collateral asset)
    // 2. Approve collateral asset to swap from for swapper contract
    // 3. Swap collateral assets to repay asset
    executionData.possibleTransactionsLength = collateralAssetsLength.mul(3).add(executionData.srcTokensLength).add(1);
    transactions = new MultiTransaction[](executionData.possibleTransactionsLength);

    for (uint256 i; i < collateralAssetsLength; ++i) {
      bool isPT = collateralAssets[i].detectPendlePT(pendleYieldContractFactory);

      if (isPT) {
        executionData.srcAssetsCount++;
      }
      // Here it is decided if the amount to withdraw should be taken from the swap data (validated upstream) or at the moment of execution.
      // Always chooses the amount from the swap data to withdraw exact amount which will be then swapped downstream.
      // Only if one of the collateral assets is the same as the borrow asset, amount at the moment of execution is used. (such asset won't be present in swap data)
      else if (
        collateralAssets[i].asset == address(srcData[0].srcTokenSwapDetails[executionData.srcAssetsCount].token)
      ) {
        collateralAssets[i].amount = srcData[0].srcTokenSwapDetails[executionData.srcAssetsCount].amount;
        executionData.srcAssetsCount++;
      }

      transactions[executionData.txCount].to = aaveLendingPool;
      transactions[executionData.txCount].txData = abi.encodeWithSelector(
        IAaveV3Pool.withdraw.selector,
        collateralAssets[i].asset,
        collateralAssets[i].amount,
        _pool
      );
      executionData.txCount++;

      if (isPT) {
        executionData.txCount = collateralAssets[i].processTransactions(transactions, executionData.txCount, _pool); // Mutates transactions in place
      }
    }

    for (uint256 i; i < executionData.srcTokensLength; ++i) {
      transactions[executionData.txCount].to = address(swapProps.srcData[0].srcTokenSwapDetails[i].token);
      transactions[executionData.txCount].txData = abi.encodeWithSelector(
        IERC20Extended.approve.selector,
        swapper,
        swapProps.srcData[0].srcTokenSwapDetails[i].amount
      );
      executionData.txCount++;
    }

    transactions[executionData.txCount].to = swapper;
    transactions[executionData.txCount].txData = abi.encodeWithSelector(ISwapper.swap.selector, swapProps);
    executionData.txCount++;

    uint256 reduceLength = executionData.possibleTransactionsLength.sub(executionData.txCount);
    assembly {
      mstore(transactions, sub(mload(transactions), reduceLength))
    }
  }

  /// @dev For processing onchain swap. Use case: offchain swap data is not provided
  function _withdrawCollateralTransactions(
    address _pool,
    uint256 _portion,
    address _repayAsset
  ) internal view returns (MultiTransaction[] memory transactions) {
    (AssetStructure[] memory collateralAssets, uint256 collateralAssetsLength) = _calculateCollateralAssets(
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
        IAaveV3Pool.withdraw.selector,
        collateralAssets[i].asset,
        collateralAssets[i].amount,
        _pool
      );
      txCount++;

      if (collateralAssets[i].asset != _repayAsset) {
        transactions[txCount].to = collateralAssets[i].asset;
        transactions[txCount].txData = abi.encodeWithSelector(
          IERC20Extended.approve.selector,
          onchainSwapRouter,
          collateralAssets[i].amount
        );
        txCount++;

        path[0] = collateralAssets[i].asset;
        transactions[txCount].to = onchainSwapRouter;
        transactions[txCount].txData = abi.encodeWithSelector(
          IUniswapV2RouterSwapOnly.swapExactTokensForTokens.selector,
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
