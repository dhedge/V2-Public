// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";

import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IGmxExchangeRouter} from "contracts/interfaces/gmx/IGmxExchangeRouter.sol";
import {IGmxRoleStore} from "contracts/interfaces/gmx/IGmxRoleStore.sol";
import {IGmxBaseOrderUtils} from "contracts/interfaces/gmx/IGmxBaseOrderUtils.sol";
import {IGmxDepositUtils} from "contracts/interfaces/gmx/IGmxDepositUtils.sol";
import {IGmxWithdrawalUtils} from "contracts/interfaces/gmx/IGmxWithdrawalUtils.sol";
import {IGmxSwapPricingUtils} from "contracts/interfaces/gmx/IGmxSwapPricingUtils.sol";
import {IGmxMarket} from "contracts/interfaces/gmx/IGmxMarket.sol";
import {IGmxPrice} from "contracts/interfaces/gmx/IGmxPrice.sol";
import {Order} from "contracts/interfaces/gmx/IGmxOrder.sol";
import {GmxTimeKeyViewer} from "contracts/test/GmxTimeKeyViewer.sol";
import {GmxClaimableCollateralTrackerLib} from "contracts/utils/gmx/GmxClaimableCollateralTrackerLib.sol";

import {GmxTestSetup} from "./GmxTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {IGmxOracleUtils} from "contracts/interfaces/gmx/IGmxOracleUtils.sol";

// Minimal interfaces for the real GMX keeper-created order handlers and for DataStore.setBool.
// Production contracts do not need these handler interfaces.
interface IGmxLiquidationHandler {
  function executeLiquidation(
    address account,
    address market,
    address collateralToken,
    bool isLong,
    IGmxOracleUtils.SetPricesParams calldata oracleParams
  ) external;
}

interface IGmxAdlHandler {
  function executeAdl(
    address account,
    address market,
    address collateralToken,
    bool isLong,
    uint256 sizeDeltaUsd,
    IGmxOracleUtils.SetPricesParams calldata oracleParams
  ) external;
}

interface IGmxDataStoreBoolSetter {
  function setBool(bytes32 key, bool value) external;
}

