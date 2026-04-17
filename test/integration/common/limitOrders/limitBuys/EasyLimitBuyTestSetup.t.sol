// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {EasyLimitBuyManager} from "contracts/limitOrders/EasyLimitBuyManager.sol";
import {EasyLimitBuyTypeHashLib} from "contracts/limitOrders/EasyLimitBuyTypeHashLib.sol";
import {ICommonErrors} from "contracts/interfaces/ICommonErrors.sol";
import {ISignatureTransfer} from "contracts/interfaces/permit2/ISignatureTransfer.sol";
import {IPoolFactory} from "contracts/interfaces/IPoolFactory.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IEasySwapperV2} from "contracts/swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {AuthorizedKeepersBase} from "contracts/utils/keepers/AuthorizedKeepersBase.sol";
import {IPoolFactoryMock} from "test/integration/common/limitOrders/IPoolFactoryMock.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/// @title EasyLimitBuyTestSetup
/// @notice Abstract test setup for EasyLimitBuyManager tests
/// @dev Runs against any fork with real Permit2 contract
abstract contract EasyLimitBuyTestSetup is Test {
  // ============ Constants ============
  uint256 public constant USER_DEPOSIT_AMOUNT = 1000e6; // 1000 USDC
  uint16 public constant DEFAULT_SLIPPAGE_BPS = 100; // 1%

  // ============ Test Actors ============

  address public owner = makeAddr("owner");
  address public keeper = makeAddr("keeper");

  // User is controlled by private key for signing
  uint256 public userPrivateKey = 0xA11CE;
  address public user;

  // ============ Deployed Contracts ============

  EasyLimitBuyManager public easyLimitBuyManager;

  // ============ Chain-specific Config (set by inheriting contract) ============

  address public poolFactory;
  address public usdc;
  address public targetVault; // dHEDGE vault that accepts USDC deposits
  address public pricingAsset; // Asset whose price triggers the order
  address public easySwapperV2;

  constructor(
    address _poolFactory,
    address _usdc,
    address _targetVault,
    address _pricingAsset,
    address _easySwapperV2
  ) {
    poolFactory = _poolFactory;
    usdc = _usdc;
    targetVault = _targetVault;
    pricingAsset = _pricingAsset;
    easySwapperV2 = _easySwapperV2;

    user = vm.addr(userPrivateKey);
  }

  function setUp() public virtual {
    vm.startPrank(owner);

    // Deploy EasyLimitBuyManager
    easyLimitBuyManager = new EasyLimitBuyManager(
      owner,
      ISignatureTransfer(EthereumConfig.PERMIT2),
      IPoolFactory(poolFactory),
      IEasySwapperV2(easySwapperV2)
    );
    easyLimitBuyManager.addAuthorizedKeeper(keeper);

    vm.stopPrank();

    // Whitelist the EasyLimitBuyManager in PoolFactory for custom cooldown
    _whitelistInPoolFactory();

    // Give user USDC
    deal(usdc, user, USER_DEPOSIT_AMOUNT * 10);

    // User approves Permit2 to spend USDC (one-time max approval pattern)
    vm.prank(user);
    IERC20(usdc).approve(EthereumConfig.PERMIT2, type(uint256).max);
  }

  // ============================================
  // Keeper Authorization Tests
  // ============================================

  function test_revert_fill_not_keeper() public {
    EasyLimitBuyManager.LimitBuyExecution[] memory executions = new EasyLimitBuyManager.LimitBuyExecution[](0);

    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(AuthorizedKeepersBase.NotAuthorizedKeeper.selector, user));
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(AuthorizedKeepersBase.NotAuthorizedKeeper.selector, user));
    easyLimitBuyManager.fillLimitBuySafeBatch(executions);
  }

  function test_revert_external_fill_not_self() public {
    EasyLimitBuyTypeHashLib.LimitBuyOrder memory order;
    ISignatureTransfer.PermitTransferFrom memory permit;
    EasyLimitBuyManager.ZapData memory zapData;

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(ICommonErrors.UnauthorizedCaller.selector, keeper));
    easyLimitBuyManager._fillLimitBuyExternal(order, permit, "", zapData);
  }

  // ============================================
  // Validation Tests
  // ============================================

  function test_revert_invalid_pool() public {
    address invalidPool = makeAddr("notAPool");

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      invalidPool,
      USER_DEPOSIT_AMOUNT,
      0, // min price
      type(uint256).max, // max price
      DEFAULT_SLIPPAGE_BPS
    );

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(ICommonErrors.InvalidPool.selector, invalidPool));
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  function test_revert_invalid_slippage_zero() public {
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      0,
      type(uint256).max,
      0 // zero slippage
    );

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(EasyLimitBuyManager.InvalidSlippage.selector, 0));
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  function test_revert_invalid_slippage_too_high() public {
    uint16 tooHighSlippage = 501; // > 5% max

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      0,
      type(uint256).max,
      tooHighSlippage
    );

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(EasyLimitBuyManager.InvalidSlippage.selector, tooHighSlippage));
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice Protects "Buy the Breakout" users from premature execution before their target price is reached
  /// @dev User sets minTriggerPrice as breakout level - keeper cannot execute until price rises above it
  function test_revert_breakout_order_price_below_min() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();
    uint256 minPrice = currentPrice + 1000e18; // Set min higher than current

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      type(uint256).max,
      DEFAULT_SLIPPAGE_BPS
    );

    vm.prank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.PriceConditionNotMet.selector,
        currentPrice,
        minPrice,
        type(uint256).max
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice Protects "Buy the Dip" users from execution at prices higher than their target
  /// @dev User sets maxTriggerPrice as dip level - keeper cannot execute until price drops below it
  function test_revert_dip_order_price_above_max() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();
    uint256 maxPrice = currentPrice > 100e18 ? currentPrice - 100e18 : 1; // Set max lower than current

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      0,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS
    );

    vm.prank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(EasyLimitBuyManager.PriceConditionNotMet.selector, currentPrice, 0, maxPrice)
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice Test with minPrice = 0 and maxPrice = type(uint256).max - should always execute
  function test_fill_limit_buy_extreme_price_bounds_unlimited() public {
    // Create order that accepts any price (0, max)
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      0, // no minimum price
      type(uint256).max, // no maximum price
      DEFAULT_SLIPPAGE_BPS
    );

    uint256 expectedVaultTokens = IEasySwapperV2(easySwapperV2).depositQuote(targetVault, usdc, USER_DEPOSIT_AMOUNT);
    uint256 userVaultBefore = IERC20(targetVault).balanceOf(user);

    vm.prank(keeper);
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    assertApproxEqAbs(
      IERC20(targetVault).balanceOf(user) - userVaultBefore,
      expectedVaultTokens,
      800,
      "Should execute at any price"
    );
  }

  /// @notice Test with minPrice = maxPrice (exact price match required)
  function test_fill_limit_buy_extreme_price_bounds_exact_match() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Create order that requires exact price match
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      currentPrice, // exact min
      currentPrice, // exact max
      DEFAULT_SLIPPAGE_BPS
    );

    uint256 expectedVaultTokens = IEasySwapperV2(easySwapperV2).depositQuote(targetVault, usdc, USER_DEPOSIT_AMOUNT);
    uint256 userVaultBefore = IERC20(targetVault).balanceOf(user);

    vm.prank(keeper);
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    assertApproxEqAbs(
      IERC20(targetVault).balanceOf(user) - userVaultBefore,
      expectedVaultTokens,
      800,
      "Should execute at exact price"
    );
  }

  /// @notice Test with minPrice = maxPrice = 0 - never executes (unless price is exactly 0)
  function test_revert_price_bounds_zero_zero() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Create order with both bounds at 0 - will fail since price > 0
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      0,
      0, // maxPrice = 0 means price must be exactly 0
      DEFAULT_SLIPPAGE_BPS
    );

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(EasyLimitBuyManager.PriceConditionNotMet.selector, currentPrice, 0, 0));
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice Test with minPrice = maxPrice = type(uint256).max - never executes
  function test_revert_price_bounds_max_max() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Create order with both bounds at max - will fail since price < max
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      type(uint256).max,
      type(uint256).max,
      DEFAULT_SLIPPAGE_BPS
    );

    vm.prank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.PriceConditionNotMet.selector,
        currentPrice,
        type(uint256).max,
        type(uint256).max
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice Test with minPrice > maxPrice - invalid range, always reverts with InvalidPriceRange
  function test_revert_invalid_price_range() public {
    uint256 minPrice = 100_000e18;
    uint256 maxPrice = 80_000e18; // Less than min - invalid

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS
    );

    vm.prank(keeper);
    vm.expectRevert(abi.encodeWithSelector(EasyLimitBuyManager.InvalidPriceRange.selector, minPrice, maxPrice));
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  // ============================================
  // Happy Path Tests
  // ============================================

  function test_fill_limit_buy_non_zap_deposit() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Create order with price bounds around current price
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, bytes32 orderHash, ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      currentPrice > 100e18 ? currentPrice - 100e18 : 0, // min slightly below
      currentPrice + 100e18, // max slightly above
      DEFAULT_SLIPPAGE_BPS
    );

    // Get expected vault tokens using depositQuote (may differ slightly from actual)
    uint256 expectedVaultTokens = IEasySwapperV2(easySwapperV2).depositQuote(targetVault, usdc, USER_DEPOSIT_AMOUNT);

    uint256 userUsdcBefore = IERC20(usdc).balanceOf(user);
    uint256 userVaultTokensBefore = IERC20(targetVault).balanceOf(user);

    vm.prank(keeper);
    // Check event is emitted with correct indexed params; data params may have slight rounding diff
    vm.expectEmit(true, true, true, false);
    emit EasyLimitBuyManager.LimitBuyFilled(
      orderHash,
      user,
      targetVault,
      usdc,
      USER_DEPOSIT_AMOUNT,
      expectedVaultTokens
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    uint256 userUsdcAfter = IERC20(usdc).balanceOf(user);
    uint256 userVaultTokensAfter = IERC20(targetVault).balanceOf(user);

    // User's USDC should decrease exactly by deposit amount
    assertEq(userUsdcBefore - userUsdcAfter, USER_DEPOSIT_AMOUNT, "User USDC should decrease");

    // User should receive ~expected vault tokens (depositQuote may differ slightly from actual execution)
    assertApproxEqAbs(
      userVaultTokensAfter - userVaultTokensBefore,
      expectedVaultTokens,
      800,
      "User should receive expected vault tokens"
    );
  }

  function test_fill_limit_buy_batch_multiple() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();
    uint256 minPrice = currentPrice > 100e18 ? currentPrice - 100e18 : 0;
    uint256 maxPrice = currentPrice + 100e18;

    // Create two separate users with their own orders
    // Use a distinctive private key unlikely to collide with contracts on-chain
    uint256 user2PrivateKey = 0xDEADBEEF1234;
    address user2 = vm.addr(user2PrivateKey);
    deal(usdc, user2, USER_DEPOSIT_AMOUNT);

    vm.prank(user2);
    IERC20(usdc).approve(EthereumConfig.PERMIT2, type(uint256).max);

    // Build execution for user1
    (EasyLimitBuyManager.LimitBuyExecution[] memory exec1, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS
    );

    // Build execution for user2
    (EasyLimitBuyManager.LimitBuyExecution[] memory exec2, , ) = _createSignedExecutionForUser(
      user2PrivateKey,
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS,
      0
    );

    // Combine into batch
    EasyLimitBuyManager.LimitBuyExecution[] memory batch = new EasyLimitBuyManager.LimitBuyExecution[](2);
    batch[0] = exec1[0];
    batch[1] = exec2[0];

    // Get expected vault tokens using depositQuote (same for both users at current vault state)
    uint256 expectedVaultTokens = IEasySwapperV2(easySwapperV2).depositQuote(targetVault, usdc, USER_DEPOSIT_AMOUNT);

    uint256 user1VaultBefore = IERC20(targetVault).balanceOf(user);
    uint256 user2VaultBefore = IERC20(targetVault).balanceOf(user2);
    uint256 user1UsdcBefore = IERC20(usdc).balanceOf(user);
    uint256 user2UsdcBefore = IERC20(usdc).balanceOf(user2);

    vm.prank(keeper);
    easyLimitBuyManager.fillLimitBuyBatch(batch);

    // User1: exact USDC decrease and vault tokens received
    assertEq(user1UsdcBefore - IERC20(usdc).balanceOf(user), USER_DEPOSIT_AMOUNT, "User1 USDC should decrease");
    assertApproxEqAbs(
      IERC20(targetVault).balanceOf(user) - user1VaultBefore,
      expectedVaultTokens,
      800,
      "User1 should receive expected vault tokens"
    );

    // User2: exact USDC decrease and vault tokens received
    assertEq(user2UsdcBefore - IERC20(usdc).balanceOf(user2), USER_DEPOSIT_AMOUNT, "User2 USDC should decrease");
    assertApproxEqAbs(
      IERC20(targetVault).balanceOf(user2) - user2VaultBefore,
      expectedVaultTokens,
      800,
      "User2 should receive expected vault tokens"
    );
  }

  function test_fill_limit_buy_safe_batch_continues_on_failure() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();
    uint256 minPrice = currentPrice > 100e18 ? currentPrice - 100e18 : 0;
    uint256 maxPrice = currentPrice + 100e18;

    // Create one valid order and one that will fail (invalid pool)
    (EasyLimitBuyManager.LimitBuyExecution[] memory validExec, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS
    );

    address invalidPool = makeAddr("invalidPool");
    (
      EasyLimitBuyManager.LimitBuyExecution[] memory invalidExec,
      bytes32 invalidOrderHash,

    ) = _createSignedExecutionForUser(
        userPrivateKey,
        invalidPool,
        USER_DEPOSIT_AMOUNT,
        minPrice,
        maxPrice,
        DEFAULT_SLIPPAGE_BPS,
        1
      );

    // Batch: invalid first, valid second
    EasyLimitBuyManager.LimitBuyExecution[] memory batch = new EasyLimitBuyManager.LimitBuyExecution[](2);
    batch[0] = invalidExec[0];
    batch[1] = validExec[0];

    // Get expected vault tokens for the valid order
    uint256 expectedVaultTokens = IEasySwapperV2(easySwapperV2).depositQuote(targetVault, usdc, USER_DEPOSIT_AMOUNT);
    uint256 userVaultBefore = IERC20(targetVault).balanceOf(user);
    uint256 userUsdcBefore = IERC20(usdc).balanceOf(user);

    vm.prank(keeper);
    vm.expectEmit(true, true, false, false);
    emit EasyLimitBuyManager.LimitBuyFillFailed(invalidOrderHash, user, "");
    easyLimitBuyManager.fillLimitBuySafeBatch(batch);

    // Valid order should succeed with expected amounts
    assertEq(userUsdcBefore - IERC20(usdc).balanceOf(user), USER_DEPOSIT_AMOUNT, "User USDC should decrease");
    assertApproxEqAbs(
      IERC20(targetVault).balanceOf(user) - userVaultBefore,
      expectedVaultTokens,
      800,
      "User should receive expected vault tokens"
    );
  }

  // ============================================
  // User Flow Simulation Test
  // ============================================

  /// @notice Simulates real user flow: sign order, wait for price condition, keeper fills
  function test_user_flow_buy_the_dip() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // User wants to buy if price drops 10%
    uint256 dipPrice = (currentPrice * 90) / 100;

    // Create order for "buy the dip" - only execute if price <= dipPrice
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      0, // no lower bound
      dipPrice, // max price is dip price
      DEFAULT_SLIPPAGE_BPS
    );

    // First attempt: price is too high, should fail
    vm.prank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(EasyLimitBuyManager.PriceConditionNotMet.selector, currentPrice, 0, dipPrice)
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    // Simulate price drop by mocking the oracle
    _setPricingAssetPrice(dipPrice - 1e18);

    // Now the order should succeed
    uint256 userVaultBefore = IERC20(targetVault).balanceOf(user);

    vm.prank(keeper);
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    assertGt(IERC20(targetVault).balanceOf(user), userVaultBefore, "User should receive vault tokens after dip");
  }

  /// @notice Simulates breakout strategy: buy when price goes up
  function test_user_flow_buy_breakout() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // User wants to buy on breakout - if price rises 10%
    uint256 breakoutPrice = (currentPrice * 110) / 100;

    // Create order for "buy the breakout" - only execute if price >= breakoutPrice
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      breakoutPrice, // min price is breakout price
      type(uint256).max, // no upper bound
      DEFAULT_SLIPPAGE_BPS
    );

    // First attempt: price is too low, should fail
    vm.prank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.PriceConditionNotMet.selector,
        currentPrice,
        breakoutPrice,
        type(uint256).max
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    // Simulate price rise
    _setPricingAssetPrice(breakoutPrice + 1e18);

    // Now the order should succeed
    uint256 userVaultBefore = IERC20(targetVault).balanceOf(user);

    vm.prank(keeper);
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    assertGt(IERC20(targetVault).balanceOf(user), userVaultBefore, "User should receive vault tokens after breakout");
  }

  // ============================================
  // Permit2 Signature Test
  // ============================================

  function test_signature_verification() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();
    uint256 minPrice = currentPrice > 100e18 ? currentPrice - 100e18 : 0;
    uint256 maxPrice = currentPrice + 100e18;

    // Create signed order
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , bytes memory signature) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS
    );

    // Verify signature length (65 bytes for ECDSA: r + s + v)
    assertEq(signature.length, 65, "Signature should be 65 bytes");

    // Execute should work with valid signature
    vm.prank(keeper);
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  function test_revert_wrong_signature() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();
    uint256 minPrice = currentPrice > 100e18 ? currentPrice - 100e18 : 0;
    uint256 maxPrice = currentPrice + 100e18;

    // Sign with wrong private key
    uint256 wrongPrivateKey = 0xDEAD;

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecutionForUser(
      wrongPrivateKey,
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS,
      0
    );

    // Override owner to be the real user (signature mismatch)
    executions[0].order.owner = user;

    vm.prank(keeper);
    // Permit2 reverts with InvalidSigner() - selector 0x815e1d64
    vm.expectRevert(bytes4(0x815e1d64));
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice User can cancel pending orders by revoking Permit2 approval
  function test_revert_user_revoked_permit2_approval() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();
    uint256 minPrice = currentPrice > 100e18 ? currentPrice - 100e18 : 0;
    uint256 maxPrice = currentPrice + 100e18;

    // Create valid signed order
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedExecution(
      targetVault,
      USER_DEPOSIT_AMOUNT,
      minPrice,
      maxPrice,
      DEFAULT_SLIPPAGE_BPS
    );

    // User decides to cancel by revoking Permit2 approval
    vm.prank(user);
    IERC20(usdc).approve(EthereumConfig.PERMIT2, 0);

    // Keeper tries to execute but fails - Permit2 cannot pull tokens
    vm.prank(keeper);
    // Permit2's SafeTransferLib reverts with TRANSFER_FROM_FAILED
    vm.expectRevert("TRANSFER_FROM_FAILED");
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  // ============================================
  // Internal Helpers
  // ============================================

  function _createSignedExecution(
    address _targetVault,
    uint256 _amount,
    uint256 _minPrice,
    uint256 _maxPrice,
    uint16 _slippageBps
  )
    internal
    view
    returns (EasyLimitBuyManager.LimitBuyExecution[] memory executions_, bytes32 orderHash_, bytes memory signature_)
  {
    return _createSignedExecutionForUser(userPrivateKey, _targetVault, _amount, _minPrice, _maxPrice, _slippageBps, 0);
  }

  function _createSignedExecutionForUser(
    uint256 _privateKey,
    address _targetVault,
    uint256 _amount,
    uint256 _minPrice,
    uint256 _maxPrice,
    uint16 _slippageBps,
    uint256 _nonce
  )
    internal
    view
    returns (EasyLimitBuyManager.LimitBuyExecution[] memory executions_, bytes32 orderHash_, bytes memory signature_)
  {
    address signer = vm.addr(_privateKey);
    EasyLimitBuyTypeHashLib.LimitBuyOrder memory order = _buildOrder(
      signer,
      _targetVault,
      _minPrice,
      _maxPrice,
      _slippageBps
    );
    orderHash_ = EasyLimitBuyTypeHashLib.hashLimitBuyOrder(order);
    uint256 deadline = block.timestamp + 1 hours;

    signature_ = _signPermitWithWitness(_privateKey, _amount, _nonce, deadline, order);
    executions_ = _buildExecutions(order, _amount, _nonce, deadline, signature_);
  }

  function _buildOrder(
    address _owner,
    address _targetVault,
    uint256 _minPrice,
    uint256 _maxPrice,
    uint16 _slippageBps
  ) internal view returns (EasyLimitBuyTypeHashLib.LimitBuyOrder memory) {
    return
      EasyLimitBuyTypeHashLib.LimitBuyOrder({
        owner: _owner,
        targetVault: _targetVault,
        pricingAsset: pricingAsset,
        minTriggerPriceD18: _minPrice,
        maxTriggerPriceD18: _maxPrice,
        slippageToleranceBps: _slippageBps
      });
  }

  function _signPermitWithWitness(
    uint256 _privateKey,
    uint256 _amount,
    uint256 _nonce,
    uint256 _deadline,
    EasyLimitBuyTypeHashLib.LimitBuyOrder memory _order
  ) internal view returns (bytes memory) {
    EasyLimitBuyTypeHashLib.LimitBuyTypedData memory typedData = EasyLimitBuyTypeHashLib.LimitBuyTypedData({
      domain: EasyLimitBuyTypeHashLib.EIP712Domain({
        name: "Permit2",
        chainId: block.chainid,
        verifyingContract: EthereumConfig.PERMIT2
      }),
      message: EasyLimitBuyTypeHashLib.PermitWitnessTransferFrom({
        permitted: EasyLimitBuyTypeHashLib.TokenPermissions({token: usdc, amount: _amount}),
        spender: address(easyLimitBuyManager),
        nonce: _nonce,
        deadline: _deadline,
        witness: _order
      })
    });

    bytes32 digest = EasyLimitBuyTypeHashLib.getDigest(typedData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
    return abi.encodePacked(r, s, v);
  }

  function _buildExecutions(
    EasyLimitBuyTypeHashLib.LimitBuyOrder memory _order,
    uint256 _amount,
    uint256 _nonce,
    uint256 _deadline,
    bytes memory _signature
  ) internal view returns (EasyLimitBuyManager.LimitBuyExecution[] memory executions_) {
    ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
      permitted: ISignatureTransfer.TokenPermissions({token: usdc, amount: _amount}),
      nonce: _nonce,
      deadline: _deadline
    });

    EasyLimitBuyManager.ZapData memory zapData = EasyLimitBuyManager.ZapData({
      aggregatorData: ISwapper.AggregatorData({routerKey: bytes32(0), swapData: ""}),
      destData: ISwapper.DestData({destToken: IERC20(address(0)), minDestAmount: 0})
    });

    executions_ = new EasyLimitBuyManager.LimitBuyExecution[](1);
    executions_[0] = EasyLimitBuyManager.LimitBuyExecution({
      order: _order,
      permit: permit,
      signature: _signature,
      zapData: zapData
    });
  }

  function _getCurrentPricingAssetPrice() internal view returns (uint256) {
    return IPoolFactory(poolFactory).getAssetPrice(pricingAsset);
  }

  function _setPricingAssetPrice(uint256 _priceD18) internal {
    // Mock the oracle to return a specific price
    // The price is returned in 18 decimals from PoolFactory
    vm.mockCall(
      poolFactory,
      abi.encodeWithSelector(IPoolFactory.getAssetPrice.selector, pricingAsset),
      abi.encode(_priceD18)
    );
  }

  function _whitelistInPoolFactory() internal {
    address factoryOwner = IPoolFactoryMock(poolFactory).owner();
    vm.prank(factoryOwner);
    IPoolFactoryMock(poolFactory).addCustomCooldownWhitelist(address(easyLimitBuyManager));
  }
}
