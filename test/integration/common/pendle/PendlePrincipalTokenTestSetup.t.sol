// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PendlePTAssetGuard} from "contracts/guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {PendleRouterV4ContractGuard} from "contracts/guards/contractGuards/pendle/PendleRouterV4ContractGuard.sol";
import {IPActionSwapPTV3} from "contracts/interfaces/pendle/IPActionSwapPTV3.sol";
import {IPActionMiscV3} from "contracts/interfaces/pendle/IPActionMiscV3.sol";
import {IPMarket, MarketState} from "contracts/interfaces/pendle/IPMarket.sol";
import {PendlePTHandlerLib} from "contracts/utils/pendle/PendlePTHandlerLib.sol";
import {PendleLogExpMath} from "contracts/utils/pendle/PendleLogExpMath.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {RewardAssetGuard} from "contracts/guards/assetGuards/RewardAssetGuard.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";

import "contracts/interfaces/pendle/IPAllActionTypeV3.sol" as IPAllActionTypeV3;
import {MaliciousYT} from "./MaliciousYT.sol";
import {MaliciousMarket} from "./MaliciousMarket.sol";

abstract contract PendlePrincipalTokenTestSetup is BackboneSetup, IntegrationDeployer {
  address private constant LIMIT_ROUTER = 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321;
  /// @dev Stands in for the YT of an unrelated Pendle market
  address private constant FOREIGN_YT = 0x1234567890123456789012345678901234567890;

  address internal immutable pendleRouterV4;
  address internal immutable underlyingYieldToken;
  address internal immutable underlyingYieldTokenPriceFeed;
  address internal immutable pendleMarket;
  IAggregatorV3Interface internal pendleChainlinkOracle;

  address private PT;
  address private YT;
  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;
  PendleRouterV4ContractGuard private pendleRouterV4ContractGuard;

  constructor(
    address _pendleRouterV4,
    address _underlyingYieldToken,
    address _underlyingYieldTokenPriceFeed,
    address _pendleMarket,
    address _pendleChainlinkOracle
  ) {
    pendleRouterV4 = _pendleRouterV4;
    underlyingYieldToken = _underlyingYieldToken;
    underlyingYieldTokenPriceFeed = _underlyingYieldTokenPriceFeed;
    pendleMarket = _pendleMarket;
    pendleChainlinkOracle = IAggregatorV3Interface(_pendleChainlinkOracle);
  }

  function setUp() public virtual override {
    super.setUp();

    if (address(pendleChainlinkOracle) == address(0)) {
      pendleChainlinkOracle = IAggregatorV3Interface(_createPendleChainlinkOracle());
    }

    (, PT, YT) = IPMarket(pendleMarket).readTokens();

    deployIntegration(poolFactoryProxy, address(0), address(slippageAccumulator), address(0));

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
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    uint8 underlyingYieldTokenDecimals = IERC20Extended(underlyingYieldToken).decimals();
    uint256 amountToDeposit = _underlyingDepositAmount() * (10 ** underlyingYieldTokenDecimals);

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

  function _underlyingDepositAmount() internal virtual returns (uint256) {
    return 10000;
  }

  /// @dev Override in chain tests for markets which have no PendleChainlinkOracle deployed at the fork block;
  ///      called after the fork is created, so the oracle can be created via Pendle's permissionless factory.
  function _createPendleChainlinkOracle() internal virtual returns (address) {
    revert("pendle oracle not provided");
  }

  /// @dev Pendle's YT caches its PY index per block (`doCacheIndexSameBlock`) and any market interaction arms
  ///      the cache for the current block. Moving time without also mining a block would settle later YT flows
  ///      (redemptions, market swaps) at the stale index. On a real chain a time gap always comes with new
  ///      blocks, and for yield tokens accruing by timestamp (e.g. sUSDS) the stale index diverges from live
  ///      oracle pricing, so every time move must advance a block as well.
  function _skipWithRoll(uint256 _time) internal {
    skip(_time);
    vm.roll(block.number + 1);
  }

  function _warpPastExpiry() internal {
    vm.warp(IPMarket(pendleMarket).expiry() + 1);
    vm.roll(block.number + 1);
  }

  /// @dev Override in chain tests where the underlying yield token has no ready USD price feed onchain,
  ///      e.g. to deploy an ERC4626PriceAggregator. Runs pranked as pool factory owner.
  function _underlyingYieldTokenAggregator(IAssetHandler) internal virtual returns (address) {
    // Wrap oracle if it doesn't return 8 decimals (e.g. apxUSD chainlink oracle returns 18)
    if (IAggregatorV3Interface(underlyingYieldTokenPriceFeed).decimals() != 8) {
      return deployCode("ChainlinkAggregatorWrapper.sol", abi.encode(underlyingYieldTokenPriceFeed));
    }

    return underlyingYieldTokenPriceFeed;
  }

  function deployIntegration(PoolFactory _poolFactory, address, address _slippageAcc, address) public override {
    Governance governance = Governance(_poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    pendleRouterV4ContractGuard = new PendleRouterV4ContractGuard(_slippageAcc, address(_poolFactory));
    governance.setContractGuard(pendleRouterV4, address(pendleRouterV4ContractGuard));

    address[] memory knownPendleMarkets = new address[](1);
    knownPendleMarkets[0] = pendleMarket;

    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(knownPendleMarkets);
    governance.setAssetGuard(uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN), address(pendlePTAssetGuard));

    RewardAssetGuard.RewardAssetSetting[] memory rewardAssetSettings = new RewardAssetGuard.RewardAssetSetting[](1);
    address[] memory linkedAssets = new address[](1);
    linkedAssets[0] = PT;
    rewardAssetSettings[0].rewardToken = underlyingYieldToken;
    rewardAssetSettings[0].linkedAssets = linkedAssets;
    RewardAssetGuard rewardAssetGuard = new RewardAssetGuard(rewardAssetSettings);

    governance.setAssetGuard(200, address(rewardAssetGuard));

    address effectiveAggregator = _underlyingYieldTokenAggregator(assetHandler);

    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({asset: underlyingYieldToken, assetType: 200, aggregator: effectiveAggregator});
    assetHandler.addAssets(assets);

    address pendlePTOracleAddress = deployCode(
      "PendlePTPriceAggregator.sol",
      abi.encode(underlyingYieldToken, address(pendleChainlinkOracle), address(assetHandler))
    );

    assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: PT,
      assetType: uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN),
      aggregator: pendlePTOracleAddress
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
    _warpPastExpiry();

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

    // PT accretes towards par as expiry approaches, so having warped to expiry the pool must be worth strictly
    // more than at purchase time; the exact magnitude is market-dependent (initial PT discount, underlying accrual)
    assertGt(totalValueBeforeRedeem, totalValueBefore, "totalValue should increase over time after buying PT");

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
    _warpPastExpiry();

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

    // PT accretes towards par as expiry approaches, so having warped to expiry the pool must be worth strictly
    // more than at purchase time; the exact magnitude is market-dependent (initial PT discount, underlying accrual)
    assertGt(totalValueBeforeRedeem, totalValueBefore, "totalValue should increase over time after buying PT");

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
    _warpPastExpiry();

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
    _warpPastExpiry();

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
    _warpPastExpiry();

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
    _warpPastExpiry();

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

    vm.expectRevert("pt not enabled");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_buy_PT_when_source_asset_not_supported() public {
    vm.startPrank(manager);

    // First remove PT (since underlyingYieldToken is linked to PT via RewardAssetGuard)
    deal(PT, address(testPool), 0);
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = PT;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    // Now remove underlyingYieldToken from supported assets
    deal(underlyingYieldToken, address(testPool), 0);
    assetsToRemove[0] = underlyingYieldToken;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    // Re-add PT so the swap can proceed past the "pt not enabled" check
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: PT, isDeposit: false});
    testPoolManagerLogic.changeAssets(assetsToAdd, new address[](0));

    // Re-add some balance for the swap attempt
    deal(underlyingYieldToken, address(testPool), 1000e18);

    bytes memory buyPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactTokenForPt.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createDefaultApproxParams(),
      IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, 100e18),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.expectRevert("unsupported source asset");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_sell_PT_when_destination_not_supported() public {
    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      pendleMarket,
      0,
      IPAllActionTypeV3.createTokenOutputSimple(wethData.asset, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);
  }

  function test_revert_redeem_PT_when_destination_not_supported() public {
    bytes memory redeemPTCalldata = abi.encodeWithSelector(
      IPActionMiscV3.exitPostExpToToken.selector,
      address(testPool),
      pendleMarket,
      0,
      0, // netLpIn
      IPAllActionTypeV3.createTokenOutputSimple(wethData.asset, 0)
    );

    vm.prank(manager);
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

    vm.expectRevert("only pt");
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

    _skipWithRoll(1 days);

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

    _skipWithRoll(1 days);

    // Now test withdrawal with PT
    uint256 ptBalanceBefore = IERC20(PT).balanceOf(address(testPool));
    assertTrue(ptBalanceBefore > 0, "No PT tokens available for withdrawal");

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4; // withdraw 25% of pool

    uint256 tokenPriceBefore = testPool.tokenPrice();

    // Manager is a single depositor
    uint256 expectedPtWithdrawal = ptBalanceBefore / 4;
    uint256 expectedPtWithdrawalValueD18 = testPoolManagerLogic.assetValue(PT, expectedPtWithdrawal);

    // Compute expected minTokenOut before withdrawal (prediction)
    uint256 computedMinTokenOut = PendlePTHandlerLib.computeMinTokenOutPreExp(
      PT,
      expectedPtWithdrawal,
      underlyingYieldToken,
      address(poolFactoryProxy),
      pendleMarket
    );

    // Compute fee rate before withdrawal
    MarketState memory state = IPMarket(pendleMarket).readState(PendlePTHandlerLib.ROUTER_V4);
    uint256 lnFeeExponent = (state.lnFeeRateRoot * (state.expiry - block.timestamp)) / 365 days;
    uint256 feeRate = uint256(PendleLogExpMath.exp(int256(lnFeeExponent)));
    uint256 feeValueD18 = (expectedPtWithdrawalValueD18 * (feeRate - 1e18)) / feeRate;

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

    // Actual output should be close to the computed minimum (it's a tight bound)
    assertApproxEqRel(
      actualUnderlyingBalance,
      computedMinTokenOut,
      0.001e18, // 0.1% tolerance
      "Actual output deviates from computed minTokenOut"
    );

    // Verify actual value matches expected value minus fee
    assertApproxEqRel(
      actualUnderlyingValueD18,
      expectedPtWithdrawalValueD18 - feeValueD18,
      0.001e18, // 0.1% tolerance
      "Actual value doesn't match expected minus fee"
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
    _warpPastExpiry();

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
    _skipWithRoll(1 days);

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
    // First buy some PT tokens
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

    vm.prank(manager);
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    _skipWithRoll(1 days);

    address[] memory knownPendleMarkets = new address[](0);
    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(knownPendleMarkets);

    vm.prank(owner);
    governance.setAssetGuard(uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN), address(pendlePTAssetGuard));

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4; // withdraw 25% of pool

    vm.startPrank(manager);

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
    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(knownPendleMarkets);

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

  function test_revert_buy_PT_when_normal_fill_carries_foreign_yt() public {
    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(
      _getLimitOrderData(LIMIT_ROUTER, _getFills(FOREIGN_YT, IPAllActionTypeV3.OrderType.PT_FOR_SY), true)
    );

    vm.prank(manager);
    vm.expectRevert("invalid yt");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_buy_PT_when_flash_fill_carries_foreign_yt() public {
    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(
      _getLimitOrderData(LIMIT_ROUTER, _getFills(FOREIGN_YT, IPAllActionTypeV3.OrderType.SY_FOR_YT), false)
    );

    vm.prank(manager);
    vm.expectRevert("invalid yt");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_buy_PT_when_fills_provided_without_limit_router() public {
    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(
      _getLimitOrderData(address(0), _getFills(YT, IPAllActionTypeV3.OrderType.PT_FOR_SY), true)
    );

    vm.prank(manager);
    vm.expectRevert("unknown limit router");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_buy_PT_when_normal_fill_has_wrong_order_type() public {
    // Buying PT expects normal fills to be PT_FOR_SY; SY_FOR_PT is the sell-side type and must be rejected.
    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(
      _getLimitOrderData(LIMIT_ROUTER, _getFills(YT, IPAllActionTypeV3.OrderType.SY_FOR_PT), true)
    );

    vm.prank(manager);
    vm.expectRevert("invalid order type");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_buy_PT_when_flash_fill_has_wrong_order_type() public {
    // Buying PT expects flash fills to be SY_FOR_YT; YT_FOR_SY is the sell-side flash type and must be rejected.
    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(
      _getLimitOrderData(LIMIT_ROUTER, _getFills(YT, IPAllActionTypeV3.OrderType.YT_FOR_SY), false)
    );

    vm.prank(manager);
    vm.expectRevert("invalid order type");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_buy_PT_when_maker_token_is_zero() public {
    // Correct YT and order type, but a raw native (address(0)) maker token must be rejected.
    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(
      _getLimitOrderData(LIMIT_ROUTER, _getFills(YT, IPAllActionTypeV3.OrderType.PT_FOR_SY, address(0)), true)
    );

    vm.prank(manager);
    vm.expectRevert("invalid maker token");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_buy_PT_when_epsSkipMarket_not_zero() public {
    // A non-zero epsilon must be rejected even with no fills attached.
    IPAllActionTypeV3.LimitOrderData memory limitOrderData = IPAllActionTypeV3.createEmptyLimitOrderData();
    limitOrderData.limitRouter = LIMIT_ROUTER;
    limitOrderData.epsSkipMarket = 1;

    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(limitOrderData);

    vm.prank(manager);
    vm.expectRevert("eps skip market not zero");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  function test_revert_sell_PT_when_normal_fill_carries_foreign_yt() public {
    vm.startPrank(manager);

    testPool.execTransaction(
      pendleRouterV4,
      _getBuyPTCalldataWithLimitOrder(IPAllActionTypeV3.createEmptyLimitOrderData())
    );

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      pendleMarket,
      IERC20(PT).balanceOf(address(testPool)),
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0),
      _getLimitOrderData(LIMIT_ROUTER, _getFills(FOREIGN_YT, IPAllActionTypeV3.OrderType.SY_FOR_PT), true)
    );

    vm.expectRevert("invalid yt");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);
  }

  /// @dev Fills carrying the market's own YT and correct direction must reach Pendle instead of being rejected by
  ///      the guard. The order is unsigned, so reverting inside the limit order protocol is proof the guard let a
  ///      well formed fill through.
  function test_buy_PT_with_well_formed_fill_reaches_limit_order_protocol() public {
    bytes memory buyPTCalldata = _getBuyPTCalldataWithLimitOrder(
      _getLimitOrderData(LIMIT_ROUTER, _getFills(YT, IPAllActionTypeV3.OrderType.PT_FOR_SY), true)
    );

    vm.prank(manager);
    vm.expectRevert("LOP: bad signature");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);
  }

  /// @dev The economic bound (AR-001 defense): a manager-initiated PT swap whose received value falls more than
  ///      the allowed slippage below the value spent must revert, even through the plain AMM path. Modelled by
  ///      marking the PT oracle above its real reading so the underlying received is worth too little.
  function test_revert_sell_PT_when_value_loss_exceeds_cap() public {
    vm.startPrank(manager);

    uint256 underlyingAmount = IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2;
    testPool.execTransaction(
      pendleRouterV4,
      abi.encodeWithSelector(
        IPActionSwapPTV3.swapExactTokenForPt.selector,
        address(testPool),
        pendleMarket,
        0,
        IPAllActionTypeV3.createDefaultApproxParams(),
        IPAllActionTypeV3.createTokenInputSimple(underlyingYieldToken, underlyingAmount),
        IPAllActionTypeV3.createEmptyLimitOrderData()
      )
    );

    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    // Mark PT ~1% above its true oracle price: selling it then returns underlying worth < 99.5% of the marked PT.
    address ptOracle = IAssetHandler(poolFactoryProxy.getAssetHandler()).priceAggregators(PT);
    (, int256 realPtPrice, , uint256 updatedAt, ) = IAggregatorV3Interface(ptOracle).latestRoundData();
    vm.mockCall(
      ptOracle,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(uint80(0), (realPtPrice * 10100) / 10000, uint256(0), updatedAt, uint80(0))
    );

    testPool.execTransaction(PT, abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance));

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      pendleMarket,
      ptBalance,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.expectRevert("swap slippage too high");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);

    vm.clearMockedCalls();
  }

  function test_revert_buy_PT_when_value_loss_exceeds_cap() public {
    // Mark PT ~1% below its true oracle price: buying it then books PT worth < 99.5% of the underlying spent.
    address ptOracle = IAssetHandler(poolFactoryProxy.getAssetHandler()).priceAggregators(PT);
    (, int256 realPtPrice, , uint256 updatedAt, ) = IAggregatorV3Interface(ptOracle).latestRoundData();
    vm.mockCall(
      ptOracle,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(uint80(0), (realPtPrice * 9900) / 10000, uint256(0), updatedAt, uint80(0))
    );

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

    vm.prank(manager);
    vm.expectRevert("swap slippage too high");
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    vm.clearMockedCalls();
  }

  function _getBuyPTCalldataWithLimitOrder(
    IPAllActionTypeV3.LimitOrderData memory _limitOrderData
  ) internal view returns (bytes memory) {
    return
      abi.encodeWithSelector(
        IPActionSwapPTV3.swapExactTokenForPt.selector,
        address(testPool),
        pendleMarket,
        0,
        IPAllActionTypeV3.createDefaultApproxParams(),
        IPAllActionTypeV3.createTokenInputSimple(
          underlyingYieldToken,
          IERC20(underlyingYieldToken).balanceOf(address(testPool)) / 2
        ),
        _limitOrderData
      );
  }

  function _getLimitOrderData(
    address _limitRouter,
    IPAllActionTypeV3.FillOrderParams[] memory _fills,
    bool _normal
  ) internal pure returns (IPAllActionTypeV3.LimitOrderData memory limitOrderData) {
    limitOrderData.limitRouter = _limitRouter;
    limitOrderData.normalFills = _normal ? _fills : new IPAllActionTypeV3.FillOrderParams[](0);
    limitOrderData.flashFills = _normal ? new IPAllActionTypeV3.FillOrderParams[](0) : _fills;
  }

  function _getFills(
    address _yt,
    IPAllActionTypeV3.OrderType _orderType
  ) internal view returns (IPAllActionTypeV3.FillOrderParams[] memory fills) {
    fills = _getFills(_yt, _orderType, underlyingYieldToken);
  }

  function _getFills(
    address _yt,
    IPAllActionTypeV3.OrderType _orderType,
    address _makerToken
  ) internal view returns (IPAllActionTypeV3.FillOrderParams[] memory fills) {
    fills = new IPAllActionTypeV3.FillOrderParams[](1);
    fills[0].order.YT = _yt;
    fills[0].order.orderType = _orderType;
    fills[0].order.token = _makerToken;
    fills[0].order.maker = manager;
    fills[0].order.receiver = manager;
    fills[0].order.expiry = block.timestamp + 1 days;
    fills[0].makingAmount = 1e18;
    fills[0].signature = new bytes(65);
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

  function test_revert_redeemPyToToken_when_malicious_yt_provided() public {
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

    vm.startPrank(manager);
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    uint256 ptBalanceOfPool = IERC20(PT).balanceOf(address(testPool));

    _warpPastExpiry();

    address maliciousYT = address(new MaliciousYT(PT, address(pendleRouterV4ContractGuard)));
    bytes memory redeemCalldata = abi.encodeWithSelector(
      IPActionMiscV3.redeemPyToToken.selector,
      address(testPool),
      maliciousYT,
      ptBalanceOfPool,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0)
    );

    bytes memory approvePTCalldata = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalanceOfPool);
    testPool.execTransaction(PT, approvePTCalldata);

    vm.expectRevert();
    testPool.execTransaction(pendleRouterV4, redeemCalldata);

    // assertEq(IERC20(PT).balanceOf(address(testPool)), 0);
    // assertEq(IERC20(PT).balanceOf(maliciousYT), ptBalanceOfPool);
  }

  function test_revert_swapExactPtForToken_when_malicious_market_provided() public {
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

    vm.startPrank(manager);
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    uint256 ptBalanceOfPool = IERC20(PT).balanceOf(address(testPool));

    address maliciousReceiver = makeAddr("receiver");
    address maliciousMarket = address(
      new MaliciousMarket(PT, maliciousReceiver, underlyingYieldToken, address(pendleRouterV4ContractGuard))
    );

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      maliciousMarket,
      ptBalanceOfPool,
      IPAllActionTypeV3.createTokenOutputSimple(underlyingYieldToken, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    bytes memory approvePTCalldata = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalanceOfPool);
    testPool.execTransaction(PT, approvePTCalldata);

    vm.expectRevert("invalid market");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);

    // assertEq(IERC20(PT).balanceOf(address(testPool)), 0);
    // assertEq(IERC20(PT).balanceOf(maliciousReceiver), ptBalanceOfPool);
  }

  function test_revert_sell_PT_when_tokenRedeemSy_not_equal_tokenOut() public {
    // First buy some PT tokens
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

    vm.prank(manager);
    testPool.execTransaction(pendleRouterV4, buyPTCalldata);

    uint256 ptBalance = IERC20(PT).balanceOf(address(testPool));

    // Change asset type of underlyingYieldToken to 0 just for the sake of this test
    IAssetHandler assetHandler = IAssetHandler(poolFactoryProxy.getAssetHandler());
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: underlyingYieldToken,
      assetType: 0,
      aggregator: assetHandler.priceAggregators(underlyingYieldToken)
    });
    vm.prank(poolFactoryProxy.owner());
    assetHandler.addAssets(assets);

    vm.startPrank(manager);

    // Remove underlyingYieldToken from supported assets
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = underlyingYieldToken;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    bytes memory approvePTCalldata = abi.encodeWithSelector(IERC20.approve.selector, pendleRouterV4, ptBalance);
    testPool.execTransaction(PT, approvePTCalldata);

    // Set `tokenOut` to any supported asset in the vault (for example USDC) instead of being same as `tokenRedeemSy`, which is set to `underlyingYieldToken`
    IPAllActionTypeV3.TokenOutput memory maliciousTokenOutput = IPAllActionTypeV3.createTokenOutputSimple(
      underlyingYieldToken,
      0
    );
    maliciousTokenOutput.tokenOut = usdcData.asset;

    bytes memory sellPTCalldata = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(testPool),
      pendleMarket,
      ptBalance,
      maliciousTokenOutput,
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    vm.expectRevert("tokenOut mismatch");
    testPool.execTransaction(pendleRouterV4, sellPTCalldata);
  }

  function test_revert_single_asset_withdraw_sandwich_attack_pre_expiry() public {
    // Buy all underlying into PT
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

    _skipWithRoll(1 days);

    uint256 poolManagerBalance = IERC20(address(testPool)).balanceOf(manager);
    uint256 withdrawAmount = poolManagerBalance / 4;

    // Simulate sandwich: mock the PT oracle 20 bps above its real reading
    IAssetHandler ah = IAssetHandler(poolFactoryProxy.getAssetHandler());
    address ptOracle = ah.priceAggregators(PT);
    (, int256 realPtPriceD8, , uint256 realUpdatedAt, ) = IAggregatorV3Interface(ptOracle).latestRoundData();
    vm.mockCall(
      ptOracle,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(uint80(0), (realPtPriceD8 * 10020) / 10000, uint256(0), realUpdatedAt, uint80(0))
    );

    testPool.approve(address(easySwapperV2Proxy), withdrawAmount);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(testPool));

    // Pendle router enforces minTokenOut > actual output → revert.
    vm.expectRevert("Slippage: INSUFFICIENT_TOKEN_OUT");
    easySwapperV2Proxy.initWithdrawal(address(testPool), withdrawAmount, complexAssetsData);

    vm.clearMockedCalls();
  }
}