abstract contract GmxTestScenarios is GmxTestSetup {
  struct ClaimCondition {
    uint256 timeKey;
    address token;
    uint256 amount;
  }

  function test_perps() public {
    uint256 snapshotId = _snapshot();
    _perpsRejectsHighLeverage();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsRejectsHighLeverageAdjustment();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsRejectsUnsupportedMarket();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsRejectsWrongFeeReceiver();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsRejectsWrongCallback();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsRejectsWrongOrderVault();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsRejectsTokenOnlyMulticall();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsExecutesIncrease();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsExecutesDecrease();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsAcceptsOppositeCollateral();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _perpsRejectsWithdrawalWithPendingOrder();
    _restore(snapshotId);

    _perpsAllowsWithdrawalAfterExecution();
  }

  function _perpsRejectsHighLeverage() internal {
    uint256 collateralAmount = USDC_TEST_AMOUNT / 2;
    uint256 collateralValue = testPoolManagerLogic.assetValue(ArbitrumConfig.USDC, collateralAmount);

    OpenOrderParams memory params = _emptyOrderParams();
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = collateralAmount;
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = collateralValue * 1e12 * 8;

    vm.expectRevert(bytes("max leverage exceeded"));
    _openOrder(params);
  }

  function _perpsRejectsHighLeverageAdjustment() internal {
    uint256 collateralAmount = USDC_TEST_AMOUNT / 2;
    uint256 collateralValue = testPoolManagerLogic.assetValue(ArbitrumConfig.USDC, collateralAmount);
    uint256 initialSize = collateralValue * 1e12 * 3;

    OpenOrderParams memory params = _emptyOrderParams();
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = collateralAmount;
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = initialSize;

    uint256 collateralBalanceBefore = IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool));
    _openOrder(params);
    _executeOrder();
    assertLt(
      IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool)),
      collateralBalanceBefore,
      "increase should consume collateral"
    );

    params = _emptyOrderParams();
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = 0;
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = collateralValue * 1e12 * 8 - initialSize;
    vm.expectRevert(bytes("max leverage exceeded"));
    _openOrder(params);

    params = _emptyOrderParams();
    params.decreasePosition = true;
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = collateralAmount - (collateralAmount * 3) / 8;
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = 0;
    vm.expectRevert(bytes("max leverage exceeded"));
    _openOrder(params);
  }

  function _perpsRejectsUnsupportedMarket() internal {
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = marketConfig.market;
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    vm.expectRevert(bytes("unsupported market"));
    _openOrder(_emptyOrderParams());
  }

  function _perpsRejectsWrongFeeReceiver() internal {
    OpenOrderParams memory params = _emptyOrderParams();
    params.uiFeeReceiver = makeAddr("invalid fee receiver");
    vm.expectRevert(bytes("invalid fee receiver"));
    _openOrder(params);
  }

  function _perpsRejectsWrongCallback() internal {
    OpenOrderParams memory params = _emptyOrderParams();
    params.callbackContract = makeAddr("invalid callback");
    vm.expectRevert(bytes("invalid callback contract"));
    _openOrder(params);
  }

  function _perpsRejectsWrongOrderVault() internal {
    OpenOrderParams memory params = _emptyOrderParams();
    params.orderVault = makeAddr("invalid order vault");
    vm.expectRevert(bytes("invalid receiver"));
    _openOrder(params);
  }

  function _perpsRejectsTokenOnlyMulticall() internal {
    OpenOrderParams memory params = _emptyOrderParams();
    params.onlySendTokens = true;
    vm.expectRevert(bytes("dh23"));
    _openOrder(params);
  }

  function _perpsExecutesIncrease() internal {
    uint256 fundValueBefore = testPoolManagerLogic.totalFundValue();
    _openOrder(_emptyOrderParams());
    uint256 fundValueAfterRequest = testPoolManagerLogic.totalFundValue();
    assertApproxEqAbs(fundValueAfterRequest, fundValueBefore, fundValueBefore / 10_000, "request should remain valued");

    _executeOrder();
    uint256 fundValueAfterExecution = testPoolManagerLogic.totalFundValue();
    assertApproxEqAbs(
      fundValueAfterExecution,
      fundValueAfterRequest,
      fundValueAfterExecution / 100,
      "executed position value drift"
    );
    assertGt(
      IERC20(ArbitrumConfig.WETH).balanceOf(address(testPool)),
      WETH_TEST_AMOUNT / 2,
      "unused execution fee should return"
    );
  }

  function _perpsExecutesDecrease() internal {
    OpenOrderParams memory params = _emptyOrderParams();
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = marketConfig.sizeDeltaUsd;
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = USDC_TEST_AMOUNT / 4;

    uint256 collateralBeforeIncrease = IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool));
    _openOrder(params);
    assertLt(
      IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool)),
      collateralBeforeIncrease,
      "request should escrow collateral"
    );
    _executeOrder();

    uint256 fundValueBeforeDecrease = testPoolManagerLogic.totalFundValue();
    uint256 collateralBeforeDecrease = IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool));
    params = _emptyOrderParams();
    params.decreasePosition = true;
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = USDC_TEST_AMOUNT / 8;
    _openOrder(params);
    _executeOrder();

    assertGt(
      IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool)),
      collateralBeforeDecrease,
      "decrease should return collateral"
    );
    uint256 fundValueAfterDecrease = testPoolManagerLogic.totalFundValue();
    assertApproxEqAbs(
      fundValueAfterDecrease,
      fundValueBeforeDecrease,
      fundValueBeforeDecrease / 100,
      "decrease value drift"
    );
  }

  function _perpsAcceptsOppositeCollateral() internal {
    uint256 fundValueBefore = testPoolManagerLogic.totalFundValue();
    OpenOrderParams memory params = _emptyOrderParams();
    params.collateralToken = marketConfig.longCollateralToken;
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = marketConfig.longCollateralAmount / 2;
    _openOrder(params);

    uint256 fundValueAfterRequest = testPoolManagerLogic.totalFundValue();
    assertApproxEqAbs(
      fundValueAfterRequest,
      fundValueBefore,
      (fundValueBefore * 5) / 10_000,
      "opposite collateral request value drift"
    );
    _executeOrder();

    uint256 fundValueAfterExecution = testPoolManagerLogic.totalFundValue();
    assertApproxEqAbs(
      fundValueAfterExecution,
      fundValueAfterRequest,
      fundValueAfterExecution / 100,
      "opposite collateral execution value drift"
    );
  }

  function _perpsRejectsWithdrawalWithPendingOrder() internal {
    OpenOrderParams memory params = _smallOrderParams();
    _openOrder(params);

    // The exact liquid-vs-pending mix varies with the live report price. Withdrawing 90%
    // deterministically exercises the same insufficient-liquidity guard as the TS case.
    uint256 tokensToWithdraw = (testPool.balanceOf(owner) * 9) / 10;
    vm.warp(block.timestamp + 1);
    vm.prank(owner);
    vm.expectRevert(bytes("not enough available balance_1"));
    testPool.withdraw(tokensToWithdraw);
  }

  function _perpsAllowsWithdrawalAfterExecution() internal {
    _openOrder(_smallOrderParams());
    _executeOrder();

    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 poolTokensBefore = testPool.balanceOf(owner);
    uint256 ownerUsdcBefore = IERC20(ArbitrumConfig.USDC).balanceOf(owner);
    uint256 marketValueBefore = testPoolManagerLogic.assetBalance(marketConfig.market);
    uint256 liquidUsdcValueBefore = testPoolManagerLogic.assetValue(
      ArbitrumConfig.USDC,
      IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool))
    );

    uint256 tokensToWithdraw = poolTokensBefore / 10;
    vm.warp(block.timestamp + 1);
    vm.prank(owner);
    testPool.withdraw(tokensToWithdraw);

    uint256 marketValueAfter = testPoolManagerLogic.assetBalance(marketConfig.market);
    uint256 liquidUsdcValueAfter = testPoolManagerLogic.assetValue(
      ArbitrumConfig.USDC,
      IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool))
    );
    uint256 ownerUsdcReceived = IERC20(ArbitrumConfig.USDC).balanceOf(owner) - ownerUsdcBefore;
    uint256 ownerUsdcValue = testPoolManagerLogic.assetValue(ArbitrumConfig.USDC, ownerUsdcReceived);
    uint256 poolValueDecrease = marketValueBefore + liquidUsdcValueBefore - marketValueAfter - liquidUsdcValueAfter;

    assertEq(poolTokensBefore - testPool.balanceOf(owner), tokensToWithdraw, "incorrect pool tokens burned");
    assertApproxEqAbs(poolValueDecrease, ownerUsdcValue, ownerUsdcValue / 100, "incorrect withdrawal value");
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      (totalFundValueBefore * 9) / 10,
      totalFundValueBefore / 200,
      "remaining fund value should be 90 percent"
    );
  }

  function _smallOrderParams() internal pure returns (OpenOrderParams memory params) {
    params = _emptyOrderParams();
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = DEFAULT_SIZE_DELTA_USD / 4;
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = USDC_TEST_AMOUNT / 8;
  }

  function test_swap() public {
    uint256 snapshotId = _snapshot();
    _swapRejectsLongPath();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _swapRejectsUnsupportedMarket();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _swapRejectsHighSlippage();
    _restore(snapshotId);

    _swapExecutes();
  }

  function _swapRejectsLongPath() internal {
    address[] memory path = new address[](2);
    path[0] = marketConfig.market;
    path[1] = marketConfig.market;
    vm.expectRevert(bytes("invalid swap path"));
    _createSwapOrder(path, USDC_TEST_AMOUNT / 2, 0);
  }

  function _swapRejectsUnsupportedMarket() internal {
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = marketConfig.market;
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    vm.expectRevert(bytes("unsupported market"));
    _createSwapOrder(_singleMarketPath(), USDC_TEST_AMOUNT / 2, 0);
  }

  function _swapRejectsHighSlippage() internal {
    uint256 amountIn = USDC_TEST_AMOUNT / 2;
    uint256 fairAmountOut = _getFairAmountOut(ArbitrumConfig.USDC, marketConfig.longCollateralToken, amountIn);

    vm.expectRevert(bytes("high slippage"));
    _createSwapOrder(_singleMarketPath(), amountIn, (fairAmountOut * 983) / 1_000);

    vm.expectRevert(bytes("high slippage"));
    _createSwapOrder(_singleMarketPath(), amountIn, 0);
  }

  function _swapExecutes() internal {
    uint256 amountIn = USDC_TEST_AMOUNT / 2;
    uint256 minAmountOut = (_getFairAmountOut(ArbitrumConfig.USDC, marketConfig.longCollateralToken, amountIn) * 99) /
      100;
    uint256 fundValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 usdcBefore = IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool));
    uint256 wethBefore = IERC20(ArbitrumConfig.WETH).balanceOf(address(testPool));
    uint128 slippageBefore = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));

    _createSwapOrder(_singleMarketPath(), amountIn, minAmountOut);
    assertEq(testPoolManagerLogic.totalFundValue(), fundValueBefore, "swap request should remain valued");
    _executeOrder();

    assertEq(usdcBefore - IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool)), amountIn, "incorrect swap input");
    assertGt(
      IERC20(ArbitrumConfig.WETH).balanceOf(address(testPool)),
      wethBefore - WETH_TEST_AMOUNT / 2,
      "fee not returned"
    );
    uint128 slippageAfter = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));
    assertGe(uint256(slippageAfter), uint256(slippageBefore), "slippage decreased");
    assertLt(uint256(slippageAfter) - uint256(slippageBefore), 10_000, "swap slippage exceeds one percent");
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      fundValueBefore,
      fundValueBefore / 100,
      "swap value drift"
    );
  }

  function _createSwapOrder(address[] memory path, uint256 amountIn, uint256 minAmountOut) internal {
    bytes[] memory calls = new bytes[](3);
    calls[0] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      ArbitrumConfig.WETH,
      gmxOrderVault,
      WETH_TEST_AMOUNT / 2
    );
    calls[1] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      ArbitrumConfig.USDC,
      gmxOrderVault,
      amountIn
    );

    IGmxBaseOrderUtils.CreateOrderParams memory params;
    params.addresses = IGmxBaseOrderUtils.CreateOrderParamsAddresses({
      receiver: address(testPool),
      cancellationReceiver: address(0),
      callbackContract: address(gmxContractGuard),
      uiFeeReceiver: GMX_UI_FEE_RECEIVER,
      market: address(0),
      initialCollateralToken: ArbitrumConfig.USDC,
      swapPath: path
    });
    params.numbers = IGmxBaseOrderUtils.CreateOrderParamsNumbers({
      sizeDeltaUsd: 0,
      initialCollateralDeltaAmount: 0,
      triggerPrice: 0,
      acceptablePrice: 0,
      executionFee: WETH_TEST_AMOUNT / 2,
      callbackGasLimit: 3_000_000,
      minOutputAmount: minAmountOut,
      validFromTime: 0
    });
    params.orderType = Order.OrderType.MarketSwap;
    params.decreasePositionSwapType = Order.DecreasePositionSwapType.NoSwap;
    params.isLong = false;
    params.shouldUnwrapNativeToken = false;
    params.autoCancel = false;
    params.referralCode = bytes32(0);
    params.dataList = new bytes32[](0);
    calls[2] = abi.encodeWithSelector(IGmxExchangeRouter.createOrder.selector, params);

    _prepareRequestTimestamp();
    vm.prank(manager);
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(IGmxExchangeRouter.multicall.selector, calls)
    );
  }

  function _singleMarketPath() internal view returns (address[] memory path) {
    path = new address[](1);
    path[0] = marketConfig.market;
  }

  function _getFairAmountOut(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
    uint256 tokenInPrice = assetHandlerProxy.getUSDPrice(tokenIn);
    uint256 tokenOutPrice = assetHandlerProxy.getUSDPrice(tokenOut);
    return
      (amountIn * tokenInPrice * (10 ** uint256(IERC20Extended(tokenOut).decimals()))) /
      tokenOutPrice /
      (10 ** uint256(IERC20Extended(tokenIn).decimals()));
  }

  function test_lp() public {
    uint256 snapshotId = _snapshot();
    _lpDepositRejectsUnsupportedMarket();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _lpDepositRejectsWrongReceiver();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _lpDepositRejectsWrongVault();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _lpDepositRejectsHighSlippage();
    _restore(snapshotId);

    snapshotId = _snapshot();
    _lpDepositExecutes();
    _restore(snapshotId);

    _prepareLpPosition();
    uint256 lpPositionSnapshot = _snapshot();
    _lpWithdrawalExecutes();
    _restore(lpPositionSnapshot);

    lpPositionSnapshot = _snapshot();
    _lpWithdrawalRejectsUnsupportedAsset();
    _restore(lpPositionSnapshot);

    lpPositionSnapshot = _snapshot();
    _lpWithdrawalRejectsWrongReceiver();
    _restore(lpPositionSnapshot);

    lpPositionSnapshot = _snapshot();
    _lpWithdrawalRejectsWrongVault();
    _restore(lpPositionSnapshot);

    _lpWithdrawalRejectsHighSlippage();
  }

  function _lpDepositRejectsUnsupportedMarket() internal {
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = marketConfig.market;
    _prepareRequestTimestamp();
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    _createDepositExpectRevert(address(0), address(0), 50, bytes("unsupported market"));
  }

  function _lpDepositRejectsWrongReceiver() internal {
    _createDepositExpectRevert(makeAddr("invalid deposit receiver"), address(0), 50, bytes("receiver not pool logic"));
  }

  function _lpDepositRejectsWrongVault() internal {
    _createDepositExpectRevert(address(0), makeAddr("invalid deposit vault"), 50, bytes("invalid receiver"));
  }

  function _lpDepositRejectsHighSlippage() internal {
    _createDepositExpectRevert(address(0), address(0), 160, bytes("high slippage"));
  }

  function _lpDepositExecutes() internal {
    uint256 fundValueBefore = testPoolManagerLogic.totalFundValue();
    uint128 slippageBefore = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));

    _createDeposit(address(0), address(0), 50);
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      fundValueBefore,
      fundValueBefore / 10_000,
      "deposit request value drift"
    );
    _executeDeposit();

    uint128 slippageAfter = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));
    assertGe(uint256(slippageAfter) + 3, uint256(slippageBefore), "deposit slippage decreased");
    assertLt(uint256(slippageAfter) + 3 - uint256(slippageBefore), 5_000, "deposit slippage exceeds 0.5 percent");
    assertGt(IERC20(marketConfig.market).balanceOf(address(testPool)), 0, "GM tokens not minted");
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      fundValueBefore,
      fundValueBefore / 100,
      "deposit execution value drift"
    );
  }

  function _prepareLpPosition() internal {
    _createDeposit(address(0), address(0), 50);
    _executeDeposit();
    assertGt(IERC20(marketConfig.market).balanceOf(address(testPool)), 0, "LP setup failed");
  }

  function _lpWithdrawalExecutes() internal {
    uint256 marketTokenAmount = IERC20(marketConfig.market).balanceOf(address(testPool));
    uint256 fundValueBefore = testPoolManagerLogic.totalFundValue();
    uint128 slippageBefore = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));

    _createWithdrawal(marketTokenAmount, address(0), address(0), 50);
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      fundValueBefore,
      fundValueBefore / 10_000,
      "withdrawal request value drift"
    );
    _executeWithdrawal();

    uint128 slippageAfter = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));
    assertGe(uint256(slippageAfter) + 3, uint256(slippageBefore), "withdrawal slippage decreased");
    assertLt(uint256(slippageAfter) + 3 - uint256(slippageBefore), 5_000, "withdrawal slippage exceeds 0.5 percent");
    assertEq(IERC20(marketConfig.market).balanceOf(address(testPool)), 0, "GM tokens remain");
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      fundValueBefore,
      fundValueBefore / 100,
      "withdrawal execution value drift"
    );
  }

  function _lpWithdrawalRejectsUnsupportedAsset() internal {
    deal(marketConfig.longCollateralToken, address(testPool), 0);
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = marketConfig.longCollateralToken;
    _prepareRequestTimestamp();
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    _createWithdrawalExpectRevert(
      IERC20(marketConfig.market).balanceOf(address(testPool)),
      address(0),
      address(0),
      50,
      bytes("unsupported withdrawal asset")
    );
  }

  function _lpWithdrawalRejectsWrongReceiver() internal {
    _createWithdrawalExpectRevert(
      IERC20(marketConfig.market).balanceOf(address(testPool)),
      makeAddr("invalid withdrawal receiver"),
      address(0),
      50,
      bytes("receiver not pool logic")
    );
  }

  function _lpWithdrawalRejectsWrongVault() internal {
    _createWithdrawalExpectRevert(
      IERC20(marketConfig.market).balanceOf(address(testPool)),
      address(0),
      makeAddr("invalid withdrawal vault"),
      50,
      bytes("invalid receiver")
    );
  }

  function _lpWithdrawalRejectsHighSlippage() internal {
    _createWithdrawalExpectRevert(
      IERC20(marketConfig.market).balanceOf(address(testPool)),
      address(0),
      address(0),
      160,
      bytes("high slippage")
    );
  }

  function _createDeposit(address receiver, address depositVaultOverride, uint256 slippageBps) internal {
    _createDepositExpectRevert(receiver, depositVaultOverride, slippageBps, new bytes(0));
  }

  function _createDepositExpectRevert(
    address receiver,
    address depositVaultOverride,
    uint256 slippageBps,
    bytes memory expectedRevert
  ) internal {
    uint256 longAmount = marketConfig.longCollateralAmount / 8;
    uint256 shortAmount = USDC_TEST_AMOUNT / 8;
    uint256 estimate = GMX_READER.getDepositAmountOut(
      GMX_DATA_STORE,
      gmxMarket,
      _getMarketPrices(),
      longAmount,
      shortAmount,
      GMX_UI_FEE_RECEIVER,
      IGmxSwapPricingUtils.SwapPricingType.Deposit,
      true
    );
    uint256 minMarketTokens = (estimate * (10_000 - slippageBps)) / 10_000;
    address gasVault = depositVaultOverride == address(0) ? gmxDepositVault : depositVaultOverride;

    bytes[] memory calls = new bytes[](4);
    calls[0] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      ArbitrumConfig.WETH,
      gasVault,
      WETH_TEST_AMOUNT
    );
    calls[1] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      marketConfig.longCollateralToken,
      gmxDepositVault,
      longAmount
    );
    calls[2] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      ArbitrumConfig.USDC,
      gmxDepositVault,
      shortAmount
    );

    IGmxDepositUtils.CreateDepositParams memory params;
    params.addresses = IGmxDepositUtils.CreateDepositParamsAddresses({
      receiver: receiver == address(0) ? address(testPool) : receiver,
      callbackContract: address(gmxContractGuard),
      uiFeeReceiver: GMX_UI_FEE_RECEIVER,
      market: marketConfig.market,
      initialLongToken: marketConfig.longCollateralToken,
      initialShortToken: ArbitrumConfig.USDC,
      longTokenSwapPath: new address[](0),
      shortTokenSwapPath: new address[](0)
    });
    params.minMarketTokens = minMarketTokens;
    params.shouldUnwrapNativeToken = false;
    params.executionFee = WETH_TEST_AMOUNT;
    params.callbackGasLimit = 3_000_000;
    params.dataList = new bytes32[](0);
    calls[3] = abi.encodeWithSelector(IGmxExchangeRouter.createDeposit.selector, params);

    _prepareRequestTimestamp();
    vm.prank(manager);
    if (expectedRevert.length > 0) vm.expectRevert(expectedRevert);
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(IGmxExchangeRouter.multicall.selector, calls)
    );
  }

  function _createWithdrawal(
    uint256 marketTokenAmount,
    address receiver,
    address withdrawalVaultOverride,
    uint256 slippageBps
  ) internal {
    _createWithdrawalExpectRevert(marketTokenAmount, receiver, withdrawalVaultOverride, slippageBps, new bytes(0));
  }

  function _createWithdrawalExpectRevert(
    uint256 marketTokenAmount,
    address receiver,
    address withdrawalVaultOverride,
    uint256 slippageBps,
    bytes memory expectedRevert
  ) internal {
    (uint256 longAmountOut, uint256 shortAmountOut) = GMX_READER.getWithdrawalAmountOut(
      GMX_DATA_STORE,
      gmxMarket,
      _getMarketPrices(),
      marketTokenAmount,
      GMX_UI_FEE_RECEIVER,
      IGmxSwapPricingUtils.SwapPricingType.Withdrawal
    );
    address gasVault = withdrawalVaultOverride == address(0) ? gmxWithdrawalVault : withdrawalVaultOverride;

    bytes[] memory calls = new bytes[](3);
    calls[0] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      ArbitrumConfig.WETH,
      gasVault,
      WETH_TEST_AMOUNT
    );
    calls[1] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      marketConfig.market,
      gmxWithdrawalVault,
      marketTokenAmount
    );

    IGmxWithdrawalUtils.CreateWithdrawalParams memory params;
    params.addresses = IGmxWithdrawalUtils.CreateWithdrawalParamsAddresses({
      receiver: receiver == address(0) ? address(testPool) : receiver,
      callbackContract: address(gmxContractGuard),
      uiFeeReceiver: GMX_UI_FEE_RECEIVER,
      market: marketConfig.market,
      longTokenSwapPath: new address[](0),
      shortTokenSwapPath: new address[](0)
    });
    params.minLongTokenAmount = (longAmountOut * (10_000 - slippageBps)) / 10_000;
    params.minShortTokenAmount = (shortAmountOut * (10_000 - slippageBps)) / 10_000;
    params.shouldUnwrapNativeToken = false;
    params.executionFee = WETH_TEST_AMOUNT;
    params.callbackGasLimit = 3_000_000;
    params.dataList = new bytes32[](0);
    calls[2] = abi.encodeWithSelector(IGmxExchangeRouter.createWithdrawal.selector, params);

    _prepareRequestTimestamp();
    vm.prank(manager);
    if (expectedRevert.length > 0) vm.expectRevert(expectedRevert);
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(IGmxExchangeRouter.multicall.selector, calls)
    );
  }

  function _executeDeposit() internal {
    _prepareExecutionTimestamp();
    bytes32 key = _getLastAccountKey(address(testPool), "DEPOSIT");
    vm.prank(keeper);
    depositHandler.executeDeposit(key, _getOracleParams());
    _consumeLivePriceReport();
  }

  function _executeWithdrawal() internal {
    _prepareExecutionTimestamp();
    bytes32 key = _getLastAccountKey(address(testPool), "WITHDRAWAL");
    vm.prank(keeper);
    withdrawalHandler.executeWithdrawal(key, _getOracleParams());
    _consumeLivePriceReport();
  }

  function _getMarketPrices() internal view returns (IGmxMarket.MarketPrices memory prices) {
    prices.indexTokenPrice = _getLiveTokenPrice(gmxMarket.indexToken);
    prices.longTokenPrice = _getLiveTokenPrice(gmxMarket.longToken);
    prices.shortTokenPrice = _getLiveTokenPrice(gmxMarket.shortToken);
  }

  function _getLiveTokenPrice(address token) internal view returns (IGmxPrice.Price memory price) {
    for (uint256 i; i < livePrices.tokens.length; ++i) {
      if (livePrices.tokens[i] == token) {
        return
          IGmxPrice.Price({
            min: livePrices.minPrices[livePriceReportIndex][i],
            max: livePrices.maxPrices[livePriceReportIndex][i]
          });
      }
    }
    revert("live GMX price missing");
  }

  function test_claim() public {
    _fundClaimPool();
    GmxTimeKeyViewer viewer = new GmxTimeKeyViewer();
    ClaimCondition memory condition = _prepareClaimCondition(viewer);
    uint256 claimSnapshot = _snapshot();

    _claimAndAssert(viewer, condition, 1, 0, 0, condition.amount);
    _restore(claimSnapshot);

    claimSnapshot = _snapshot();
    _claimAndAssert(viewer, condition, 4, 0, 0, condition.amount / 4);
    _restore(claimSnapshot);

    claimSnapshot = _snapshot();
    _claimAndAssert(viewer, condition, 0, 5, 0, condition.amount / 5);
    _restore(claimSnapshot);

    claimSnapshot = _snapshot();
    _claimAndAssert(viewer, condition, 4, 5, 0, condition.amount / 4);
    _restore(claimSnapshot);

    _claimAndAssert(viewer, condition, 2, 0, 5, (condition.amount * 3) / 10);
  }

  function _fundClaimPool() internal {
    _depositAndApprove(marketConfig.longCollateralToken, marketConfig.longCollateralAmount * 8);
    if (marketConfig.longCollateralToken != ArbitrumConfig.USDC) {
      _depositAndApprove(ArbitrumConfig.USDC, USDC_TEST_AMOUNT * 8);
    }
    if (marketConfig.longCollateralToken != ArbitrumConfig.WETH) {
      _depositAndApprove(ArbitrumConfig.WETH, WETH_TEST_AMOUNT * 8);
    }
  }

  function _prepareClaimCondition(GmxTimeKeyViewer viewer) internal returns (ClaimCondition memory condition) {
    bytes32 maxNegativePositionImpactFactorKey = keccak256(
      abi.encode(_hashString("MAX_POSITION_IMPACT_FACTOR"), marketConfig.market, false)
    );
    vm.prank(_getGmxController());
    GMX_DATA_STORE.setUint(maxNegativePositionImpactFactorKey, 1);

    _assertNoClaimableCollateral(viewer);
    _openClaimPoolLong();
    _openClaimImpactShort();
    uint256 collateralReturned = _closeClaimPoolLong();
    return _resolveClaimCondition(viewer, collateralReturned);
  }

  function _openClaimPoolLong() internal {
    uint256 poolCollateralBefore = IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool));
    OpenOrderParams memory params = _emptyOrderParams();
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = USDC_TEST_AMOUNT * 2;
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = marketConfig.sizeDeltaUsd * 8;
    _openOrder(params);
    _executeOrder();
    assertLt(
      IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool)),
      poolCollateralBefore,
      "claim setup long did not consume collateral"
    );
  }

  function _openClaimImpactShort() internal {
    address trader = makeAddr("GMX claim impact trader");
    uint256 impactSizeUsd = _getClaimImpactSizeUsd();
    OpenOrderParams memory params = _emptyOrderParams();
    params.receiver = trader;
    params.useZeroCallback = true;
    params.isShort = true;
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = impactSizeUsd / 1e24;
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = impactSizeUsd;
    params.hasAcceptablePrice = true;
    params.acceptablePrice = 0;
    params.hasCallbackGasLimit = true;
    params.callbackGasLimit = 0;
    _openExternalOrder(trader, params);
    uint256 traderCollateralBeforeExecution = IERC20(ArbitrumConfig.USDC).balanceOf(trader);
    _executeOrderFor(trader);
    assertEq(
      IERC20(ArbitrumConfig.USDC).balanceOf(trader),
      traderCollateralBeforeExecution,
      "impact trade returned collateral"
    );
  }

  function _getClaimImpactSizeUsd() internal view returns (uint256) {
    // The old Hardhat fixture always requested a 20,000x short. That regularly
    // gets cancelled as live market capacity changes. Preserve that upper bound,
    // but keep a 10% buffer below every GMX limit enforced for short increases.
    uint256 configuredSizeUsd = marketConfig.sizeDeltaUsd * marketConfig.claimImpactMultiplier;
    uint256 currentShortOpenInterest = GMX_DATA_STORE.getUint(
      keccak256(abi.encode(_hashString("OPEN_INTEREST"), marketConfig.market, marketConfig.longToken, false))
    );

    if (marketConfig.shortToken != marketConfig.longToken) {
      currentShortOpenInterest += GMX_DATA_STORE.getUint(
        keccak256(abi.encode(_hashString("OPEN_INTEREST"), marketConfig.market, marketConfig.shortToken, false))
      );
    }

    uint256 maxShortOpenInterest = GMX_DATA_STORE.getUint(
      keccak256(abi.encode(_hashString("MAX_OPEN_INTEREST"), marketConfig.market, false))
    );
    require(maxShortOpenInterest > currentShortOpenInterest, "claim setup has no short open interest capacity");
    uint256 availableOpenInterestUsd = maxShortOpenInterest - currentShortOpenInterest;

    uint256 shortPoolAmount = GMX_DATA_STORE.getUint(
      keccak256(abi.encode(_hashString("POOL_AMOUNT"), marketConfig.market, marketConfig.shortToken))
    );
    uint256 shortReserveFactor = GMX_DATA_STORE.getUint(
      keccak256(abi.encode(_hashString("RESERVE_FACTOR"), marketConfig.market, false))
    );
    uint256 shortPoolUsd = shortPoolAmount * _getLiveTokenPrice(marketConfig.shortToken).min;
    uint256 maxReservedUsd = (shortPoolUsd * shortReserveFactor) / 1e30;
    require(maxReservedUsd > currentShortOpenInterest, "claim setup has no short reserve capacity");
    uint256 availableReserveUsd = maxReservedUsd - currentShortOpenInterest;

    uint256 openInterestReserveFactor = GMX_DATA_STORE.getUint(
      keccak256(abi.encode(_hashString("OPEN_INTEREST_RESERVE_FACTOR"), marketConfig.market, false))
    );
    uint256 maxOpenInterestReservedUsd = (shortPoolUsd * openInterestReserveFactor) / 1e30;
    require(
      maxOpenInterestReservedUsd > currentShortOpenInterest,
      "claim setup has no short open interest reserve capacity"
    );
    uint256 availableOpenInterestReserveUsd = maxOpenInterestReservedUsd - currentShortOpenInterest;

    uint256 availableSizeUsd = availableOpenInterestUsd < availableReserveUsd
      ? availableOpenInterestUsd
      : availableReserveUsd;
    if (availableOpenInterestReserveUsd < availableSizeUsd) {
      availableSizeUsd = availableOpenInterestReserveUsd;
    }
    uint256 safeAvailableSizeUsd = (availableSizeUsd * 9) / 10;
    uint256 impactSizeUsd = configuredSizeUsd < safeAvailableSizeUsd ? configuredSizeUsd : safeAvailableSizeUsd;
    require(impactSizeUsd > marketConfig.sizeDeltaUsd * 8, "claim setup short cannot outweigh pool long");
    return impactSizeUsd;
  }

  function _closeClaimPoolLong() internal returns (uint256 collateralReturned) {
    uint256 collateralDecreaseAmount = USDC_TEST_AMOUNT * 2;
    OpenOrderParams memory params = _emptyOrderParams();
    params.decreasePosition = true;
    params.hasInitialCollateralDeltaAmount = true;
    params.initialCollateralDeltaAmount = collateralDecreaseAmount;
    params.hasSizeDeltaUsd = true;
    params.sizeDeltaUsd = marketConfig.sizeDeltaUsd * 8;
    uint256 fundValueBeforeDecrease = testPoolManagerLogic.totalFundValue();
    uint256 collateralBeforeDecrease = IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool));
    _openOrder(params);
    _executeOrder();
    collateralReturned = IERC20(ArbitrumConfig.USDC).balanceOf(address(testPool)) - collateralBeforeDecrease;

    assertGt(collateralReturned, 0, "claim setup decrease returned no collateral");
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      fundValueBeforeDecrease,
      (fundValueBeforeDecrease * 995) / 1_000,
      "claim setup value drift"
    );
  }

  function _resolveClaimCondition(
    GmxTimeKeyViewer viewer,
    uint256 collateralReturned
  ) internal view returns (ClaimCondition memory condition) {
    uint256 collateralDecreaseAmount = USDC_TEST_AMOUNT * 2;
    uint256 longClaimAmount = _totalClaimable(viewer, marketConfig.longToken);
    uint256 shortClaimAmount = _totalClaimable(viewer, marketConfig.shortToken);
    uint256[] memory longTimeKeys = _claimTimeKeys(viewer, marketConfig.longToken);
    uint256[] memory shortTimeKeys = _claimTimeKeys(viewer, marketConfig.shortToken);
    require(longTimeKeys.length == 1 || shortTimeKeys.length == 1, "claim time key missing");
    require(longClaimAmount > 0 || shortClaimAmount > 0, "claim amount missing");
    assertApproxEqAbs(
      collateralDecreaseAmount,
      longClaimAmount + shortClaimAmount + collateralReturned,
      collateralDecreaseAmount / 25,
      "claimable collateral mismatch"
    );

    if (longTimeKeys.length > 0) {
      condition = ClaimCondition({timeKey: longTimeKeys[0], token: marketConfig.longToken, amount: longClaimAmount});
    } else {
      condition = ClaimCondition({timeKey: shortTimeKeys[0], token: marketConfig.shortToken, amount: shortClaimAmount});
    }
  }

  function _claimAndAssert(
    GmxTimeKeyViewer viewer,
    ClaimCondition memory condition,
    uint256 timeFactorDivisor,
    uint256 accountFactorDivisor,
    uint256 reductionFactorDivisor,
    uint256 expectedAmount
  ) internal {
    if (timeFactorDivisor > 0) {
      _setClaimFactor(condition, address(0), timeFactorDivisor, false);
    }
    if (accountFactorDivisor > 0) {
      _setClaimFactor(condition, address(testPool), accountFactorDivisor, false);
    }
    if (reductionFactorDivisor > 0) {
      _setClaimFactor(condition, address(testPool), reductionFactorDivisor, true);
    }

    uint256 tokenBalanceBefore = IERC20(condition.token).balanceOf(address(testPool));
    uint256 fundValueBefore = testPoolManagerLogic.totalFundValue();
    address[] memory markets = new address[](1);
    address[] memory tokens = new address[](1);
    uint256[] memory timeKeys = new uint256[](1);
    markets[0] = marketConfig.market;
    tokens[0] = condition.token;
    timeKeys[0] = condition.timeKey;

    vm.prank(manager);
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(IGmxExchangeRouter.claimCollateral.selector, markets, tokens, timeKeys, address(testPool))
    );

    uint256 claimedAmount = IERC20(condition.token).balanceOf(address(testPool)) - tokenBalanceBefore;
    if (reductionFactorDivisor > 0) {
      assertApproxEqAbs(claimedAmount, expectedAmount, 5, "incorrect reduced claim amount");
    } else {
      assertEq(claimedAmount, expectedAmount, "incorrect claim amount");
    }
    assertApproxEqAbs(
      testPoolManagerLogic.totalFundValue(),
      fundValueBefore,
      fundValueBefore / 1e10 + 1,
      "claim changed fund value"
    );
    _assertNoClaimableCollateral(viewer);
  }

  function _setClaimFactor(
    ClaimCondition memory condition,
    address account,
    uint256 divisor,
    bool isReduction
  ) internal {
    bytes32 keyPrefix = _hashString(
      isReduction ? "CLAIMABLE_COLLATERAL_REDUCTION_FACTOR" : "CLAIMABLE_COLLATERAL_FACTOR"
    );
    bytes32 key = account == address(0)
      ? keccak256(abi.encode(keyPrefix, marketConfig.market, condition.token, condition.timeKey))
      : keccak256(abi.encode(keyPrefix, marketConfig.market, condition.token, condition.timeKey, account));
    vm.prank(_getGmxController());
    GMX_DATA_STORE.setUint(key, 1e30 / divisor);
  }

  function _getGmxController() internal view returns (address controller) {
    address[] memory controllers = IGmxRoleStore(GMX_DATA_STORE.roleStore()).getRoleMembers(
      _hashString("CONTROLLER"),
      0,
      1
    );
    require(controllers.length == 1, "GMX controller missing");
    return controllers[0];
  }

  function _claimTimeKeys(GmxTimeKeyViewer viewer, address token) internal view returns (uint256[] memory) {
    return
      viewer.getAllClaimableCollateralTimeKeys(
        address(nftTrackerStorageProxy),
        GmxClaimableCollateralTrackerLib.ClaimableCollateralInfo({
          market: marketConfig.market,
          token: token,
          account: address(testPool)
        })
      );
  }

  function _totalClaimable(GmxTimeKeyViewer viewer, address token) internal view returns (uint256) {
    return
      viewer.getTotalClaimableAmount(
        address(nftTrackerStorageProxy),
        address(GMX_DATA_STORE),
        GmxClaimableCollateralTrackerLib.ClaimableCollateralInfo({
          market: marketConfig.market,
          token: token,
          account: address(testPool)
        })
      );
  }

  function _assertNoClaimableCollateral(GmxTimeKeyViewer viewer) internal view {
    assertEq(_totalClaimable(viewer, marketConfig.longToken), 0, "long claim remains");
    assertEq(_totalClaimable(viewer, marketConfig.shortToken), 0, "short claim remains");
    assertEq(_claimTimeKeys(viewer, marketConfig.longToken).length, 0, "long claim time key remains");
    assertEq(_claimTimeKeys(viewer, marketConfig.shortToken).length, 0, "short claim time key remains");
  }

  // -------------------------------------------------------------------------------------------
  // Liquidation and ADL claimable-collateral tracking
  // -------------------------------------------------------------------------------------------
  //
  // GMX keeper-created orders (liquidations and ADLs) take their callback contract from the
  // account's saved-callback registry instead of the order itself. The vault must therefore
  // register the guard with GMX (ExchangeRouter.setSavedCallbackContract) and the callback
  // dispatch must handle the Liquidation order type. ADL orders are created as MarketDecrease
  // orders and already flow through the market-decrease branch.
  // -------------------------------------------------------------------------------------------

  address internal constant GMX_LIQUIDATION_HANDLER = 0x01B85C1e0682418f59C4fe37A2cC56c1213C1fa8;
  address internal constant GMX_ADL_HANDLER = 0xC8470eBBb6960FD00Db7D4C9f71CAda27e8f6Bfa;

  uint256 internal constant LIQUIDATION_MIN_COLLATERAL_USD = 1_000_000e30;

  function _getRoleMember(string memory role) internal view returns (address) {
    address roleStore = GMX_DATA_STORE.roleStore();
    address[] memory members = IGmxRoleStore(roleStore).getRoleMembers(_hashString(role), 0, 1);
    require(members.length == 1, "GMX role member missing");
    return members[0];
  }

  function _savedCallbackAddress(address market) internal view returns (address) {
    bytes32 key = keccak256(abi.encode(_hashString("SAVED_CALLBACK_CONTRACT"), address(testPool), market));
    return GMX_DATA_STORE.getAddress(key);
  }

  function _registerSavedCallback() internal {
    vm.prank(manager);
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(
        IGmxExchangeRouter.setSavedCallbackContract.selector,
        marketConfig.market,
        address(gmxContractGuard)
      )
    );
  }

  function _currentGmxTimeKey() internal view returns (uint256) {
    return block.timestamp / GMX_DATA_STORE.getUint(_hashString("CLAIMABLE_COLLATERAL_TIME_DIVISOR"));
  }

  function _rawClaimableAmount(address token, uint256 timeKey) internal view returns (uint256) {
    bytes32 key = keccak256(
      abi.encode(_hashString("CLAIMABLE_COLLATERAL_AMOUNT"), marketConfig.market, token, timeKey, address(testPool))
    );
    return GMX_DATA_STORE.getUint(key);
  }

  function _positionSizeInUsd(address account, address collateralToken, bool isLong) internal view returns (uint256) {
    bytes32 positionKey = keccak256(abi.encode(account, marketConfig.market, collateralToken, isLong));
    return GMX_DATA_STORE.getUint(keccak256(abi.encode(positionKey, _hashString("SIZE_IN_USD"))));
  }

  // Shared state for the forced-decrease tests: funded pool, impact cap pinned to ~zero so the
  // whole negative impact is escrowed as claimable collateral, the pool's real long (report 0)
  // and the large external short that makes closing the long impact-heavy (report 1).
  function _prepareForcedDecreaseState() internal {
    _fundClaimPool();
    bytes32 maxNegativePositionImpactFactorKey = keccak256(
      abi.encode(_hashString("MAX_POSITION_IMPACT_FACTOR"), marketConfig.market, false)
    );
    vm.prank(_getGmxController());
    GMX_DATA_STORE.setUint(maxNegativePositionImpactFactorKey, 1);

    _openClaimPoolLong(); // consumes signed report 0
    _openClaimImpactShort(); // consumes signed report 1
  }

  function _makePoolLongLiquidatable() internal {
    vm.prank(_getGmxController());
    GMX_DATA_STORE.setUint(_hashString("MIN_COLLATERAL_USD"), LIQUIDATION_MIN_COLLATERAL_USD);
  }

  function _executeLiquidation() internal {
    _prepareExecutionTimestamp();
    address liquidationKeeper = _getRoleMember("LIQUIDATION_KEEPER");
    vm.deal(liquidationKeeper, 100 ether);
    vm.prank(liquidationKeeper);
    IGmxLiquidationHandler(GMX_LIQUIDATION_HANDLER).executeLiquidation(
      address(testPool),
      marketConfig.market,
      ArbitrumConfig.USDC,
      true,
      _getOracleParams()
    );
    _consumeLivePriceReport();
  }

  // Makes the market-wide long side deterministically profitable (implied entry ~1% below the
  // report 2 index price) and enables ADL, so the real AdlHandler executes a partial ADL of
  // the pool's long position. Both the position's own SIZE_IN_TOKENS and the aggregate long
  // OPEN_INTEREST_IN_TOKENS buckets are rewritten so the forced decrease's aggregate accounting
  // stays consistent and ADL eligibility does not depend on the live market's entry prices.
  function _prepareAdlState() internal {
    bytes32 positionKey = keccak256(abi.encode(address(testPool), marketConfig.market, ArbitrumConfig.USDC, true));
    uint256 sizeInUsd = GMX_DATA_STORE.getUint(keccak256(abi.encode(positionKey, _hashString("SIZE_IN_USD"))));
    require(sizeInUsd > 0, "ADL position missing");
    uint256 indexPrice = _getLiveTokenPrice(gmxMarket.indexToken).min;
    uint256 poolDivisor = gmxMarket.longToken == gmxMarket.shortToken ? 2 : 1;

    uint256 sizeInTokens = ((sizeInUsd * 101) / 100) / indexPrice;

    vm.startPrank(_getGmxController());
    GMX_DATA_STORE.setUint(keccak256(abi.encode(positionKey, _hashString("SIZE_IN_TOKENS"))), sizeInTokens);

    address[] memory collateralTokens = new address[](2);
    collateralTokens[0] = gmxMarket.longToken;
    collateralTokens[1] = gmxMarket.shortToken;
    for (uint256 i; i < collateralTokens.length; ++i) {
      if (i > 0 && collateralTokens[i] == collateralTokens[0]) continue; // identical long/short token market
      uint256 openInterestUsd = GMX_DATA_STORE.getUint(
        keccak256(abi.encode(_hashString("OPEN_INTEREST"), marketConfig.market, collateralTokens[i], true))
      ) / poolDivisor;
      GMX_DATA_STORE.setUint(
        keccak256(abi.encode(_hashString("OPEN_INTEREST_IN_TOKENS"), marketConfig.market, collateralTokens[i], true)),
        (((openInterestUsd * 101) / 100) / indexPrice) * poolDivisor
      );
    }

    // ADL configuration: any positive long pnl triggers ADL, no overcorrection bound, enabled now.
    bytes32 adlPnlFactorType = _hashString("MAX_PNL_FACTOR_FOR_ADL");
    GMX_DATA_STORE.setUint(
      keccak256(abi.encode(_hashString("MAX_PNL_FACTOR"), adlPnlFactorType, marketConfig.market, true)),
      0
    );
    GMX_DATA_STORE.setUint(
      keccak256(abi.encode(_hashString("MIN_PNL_FACTOR_AFTER_ADL"), marketConfig.market, true)),
      0
    );
    GMX_DATA_STORE.setUint(keccak256(abi.encode(_hashString("LATEST_ADL_AT"), marketConfig.market, true)), 0);
    IGmxDataStoreBoolSetter(address(GMX_DATA_STORE)).setBool(
      keccak256(abi.encode(_hashString("IS_ADL_ENABLED"), marketConfig.market, true)),
      true
    );
    vm.stopPrank();
  }

  function _executeAdl(uint256 sizeDeltaUsd) internal {
    _prepareExecutionTimestamp();
    address adlKeeper = _getRoleMember("ADL_KEEPER");
    vm.deal(adlKeeper, 100 ether);
    vm.prank(adlKeeper);
    IGmxAdlHandler(GMX_ADL_HANDLER).executeAdl(
      address(testPool),
      marketConfig.market,
      ArbitrumConfig.USDC,
      true,
      sizeDeltaUsd,
      _getOracleParams()
    );
    _consumeLivePriceReport();
  }

  // Shared snapshot comparison for liquidation and ADL branches: executes the unregistered
  // control first (raw GMX claimable collateral is credited but is not immediately tracked), then
  // restores, registers the guard, executes the identical forced order and proves the tracker
  // records and the asset guard values the claim immediately. A later ordinary decrease in the
  // same hourly bucket could otherwise register the cumulative bucket.
  function _assertRegisteredTracking(
    GmxTimeKeyViewer viewer,
    uint256 timeKey,
    uint256 rawLong,
    uint256 rawShort,
    uint256 unregisteredMarketValue,
    uint256 unregisteredFundValue
  ) internal view {
    bool hasDistinctShortToken = marketConfig.longToken != marketConfig.shortToken;

    assertEq(_rawClaimableAmount(marketConfig.longToken, timeKey), rawLong, "long claim differs");
    if (hasDistinctShortToken) {
      assertEq(_rawClaimableAmount(marketConfig.shortToken, timeKey), rawShort, "short claim differs");
    }

    if (rawLong > 0) {
      uint256[] memory longKeys = _claimTimeKeys(viewer, marketConfig.longToken);
      assertEq(longKeys.length, 1, "long time key count");
      assertEq(longKeys[0], timeKey, "wrong long time key");
      assertEq(_totalClaimable(viewer, marketConfig.longToken), rawLong, "long tracked claim value");
    } else {
      assertEq(_claimTimeKeys(viewer, marketConfig.longToken).length, 0, "unexpected long time key");
    }

    if (hasDistinctShortToken) {
      if (rawShort > 0) {
        uint256[] memory shortKeys = _claimTimeKeys(viewer, marketConfig.shortToken);
        assertEq(shortKeys.length, 1, "short time key count");
        assertEq(shortKeys[0], timeKey, "wrong short time key");
        assertEq(_totalClaimable(viewer, marketConfig.shortToken), rawShort, "short tracked claim value");
      } else {
        assertEq(_claimTimeKeys(viewer, marketConfig.shortToken).length, 0, "unexpected short time key");
      }
    }

    uint256 expectedClaimValue = testPoolManagerLogic.assetValue(marketConfig.longToken, rawLong);
    if (hasDistinctShortToken) {
      expectedClaimValue += testPoolManagerLogic.assetValue(marketConfig.shortToken, rawShort);
    }
    uint256 registeredMarketValue = testPoolManagerLogic.assetValue(marketConfig.market);
    uint256 registeredFundValue = testPoolManagerLogic.totalFundValue();

    assertApproxEqAbs(
      registeredMarketValue - unregisteredMarketValue,
      expectedClaimValue,
      1e6,
      "market asset value delta"
    );
    assertApproxEqAbs(registeredFundValue - unregisteredFundValue, expectedClaimValue, 1e6, "total fund value delta");
  }
}
