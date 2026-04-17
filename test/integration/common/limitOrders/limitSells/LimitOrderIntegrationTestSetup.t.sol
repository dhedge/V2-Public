// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolLimitOrderManagerGuard} from "contracts/guards/contractGuards/PoolLimitOrderManagerGuard.sol";
import {EasySwapperV2UnrolledAssetsGuard} from "contracts/guards/assetGuards/EasySwapperV2UnrolledAssetsGuard.sol";
import {IPoolLimitOrderManager} from "contracts/interfaces/IPoolLimitOrderManager.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";

abstract contract LimitOrderIntegrationTestSetup is BackboneSetup {
  uint16 public constant DEFAULT_SLIPPAGE_TOLERANCE = 100; // 1%

  address private keeper = makeAddr("keeper");
  address private testPricingAsset;
  address private testPricingAssetOracle;
  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;
  PoolLogic private testTorosPool;
  PoolLimitOrderManagerGuard private poolLimitOrderManagerGuard;
  EasySwapperV2UnrolledAssetsGuard private easySwapperV2UnrolledAssetsGuard;
  IPoolLimitOrderManager private poolLimitOrderManagerProxy;

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    // Deploy the PoolLimitOrderManager using deployCode cheatcode
    address poolLimitOrderManager = deployCode("PoolLimitOrderManager.sol:PoolLimitOrderManager");
    poolLimitOrderManagerProxy = IPoolLimitOrderManager(
      address(new TransparentUpgradeableProxy(poolLimitOrderManager, proxyAdmin, ""))
    );

    // Initialize PoolLimitOrderManager (using low-level call since we can't import the 0.8.28 contract directly)
    bytes memory txData = abi.encodeWithSignature(
      "initialize(address,address,address,uint16,address)",
      owner, // admin
      address(poolFactoryProxy), // pool factory
      address(easySwapperV2Proxy), // easy swapper
      DEFAULT_SLIPPAGE_TOLERANCE, // 1% default slippage tolerance
      usdcData.asset // settlement token (USDC)
    );
    (bool success, ) = address(poolLimitOrderManagerProxy).call(txData);
    require(success, "PoolLimitOrderManager init failed");
    txData = abi.encodeWithSignature("addAuthorizedKeeper(address)", keeper);
    (success, ) = address(poolLimitOrderManagerProxy).call(txData);
    require(success, "PoolLimitOrderManager call failed");

    // Deploy the PoolLimitOrderManager contract guard
    poolLimitOrderManagerGuard = new PoolLimitOrderManagerGuard();

    // Deploy the EasySwapperV2UnrolledAssetsGuard for asset type 30
    easySwapperV2UnrolledAssetsGuard = new EasySwapperV2UnrolledAssetsGuard(address(poolLimitOrderManagerProxy));

    // Set the PoolLimitOrderManager contract guard in the governance contract
    governance.setContractGuard({
      extContract: address(poolLimitOrderManagerProxy),
      guardAddress: address(poolLimitOrderManagerGuard)
    });

    // Set the asset guard for EasySwapperV2 "asset"
    governance.setAssetGuard(
      uint16(AssetTypeIncomplete.EASYSWAPPER_V2_UNROLLED),
      address(easySwapperV2UnrolledAssetsGuard)
    );

    EasySwapperV2.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2.WhitelistSetting[](1);
    whitelistSettings[0] = EasySwapperV2.WhitelistSetting({
      whitelisted: true,
      toWhitelist: address(poolLimitOrderManagerProxy)
    });
    easySwapperV2Proxy.setAuthorizedWithdrawers(whitelistSettings);

    // Create a test Toros pool first (needed for AssetHandler)
    IHasSupportedAsset.Asset[] memory torosPoolAssets = new IHasSupportedAsset.Asset[](1);
    torosPoolAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    testTorosPool = PoolLogic(
      poolFactoryProxy.createFund(
        false, // private pool
        owner, // manager
        "Test Manager", // manager name
        "Test Toros Pool", // pool name
        "TTP", // pool symbol
        0, // performance fee numerator
        0, // manager fee numerator
        0, // entry fee numerator
        0, // exit fee numerator
        torosPoolAssets // supported assets
      )
    );

    address torosPoolPriceAggregator = deployCode(
      "DHedgePoolAggregator.sol:DHedgePoolAggregator",
      abi.encode(address(testTorosPool))
    );

    // Add EasySwapperV2 as an asset with asset type 30 and the new asset guard
    IAssetHandler.Asset memory easySwapperAsset = IAssetHandler.Asset({
      asset: address(easySwapperV2Proxy),
      assetType: uint16(AssetTypeIncomplete.EASYSWAPPER_V2_UNROLLED),
      aggregator: address(usdPriceAggregator)
    });

    // Add the created Toros pool to asset handler
    IAssetHandler.Asset memory torosPoolAsset = IAssetHandler.Asset({
      asset: address(testTorosPool),
      assetType: uint16(AssetTypeIncomplete.CHAINLINK),
      aggregator: torosPoolPriceAggregator
    });

    IAssetHandler.Asset[] memory assetsToAdd = new IAssetHandler.Asset[](2);
    assetsToAdd[0] = easySwapperAsset;
    assetsToAdd[1] = torosPoolAsset;
    assetHandlerProxy.addAssets(assetsToAdd);

    // Create the main test dHEDGE pool with required assets enabled
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true}); // USDC as deposit asset
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: address(easySwapperV2Proxy), isDeposit: false}); // EasySwapperV2 "asset"
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: address(testTorosPool), isDeposit: true}); // Created Toros pool for limit orders

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "TestManager",
        _fundName: "TestPool",
        _fundSymbol: "TP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );

    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    // Deposit some USDC into the test pools
    _makeDeposit(testTorosPool, owner, usdcData.asset, 10_000e6);
    _makeDeposit(testPool, manager, usdcData.asset, 10_000e6);

    // Give testPool some balance of testTorosPool tokens using deal cheatcode
    deal(address(testTorosPool), address(testPool), 1000e18);

    testPricingAsset = daiData.asset;
    testPricingAssetOracle = daiData.aggregator;

    vm.stopPrank();
  }

  function test_can_create_limit_order_when_required_assets_enabled() public {
    vm.startPrank(manager);

    IPoolLimitOrderManager.LimitOrderInfo memory limitOrderInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 100e18,
      stopLossPriceD18: 1e17, // $0.1
      takeProfitPriceD18: 2e18, // $2.0
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    // Test that the guard validates correctly
    bytes memory callData = abi.encodeWithSelector(IPoolLimitOrderManager.createLimitOrder.selector, limitOrderInfo);

    // Test guard validation
    (uint16 txType, bool isPublic) = poolLimitOrderManagerGuard.txGuard(
      address(testPool.poolManagerLogic()),
      address(poolLimitOrderManagerProxy),
      callData
    );

    assertEq(uint256(txType), 113, "Should return LimitOrderCreate transaction type");
    assertFalse(isPublic, "Should not be public transaction");

    // Execute the transaction through the pool
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](1);
    txs[0] = PoolLogic.TxToExecute({to: address(poolLimitOrderManagerProxy), data: callData});

    testPool.execTransactions(txs);
  }

  function test_can_modify_limit_order_when_required_assets_enabled() public {
    _createLimitOrder();

    vm.startPrank(manager);

    // Now modify the limit order
    IPoolLimitOrderManager.LimitOrderInfo memory modifiedInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 200e18, // Changed amount
      stopLossPriceD18: 5e16, // $0.05 - changed stop loss
      takeProfitPriceD18: 3e18, // $3.0 - changed take profit
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory modifyCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.modifyLimitOrder.selector,
      modifiedInfo
    );

    // This should succeed as all required assets are still enabled
    testPool.execTransaction(address(poolLimitOrderManagerProxy), modifyCallData);
  }

  function test_can_delete_limit_order() public {
    _createLimitOrder();

    vm.startPrank(manager);

    // Now delete the limit order
    bytes memory deleteCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.deleteLimitOrder.selector,
      address(testTorosPool)
    );

    // This should succeed
    testPool.execTransaction(address(poolLimitOrderManagerProxy), deleteCallData);
  }

  function test_revert_create_limit_order_when_easyswapperv2_not_supported() public {
    vm.startPrank(manager);

    // Remove EasySwapperV2 asset from pool
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = address(easySwapperV2Proxy);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    IPoolLimitOrderManager.LimitOrderInfo memory limitOrderInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 100e18,
      stopLossPriceD18: 1e17, // $0.1
      takeProfitPriceD18: 2e18, // $2.0
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory callData = abi.encodeWithSelector(IPoolLimitOrderManager.createLimitOrder.selector, limitOrderInfo);

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(address(poolLimitOrderManagerProxy), callData);
  }

  function test_revert_create_limit_order_when_settlement_token_not_supported() public {
    vm.startPrank(manager);

    // Remove settlement token from pool
    deal(usdcData.asset, address(testPool), 0);
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = usdcData.asset;
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    IPoolLimitOrderManager.LimitOrderInfo memory limitOrderInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 100e18,
      stopLossPriceD18: 1e17, // $0.1
      takeProfitPriceD18: 2e18, // $2.0
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory callData = abi.encodeWithSelector(IPoolLimitOrderManager.createLimitOrder.selector, limitOrderInfo);

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(address(poolLimitOrderManagerProxy), callData);
  }

  function test_revert_create_limit_order_when_toros_pool_not_supported() public {
    vm.startPrank(manager);

    // Remove Toros pool from supported assets
    deal(address(testTorosPool), address(testPool), 0);
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = address(testTorosPool);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    IPoolLimitOrderManager.LimitOrderInfo memory limitOrderInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 100e18,
      stopLossPriceD18: 1e17, // $0.1
      takeProfitPriceD18: 2e18, // $2.0
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory callData = abi.encodeWithSelector(IPoolLimitOrderManager.createLimitOrder.selector, limitOrderInfo);

    vm.expectRevert("unsupported source asset");
    testPool.execTransaction(address(poolLimitOrderManagerProxy), callData);
  }

  function test_revert_modify_limit_order_when_easyswapperv2_not_supported() public {
    vm.startPrank(manager);

    // Now remove EasySwapperV2 asset from pool
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = address(easySwapperV2Proxy);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    // Try to modify the limit order
    IPoolLimitOrderManager.LimitOrderInfo memory modifiedInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 200e18,
      stopLossPriceD18: 5e16,
      takeProfitPriceD18: 3e18,
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory modifyCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.modifyLimitOrder.selector,
      modifiedInfo
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(address(poolLimitOrderManagerProxy), modifyCallData);
  }

  function test_revert_modify_limit_order_when_settlement_token_not_supported() public {
    _createLimitOrder();

    vm.startPrank(manager);

    // Now remove settlement token from pool
    deal(usdcData.asset, address(testPool), 0);
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = usdcData.asset;
    // Below we check that settlement token (USDC) cannot be removed when there is an open order
    vm.expectRevert("has open order");
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);
    // After we made sure removing USDC reverts, we add the mock call so that it becomes possible to remove USDC, to check further reverts work
    vm.mockCall(address(governance), abi.encodeWithSignature("assetGuards(uint16)", 30), abi.encode(address(0)));
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    // Try to modify the limit order
    IPoolLimitOrderManager.LimitOrderInfo memory modifiedInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 200e18,
      stopLossPriceD18: 5e16,
      takeProfitPriceD18: 3e18,
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory modifyCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.modifyLimitOrder.selector,
      modifiedInfo
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(address(poolLimitOrderManagerProxy), modifyCallData);
  }

  function test_revert_modify_limit_order_when_toros_pool_not_supported() public {
    _createLimitOrder();

    vm.startPrank(manager);

    // Now remove Toros pool from supported assets
    deal(address(testTorosPool), address(testPool), 0);
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = address(testTorosPool);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    // Try to modify the limit order
    IPoolLimitOrderManager.LimitOrderInfo memory modifiedInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 200e18,
      stopLossPriceD18: 5e16,
      takeProfitPriceD18: 3e18,
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory modifyCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.modifyLimitOrder.selector,
      modifiedInfo
    );

    vm.expectRevert("unsupported source asset");
    testPool.execTransaction(address(poolLimitOrderManagerProxy), modifyCallData);
  }

  function test_revert_unsupported_function_call() public {
    vm.startPrank(manager);

    // Try to call an unsupported function (should return txType 0 and fail)
    bytes memory invalidCallData = abi.encodeWithSignature("unsupportedFunction()");

    vm.expectRevert(bytes("dh23")); // Transaction type not supported
    testPool.execTransaction(address(poolLimitOrderManagerProxy), invalidCallData);
  }

  function test_revert_when_remove_easyswapperv2_after_order_created() public {
    _createLimitOrder();

    address[] memory removeAssets = new address[](1);
    removeAssets[0] = address(easySwapperV2Proxy);
    vm.prank(manager);
    vm.expectRevert("limit order opened");
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);
  }

  function test_revert_execute_order_when_settlement_token_not_supported() public {
    _approveLimitOrderContract();

    _createLimitOrder();

    _setPricingAssetPriceD8(3e8); // Set price to $3.0 to trigger take profit

    uint256 testPoolValueBefore = testPoolManagerLogic.totalFundValue();

    IPoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new IPoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    limitOrders[0] = IPoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(address(testPool), address(testTorosPool)),
      complexAssetsData: _getPoolComplexAssetsData(address(testTorosPool)),
      amount: type(uint256).max
    });

    vm.prank(keeper);
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    uint256 testPoolValueAfter = testPoolManagerLogic.totalFundValue();
    // This assertion checks that accounting in EasySwapperV2UnrolledAssetsGuard::getBalance is ok
    assertApproxEqRel(
      testPoolValueAfter,
      testPoolValueBefore,
      0.000001e18, // 0.0001%
      "Value should not change after limit order execution"
    );

    // Now remove settlement token from pool
    deal(usdcData.asset, address(testPool), 0);
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = usdcData.asset;
    vm.prank(manager);
    // Below we check that settlement token (USDC) cannot be removed when there is an open order
    vm.expectRevert("has open order");
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);
    // After we made sure removing USDC reverts, we add the mock call so that it becomes possible to remove USDC, to check further reverts work
    vm.mockCall(address(governance), abi.encodeWithSignature("assetGuards(uint16)", 30), abi.encode(address(0)));
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);

    IWithdrawalVault.MultiInSingleOutData memory swapData;
    swapData.destData.destToken = IERC20(usdcData.asset);
    IPoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new IPoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = IPoolLimitOrderManager.SettlementOrderExecution({user: address(testPool), swapData: swapData});

    // These assertions test revert checks for dhedge vaults added to EasySwapperV2::completeLimitOrderWithdrawalFor
    // Case when settlement order is settled to settlement token (USDC) which is not supported by the vault
    vm.prank(keeper);
    vm.expectRevert("dst token disabled");
    poolLimitOrderManagerProxy.executeSettlementOrders(orders);

    // Case when anyone can claim tokens on bahalf of the dhedge vault but underlying tokens are not supported by the vault
    vm.prank(dao);
    vm.expectRevert("dst token disabled");
    easySwapperV2Proxy.completeLimitOrderWithdrawalFor(address(testPool));
  }

  function test_can_withdraw_from_vault_after_order_executed() public {
    _approveLimitOrderContract();

    _createLimitOrder();

    _setPricingAssetPriceD8(3e8); // Set price to $3.0 to trigger take profit

    IPoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new IPoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    limitOrders[0] = IPoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(address(testPool), address(testTorosPool)),
      complexAssetsData: _getPoolComplexAssetsData(address(testTorosPool)),
      amount: type(uint256).max
    });

    vm.prank(keeper);
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    // Now test vault holds some balance in its WithdrawalVault, e.g. "EasySwapperV2 asset"
    uint256 testPoolValueBeforeWithdrawal = testPoolManagerLogic.totalFundValue();
    uint256 vaultTokensBalance = testPool.balanceOf(manager);
    address withdrawalVault = easySwapperV2Proxy.limitOrderContracts(address(testPool));
    uint256 usdcManagerBalanceBefore = IERC20(usdcData.asset).balanceOf(manager);
    uint256 usdcVaultBalance = IERC20(usdcData.asset).balanceOf(withdrawalVault);
    assertGt(usdcVaultBalance, 0, "Vault should hold some USDC after limit order execution");

    skip(1 days);
    vm.startPrank(manager);
    testPool.withdrawSafe(vaultTokensBalance / 2, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 vaultTokenBalanceAfter = testPool.balanceOf(manager);
    uint256 testPoolValueAfterWithdrawal = testPoolManagerLogic.totalFundValue();
    uint256 usdcManagerBalanceAfter = IERC20(usdcData.asset).balanceOf(manager);
    uint256 usdcVaultBalanceAfter = IERC20(usdcData.asset).balanceOf(withdrawalVault);
    assertEq(
      vaultTokenBalanceAfter,
      vaultTokensBalance / 2,
      "Depositor should be able to withdraw tokens after limit order execution"
    );
    assertEq(testPoolValueAfterWithdrawal, testPoolValueBeforeWithdrawal / 2, "Pool value should decrease accordingly");
    assertEq(usdcVaultBalanceAfter, usdcVaultBalance / 2, "Vault USDC balance should be zero after withdrawal");
    assertGt(
      usdcManagerBalanceAfter,
      usdcManagerBalanceBefore,
      "Manager USDC balance should increase after withdrawal"
    );
  }

  function test_hasOpenLimitOrder_returns_true_after_create() public {
    // Before creating order, user should have no open orders
    assertFalse(
      poolLimitOrderManagerProxy.hasOpenLimitOrder(address(testPool)),
      "Should have no open orders before create"
    );

    _createLimitOrder();

    // After creating order, user should have open order
    assertTrue(poolLimitOrderManagerProxy.hasOpenLimitOrder(address(testPool)), "Should have open order after create");
  }

  function test_hasOpenLimitOrder_returns_false_after_delete() public {
    _createLimitOrder();

    assertTrue(poolLimitOrderManagerProxy.hasOpenLimitOrder(address(testPool)), "Should have open order after create");

    // Delete the order
    bytes memory deleteCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.deleteLimitOrder.selector,
      address(testTorosPool)
    );
    vm.prank(manager);
    testPool.execTransaction(address(poolLimitOrderManagerProxy), deleteCallData);

    // After deleting, user should have no open orders
    assertFalse(
      poolLimitOrderManagerProxy.hasOpenLimitOrder(address(testPool)),
      "Should have no open orders after delete"
    );
  }

  function test_getUserLimitOrderIds_returns_correct_order_ids() public {
    // Before creating order, user should have empty array
    bytes32[] memory orderIdsBefore = poolLimitOrderManagerProxy.getUserLimitOrderIds(address(testPool));
    assertEq(orderIdsBefore.length, 0, "Should have no order IDs before create");

    _createLimitOrder();

    // After creating order, user should have one order ID
    bytes32[] memory orderIdsAfter = poolLimitOrderManagerProxy.getUserLimitOrderIds(address(testPool));
    assertEq(orderIdsAfter.length, 1, "Should have one order ID after create");

    bytes32 expectedOrderId = _getLimitOrderId(address(testPool), address(testTorosPool));
    assertEq(orderIdsAfter[0], expectedOrderId, "Order ID should match expected");
  }

  function test_getUserLimitOrderIds_updates_after_delete() public {
    _createLimitOrder();

    bytes32[] memory orderIdsAfterCreate = poolLimitOrderManagerProxy.getUserLimitOrderIds(address(testPool));
    assertEq(orderIdsAfterCreate.length, 1, "Should have one order ID after create");

    // Delete the order
    bytes memory deleteCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.deleteLimitOrder.selector,
      address(testTorosPool)
    );
    vm.prank(manager);
    testPool.execTransaction(address(poolLimitOrderManagerProxy), deleteCallData);

    // After deleting, user should have empty array
    bytes32[] memory orderIdsAfterDelete = poolLimitOrderManagerProxy.getUserLimitOrderIds(address(testPool));
    assertEq(orderIdsAfterDelete.length, 0, "Should have no order IDs after delete");
  }

  function test_getUserLimitOrderIds_updates_after_order_execution() public {
    _approveLimitOrderContract();
    _createLimitOrder();

    bytes32[] memory orderIdsAfterCreate = poolLimitOrderManagerProxy.getUserLimitOrderIds(address(testPool));
    assertEq(orderIdsAfterCreate.length, 1, "Should have one order ID after create");

    _setPricingAssetPriceD8(3e8); // Set price to $3.0 to trigger take profit

    IPoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new IPoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    limitOrders[0] = IPoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(address(testPool), address(testTorosPool)),
      complexAssetsData: _getPoolComplexAssetsData(address(testTorosPool)),
      amount: type(uint256).max
    });

    vm.prank(keeper);
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    // After full execution, user should have no order IDs
    bytes32[] memory orderIdsAfterExec = poolLimitOrderManagerProxy.getUserLimitOrderIds(address(testPool));
    assertEq(orderIdsAfterExec.length, 0, "Should have no order IDs after full execution");

    // hasOpenLimitOrder should also return false
    assertFalse(
      poolLimitOrderManagerProxy.hasOpenLimitOrder(address(testPool)),
      "Should have no open orders after execution"
    );
  }

  function _createLimitOrder() internal {
    IPoolLimitOrderManager.LimitOrderInfo memory limitOrderInfo = IPoolLimitOrderManager.LimitOrderInfo({
      amount: 100e18,
      stopLossPriceD18: 1e17, // $0.1
      takeProfitPriceD18: 2e18, // $2.0
      user: address(testPool),
      pool: address(testTorosPool),
      pricingAsset: testPricingAsset
    });

    bytes memory createCallData = abi.encodeWithSelector(
      IPoolLimitOrderManager.createLimitOrder.selector,
      limitOrderInfo
    );

    vm.prank(manager);
    testPool.execTransaction(address(poolLimitOrderManagerProxy), createCallData);
  }

  function _approveLimitOrderContract() internal {
    // First approve toros vault tokens to PoolLimitOrderManager contract so that orders can be executed
    bytes memory approveCallData = abi.encodeWithSelector(
      IPoolLogic.approve.selector,
      address(poolLimitOrderManagerProxy),
      100e18
    );
    vm.prank(manager);
    testPool.execTransaction(address(testTorosPool), approveCallData);
  }

  function _setPricingAssetPriceD8(uint256 _priceD8) internal {
    vm.mockCall(
      testPricingAssetOracle,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, _priceD8, 0, type(uint128).max, 0)
    );
  }

  function _getLimitOrderId(address _user, address _pool) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_user, _pool));
  }

  function _getPoolComplexAssetsData(
    address _pool
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();
    complexAssetsData = new IPoolLogic.ComplexAsset[](IHasSupportedAsset(poolManagerLogic).getSupportedAssets().length);
    for (uint256 i; i < complexAssetsData.length; ++i) {
      complexAssetsData[i].slippageTolerance = DEFAULT_SLIPPAGE_TOLERANCE;
    }
  }
}
