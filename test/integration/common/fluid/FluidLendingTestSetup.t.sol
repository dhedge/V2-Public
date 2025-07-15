// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {FluidTokenAssetGuard} from "contracts/guards/assetGuards/fluid/FluidTokenAssetGuard.sol";
import {FluidTokenContractGuard} from "contracts/guards/contractGuards/fluid/FluidTokenContractGuard.sol";
import {FluidTokenPriceAggregator} from "contracts/priceAggregators/FluidTokenPriceAggregator.sol";
import {IPoolFactory} from "contracts/interfaces/IPoolFactory.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IFToken} from "contracts/interfaces/fluid/IFToken.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract FluidLendingTestSetup is BackboneSetup {
  address private immutable fluidWETH;
  address private immutable fluidUSDC;

  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;

  constructor(address _fluidWETH, address _fluidUSDC) {
    fluidWETH = _fluidWETH;
    fluidUSDC = _fluidUSDC;
  }

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    FluidTokenContractGuard fluidTokenContractGuard = new FluidTokenContractGuard();
    governance.setContractGuard({extContract: fluidWETH, guardAddress: address(fluidTokenContractGuard)});
    governance.setContractGuard({extContract: fluidUSDC, guardAddress: address(fluidTokenContractGuard)});

    FluidTokenAssetGuard fluidTokenAssetGuard = new FluidTokenAssetGuard();
    governance.setAssetGuard({
      assetType: uint16(AssetTypeIncomplete.FLUID_TOKEN),
      guardAddress: address(fluidTokenAssetGuard)
    });

    FluidTokenPriceAggregator fluidWethOracle = new FluidTokenPriceAggregator(
      IFToken(fluidWETH),
      IPoolFactory(address(poolFactoryProxy))
    );

    FluidTokenPriceAggregator fluidUsdcOracle = new FluidTokenPriceAggregator(
      IFToken(fluidUSDC),
      IPoolFactory(address(poolFactoryProxy))
    );

    IAssetHandler.Asset[] memory fluidTokensToAdd = new IAssetHandler.Asset[](2);
    fluidTokensToAdd[0] = IAssetHandler.Asset({
      asset: fluidWETH,
      assetType: uint16(AssetTypeIncomplete.FLUID_TOKEN),
      aggregator: address(fluidWethOracle)
    });
    fluidTokensToAdd[1] = IAssetHandler.Asset({
      asset: fluidUSDC,
      assetType: uint16(AssetTypeIncomplete.FLUID_TOKEN),
      aggregator: address(fluidUsdcOracle)
    });

    assetHandlerProxy.addAssets(fluidTokensToAdd);

    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](4);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: fluidWETH, isDeposit: true});
    supportedAssets[3] = IHasSupportedAsset.Asset({asset: fluidUSDC, isDeposit: true});

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "FluidLendingTest",
        _fundSymbol: "FLT",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    deal(wethData.asset, manager, 10e18);
    IERC20(wethData.asset).approve(address(testPool), 10e18);
    testPool.deposit(wethData.asset, 10e18);

    deal(usdcData.asset, manager, 10000e6);
    IERC20(usdcData.asset).approve(address(testPool), 10000e6);
    testPool.deposit(usdcData.asset, 10000e6);
  }

  function test_can_deposit_and_receive_fluid_token_USDC() public {
    _test_can_deposit_and_receive_fluid_token(usdcData.asset, fluidUSDC);
  }

  function test_can_deposit_and_receive_fluid_token_WETH() public {
    _test_can_deposit_and_receive_fluid_token(wethData.asset, fluidWETH);
  }

  function test_can_redeem_fluid_token_and_receive_underlying_asset_USDC() public {
    _test_can_redeem_fluid_token_and_receive_underlying_asset(usdcData.asset, fluidUSDC);
  }

  function test_can_redeem_fluid_token_and_receive_underlying_asset_WETH() public {
    _test_can_redeem_fluid_token_and_receive_underlying_asset(wethData.asset, fluidWETH);
  }

  function test_can_withdraw_fluid_token_and_receive_underlying_asset_USDC() public {
    _test_can_withdraw_fluid_token_and_receive_underlying_asset(usdcData.asset, fluidUSDC);
  }

  function test_can_withdraw_fluid_token_and_receive_underlying_asset_WETH() public {
    _test_can_withdraw_fluid_token_and_receive_underlying_asset(wethData.asset, fluidWETH);
  }

  function test_revert_deposit_when_fluid_token_not_supported() public {
    vm.startPrank(manager);

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = address(fluidWETH);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    uint256 wethBalanceOfPoolBefore = IERC20(wethData.asset).balanceOf(address(testPool));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, fluidWETH, wethBalanceOfPoolBefore);
    bytes memory depositCallData = abi.encodeWithSelector(
      IFToken.deposit.selector,
      wethBalanceOfPoolBefore,
      address(testPool)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: wethData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: fluidWETH, data: depositCallData});

    vm.expectRevert("unsupported destination asset");
    testPool.execTransactions(txs);
  }

  function test_revert_deposit_when_receiver_not_pool() public {
    vm.startPrank(manager);

    uint256 wethBalanceOfPoolBefore = IERC20(wethData.asset).balanceOf(address(testPool));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, fluidWETH, wethBalanceOfPoolBefore);
    bytes memory depositCallData = abi.encodeWithSelector(IFToken.deposit.selector, wethBalanceOfPoolBefore, manager);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: wethData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: fluidWETH, data: depositCallData});

    vm.expectRevert("recipient is not pool");
    testPool.execTransactions(txs);
  }

  function test_revert_redeem_when_underlying_not_supported() public {
    _deposit_underlying_asset(wethData.asset, fluidWETH);

    uint256 fTokenBalanceOfPoolBefore = IFToken(fluidWETH).balanceOf(address(testPool));

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = wethData.asset;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    bytes memory redeemCallData = abi.encodeWithSelector(
      IFToken.redeem.selector,
      fTokenBalanceOfPoolBefore,
      address(testPool),
      address(testPool)
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(fluidWETH, redeemCallData);
  }

  function test_revert_redeem_when_receiver_not_pool() public {
    vm.startPrank(manager);

    bytes memory redeemCallData = abi.encodeWithSelector(IFToken.redeem.selector, 0, manager, address(testPool));

    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(fluidWETH, redeemCallData);

    redeemCallData = abi.encodeWithSelector(IFToken.redeem.selector, 0, address(testPool), manager);

    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(fluidWETH, redeemCallData);
  }

  function test_can_withdraw_from_pool_with_fluid_token_USDC() public {
    _test_can_withdraw_from_pool_with_fluid_token(usdcData.asset, fluidUSDC);
  }

  function test_can_withdraw_from_pool_with_fluid_token_WETH() public {
    _test_can_withdraw_from_pool_with_fluid_token(wethData.asset, fluidWETH);
  }

  /* Internal functions */

  function _test_can_deposit_and_receive_fluid_token(address _underlying, address _fToken) internal {
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 underlyingBalanceOfPoolBeforeDeposit = _deposit_underlying_asset(_underlying, _fToken);
    uint256 projectedFTokenBalance = IFToken(_fToken).convertToShares(underlyingBalanceOfPoolBeforeDeposit);

    uint256 underlyingBalanceOfPoolAfter = IERC20(_underlying).balanceOf(address(testPool));
    uint256 fTokenBalanceOfPoolAfter = IFToken(_fToken).balanceOf(address(testPool));
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();

    assertEq(underlyingBalanceOfPoolAfter, 0, "Underlying balance of pool should be 0 after deposit");
    assertEq(fTokenBalanceOfPoolAfter, projectedFTokenBalance, "Fluid token balance should match projected balance");
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore,
      0.0001e18,
      "Total value should be approximately the same after deposit"
    );
  }

  function _test_can_redeem_fluid_token_and_receive_underlying_asset(address _underlying, address _fToken) internal {
    uint256 underlyingBalanceOfPoolBeforeDeposit = _deposit_underlying_asset(_underlying, _fToken);

    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 fTokenBalanceOfPoolBefore = IFToken(_fToken).balanceOf(address(testPool));

    bytes memory redeemCallData = abi.encodeWithSelector(
      IFToken.redeem.selector,
      fTokenBalanceOfPoolBefore,
      address(testPool),
      address(testPool)
    );

    testPool.execTransaction(_fToken, redeemCallData);

    uint256 underlyingBalanceOfPoolAfter = IERC20(_underlying).balanceOf(address(testPool));
    uint256 fTokenBalanceOfPoolAfter = IFToken(_fToken).balanceOf(address(testPool));
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();

    assertApproxEqAbs(
      underlyingBalanceOfPoolAfter,
      underlyingBalanceOfPoolBeforeDeposit,
      1,
      "Pool balance of underlying should be the same after redeem"
    );
    assertEq(fTokenBalanceOfPoolAfter, 0, "Fluid token balance of pool should be 0 after redeem");
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore,
      0.0001e18,
      "Total value should be approximately the same after redeem"
    );
  }

  function _test_can_withdraw_fluid_token_and_receive_underlying_asset(address _underlying, address _fToken) internal {
    uint256 underlyingBalanceOfPoolBeforeDeposit = _deposit_underlying_asset(_underlying, _fToken);

    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 fTokenBalanceOfPoolBefore = IFToken(_fToken).balanceOf(address(testPool));
    uint256 underlyingToReceive = IFToken(_fToken).convertToAssets(fTokenBalanceOfPoolBefore);

    bytes memory withdrawCallData = abi.encodeWithSelector(
      IFToken.withdraw.selector,
      underlyingToReceive,
      address(testPool),
      address(testPool)
    );

    testPool.execTransaction(_fToken, withdrawCallData);

    uint256 underlyingBalanceOfPoolAfter = IERC20(_underlying).balanceOf(address(testPool));
    uint256 fTokenBalanceOfPoolAfter = IFToken(_fToken).balanceOf(address(testPool));
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();

    assertApproxEqAbs(
      underlyingBalanceOfPoolAfter,
      underlyingBalanceOfPoolBeforeDeposit,
      1,
      "Pool balance of underlying should be the same after redeem"
    );
    assertEq(fTokenBalanceOfPoolAfter, 0, "Fluid token balance of pool should be 0 after redeem");
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore,
      0.0001e18,
      "Total value should be approximately the same after redeem"
    );
  }

  function _test_can_withdraw_from_pool_with_fluid_token(address _underlying, address _fToken) internal {
    _deposit_underlying_asset(_underlying, _fToken);

    skip(1 days);

    uint256 poolTokensBefore = testPool.balanceOf(manager);
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 underlyingBalanceBefore = IERC20(_underlying).balanceOf(manager);
    uint256 fTokenBalanceOfPoolBefore = IFToken(_fToken).balanceOf(address(testPool));
    uint256 potentialUnderlyingBalanceOfPool = IFToken(_fToken).convertToAssets(fTokenBalanceOfPoolBefore);

    assertEq(underlyingBalanceBefore, 0, "User underlying balance should be 0 before withdraw");

    testPool.withdraw(poolTokensBefore / 2);

    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 underlyingBalanceAfter = IERC20(_underlying).balanceOf(manager);
    uint256 fTokenBalanceOfPoolAfter = IFToken(_fToken).balanceOf(address(testPool));

    assertApproxEqAbs(
      underlyingBalanceAfter,
      potentialUnderlyingBalanceOfPool / 2,
      1,
      "User underlying balance should match withdraw"
    );
    assertApproxEqAbs(
      fTokenBalanceOfPoolAfter,
      fTokenBalanceOfPoolBefore / 2,
      1,
      "Fluid token balance of pool should be half after withdraw"
    );
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.0001e18,
      "Total value should be approximately half after withdraw"
    );
  }

  function _deposit_underlying_asset(
    address _underlying,
    address _fToken
  ) internal returns (uint256 underlyingBalanceOfPoolBeforeDeposit) {
    vm.startPrank(manager);

    underlyingBalanceOfPoolBeforeDeposit = IERC20(_underlying).balanceOf(address(testPool));

    bytes memory approveCallData = abi.encodeWithSelector(
      IERC20.approve.selector,
      _fToken,
      underlyingBalanceOfPoolBeforeDeposit
    );
    bytes memory depositCallData = abi.encodeWithSelector(
      IFToken.deposit.selector,
      underlyingBalanceOfPoolBeforeDeposit,
      address(testPool)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: _underlying, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: _fToken, data: depositCallData});

    testPool.execTransactions(txs);
  }
}
