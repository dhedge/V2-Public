// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PendlePTAssetGuard} from "contracts/guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {PendleRouterV4ContractGuard} from "contracts/guards/contractGuards/pendle/PendleRouterV4ContractGuard.sol";
import {PendlePTPriceAggregator} from "contracts/priceAggregators/PendlePTPriceAggregator.sol";
import {IPActionSwapPTV3} from "contracts/interfaces/pendle/IPActionSwapPTV3.sol";
import {IPActionMiscV3} from "contracts/interfaces/pendle/IPActionMiscV3.sol";
import {IPMarket} from "contracts/interfaces/pendle/IPMarket.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolFactory} from "contracts/interfaces/IPoolFactory.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {RewardAssetGuard} from "contracts/guards/assetGuards/RewardAssetGuard.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

import "contracts/interfaces/pendle/IPAllActionTypeV3.sol" as IPAllActionTypeV3;

abstract contract PendlePrincipalTokenTestSetup is BackboneSetup, IntegrationDeployer {
  address internal immutable pendleMarketFactoryV3;
  address internal immutable pendleRouterV4;
  address internal immutable underlyingYieldToken;
  address internal immutable underlyingYieldTokenPriceFeed;
  address internal immutable pendleMarket;
  IAggregatorV3Interface internal immutable pendleChainlinkOracle;

  address private PT;
  address private YT;
  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;

  constructor(
    address _pendleMarketFactoryV3,
    address _pendleRouterV4,
    address _underlyingYieldToken,
    address _underlyingYieldTokenPriceFeed,
    address _pendleMarket,
    address _pendleChainlinkOracle
  ) {
    pendleMarketFactoryV3 = _pendleMarketFactoryV3;
    pendleRouterV4 = _pendleRouterV4;
    underlyingYieldToken = _underlyingYieldToken;
    underlyingYieldTokenPriceFeed = _underlyingYieldTokenPriceFeed;
    pendleMarket = _pendleMarket;
    pendleChainlinkOracle = IAggregatorV3Interface(_pendleChainlinkOracle);
  }

  function setUp() public virtual override {
    super.setUp();

    (, PT, YT) = IPMarket(pendleMarket).readTokens();

    deployIntegration(poolFactoryProxy, address(0), address(slippageAccumulator), address(0));

    if (pendleMarket == EthereumConfig.PENDLE_MARKET_sUSDe_SEP_2025) {
      _use_different_oracle_for_staked_usde();
    }

    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: underlyingYieldToken, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: PT, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Pendle Principal Token Test",
        _fundSymbol: "PPTT",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    uint8 underlyingYieldTokenDecimals = IERC20Extended(underlyingYieldToken).decimals();
    uint256 amountToDeposit = 10000 * (10 ** underlyingYieldTokenDecimals);

    deal(underlyingYieldToken, manager, amountToDeposit);
    IERC20(underlyingYieldToken).approve(address(testPool), amountToDeposit);
    testPool.deposit(underlyingYieldToken, amountToDeposit);

    deal(usdcData.asset, manager, 10000e6);
    IERC20(usdcData.asset).approve(address(testPool), 10000e6);
    testPool.deposit(usdcData.asset, 10000e6);

    // Max approve spending underlying yield token and USDC from within the whitelisted pool
    testPool.execTransaction(
      underlyingYieldToken,
      abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, type(uint256).max)
    );
    testPool.execTransaction(
      usdcData.asset,
      abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, type(uint256).max)
    );

    vm.stopPrank();
  }

  function deployIntegration(PoolFactory _poolFactory, address, address _slippageAcc, address) public override {
    Governance governance = Governance(_poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    PendleRouterV4ContractGuard pendleRouterV4ContractGuard = new PendleRouterV4ContractGuard(_slippageAcc);
    governance.setContractGuard(pendleRouterV4, address(pendleRouterV4ContractGuard));

    address[] memory knownPendleMarkets = new address[](1);
    knownPendleMarkets[0] = pendleMarket;

    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(pendleMarketFactoryV3, knownPendleMarkets);
    governance.setAssetGuard(uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN), address(pendlePTAssetGuard));

    RewardAssetGuard.RewardAssetSetting[] memory rewardAssetSettings = new RewardAssetGuard.RewardAssetSetting[](1);
    address[] memory linkedAssets = new address[](1);
    linkedAssets[0] = PT;
    rewardAssetSettings[0].rewardToken = underlyingYieldToken;
    rewardAssetSettings[0].linkedAssets = linkedAssets;
    RewardAssetGuard rewardAssetGuard = new RewardAssetGuard(rewardAssetSettings);

    governance.setAssetGuard(200, address(rewardAssetGuard));

    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: underlyingYieldToken,
      assetType: 200,
      aggregator: underlyingYieldTokenPriceFeed
    });
    assetHandler.addAssets(assets);

    PendlePTPriceAggregator pendlePTOracle = new PendlePTPriceAggregator(
      underlyingYieldToken,
      pendleChainlinkOracle,
      IPoolFactory(address(_poolFactory))
    );

    assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: PT,
      assetType: uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN),
      aggregator: address(pendlePTOracle)
    });
    assetHandler.addAssets(assets);

    vm.stopPrank();
  }

  function test_can_buy_PT_and_account_for_it_correctly() public {
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();

    vm.startPrank(manager);

    uint256 underlyingBalanceOfPoolBefore = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingBalanceOfPoolBefore),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();

    // Acceptable tolerance can vary depending on fee conditions of PT which is tested. This is related to pendle fees being lower if maturity period is closer.
    // https://docs.pendle.finance/ProtocolMechanics/Mechanisms/Fees less time to maturity -> less yield-receivables -> lower fees in $ terms
    // If maturity is close, 0.01% tolerance can work
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.001e18, "totalValue deviation is huge"); // 0.1% tolerance

    // Verify PT was received
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));
    assertTrue(ptBalance > 0, "No PT tokens received");

    // Verify underlying yield token was spent
    uint256 underlyingBalanceOfPoolAfter = IERC20(underlyingYieldToken).balanceOf(address(testPool));
    assertEq(underlyingBalanceOfPoolAfter, 0, "Underlying tokens not spent");
  }

  function test_can_sell_PT_and_account_for_it_correctly() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Now test selling the PT
    uint256 totalValueAfterBuyingPT = testPoolManagerLogic.totalFundValue();
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));
    uint256 underlyingBalanceBefore = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    bytes memory approvePTCallData = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance);

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      pendleMarket,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: PT, data: approvePTCallData});
    txs[1] = PoolLogic.TxToExecute({to: pendleRouterV4, data: sellPTCalldata});

    testPool.execTransactions(txs);

    uint256 totalValueAfterSellingPT = testPoolManagerLogic.totalFundValue();
    uint256 ptBalanceAfter = IERC20(PT).balanceOf(address(testPool));
    uint256 underlyingBalanceAfter = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    assertApproxEqRel(totalValueAfterBuyingPT, totalValueBefore, 0.001e18, "totalValue deviation is huge"); // 0.1% tolerance
    assertApproxEqRel(totalValueAfterSellingPT, totalValueAfterBuyingPT, 0.001e18, "totalValue deviation is huge"); // 0.1% tolerance
    assertLt(totalValueAfterBuyingPT, totalValueBefore, "totalValue should decrease after buying PT");
    assertLt(totalValueAfterSellingPT, totalValueAfterBuyingPT, "totalValue should decrease after selling PT");
    assertEq(ptBalanceAfter, 0, "PT tokens not fully sold");
    assertTrue(underlyingBalanceAfter > underlyingBalanceBefore, "Underlying tokens not received");
  }

  function test_can_redeem_PT_after_expiry() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Simulate time moving past expiry
    uint256 expiry = IPMarket(pendleMarket).expiry();
    vm.warp(expiry + 1);

    // Now test redemption post-expiry
    uint256 totalValueBeforeRedeem = testPoolManagerLogic.totalFundValue();
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));
    uint256 underlyingBalanceBefore = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    bytes memory approvePTCallData = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance);

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.exitPostExpToToken.selector,
      address(testPool),
      pendleMarket,
      ptBalance,
      0, // netLpIn
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: PT, data: approvePTCallData});
    txs[1] = PoolLogic.TxToExecute({to: pendleRouterV4, data: redeemPTCalldata});

    testPool.execTransactions(txs);

    uint256 totalValueAfterRedeem = testPoolManagerLogic.totalFundValue();
    uint256 ptBalanceAfter = IERC20(PT).balanceOf(address(testPool));
    uint256 underlyingBalanceAfter = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    assertGt(
      totalValueBeforeRedeem - (totalValueBeforeRedeem * 0.01e18), // test should allow for enough time to pass
      totalValueBefore,
      "totalValue should increase over time after buying PT"
    );

    // Upon maturity, PT can be redeemed at 1:1 for the accounting asset, so delta is very tight
    assertApproxEqRel(totalValueAfterRedeem, totalValueBeforeRedeem, 0.000012e18, "totalValue deviation is huge"); // 0.0012% tolerance
    assertEq(ptBalanceAfter, 0, "PT tokens not fully redeemed");
    assertTrue(underlyingBalanceAfter > underlyingBalanceBefore, "Underlying tokens not received after redemption");
  }

  function test_can_redeem_PT_using_redeemPyToToken_after_expiry() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Simulate time moving past expiry
    uint256 expiry = IPMarket(pendleMarket).expiry();
    vm.warp(expiry + 1);

    // Now test redemption post-expiry using redeemPyToToken
    uint256 totalValueBeforeRedeem = testPoolManagerLogic.totalFundValue();
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));
    uint256 underlyingBalanceBefore = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    bytes memory approvePTCallData = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance);

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.redeemPyToToken.selector,
      address(testPool),
      YT,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: PT, data: approvePTCallData});
    txs[1] = PoolLogic.TxToExecute({to: pendleRouterV4, data: redeemPTCalldata});

    testPool.execTransactions(txs);

    uint256 totalValueAfterRedeem = testPoolManagerLogic.totalFundValue();
    uint256 ptBalanceAfter = IERC20(PT).balanceOf(address(testPool));
    uint256 underlyingBalanceAfter = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    assertGt(
      totalValueBeforeRedeem - (totalValueBeforeRedeem * 0.01e18), // test should allow for enough time to pass
      totalValueBefore,
      "totalValue should increase over time after buying PT"
    );

    // Upon maturity, PT can be redeemed at 1:1 for the accounting asset, so delta is very tight
    assertApproxEqRel(totalValueAfterRedeem, totalValueBeforeRedeem, 0.000012e18, "totalValue deviation is huge"); // 0.0012% tolerance
    assertEq(ptBalanceAfter, 0, "PT tokens not fully redeemed");
    assertTrue(underlyingBalanceAfter > underlyingBalanceBefore, "Underlying tokens not received after redemption");
  }

  function test_slippage_gets_updated_when_buying_PT() public {
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    uint128 cumulativeSlippage = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));
    assertGt(uint256(cumulativeSlippage), 0, "Slippage not udpated");
  }

  function test_slippage_gets_updated_when_selling_PT() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    uint128 cumulativeSlippageBefore = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));

    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    bytes memory approvePTCallData = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance);

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      pendleMarket,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: PT, data: approvePTCallData});
    txs[1] = PoolLogic.TxToExecute({to: pendleRouterV4, data: sellPTCalldata});

    testPool.execTransactions(txs);

    uint128 cumulativeSlippageAfter = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));
    assertGt(uint256(cumulativeSlippageAfter), uint256(cumulativeSlippageBefore), "Slippage not udpated");
  }

  function test_slippage_doesnt_get_updated_when_redeeming_PT() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Simulate time moving past expiry
    uint256 expiry = IPMarket(pendleMarket).expiry();
    vm.warp(expiry + 1);

    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    bytes memory approvePTCallData = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance);

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.exitPostExpToToken.selector,
      address(testPool),
      pendleMarket,
      ptBalance,
      0, // netLpIn
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: PT, data: approvePTCallData});
    txs[1] = PoolLogic.TxToExecute({to: pendleRouterV4, data: redeemPTCalldata});

    testPool.execTransactions(txs);

    // Upon maturity, PT can be redeemed at 1:1 for the accounting asset.
    uint128 cumulativeSlippage = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));
    assertEq(uint256(cumulativeSlippage), 0, "Slippage increased");
  }

  function test_slippage_doesnt_get_updated_when_using_redeemPyToToken() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Simulate time moving past expiry
    uint256 expiry = IPMarket(pendleMarket).expiry();
    vm.warp(expiry + 1);

    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    bytes memory approvePTCallData = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance);

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.redeemPyToToken.selector,
      address(testPool),
      YT,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: PT, data: approvePTCallData});
    txs[1] = PoolLogic.TxToExecute({to: pendleRouterV4, data: redeemPTCalldata});

    testPool.execTransactions(txs);

    // Upon maturity, PT can be redeemed at 1:1 for the accounting asset.
    uint128 cumulativeSlippage = slippageAccumulator.getCumulativeSlippageImpact(address(testPoolManagerLogic));
    assertEq(uint256(cumulativeSlippage), 0, "Slippage increased");
  }

  function test_revert_buy_PT_when_receiver_is_not_pool() public {
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      manager, // Setting receiver to manager instead of pool
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_sell_PT_when_receiver_is_not_pool() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Now try to sell but send to manager instead of pool
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      manager, // Setting receiver to manager instead of pool
      pendleMarket,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);
  }

  function test_revert_redeem_PT_when_receiver_is_not_pool() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Simulate time moving past expiry
    uint256 expiry = IPMarket(pendleMarket).expiry();
    vm.warp(expiry + 1);

    // Now try to redeem but send to manager instead of pool
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.exitPostExpToToken.selector,
      manager, // Setting receiver to manager instead of pool
      pendleMarket,
      ptBalance,
      0, // netLpIn
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(pendleRouterV4, redeemPTCalldata);
  }

  function test_revert_redeemPyToToken_when_receiver_is_not_pool() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Simulate time moving past expiry
    uint256 expiry = IPMarket(pendleMarket).expiry();
    vm.warp(expiry + 1);

    // Now try to redeem but send to manager instead of pool
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.redeemPyToToken.selector,
      manager, // Wrong receiver - should be testPool
      YT,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(pendleRouterV4, redeemPTCalldata);
  }

  function test_revert_buy_PT_when_PT_not_supported() public {
    vm.startPrank(manager);

    // Remove PT from supported assets
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = PT;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_sell_PT_when_destination_not_supported() public {
    vm.startPrank(manager);

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = PT;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    deal(underlyingYieldToken, address(testPool), 0);

    assetsToRemove = new address[](1);
    assetsToRemove[0] = underlyingYieldToken;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);
  }

  function test_revert_redeem_PT_when_destination_not_supported() public {
    vm.startPrank(manager);

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = PT;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    deal(underlyingYieldToken, address(testPool), 0);

    assetsToRemove = new address[](1);
    assetsToRemove[0] = underlyingYieldToken;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.exitPostExpToToken.selector,
      address(testPool),
      pendleMarket,
      0,
      0, // netLpIn
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(pendleRouterV4, redeemPTCalldata);
  }

  function test_revert_redeemPyToToken_when_destination_not_supported() public {
    vm.startPrank(manager);

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = PT;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    deal(underlyingYieldToken, address(testPool), 0);

    assetsToRemove = new address[](1);
    assetsToRemove[0] = underlyingYieldToken;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    bytes memory redeemPyToTokenCalldata = abi.encodeWithSelector(
      IPActionMiscV3.redeemPyToToken.selector,
      address(testPool),
      YT,
      0,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(pendleRouterV4, redeemPyToTokenCalldata);
  }

  function test_revert_redeem_PT_when_netLpIn_not_zero() public {
    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.exitPostExpToToken.selector,
      address(testPool),
      pendleMarket,
      0,
      1, // netLpIn not zero
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    vm.expectRevert("only PT");
    testPool.execTransaction(pendleRouterV4, redeemPTCalldata);
  }

  function test_price_oracle_correctly_values_PT() public view {
    // Calculate PT price from dhedge's price oracle
    address ptPriceAggregator = IAssetHandler(poolFactoryProxy.getAssetHandler()).priceAggregators(PT);
    (, int256 ptPrice, , , ) = IAggregatorV3Interface(ptPriceAggregator).latestRoundData();

    // Get PT price information from Pendle oracle
    (, int256 ptRateFromPendle, , , ) = pendleChainlinkOracle.latestRoundData();

    // Get underlying token price
    address underlyingPriceAggregator = IAssetHandler(poolFactoryProxy.getAssetHandler()).priceAggregators(
      underlyingYieldToken
    );
    (, int256 underlyingPrice, , , ) = IAggregatorV3Interface(underlyingPriceAggregator).latestRoundData();

    // Verify PT price is related to underlying token price and PT rate from Pendle
    // Note: This is an approximate check, actual calculation depends on decimal adjustment
    uint8 pendleOracleDecimals = pendleChainlinkOracle.decimals();
    int256 expectedPrice = (ptRateFromPendle * underlyingPrice) / int256(10 ** pendleOracleDecimals);

    assertEq(uint256(ptPrice), uint256(expectedPrice), "PT price mismatch");
  }

  function test_price_oracle_update_after_underlying_aggregator_update() public {
    // Record initial PT price
    address ptPriceAggregator = IAssetHandler(poolFactoryProxy.getAssetHandler()).priceAggregators(PT);
    (, int256 initialPtPrice, , , ) = IAggregatorV3Interface(ptPriceAggregator).latestRoundData();

    // Force update of underlying aggregator via the PT aggregator's public function: doesn't do anything as new underlying aggregator has not changed
    PendlePTPriceAggregator(ptPriceAggregator).updateUnderlyingAggregator();

    // Get updated PT price
    (, int256 updatedPtPrice, , , ) = IAggregatorV3Interface(ptPriceAggregator).latestRoundData();

    assertEq(initialPtPrice, updatedPtPrice, "Price shouldn't change");
  }

  function test_withdraw_from_pool_with_PT() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    skip(1 days);

    // Now test withdrawal with PT
    uint256 ptBalanceBefore = IERC20(PT).balanceOf(address(testPool));
    assertTrue(ptBalanceBefore > 0, "No PT tokens available for withdrawal");

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4; // withdraw 25% of pool

    uint256 tokenPriceBefore = testPool.tokenPrice();

    // Manager is a single depositor
    uint256 expectedPtWithdrawal = ptBalanceBefore / 4;

    uint256 managerPtBalanceBefore = IERC20(PT).balanceOf(manager);
    assertEq(managerPtBalanceBefore, 0, "Manager should not have PT before withdrawal");

    testPool.withdraw(withdrawAmount);

    uint256 ptWithdrawn = IERC20(PT).balanceOf(manager);
    assertEq(ptWithdrawn, expectedPtWithdrawal, "Incorrect PT withdrawn");

    assertEq(tokenPriceBefore, testPool.tokenPrice(), "Token price should not change after withdrawal");
  }

  function test_single_asset_withdraw_from_pool_with_PT_not_expired() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    skip(1 days);

    // Now test withdrawal with PT
    uint256 ptBalanceBefore = IERC20(PT).balanceOf(address(testPool));
    assertTrue(ptBalanceBefore > 0, "No PT tokens available for withdrawal");

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4; // withdraw 25% of pool

    uint256 tokenPriceBefore = testPool.tokenPrice();

    // Manager is a single depositor
    uint256 expectedPtWithdrawal = ptBalanceBefore / 4;
    uint256 expectedPtWithdrawalValueD18 = testPoolManagerLogic.assetValue(PT, expectedPtWithdrawal);

    testPool.approve(address(easySwapperV2Proxy), withdrawAmount);
    easySwapperV2Proxy.initWithdrawal(
      address(testPool),
      withdrawAmount,
      _getEmptyPoolComplexAssetsData(address(testPool))
    );

    assertEq(tokenPriceBefore, testPool.tokenPrice(), "Token price should not change after withdrawal");

    address managersWithdrawalVault = easySwapperV2Proxy.withdrawalContracts(manager);
    uint256 actualUnderlyingBalance = IERC20(underlyingYieldToken).balanceOf(managersWithdrawalVault);
    uint256 actualUnderlyingValueD18 = testPoolManagerLogic.assetValue(underlyingYieldToken, actualUnderlyingBalance);

    assertEq(IERC20(PT).balanceOf(managersWithdrawalVault), 0, "PT tokens should not be in withdrawal vault");

    assertApproxEqRel(
      actualUnderlyingValueD18,
      expectedPtWithdrawalValueD18,
      0.001e18, // 0.1% tolerance
      "Incorrect underlying value received in withdrawal"
    );
  }

  function test_single_asset_withdraw_from_pool_with_PT_expired() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Simulate time moving past expiry
    uint256 expiry = IPMarket(pendleMarket).expiry();
    vm.warp(expiry + 1);

    // Now test withdrawal with PT
    uint256 ptBalanceBefore = IERC20(PT).balanceOf(address(testPool));
    assertTrue(ptBalanceBefore > 0, "No PT tokens available for withdrawal");

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4; // withdraw 25% of pool

    uint256 tokenPriceBefore = testPool.tokenPrice();

    // Manager is a single depositor
    uint256 expectedPtWithdrawal = ptBalanceBefore / 4;
    uint256 expectedPtWithdrawalValueD18 = testPoolManagerLogic.assetValue(PT, expectedPtWithdrawal);

    testPool.approve(address(easySwapperV2Proxy), withdrawAmount);
    easySwapperV2Proxy.initWithdrawal(
      address(testPool),
      withdrawAmount,
      _getEmptyPoolComplexAssetsData(address(testPool))
    );

    assertEq(tokenPriceBefore, testPool.tokenPrice(), "Token price should not change after withdrawal");

    address managersWithdrawalVault = easySwapperV2Proxy.withdrawalContracts(manager);
    uint256 actualUnderlyingBalance = IERC20(underlyingYieldToken).balanceOf(managersWithdrawalVault);
    uint256 actualUnderlyingValueD18 = testPoolManagerLogic.assetValue(underlyingYieldToken, actualUnderlyingBalance);

    assertEq(IERC20(PT).balanceOf(managersWithdrawalVault), 0, "PT tokens should not be in withdrawal vault");

    assertApproxEqRel(
      actualUnderlyingValueD18,
      expectedPtWithdrawalValueD18,
      0.001e18, // 0.1% tolerance
      "Incorrect underlying value received in withdrawal"
    );
  }

  function test_single_asset_withdraw_from_pool_with_PT_enabled_but_zero_balance() public {
    skip(1 days);

    vm.startPrank(manager);

    uint256 ptBalanceBefore = IERC20(PT).balanceOf(address(testPool));
    assertEq(ptBalanceBefore, 0, "PT tokens balance should be zero");

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4; // withdraw 25% of pool

    uint256 tokenPriceBefore = testPool.tokenPrice();

    testPool.approve(address(easySwapperV2Proxy), withdrawAmount);
    easySwapperV2Proxy.initWithdrawal(
      address(testPool),
      withdrawAmount,
      _getEmptyPoolComplexAssetsData(address(testPool))
    );

    assertEq(tokenPriceBefore, testPool.tokenPrice(), "Token price should not change after withdrawal");
  }

  function test_revert_single_asset_withdraw_when_pt_market_unknown() public {
    address[] memory knownPendleMarkets = new address[](0);

    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(pendleMarketFactoryV3, knownPendleMarkets);

    vm.prank(owner);
    governance.setAssetGuard(uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN), address(pendlePTAssetGuard));

    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool));

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    skip(1 days);

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4; // withdraw 25% of pool

    testPool.approve(address(easySwapperV2Proxy), withdrawAmount);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(testPool));

    vm.expectRevert("pt not handled");
    easySwapperV2Proxy.initWithdrawal(address(testPool), withdrawAmount, complexAssetsData);
  }

  function test_revert_enable_asset_when_PT_market_not_updated() public {
    // Remove PT from supported assets
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = PT;

    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    // Redeploy asset guard with empty known markets
    address[] memory knownPendleMarkets = new address[](0);
    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(pendleMarketFactoryV3, knownPendleMarkets);

    vm.prank(owner);
    governance.setAssetGuard(uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN), address(pendlePTAssetGuard));

    // Add PT back to supported assets
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: PT, isDeposit: false});

    vm.expectRevert("unknown PT");
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(assetsToAdd, new address[](0));
  }

  function test_revert_disable_underlying_yield_token_when_PT_enabled() public {
    deal(underlyingYieldToken, address(testPool), 0);

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = underlyingYieldToken;

    vm.expectRevert("remove linked asset first");
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);
  }

  function test_revert_buy_PT_when_unknown_limit_router() public {
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    // Create limit order data with an unknown limit router (not the expected LIMIT_ROUTER or address(0))
    address maliciousContract = address(0x1234567890123456789012345678901234567890);
    IPAllActionTypeV3.LimitOrderData memory limitOrderData = IPAllActionTypeV3.LimitOrderData({
      limitRouter: maliciousContract,
      epsSkipMarket: 0,
      normalFills: new IPAllActionTypeV3.FillOrderParams[](0),
      flashFills: new IPAllActionTypeV3.FillOrderParams[](0),
      optData: ""
    });

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool), // receiver
      pendleMarket, // market
      underlyingAmount, // netPtOut
      IPAllActionTypeV3.createDefaultApproxParams(), // guessPtOut
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount), // input
      limitOrderData // limit
    );

    vm.expectRevert("unknown limit router");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_sell_PT_when_unknown_limit_router() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Now test selling PT with unknown limit router
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    // Create limit order data with an unknown limit router (not the expected LIMIT_ROUTER or address(0))
    address maliciousContract = address(0x1234567890123456789012345678901234567890);
    IPAllActionTypeV3.LimitOrderData memory limitOrderData = IPAllActionTypeV3.LimitOrderData({
      limitRouter: maliciousContract,
      epsSkipMarket: 0,
      normalFills: new IPAllActionTypeV3.FillOrderParams[](0),
      flashFills: new IPAllActionTypeV3.FillOrderParams[](0),
      optData: ""
    });

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool), // receiver
      pendleMarket,
      ptBalance, // exactPtIn
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0), // output
      limitOrderData // limit
    );

    vm.expectRevert("unknown limit router");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);
  }

  function _use_different_oracle_for_staked_usde() internal {
    vm.startPrank(poolFactoryProxy.owner());

    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: EthereumConfig.USDe,
      assetType: 200,
      aggregator: EthereumConfig.USDe_CHAINLINK_ORACLE
    });
    assetHandlerProxy.addAssets(assets);

    address newStakedUSDeOracle = deployCode(
      "ERC4626PriceAggregator.sol:ERC4626PriceAggregator",
      abi.encode(underlyingYieldToken, IPoolFactory(address(poolFactoryProxy)))
    );

    assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({asset: underlyingYieldToken, assetType: 200, aggregator: newStakedUSDeOracle});
    assetHandlerProxy.addAssets(assets);

    PendlePTPriceAggregator pendlePTOracle = new PendlePTPriceAggregator(
      underlyingYieldToken,
      pendleChainlinkOracle,
      IPoolFactory(address(poolFactoryProxy))
    );

    assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: PT,
      assetType: uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN),
      aggregator: address(pendlePTOracle)
    });
    assetHandlerProxy.addAssets(assets);

    vm.stopPrank();
  }

  function test_revert_redeemPyToToken_when_not_expired() public {
    // First buy some PT tokens
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    // Do NOT simulate time moving past expiry - keep it before expiry
    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.redeemPyToToken.selector,
      address(testPool),
      YT,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    vm.expectRevert("only expired");
    testPool.execTransaction(pendleRouterV4, redeemPTCalldata);
  }
}
