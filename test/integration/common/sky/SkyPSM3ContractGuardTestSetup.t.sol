// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {CustomCrossAggregator} from "contracts/priceAggregators/CustomCrossAggregator.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {SkyPSM3ContractGuard} from "contracts/guards/contractGuards/SkyPSM3ContractGuard.sol";
import {IPSM3} from "contracts/interfaces/sky/IPSM3.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract SkyPSM3ContractGuardTestSetup is BackboneSetup {
  address private PSM3;
  IAssetHandler.Asset private usdsData;
  IAssetHandler.Asset private susdsData;
  address private susdsUsdsPriceOracle;
  int256 private usdcPrice;
  int256 private usdsPrice;

  PoolLogic private testPool;
  SkyPSM3ContractGuard private skyPSM3ContractGuard;
  CustomCrossAggregator private susdsPriceOracle;

  constructor(
    address _PSM3,
    IAssetHandler.Asset memory _usdsData,
    IAssetHandler.Asset memory _susdsData,
    address _susdsUsdsPriceOracle
  ) {
    PSM3 = _PSM3;
    usdsData = _usdsData;
    susdsData = _susdsData;
    susdsUsdsPriceOracle = _susdsUsdsPriceOracle;
  }

  function setUp() public virtual override {
    super.setUp();

    (, usdcPrice, , , ) = IAggregatorV3Interface(usdcData.aggregator).latestRoundData();
    (, usdsPrice, , , ) = IAggregatorV3Interface(usdsData.aggregator).latestRoundData();

    // Deploy USDS and sUSDS price oracle
    {
      susdsPriceOracle = new CustomCrossAggregator({
        _token: susdsData.asset,
        _tokenToTokenAggregator: IAggregatorV3Interface(susdsUsdsPriceOracle),
        _tokenToUsdAggregator: IAggregatorV3Interface(usdsData.aggregator)
      });

      susdsData.aggregator = address(susdsPriceOracle);
    }

    vm.startPrank(owner);

    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](2);
    assets[0] = usdsData;
    assets[1] = susdsData;

    assetHandlerProxy.addAssets(assets);

    // Create a test dHEDGE pool with USDC, USDS and sUSDS enabled as deposit asset.
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: usdsData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: susdsData.asset, isDeposit: true});

    vm.startPrank(manager);

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "SkyVault",
        _fundSymbol: "SKY",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );

    deal(usdcData.asset, manager, 10_000e6);
    IERC20(usdcData.asset).approve(address(testPool), 10_000e6);
    testPool.deposit(usdcData.asset, 10_000e6);

    vm.startPrank(owner);

    // Deploy the Sky PSM3 contract guard.
    skyPSM3ContractGuard = new SkyPSM3ContractGuard(address(slippageAccumulator));

    // Set the PSM3 contract guard in the governance contract.
    governance.setContractGuard({extContract: PSM3, guardAddress: address(skyPSM3ContractGuard)});
  }

  function test_revert_swapExactIn_when_receiver_is_not_pool() public {
    vm.startPrank(manager);

    uint256 usdcBalanceOfPoolBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, PSM3, usdcBalanceOfPoolBefore);
    bytes memory swapExactInCallData = abi.encodeWithSelector(
      IPSM3.swapExactIn.selector,
      usdcData.asset,
      wethData.asset,
      10_000e6,
      0,
      manager,
      0
    );
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdcData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: PSM3, data: swapExactInCallData});

    vm.expectRevert("recipient is not pool");
    testPool.execTransactions(txs);
  }

  function test_revert_swapExactIn_when_swapping_to_unsupported_asset() public {
    vm.startPrank(manager);

    uint256 usdcBalanceOfPoolBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, PSM3, usdcBalanceOfPoolBefore);
    bytes memory swapExactInCallData = abi.encodeWithSelector(
      IPSM3.swapExactIn.selector,
      usdcData.asset,
      wethData.asset,
      10_000e6,
      0,
      testPool,
      0
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdcData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: PSM3, data: swapExactInCallData});

    vm.expectRevert("unsupported destination asset");
    testPool.execTransactions(txs);
  }

  function test_revert_swapExactIn_when_susds_unsupported() public {
    vm.startPrank(manager);

    uint256 usdcBalanceOfPoolBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    // remove sUSDS asset from pool
    PoolManagerLogic poolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = address(susdsData.asset);
    poolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, PSM3, usdcBalanceOfPoolBefore);
    bytes memory swapExactInCallData = abi.encodeWithSelector(
      IPSM3.swapExactIn.selector,
      usdcData.asset,
      susdsData.asset,
      10_000e6,
      0,
      testPool,
      0
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdcData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: PSM3, data: swapExactInCallData});

    vm.expectRevert("unsupported destination asset");
    testPool.execTransactions(txs);
  }

  function test_revert_swapExactIn_when_usds_unsupported() public {
    vm.startPrank(manager);

    uint256 usdcBalanceOfPoolBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    // remove USDS asset from pool
    PoolManagerLogic poolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = address(usdsData.asset);
    poolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, PSM3, usdcBalanceOfPoolBefore);
    bytes memory swapExactInCallData = abi.encodeWithSelector(
      IPSM3.swapExactIn.selector,
      usdcData.asset,
      usdsData.asset,
      10_000e6,
      0,
      testPool,
      0
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdcData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: PSM3, data: swapExactInCallData});

    vm.expectRevert("unsupported destination asset");
    testPool.execTransactions(txs);
  }

  function test_swapExactIn_usdc_to_usds_susds_and_back_to_usdc() public {
    vm.startPrank(manager);

    uint256 usdcBalanceOfPoolBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    // swap USDC to USDS
    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, PSM3, usdcBalanceOfPoolBefore);
    bytes memory swapExactInCallData = abi.encodeWithSelector(
      IPSM3.swapExactIn.selector,
      usdcData.asset,
      usdsData.asset,
      10_000e6,
      0,
      testPool,
      0
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdcData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: PSM3, data: swapExactInCallData});

    testPool.execTransactions(txs);

    uint256 usdsBalanceOfPool = IERC20(usdsData.asset).balanceOf(address(testPool));

    assertEq(IERC20(usdcData.asset).balanceOf(address(testPool)), 0, "USDC balance of pool should be 0");
    assertApproxEqAbs(usdsBalanceOfPool, 10_000e18, 1, "USDS balance of pool should be 10_000");
    assertEq(IERC20(susdsData.asset).balanceOf(address(testPool)), 0, "sUSDS balance of pool should be 0");
    // The PSM will exchange USDC to USDS at a rate of 1:1, but the USDS Chainlink oracle will not be 1:1 with USDC
    assertApproxEqRel(testPool.tokenPrice(), 1e18, 1e16, "Token price should be roughly $1");
    assertApproxEqAbs(
      testPool.tokenPrice(),
      (1e18 * uint256(usdsPrice)) / uint256(usdcPrice),
      1,
      "Token price incorrect"
    );
    // get slippage accumulator data
    uint128 cumulativeSlippage = slippageAccumulator.getCumulativeSlippageImpact(address(testPool.poolManagerLogic()));

    if (usdsPrice < usdcPrice) {
      assertGt(uint256(cumulativeSlippage), 0, "Slippage should be greater than 0");
      assertLt(uint256(cumulativeSlippage), 1e4, "Slippage should be less than 1%");
    } else {
      assertEq(uint256(cumulativeSlippage), 0, "Slippage should be 0");
    }

    // swap USDS to sUSDS
    approveCallData = abi.encodeWithSelector(IERC20.approve.selector, PSM3, usdsBalanceOfPool);
    swapExactInCallData = abi.encodeWithSelector(
      IPSM3.swapExactIn.selector,
      usdsData.asset,
      susdsData.asset,
      usdsBalanceOfPool,
      0,
      testPool,
      0
    );

    txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdsData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: PSM3, data: swapExactInCallData});

    testPool.execTransactions(txs);

    uint256 susdsBalanceOfPool;
    {
      (, int256 susdsUsdsPrice, , , ) = susdsPriceOracle.tokenToTokenAggregator().latestRoundData();
      uint8 susdsUsdsOracleDecimals = susdsPriceOracle.tokenToTokenAggregator().decimals();
      uint256 estSusdsBalance = (usdsBalanceOfPool * (10 ** susdsUsdsOracleDecimals)) / uint256(susdsUsdsPrice);
      susdsBalanceOfPool = IERC20(susdsData.asset).balanceOf(address(testPool));
      assertApproxEqAbs(
        IERC20(susdsData.asset).balanceOf(address(testPool)),
        estSusdsBalance,
        1,
        "sUSDS balance of pool should be 10k / oracle rate"
      );
    }

    assertEq(IERC20(usdcData.asset).balanceOf(address(testPool)), 0, "USDC balance of pool should be 0");
    assertEq(IERC20(usdsData.asset).balanceOf(address(testPool)), 0, "USDS balance of pool should be 0");
    assertApproxEqRel(testPool.tokenPrice(), 1e18, 1e16, "Token price should be roughly $1");
    assertApproxEqAbs(
      testPool.tokenPrice(),
      (1e18 * uint256(usdsPrice)) / uint256(usdcPrice),
      1e11, // because of 8 decimal oracle rounding
      "Token price incorrect"
    );

    // get slippage accumulator data
    uint128 cumulativeSlippageNew = slippageAccumulator.getCumulativeSlippageImpact(
      address(testPool.poolManagerLogic())
    );

    assertApproxEqAbs(uint256(cumulativeSlippage), uint256(cumulativeSlippageNew), 1, "Slippage should not change");

    // swap sUSDS back to USDC
    approveCallData = abi.encodeWithSelector(IERC20.approve.selector, PSM3, susdsBalanceOfPool);
    swapExactInCallData = abi.encodeWithSelector(
      IPSM3.swapExactIn.selector,
      susdsData.asset,
      usdcData.asset,
      susdsBalanceOfPool,
      0,
      testPool,
      0
    );

    txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: susdsData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: PSM3, data: swapExactInCallData});

    testPool.execTransactions(txs);

    assertApproxEqAbs(
      IERC20(usdcData.asset).balanceOf(address(testPool)),
      10_000e6,
      1,
      "USDC balance of pool should be 10,000"
    );
    assertEq(IERC20(usdsData.asset).balanceOf(address(testPool)), 0, "USDS balance of pool should be 0");
    assertEq(IERC20(susdsData.asset).balanceOf(address(testPool)), 0, "sUSDS balance of pool should be 0");
    assertApproxEqAbs(
      testPool.tokenPrice(),
      1e18,
      1e11, // because of 8 decimal oracle rounding
      "Token price should be back to $1"
    );

    // get slippage accumulator data
    cumulativeSlippage = slippageAccumulator.getCumulativeSlippageImpact(address(testPool.poolManagerLogic()));

    if (usdsPrice < usdcPrice) {
      assertApproxEqAbs(uint256(cumulativeSlippage), 0, 1e6, "Slippage should be 0");
    } else {
      assertGt(uint256(cumulativeSlippage), 0, "Slippage should be greater than 0");
      assertLt(uint256(cumulativeSlippage), 1e4, "Slippage should be less than 1%");
    }
  }
}
