// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/v5/contracts/proxy/transparent/ProxyAdmin.sol";

import {PoolLimitOrderManager} from "contracts/limitOrders/PoolLimitOrderManager.sol";
import {IEasySwapperV2} from "contracts/swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IPoolFactory} from "contracts/interfaces/IPoolFactory.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";

import {EasySwapperV2Mock, IEasySwapperV2Mock} from "./IEasySwapperV2Mock.sol";
import {IPoolFactoryMock, IHasSupportedAssetMock} from "./IPoolFactoryMock.sol";
import {IAssetHandlerMock} from "./IAssetHandlerMock.sol";

abstract contract PoolLimitOrderManagerTestSetup is Test {
  uint16 public constant DEFAULT_SLIPPAGE_TOLERANCE = 100; // 1%
  uint256 public constant AMOUNT_DEPOSITED = 10000e18;

  address public owner = makeAddr("owner");
  address public keeper = makeAddr("keeper");
  address public user = makeAddr("user");

  address public proxyAdmin;
  address public withdrawalVault;
  address public easySwapperV2;
  IEasySwapperV2Mock public easySwapperV2Proxy;
  address public poolLimitOrderManager;
  PoolLimitOrderManager public poolLimitOrderManagerProxy;

  address public weth;
  address public wnt;
  address public swapper;
  address public poolFactory;
  address public usdc;
  address public pool;
  address public secondPool;
  address public pricingAsset;
  address public pricingAssetOracle;

  constructor(
    address _weth,
    address _wnt,
    address _swapper,
    address _poolFactory,
    address _usdc,
    address _pool,
    address _secondPool,
    address _pricingAsset,
    address _pricingAssetOracle
  ) {
    weth = _weth;
    wnt = _wnt;
    swapper = _swapper;
    poolFactory = _poolFactory;
    usdc = _usdc;
    pool = _pool;
    secondPool = _secondPool;
    pricingAsset = _pricingAsset;
    pricingAssetOracle = _pricingAssetOracle;
  }

  function setUp() public virtual {
    vm.startPrank(owner);

    proxyAdmin = address(new ProxyAdmin(owner));
    withdrawalVault = deployCode("WithdrawalVault.sol:WithdrawalVault");
    easySwapperV2 = deployCode("EasySwapperV2.sol:EasySwapperV2");

    // It's not necessary to deploy contracts as upgradeable proxies as we are not testing upgradeability
    easySwapperV2Proxy = IEasySwapperV2Mock(address(new TransparentUpgradeableProxy(easySwapperV2, proxyAdmin, "")));
    easySwapperV2Proxy.initialize(withdrawalVault, weth, wnt, swapper, 3600);
    easySwapperV2Proxy.setdHedgePoolFactory(poolFactory);

    poolLimitOrderManager = address(new PoolLimitOrderManager());
    poolLimitOrderManagerProxy = PoolLimitOrderManager(
      address(new TransparentUpgradeableProxy(poolLimitOrderManager, proxyAdmin, ""))
    );
    poolLimitOrderManagerProxy.initialize(
      owner,
      IPoolFactory(poolFactory),
      IEasySwapperV2(address(easySwapperV2Proxy)),
      DEFAULT_SLIPPAGE_TOLERANCE,
      usdc
    );
    poolLimitOrderManagerProxy.addAuthorizedKeeper(keeper);

    EasySwapperV2Mock.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2Mock.WhitelistSetting[](1);
    whitelistSettings[0] = EasySwapperV2Mock.WhitelistSetting({
      whitelisted: true,
      toWhitelist: address(poolLimitOrderManagerProxy)
    });
    easySwapperV2Proxy.setAuthorizedWithdrawers(whitelistSettings);

    vm.stopPrank();

    // Doesn't change totalSupply hence doesn't affect token price. Afaiu can be safely used instead of describing deposit flow
    deal(pool, user, AMOUNT_DEPOSITED);
    deal(secondPool, user, AMOUNT_DEPOSITED);

    _setPricingAssetPriceD8(1000e8);
  }

  // ============================================
  // Create Limit Order Tests
  // ============================================

  function test_can_create_take_profit_limit_order() public {
    vm.prank(user);
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();

    assertEq(limitOrderIds.length, 1);
    assertEq(limitOrderIds[0], _getLimitOrderId(user, pool));
  }

  function test_can_create_stop_loss_limit_order() public {
    vm.prank(user);
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: type(uint256).max,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();

    assertEq(limitOrderIds.length, 1);
    assertEq(limitOrderIds[0], _getLimitOrderId(user, pool));
  }

  function test_can_create_both_stop_loss_and_take_profit_limit_order() public {
    vm.prank(user);
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();

    assertEq(limitOrderIds.length, 1);
    assertEq(limitOrderIds[0], _getLimitOrderId(user, pool));
  }

  function test_revert_create_limit_order_if_already_exists() public {
    vm.startPrank(user);
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderAlreadyExists.selector, user, pool));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: type(uint256).max,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
  }

  function test_revert_create_limit_order_if_invalid_prices() public {
    vm.startPrank(user);

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidPrices.selector, 800e18, 0, 1000e18));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 0,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    vm.expectRevert(
      abi.encodeWithSelector(PoolLimitOrderManager.InvalidPrices.selector, type(uint256).max, 1200e18, 1000e18)
    );
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: type(uint256).max,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidPrices.selector, 0, 0, 1000e18));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 0,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        PoolLimitOrderManager.InvalidPrices.selector,
        type(uint256).max,
        type(uint256).max,
        1000e18
      )
    );
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: type(uint256).max,
        takeProfitPriceD18: type(uint256).max,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
  }

  function test_revert_create_limit_order_if_user_not_sender() public {
    vm.startPrank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidValue.selector, "user"));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
  }

  function test_revert_create_limit_order_if_not_pool() public {
    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidPool.selector, swapper));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: swapper,
        pricingAsset: pricingAsset
      })
    );
  }

  function test_revert_create_limit_order_if_not_enough_balance() public {
    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidValue.selector, "amount"));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: type(uint128).max,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidValue.selector, "amount"));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 0,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
  }

  function test_revert_create_limit_order_if_invalid_pricing_asset() public {
    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidAsset.selector, swapper));
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: swapper
      })
    );
  }

  // ============================================
  // Modify Limit Order Tests
  // ============================================

  function test_can_modify_limit_order() public {
    vm.startPrank(user);
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    poolLimitOrderManagerProxy.modifyLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 2000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: type(uint256).max,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();
    (uint256 amount, uint256 stopLossPriceD18, uint256 takeProfitPriceD18, , , ) = poolLimitOrderManagerProxy
      .limitOrders(_getLimitOrderId(user, pool));

    assertEq(limitOrderIds.length, 1);
    assertEq(amount, 2000e18);
    assertEq(stopLossPriceD18, 800e18);
    assertEq(takeProfitPriceD18, type(uint256).max);
  }

  function test_revert_modify_limit_order_if_not_exists() public {
    vm.prank(user);
    vm.expectRevert(
      abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFound.selector, _getLimitOrderId(user, pool))
    );
    poolLimitOrderManagerProxy.modifyLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 2000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: type(uint256).max,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
  }

  // ============================================
  // Delete Limit Order Tests
  // ============================================

  function test_can_delete_limit_order() public {
    vm.startPrank(user);
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    poolLimitOrderManagerProxy.deleteLimitOrder(pool);

    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();
    (uint256 amount, uint256 stopLossPriceD18, uint256 takeProfitPriceD18, , , ) = poolLimitOrderManagerProxy
      .limitOrders(_getLimitOrderId(user, pool));

    assertEq(limitOrderIds.length, 0);
    assertEq(amount, 0);
    assertEq(stopLossPriceD18, 0);
    assertEq(takeProfitPriceD18, 0);
  }

  function test_revert_delete_limit_order_if_not_exists() public {
    vm.prank(user);
    vm.expectRevert(
      abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFound.selector, _getLimitOrderId(user, pool))
    );
    poolLimitOrderManagerProxy.deleteLimitOrder(pool);
  }

  // ============================================
  // Delete Multiple Limit Orders Tests
  // ============================================

  function test_can_delete_limit_order_if_user_has_zero_balance() public {
    vm.startPrank(user);

    IERC20(pool).approve(address(poolLimitOrderManagerProxy), type(uint256).max);

    // Create a limit order
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    vm.stopPrank();

    // Set user's balance to zero
    deal(pool, user, 0);

    // Allowance is properly set
    assertGt(IERC20(pool).allowance(user, address(poolLimitOrderManagerProxy)), 1000e18);

    bytes32[] memory orderIdsToDelete = new bytes32[](1);
    orderIdsToDelete[0] = _getLimitOrderId(user, pool);

    // Order should be deletable because user has zero balance
    vm.prank(keeper);
    poolLimitOrderManagerProxy.deleteLimitOrders(orderIdsToDelete);

    // Verify the order was deleted
    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();
    assertEq(limitOrderIds.length, 0);
  }

  function test_can_delete_limit_order_if_user_has_zero_allowance() public {
    vm.startPrank(user);

    // Create a limit order without setting allowance beforehand
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    vm.stopPrank();

    // Assert user has enough balance
    assertGt(IPoolLogic(pool).balanceOf(user), 1000e18);

    // Allowance is zero
    assertEq(IERC20(pool).allowance(user, address(poolLimitOrderManagerProxy)), 0);

    bytes32[] memory orderIdsToDelete = new bytes32[](1);
    orderIdsToDelete[0] = _getLimitOrderId(user, pool);

    // Order should be deletable because user has zero allowance
    vm.prank(keeper);
    poolLimitOrderManagerProxy.deleteLimitOrders(orderIdsToDelete);

    // Verify the order was deleted
    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();
    assertEq(limitOrderIds.length, 0);
  }

  function test_can_delete_multiple_limit_orders() public {
    vm.startPrank(user);

    // Only one pool is approved
    IERC20(pool).approve(address(poolLimitOrderManagerProxy), type(uint256).max);

    // Create first limit order for the first pool
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    // Create second limit order for the second pool
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 2000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: secondPool,
        pricingAsset: pricingAsset
      })
    );

    vm.stopPrank();

    // Set user's first pool balance to zero
    deal(pool, user, 0);

    // User has enough balance of the second pool
    assertGt(IPoolLogic(secondPool).balanceOf(user), 2000e18);

    assertGt(IERC20(pool).allowance(user, address(poolLimitOrderManagerProxy)), 1000e18);
    assertEq(IERC20(secondPool).allowance(user, address(poolLimitOrderManagerProxy)), 0);

    bytes32[] memory limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();
    assertEq(limitOrderIds.length, 2);

    bytes32[] memory orderIdsToDelete = new bytes32[](2);
    orderIdsToDelete[0] = _getLimitOrderId(user, pool);
    orderIdsToDelete[1] = _getLimitOrderId(user, secondPool);

    vm.prank(keeper);
    poolLimitOrderManagerProxy.deleteLimitOrders(orderIdsToDelete);

    limitOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();
    assertEq(limitOrderIds.length, 0);
  }

  function test_revert_delete_limit_orders_if_order_not_found() public {
    vm.startPrank(user);

    // Create one limit order
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
    vm.stopPrank();

    // Try to delete a non-existent order along with the existing one
    bytes32[] memory orderIdsToDelete = new bytes32[](2);
    orderIdsToDelete[0] = _getLimitOrderId(user, pool);
    orderIdsToDelete[1] = _getLimitOrderId(user, secondPool); // This order does not exist

    vm.prank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFound.selector, _getLimitOrderId(user, secondPool))
    );
    poolLimitOrderManagerProxy.deleteLimitOrders(orderIdsToDelete);
  }

  function test_revert_delete_limit_orders_if_not_keeper() public {
    vm.startPrank(user);

    // Create a limit order
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32[] memory orderIdsToDelete = new bytes32[](1);
    orderIdsToDelete[0] = _getLimitOrderId(user, pool);

    // Try to delete the order as a regular user (not a keeper)
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.deleteLimitOrders(orderIdsToDelete);
  }

  function test_revert_delete_limit_orders_if_user_has_balance_and_allowance() public {
    vm.startPrank(user);

    IERC20(pool).approve(address(poolLimitOrderManagerProxy), type(uint256).max);

    // Create a limit order
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: 1000e18,
        stopLossPriceD18: 800e18,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    vm.stopPrank();

    bytes32[] memory orderIdsToDelete = new bytes32[](1);
    orderIdsToDelete[0] = _getLimitOrderId(user, pool);

    // Try to delete the order as a keeper, but it should revert since user has balance and allowance
    vm.startPrank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotDeletable.selector, user, pool));
    poolLimitOrderManagerProxy.deleteLimitOrders(orderIdsToDelete);
  }

  // ============================================
  // Execute Limit Order Tests
  // ============================================

  function test_can_execute_limit_order() public {
    vm.startPrank(user);

    uint256 amountToOpenLimitOrderFor = 1000e18;

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), amountToOpenLimitOrderFor);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: amountToOpenLimitOrderFor,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    assertEq(IPoolLogic(pool).balanceOf(user), AMOUNT_DEPOSITED);
    assertEq(IPoolLogic(pool).balanceOf(address(poolLimitOrderManagerProxy)), 0);

    _setPricingAssetPriceD8(1200e8);

    vm.startPrank(keeper);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: type(uint256).max
    });

    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    (uint256 amount, , , , , ) = poolLimitOrderManagerProxy.limitOrders(_getLimitOrderId(user, pool));
    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();

    assertEq(IPoolLogic(pool).balanceOf(address(poolLimitOrderManagerProxy)), 0);
    assertEq(amount, 0);
    assertEq(IPoolLogic(pool).balanceOf(user), AMOUNT_DEPOSITED - amountToOpenLimitOrderFor);
    assertEq(poolLimitOrderManagerProxy.getAllLimitOrderIds().length, 0);
    assertEq(usersToSettle.length, 1);
    assertEq(usersToSettle[0], user);
  }

  function test_can_execute_multiple_limit_orders_same_user() public {
    vm.startPrank(user);

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), AMOUNT_DEPOSITED);
    IPoolLogic(secondPool).approve(address(poolLimitOrderManagerProxy), AMOUNT_DEPOSITED);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: AMOUNT_DEPOSITED,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: AMOUNT_DEPOSITED,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: secondPool,
        pricingAsset: pricingAsset
      })
    );

    _setPricingAssetPriceD8(1200e8);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](2);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: type(uint256).max
    });
    limitOrders[1] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, secondPool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(secondPool),
      amount: type(uint256).max
    });

    vm.startPrank(keeper);
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();
    assertEq(poolLimitOrderManagerProxy.getAllLimitOrderIds().length, 0);
    assertEq(usersToSettle.length, 1);
    assertEq(usersToSettle[0], user);
  }

  function test_can_execute_limit_orders_safe_if_contains_reverting_order() public {
    vm.startPrank(user);

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), AMOUNT_DEPOSITED);
    IPoolLogic(secondPool).approve(address(poolLimitOrderManagerProxy), AMOUNT_DEPOSITED);

    // Create a valid take-profit order for pool
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: AMOUNT_DEPOSITED,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    // Create an invalid take-profit order for secondPool (price too high)
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: AMOUNT_DEPOSITED,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1300e18,
        user: user,
        pool: secondPool,
        pricingAsset: pricingAsset
      })
    );

    _setPricingAssetPriceD8(1200e8);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](2);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: type(uint256).max
    });
    limitOrders[1] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, secondPool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(secondPool),
      amount: type(uint256).max
    });

    vm.startPrank(keeper);
    vm.expectEmit(address(poolLimitOrderManagerProxy));
    emit PoolLimitOrderManager.LimitOrderExecutionFailed(
      _getLimitOrderId(user, secondPool),
      abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFillable.selector, 1200e18, 0, 1300e18)
    );
    poolLimitOrderManagerProxy.executeLimitOrdersSafe(limitOrders);

    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();
    bytes32[] memory remainingOrderIds = poolLimitOrderManagerProxy.getAllLimitOrderIds();

    // First order should be executed
    assertEq(IPoolLogic(pool).balanceOf(user), 0);
    // Second order should remain
    assertEq(IPoolLogic(secondPool).balanceOf(user), AMOUNT_DEPOSITED);
    assertEq(usersToSettle.length, 1);
    assertEq(usersToSettle[0], user);
    assertEq(remainingOrderIds.length, 1);
    assertEq(remainingOrderIds[0], _getLimitOrderId(user, secondPool));
  }

  function test_revert_execute_limit_order_if_price_condition_not_met() public {
    vm.startPrank(user);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: AMOUNT_DEPOSITED,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32 limitOrderId = _getLimitOrderId(user, pool);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: type(uint256).max
    });

    vm.startPrank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFillable.selector, 1000e18, 0, 1200e18));
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);
  }

  function test_revert_execute_limit_order_if_slippage_invalid() public {
    vm.startPrank(user);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: AMOUNT_DEPOSITED,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32 limitOrderId = _getLimitOrderId(user, pool);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](
      IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).getSupportedAssets().length
    );

    _setPricingAssetPriceD8(1200e8);

    vm.startPrank(keeper);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: complexAssetsData,
      amount: type(uint256).max
    });

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidValue.selector, "slippage"));
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    for (uint256 i; i < complexAssetsData.length; ++i) {
      complexAssetsData[i].slippageTolerance = DEFAULT_SLIPPAGE_TOLERANCE + 1;
    }

    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: complexAssetsData,
      amount: type(uint256).max
    });

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidValue.selector, "slippage"));
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);
  }

  function test_revert_execute_limit_order_if_not_exists() public {
    bytes32 limitOrderId = _getLimitOrderId(user, pool);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(pool);

    vm.prank(keeper);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: complexAssetsData,
      amount: type(uint256).max
    });

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFound.selector, limitOrderId));
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);
  }

  function test_revert_execute_limit_order_if_caller_not_keeper() public {
    bytes32 limitOrderId = _getLimitOrderId(user, pool);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(pool);

    vm.prank(user);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: complexAssetsData,
      amount: type(uint256).max
    });

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);
  }

  function test_revert_execute_limit_orders_if_caller_not_keeper() public {
    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](2);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: type(uint256).max
    });
    limitOrders[1] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, secondPool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(secondPool),
      amount: type(uint256).max
    });

    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeLimitOrdersSafe(limitOrders);
  }

  function test_revert_execute_limit_order_internal_if_caller_not_self() public {
    PoolLimitOrderManager.LimitOrderExecution memory limitOrder;

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.ExternalCallerNotAllowed.selector));
    poolLimitOrderManagerProxy._executeLimitOrder(limitOrder);
  }

  // ============================================
  // Execute Settlement Order Tests
  // ============================================

  function test_revert_execute_settlement_order_if_caller_not_keeper() public {
    IWithdrawalVault.MultiInSingleOutData memory swapData;

    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));

    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: user, swapData: swapData});

    poolLimitOrderManagerProxy.executeSettlementOrders(orders);
  }

  function test_revert_execute_settlement_orders_if_caller_not_keeper() public {
    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeSettlementOrders(new PoolLimitOrderManager.SettlementOrderExecution[](1));
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeSettlementOrdersSafe(new PoolLimitOrderManager.SettlementOrderExecution[](1));
  }

  function test_revert_execute_settlement_order_internal_if_caller_not_self() public {
    IWithdrawalVault.MultiInSingleOutData memory swapData;

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.ExternalCallerNotAllowed.selector));
    poolLimitOrderManagerProxy._executeSettlementOrder(user, swapData);
  }

  function test_revert_execute_settlement_order_if_not_exists() public {
    address userToSettle;
    IWithdrawalVault.MultiInSingleOutData memory swapData;

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.SettlementOrderNotFound.selector, userToSettle));

    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: userToSettle, swapData: swapData});

    poolLimitOrderManagerProxy.executeSettlementOrders(orders);
  }

  function test_revert_execute_settlement_order_if_wrong_settlement_token() public {
    _executeLimitOrder();

    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();
    IWithdrawalVault.MultiInSingleOutData memory swapData;
    swapData.destData.destToken = IERC20(pricingAsset);

    vm.startPrank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.InvalidAsset.selector, pricingAsset));

    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: usersToSettle[0], swapData: swapData});

    poolLimitOrderManagerProxy.executeSettlementOrders(orders);
  }

  function test_revert_execute_settlement_order_if_keeper_not_authorized() public {
    _executeLimitOrder();

    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();
    IWithdrawalVault.MultiInSingleOutData memory swapData;
    swapData.destData.destToken = IERC20(usdc);

    vm.prank(owner);
    EasySwapperV2Mock.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2Mock.WhitelistSetting[](1);
    whitelistSettings[0] = EasySwapperV2Mock.WhitelistSetting({
      whitelisted: false,
      toWhitelist: address(poolLimitOrderManagerProxy)
    });
    easySwapperV2Proxy.setAuthorizedWithdrawers(whitelistSettings);

    vm.startPrank(keeper);
    vm.expectRevert("not authorized");

    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: usersToSettle[0], swapData: swapData});

    poolLimitOrderManagerProxy.executeSettlementOrders(orders);
  }

  function test_can_execute_settlement_order_if_already_claimed_by_user() public {
    _executeLimitOrder();

    vm.prank(user);
    easySwapperV2Proxy.completeLimitOrderWithdrawal();

    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();
    IWithdrawalVault.MultiInSingleOutData memory swapData;

    vm.startPrank(keeper);

    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: usersToSettle[0], swapData: swapData});

    poolLimitOrderManagerProxy.executeSettlementOrders(orders);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.SettlementOrderNotFound.selector, usersToSettle[0]));
    poolLimitOrderManagerProxy.executeSettlementOrders(orders);

    assertEq(poolLimitOrderManagerProxy.getAllUsersToSettle().length, 0);
    assertEq(easySwapperV2Proxy.getTrackedAssetsFromLimitOrders(user).length, 0);
  }

  function test_can_execute_settlement_order_if_no_swap_required() public {
    // Assuming test pool is a BULL LT built on Aave, leave only Aave position at its portfolio
    deal(pricingAsset, pool, 0);

    assertEq(IERC20(usdc).balanceOf(user), 0);

    _executeLimitOrder();

    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();
    IWithdrawalVault.MultiInSingleOutData memory swapData;
    swapData.destData.destToken = IERC20(usdc);

    vm.startPrank(keeper);

    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: usersToSettle[0], swapData: swapData});

    poolLimitOrderManagerProxy.executeSettlementOrders(orders);

    assertEq(poolLimitOrderManagerProxy.getAllUsersToSettle().length, 0);
    assertEq(easySwapperV2Proxy.getTrackedAssetsFromLimitOrders(usersToSettle[0]).length, 0);
    assertEq(IERC20(usdc).balanceOf(address(poolLimitOrderManagerProxy)), 0);
    assertEq(IERC20(usdc).balanceOf(easySwapperV2Proxy.limitOrderContracts(user)), 0);
    assertGt(IERC20(usdc).balanceOf(user), 0);
  }

  function test_can_execute_settlement_orders_safe_if_contains_reverting_order() public {
    // Assuming test pool is a BULL LT built on Aave, leave only Aave position at its portfolio
    deal(pricingAsset, pool, 0);

    _executeLimitOrder();

    IWithdrawalVault.MultiInSingleOutData memory swapData;
    swapData.destData.destToken = IERC20(usdc);
    PoolLimitOrderManager.SettlementOrderExecution[]
      memory settlementOrders = new PoolLimitOrderManager.SettlementOrderExecution[](2);
    settlementOrders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: user, swapData: swapData});
    settlementOrders[1] = PoolLimitOrderManager.SettlementOrderExecution({user: owner, swapData: swapData});

    vm.startPrank(keeper);
    // Second settlement order should fail
    vm.expectEmit(address(poolLimitOrderManagerProxy));
    emit PoolLimitOrderManager.SettlementOrderExecutionFailed(
      owner,
      abi.encodeWithSelector(PoolLimitOrderManager.SettlementOrderNotFound.selector, owner)
    );
    poolLimitOrderManagerProxy.executeSettlementOrdersSafe(settlementOrders);

    // First settlement order should be executed
    assertEq(poolLimitOrderManagerProxy.getAllUsersToSettle().length, 0);
    assertEq(easySwapperV2Proxy.getTrackedAssetsFromLimitOrders(user).length, 0);
    assertEq(IERC20(usdc).balanceOf(address(poolLimitOrderManagerProxy)), 0);
    assertEq(IERC20(usdc).balanceOf(easySwapperV2Proxy.limitOrderContracts(user)), 0);
    assertGt(IERC20(usdc).balanceOf(user), 0);
  }

  function test_can_execute_settlement_order() public {
    // Preparations before creating a test pool
    IAssetHandlerMock assetHandler = IAssetHandlerMock(IPoolFactoryMock(poolFactory).getAssetHandler());
    vm.startPrank(assetHandler.owner());
    assetHandler.setChainlinkTimeout(86400 * 365);
    // This is instead of setting setExitCooldown to 0 (less code)
    IPoolFactoryMock(poolFactory).addReceiverWhitelist(address(poolLimitOrderManagerProxy));

    // Create a pool with WETH and USDC as supported assets
    IHasSupportedAssetMock.Asset[] memory supportedAssets = new IHasSupportedAssetMock.Asset[](2);
    supportedAssets[0] = IHasSupportedAssetMock.Asset({asset: weth, isDeposit: true});
    supportedAssets[1] = IHasSupportedAssetMock.Asset({asset: usdc, isDeposit: true});

    address testPool = IPoolFactoryMock(poolFactory).createFund(
      false,
      user,
      "User",
      "Test Settlement Order",
      "TSO",
      0,
      0,
      supportedAssets
    );

    // Deposit WETH and USDC into pool
    deal(weth, user, 4e18);
    deal(usdc, user, 1000e6);
    vm.startPrank(user);
    IERC20(weth).approve(testPool, 4e18);
    IERC20(usdc).approve(testPool, 1000e6);
    IPoolLogic(testPool).deposit(weth, 4e18);
    IPoolLogic(testPool).deposit(usdc, 1000e6);

    assertEq(IERC20(weth).balanceOf(testPool), 4e18);
    assertEq(IERC20(usdc).balanceOf(testPool), 1000e6);
    assertGt(IERC20(testPool).totalSupply(), 0);

    assertEq(IERC20(weth).balanceOf(user), 0);
    assertEq(IERC20(usdc).balanceOf(user), 0);
    uint256 userTestPoolBalance = IERC20(testPool).balanceOf(user);
    assertGt(userTestPoolBalance, 0);

    // Create limit order in a same fashion as in _executeLimitOrder
    IPoolLogic(testPool).approve(address(poolLimitOrderManagerProxy), userTestPoolBalance);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: userTestPoolBalance,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: testPool,
        pricingAsset: pricingAsset
      })
    );

    _setPricingAssetPriceD8(1200e8);

    // Execute limit order first to create settlement order
    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, testPool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(testPool),
      amount: type(uint256).max
    });

    vm.startPrank(keeper);
    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();
    assertEq(usersToSettle.length, 1);
    assertEq(usersToSettle[0], user);

    address vault = easySwapperV2Proxy.limitOrderContracts(user);

    // Prepare swap data, it passes slippage tolerance check
    IWithdrawalVault.MultiInSingleOutData memory swapData;
    swapData.destData.destToken = IERC20(usdc);
    swapData.destData.minDestAmount = 10825000000;
    swapData.srcData = new ISwapper.SrcTokenSwapDetails[](1);
    swapData.srcData[0].token = IERC20(weth);
    swapData.srcData[0].amount = IERC20(weth).balanceOf(vault);
    swapData.srcData[0].aggregatorData.routerKey = bytes32("PARASWAP_V6");
    swapData
      .srcData[0]
      .aggregatorData
      .swapData = hex"e3ead59e000000000000000000000000000010036c0190e009a000d0fc3541100a07380a00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e58310000000000000000000000000000000000000000000000003782dace9d90000000000000000000000000000000000000000000000000000000000002836b5f2800000000000000000000000000000000000000000000000000000002855b01362ab4d244d9d84da6a485c941cf511ae60000000000000000000000001257e438000000000000000000000000000000000000000000000000000000000000000008a3c2a819e3de7aca384c798269b3ce1cd0e437900000000000000000000000000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000300010224949cca211fb5ddfedd28dc8bf9d2990368000001e000000044ff0c000800000000000000000000000000000000000000000000000000000000944bda00000010036c0190e009a000d0fc3541100a07380a8a91e49073a75000000000000000000000000000000000000000000000000000000000000000000067b60a44000000000000000000000000fd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb900000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000010224949cca211fb5ddfedd28dc8bf9d29903680000000000000000000000004f754e0f0924afd74980886b0b479fa1d7c58d0d0000000000000000000000000000000000000000000000000000000285662b000000000000000000000000000000000000000000000000003782dace9d90000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000003782dace9d90000000000000000000000000000000000000000000000000000000000000000000412dc77571f4a9de935bddced5b7daefbd4c8b6de73d217551146fd2e3aee0a990504cd74817530c7e46df76683bb46b5159c69c91c3778b537ace9b593c180ccb1c000000000000000000000000000000000000000000000000000000000000003c0441b42195f4ad6aa9a0978e06096ea616cda7000000a00024000000000003000000000000000000000000000000000000000000000000000000002668dfaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000285662b0000000000000000000000000000000000000000000000000000000000000000010000000000000000000000006a000f20005980200259b80c5102003040001068";

    // Execute settlement order
    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: user, swapData: swapData});
    poolLimitOrderManagerProxy.executeSettlementOrders(orders);

    // Verify settlement order was completed
    assertEq(poolLimitOrderManagerProxy.getAllUsersToSettle().length, 0);
    assertEq(easySwapperV2Proxy.getTrackedAssetsFromLimitOrders(user).length, 0);

    // Verify tokens were transferred correctly
    assertEq(IERC20(usdc).balanceOf(address(poolLimitOrderManagerProxy)), 0);
    assertEq(IERC20(weth).balanceOf(address(poolLimitOrderManagerProxy)), 0);

    assertEq(IERC20(usdc).balanceOf(vault), 0);
    assertEq(IERC20(weth).balanceOf(vault), 0);

    assertGt(IERC20(usdc).balanceOf(user), swapData.destData.minDestAmount + 1000e6);
  }

  function test_can_complete_limit_order_withdrawal_for() public {
    _executeLimitOrder();

    // Tokens from vault are being sent to the user
    vm.startPrank(keeper);
    easySwapperV2Proxy.completeLimitOrderWithdrawalFor(user);

    assertEq(easySwapperV2Proxy.getTrackedAssetsFromLimitOrders(user).length, 0);
    // Settlement order is still in the queue
    assertEq(poolLimitOrderManagerProxy.getAllUsersToSettle().length, 1);

    IWithdrawalVault.MultiInSingleOutData memory swapData;

    PoolLimitOrderManager.SettlementOrderExecution[]
      memory orders = new PoolLimitOrderManager.SettlementOrderExecution[](1);
    orders[0] = PoolLimitOrderManager.SettlementOrderExecution({user: user, swapData: swapData});

    poolLimitOrderManagerProxy.executeSettlementOrders(orders);

    // The above call removes settlement order from the queue and early exits
    assertEq(poolLimitOrderManagerProxy.getAllUsersToSettle().length, 0);
  }

  // ============================================
  // Execute Partially Limit Order Tests
  // ============================================

  function test_can_execute_partially_limit_order() public {
    vm.startPrank(user);

    uint256 totalAmount = 1000e18;
    uint256 amount = 400e18;

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), totalAmount);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: totalAmount,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    assertEq(IPoolLogic(pool).balanceOf(user), AMOUNT_DEPOSITED);
    assertEq(IPoolLogic(pool).balanceOf(address(poolLimitOrderManagerProxy)), 0);

    _setPricingAssetPriceD8(1200e8);

    vm.startPrank(keeper);

    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: amount
    });

    poolLimitOrderManagerProxy.executeLimitOrders(partialOrders);

    // Check that the order still exists with reduced amount
    bytes32 orderId = _getLimitOrderId(user, pool);
    (uint256 remainingAmount, , , , , ) = poolLimitOrderManagerProxy.limitOrders(orderId);
    address[] memory usersToSettle = poolLimitOrderManagerProxy.getAllUsersToSettle();

    assertEq(IPoolLogic(pool).balanceOf(address(poolLimitOrderManagerProxy)), 0);
    assertEq(remainingAmount, totalAmount - amount);
    assertEq(IPoolLogic(pool).balanceOf(user), AMOUNT_DEPOSITED - amount);
    assertEq(poolLimitOrderManagerProxy.getAllLimitOrderIds().length, 1);
    assertEq(usersToSettle.length, 1);
    assertEq(usersToSettle[0], user);
  }

  function test_can_execute_multiple_partial_limit_orders() public {
    vm.startPrank(user);

    uint256 totalAmount = 1000e18;
    uint256 firstPartialAmount = 300e18;
    uint256 secondPartialAmount = 200e18;

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), totalAmount);
    IPoolLogic(secondPool).approve(address(poolLimitOrderManagerProxy), totalAmount);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: totalAmount,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: totalAmount,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: secondPool,
        pricingAsset: pricingAsset
      })
    );

    _setPricingAssetPriceD8(1200e8);

    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      2
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: firstPartialAmount
    });
    partialOrders[1] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, secondPool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(secondPool),
      amount: secondPartialAmount
    });

    vm.startPrank(keeper);
    poolLimitOrderManagerProxy.executeLimitOrders(partialOrders);

    // Check that orders still exist with reduced amounts
    (uint256 remainingAmountPool1, , , , , ) = poolLimitOrderManagerProxy.limitOrders(_getLimitOrderId(user, pool));
    (uint256 remainingAmountPool2, , , , , ) = poolLimitOrderManagerProxy.limitOrders(
      _getLimitOrderId(user, secondPool)
    );

    assertEq(remainingAmountPool1, totalAmount - firstPartialAmount);
    assertEq(remainingAmountPool2, totalAmount - secondPartialAmount);
    assertEq(IPoolLogic(pool).balanceOf(user), AMOUNT_DEPOSITED - firstPartialAmount);
    assertEq(IPoolLogic(secondPool).balanceOf(user), AMOUNT_DEPOSITED - secondPartialAmount);
    assertEq(poolLimitOrderManagerProxy.getAllLimitOrderIds().length, 2);
  }

  function test_can_execute_partial_limit_orders_safe_if_contains_reverting_order() public {
    vm.startPrank(user);

    uint256 totalAmount = 1000e18;
    uint256 amount = 400e18;

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), totalAmount);
    IPoolLogic(secondPool).approve(address(poolLimitOrderManagerProxy), totalAmount);

    // Create a valid take-profit order for pool
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: totalAmount,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    // Create an invalid take-profit order for secondPool (price too high)
    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: totalAmount,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1300e18,
        user: user,
        pool: secondPool,
        pricingAsset: pricingAsset
      })
    );

    _setPricingAssetPriceD8(1200e8);

    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      2
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: amount
    });
    partialOrders[1] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, secondPool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(secondPool),
      amount: amount
    });

    vm.startPrank(keeper);
    vm.expectEmit(address(poolLimitOrderManagerProxy));
    emit PoolLimitOrderManager.LimitOrderExecutionFailed(
      _getLimitOrderId(user, secondPool),
      abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFillable.selector, 1200e18, 0, 1300e18)
    );
    poolLimitOrderManagerProxy.executeLimitOrdersSafe(partialOrders);

    // Check that first order was partially executed
    (uint256 remainingAmountPool1, , , , , ) = poolLimitOrderManagerProxy.limitOrders(_getLimitOrderId(user, pool));
    assertEq(remainingAmountPool1, totalAmount - amount);
    assertEq(IPoolLogic(pool).balanceOf(user), AMOUNT_DEPOSITED - amount);

    // Second order should remain unchanged
    (uint256 remainingAmountPool2, , , , , ) = poolLimitOrderManagerProxy.limitOrders(
      _getLimitOrderId(user, secondPool)
    );
    assertEq(remainingAmountPool2, totalAmount);
    assertEq(IPoolLogic(secondPool).balanceOf(user), AMOUNT_DEPOSITED);
  }

  function test_can_execute_partial_then_full_limit_order() public {
    vm.startPrank(user);

    uint256 totalAmount = 1000e18;
    uint256 amount = 400e18;

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), totalAmount);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: totalAmount,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    _setPricingAssetPriceD8(1200e8);

    // First execute partial order
    vm.startPrank(keeper);

    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: amount
    });

    poolLimitOrderManagerProxy.executeLimitOrders(partialOrders);

    // Check that the order still exists with reduced amount
    bytes32 orderId = _getLimitOrderId(user, pool);
    (uint256 remainingAmount, , , , , ) = poolLimitOrderManagerProxy.limitOrders(orderId);
    assertEq(remainingAmount, totalAmount - amount);

    // Now execute the remaining amount
    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: orderId,
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: remainingAmount
    });

    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);

    // Check that the order has been fully executed
    (remainingAmount, , , , , ) = poolLimitOrderManagerProxy.limitOrders(orderId);
    assertEq(remainingAmount, 0);
    assertEq(IPoolLogic(pool).balanceOf(user), AMOUNT_DEPOSITED - totalAmount);
    assertEq(poolLimitOrderManagerProxy.getAllLimitOrderIds().length, 0);
  }

  function test_revert_execute_partially_limit_order_if_price_condition_not_met() public {
    vm.startPrank(user);

    uint256 totalAmount = 1000e18;
    uint256 amount = 400e18;

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: totalAmount,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    bytes32 limitOrderId = _getLimitOrderId(user, pool);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(pool);

    vm.startPrank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFillable.selector, 1000e18, 0, 1200e18));

    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: complexAssetsData,
      amount: amount
    });

    poolLimitOrderManagerProxy.executeLimitOrders(partialOrders);
  }

  function test_revert_execute_partially_limit_order_if_not_exists() public {
    bytes32 limitOrderId = _getLimitOrderId(user, pool);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(pool);

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.LimitOrderNotFound.selector, limitOrderId));

    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: complexAssetsData,
      amount: 400e18
    });

    poolLimitOrderManagerProxy.executeLimitOrders(partialOrders);
  }

  function test_revert_execute_partially_limit_order_if_caller_not_keeper() public {
    bytes32 limitOrderId = _getLimitOrderId(user, pool);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(pool);

    vm.prank(user);

    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      1
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: limitOrderId,
      complexAssetsData: complexAssetsData,
      amount: 400e18
    });

    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeLimitOrders(partialOrders);
  }

  function test_revert_execute_partially_limit_orders_if_caller_not_keeper() public {
    PoolLimitOrderManager.LimitOrderExecution[] memory partialOrders = new PoolLimitOrderManager.LimitOrderExecution[](
      2
    );
    partialOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: 400e18
    });
    partialOrders[1] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, secondPool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(secondPool),
      amount: 300e18
    });

    vm.startPrank(user);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeLimitOrders(partialOrders);
    vm.expectRevert(abi.encodeWithSelector(PoolLimitOrderManager.NotAuthorizedKeeper.selector, user));
    poolLimitOrderManagerProxy.executeLimitOrdersSafe(partialOrders);
  }

  // ============================================
  // Helper Functions
  // ============================================

  function _setPricingAssetPriceD8(uint256 _priceD8) internal {
    vm.mockCall(
      pricingAssetOracle,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, _priceD8, 0, type(uint128).max, 0)
    );
  }

  function _getLimitOrderId(address _user, address _pool) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_user, _pool));
  }

  function _getEmptyPoolComplexAssetsData(
    address _pool
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();
    complexAssetsData = new IPoolLogic.ComplexAsset[](IHasSupportedAsset(poolManagerLogic).getSupportedAssets().length);
    for (uint256 i; i < complexAssetsData.length; ++i) {
      complexAssetsData[i].slippageTolerance = DEFAULT_SLIPPAGE_TOLERANCE;
    }
  }

  function _executeLimitOrder() internal {
    vm.startPrank(user);

    IPoolLogic(pool).approve(address(poolLimitOrderManagerProxy), AMOUNT_DEPOSITED);

    poolLimitOrderManagerProxy.createLimitOrder(
      PoolLimitOrderManager.LimitOrderInfo({
        amount: AMOUNT_DEPOSITED,
        stopLossPriceD18: 0,
        takeProfitPriceD18: 1200e18,
        user: user,
        pool: pool,
        pricingAsset: pricingAsset
      })
    );

    _setPricingAssetPriceD8(1200e8);

    vm.startPrank(keeper);

    PoolLimitOrderManager.LimitOrderExecution[] memory limitOrders = new PoolLimitOrderManager.LimitOrderExecution[](1);
    limitOrders[0] = PoolLimitOrderManager.LimitOrderExecution({
      orderId: _getLimitOrderId(user, pool),
      complexAssetsData: _getEmptyPoolComplexAssetsData(pool),
      amount: type(uint256).max
    });

    poolLimitOrderManagerProxy.executeLimitOrders(limitOrders);
    vm.stopPrank();
  }
}
