// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {ITypedStructuredDataValidatorMock} from "test/integration/common/odos/ITypedStructuredDataValidatorMock.sol";

/// @notice Abstract contract for testing TypedStructuredDataValidator core functionality
/// @dev Contains tests for order storage, cleanup, hasActiveOrderWithToken, max orders, and cancel/remove flows.
///      Child contracts must implement abstract methods to build protocol-specific typed data.
abstract contract TypedStructuredDataValidatorTestSetup is BackboneSetup {
  // ============ Common Error Selectors ============
  bytes4 internal constant UNAUTHORIZED_CALLER_SELECTOR = bytes4(keccak256("UnauthorizedCaller(address)"));
  bytes4 internal constant MAX_ORDERS_REACHED_SELECTOR = bytes4(keccak256("MaxOrdersReached(address)"));
  bytes4 internal constant ORDER_NOT_FOUND_SELECTOR = bytes4(keccak256("OrderNotFound(address,bytes32)"));
  bytes4 internal constant ORDER_STILL_ACTIVE_SELECTOR = bytes4(keccak256("OrderStillActive(address,bytes32)"));

  /// @dev TypedStructuredDataValidator proxy address
  address public dataValidatorProxy;

  /// @dev Test pool for orders
  PoolLogic internal testPool;

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    // Deploy TypedStructuredDataValidator
    address dataValidator = deployCode("TypedStructuredDataValidator.sol:TypedStructuredDataValidator");
    dataValidatorProxy = address(new TransparentUpgradeableProxy(dataValidator, proxyAdmin, ""));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).initialize(owner, address(poolFactoryProxy));

    // Let child contracts configure validation for their order type
    _setupValidationConfig();

    // Set data validator in pool factory
    poolFactoryProxy.setDataValidator(dataValidatorProxy);

    // Let child contracts set up protocol-specific guards
    _setupProtocolGuards();

    // Create test pool with supported assets
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "ValidatorTestPool",
        _fundSymbol: "VALTEST",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    vm.stopPrank();

    vm.label(address(testPool), "ValidatorTestPool");

    // Fund the pool with USDC
    deal(usdcData.asset, investor, 10000e6);
    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), 10000e6);
    testPool.deposit(usdcData.asset, 10000e6);
    vm.stopPrank();
  }

  // ============ Abstract Methods (Child Contracts Must Implement) ============

  /// @notice Set up validation config for the specific order type
  function _setupValidationConfig() internal virtual;

  /// @notice Set up any protocol-specific contract guards
  function _setupProtocolGuards() internal virtual;

  /// @notice Build typed data for an order with the given expiry and unique index
  /// @param expiry Order expiration timestamp
  /// @param index Unique index to differentiate orders (use different buyAmount)
  /// @return Encoded typed data for the order
  function _buildOrderTypedData(uint256 expiry, uint256 index) internal view virtual returns (bytes memory);

  /// @notice Compute the order hash from encoded typed data
  /// @param typedData Encoded typed data
  /// @return Order hash/digest
  function _getOrderHash(bytes memory typedData) internal view virtual returns (bytes32);

  /// @notice Get the input/sell token from encoded typed data
  /// @param typedData Encoded typed data
  /// @return Input token address
  function _getOrderInputToken(bytes memory typedData) internal view virtual returns (address);

  /// @notice Get the output/buy token from encoded typed data
  /// @param typedData Encoded typed data
  /// @return Output token address
  function _getOrderOutputToken(bytes memory typedData) internal view virtual returns (address);

  /// @notice Get the order type enum value
  /// @return The StructuredDataSupported enum value for this order type
  function _getOrderType() internal view virtual returns (ITypedStructuredDataValidatorMock.StructuredDataSupported);

  // ============ Helper Functions ============

  function _submitOrder(bytes memory typedData) internal {
    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(address(testPool), _getOrderType(), typedData);
  }

  // ============ Tests: hasActiveOrderWithToken ============

  function test_has_active_order_with_token_returns_true_for_active_order() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    // Both input and output tokens should be marked as having active orders
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        _getOrderInputToken(typedData)
      ),
      "Input token should have active order"
    );
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        _getOrderOutputToken(typedData)
      ),
      "Output token should have active order"
    );
    // DAI is not part of the order
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), daiData.asset),
      "Unrelated token should not have active order"
    );
  }

  function test_has_active_order_with_token_returns_false_after_expiry() public {
    uint256 expiry = block.timestamp + 1 hours;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    address inputToken = _getOrderInputToken(typedData);

    // Before expiry
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), inputToken),
      "Should have active order before expiry"
    );

    // Warp past expiry
    vm.warp(expiry + 1);

    // After expiry
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), inputToken),
      "Should not have active order after expiry"
    );
  }

  // ============ Tests: EnumerableSet & Order Management ============

  function test_get_pool_order_hashes_returns_all_hashes() public {
    uint256 expiry = block.timestamp + 1 days;

    // Submit 3 orders with different indices (different buyAmount)
    bytes32[] memory expectedHashes = new bytes32[](3);
    for (uint256 i = 0; i < 3; i++) {
      bytes memory typedData = _buildOrderTypedData(expiry, i);
      _submitOrder(typedData);
      expectedHashes[i] = _getOrderHash(typedData);
    }

    // Get all hashes
    bytes32[] memory storedHashes = ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(
      address(testPool)
    );

    assertEq(storedHashes.length, 3, "Should have 3 order hashes");

    // Verify all hashes are present (order may differ due to EnumerableSet)
    for (uint256 i = 0; i < 3; i++) {
      bool found = false;
      for (uint256 j = 0; j < storedHashes.length; j++) {
        if (storedHashes[j] == expectedHashes[i]) {
          found = true;
          break;
        }
      }
      assertTrue(found, "Expected hash should be in stored hashes");
    }
  }

  function test_submit_order_prevents_duplicate_hashes() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);

    // Submit same order twice
    _submitOrder(typedData);
    _submitOrder(typedData);

    // EnumerableSet should prevent duplicate - only 1 hash stored
    bytes32[] memory storedHashes = ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(
      address(testPool)
    );
    assertEq(storedHashes.length, 1, "Should only have 1 hash (no duplicates)");
  }

  function test_remove_order_removes_hash_from_set() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    bytes32 orderHash = _getOrderHash(typedData);

    // Verify hash is stored and validated
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      1,
      "Should have 1 hash before removal"
    );
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Hash should be validated before removal"
    );

    // Warp past expiry - CoWSwap orders can only be removed if expired or filled
    vm.warp(expiry + 1);

    // Owner removes the order
    vm.prank(owner);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).removeOrder(address(testPool), orderHash);

    // Verify order hash is removed from tracking
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      0,
      "Should have 0 hashes after removal"
    );

    // Verify hash is invalidated (removed from validatedHashes)
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Hash should NOT be validated after removal"
    );

    // Token should no longer be locked
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        _getOrderInputToken(typedData)
      ),
      "Token should not be locked after order removal"
    );
  }

  function test_remove_order_reverts_for_non_existent_order() public {
    bytes32 nonExistentHash = keccak256("non-existent");

    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ORDER_NOT_FOUND_SELECTOR, address(testPool), nonExistentHash));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).removeOrder(address(testPool), nonExistentHash);
  }

  // ============ Tests: Cancel Order (Manager/Trader) ============

  function test_cancel_order_manager_can_cancel_order() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    bytes32 orderHash = _getOrderHash(typedData);

    // Verify order is active before cancel
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Hash should be validated before cancel"
    );
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      1,
      "Should have 1 order before cancel"
    );

    // Warp past expiry - CoWSwap orders can only be cancelled if expired or filled
    vm.warp(expiry + 1);

    // Manager cancels the order
    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderHash);

    // Verify hash is invalidated
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Hash should NOT be validated after cancel"
    );

    // Verify order is removed from tracking
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      0,
      "Should have 0 orders after cancel"
    );

    // Token should no longer be locked
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        _getOrderInputToken(typedData)
      ),
      "Token should not be locked after cancel"
    );
  }

  function test_cancel_order_reverts_for_non_manager() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    bytes32 orderHash = _getOrderHash(typedData);

    // Random user tries to cancel - should fail
    vm.prank(investor);
    vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_CALLER_SELECTOR, investor));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderHash);
  }

  function test_cancel_order_reverts_for_non_existent_order() public {
    bytes32 nonExistentHash = keccak256("non-existent");

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_NOT_FOUND_SELECTOR, address(testPool), nonExistentHash));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), nonExistentHash);
  }

  function test_cancel_order_reverts_if_order_still_active() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    bytes32 orderHash = _getOrderHash(typedData);

    // Manager tries to cancel an active order (not expired, not filled)
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_STILL_ACTIVE_SELECTOR, address(testPool), orderHash));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderHash);

    // Order should still be tracked
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Hash should still be validated"
    );
  }

  function test_remove_order_reverts_if_order_still_active() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    bytes32 orderHash = _getOrderHash(typedData);

    // Owner tries to remove an active order (not expired, not filled)
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ORDER_STILL_ACTIVE_SELECTOR, address(testPool), orderHash));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).removeOrder(address(testPool), orderHash);

    // Order should still be tracked
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Hash should still be validated"
    );
  }

  function test_cancel_order_succeeds_after_expiry() public {
    uint256 expiry = block.timestamp + 1 hours;

    bytes memory typedData = _buildOrderTypedData(expiry, 0);
    _submitOrder(typedData);

    bytes32 orderHash = _getOrderHash(typedData);

    // Cannot cancel before expiry
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_STILL_ACTIVE_SELECTOR, address(testPool), orderHash));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderHash);

    // Warp past expiry
    vm.warp(expiry + 1);

    // Now cancel should succeed
    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderHash);

    // Verify order is removed
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Hash should NOT be validated after cancel"
    );
  }

  // ============ Tests: Auto Cleanup ============

  function test_submit_order_cleans_up_expired_orders() public {
    uint256 shortExpiry = block.timestamp + 1 hours;
    uint256 longExpiry = block.timestamp + 1 days;

    // Submit an order with short expiry
    bytes memory shortExpiryData = _buildOrderTypedData(shortExpiry, 0);
    _submitOrder(shortExpiryData);

    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      1,
      "Should have 1 order"
    );

    // Warp past short expiry
    vm.warp(shortExpiry + 1);

    // Submit another order - this should trigger cleanup of expired order
    bytes memory longExpiryData = _buildOrderTypedData(longExpiry, 1);
    _submitOrder(longExpiryData);

    // Should only have 1 order (expired one was cleaned up)
    bytes32[] memory hashes = ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(
      address(testPool)
    );
    assertEq(hashes.length, 1, "Should have 1 order after cleanup");

    // The remaining hash should be the long expiry order
    bytes32 expectedHash = _getOrderHash(longExpiryData);
    assertEq(hashes[0], expectedHash, "Remaining hash should be the long expiry order");

    // Verify expired order's hash is also removed from validatedHashes
    bytes32 expiredHash = _getOrderHash(shortExpiryData);
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), expiredHash),
      "Expired order hash should be removed from validatedHashes"
    );
  }

  // ============ Tests: Max Orders Limit ============

  function test_submit_order_reverts_when_max_orders_reached() public {
    uint256 maxOrders = ITypedStructuredDataValidatorMock(dataValidatorProxy).MAX_ORDERS_PER_POOL();
    uint256 expiry = block.timestamp + 1 days;

    // Submit max orders
    for (uint256 i = 0; i < maxOrders; i++) {
      bytes memory typedData = _buildOrderTypedData(expiry, i);
      _submitOrder(typedData);
    }

    // Verify we're at max
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      maxOrders,
      "Should be at max orders"
    );

    // Try to submit one more - should revert
    bytes memory extraOrder = _buildOrderTypedData(expiry, maxOrders);

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(MAX_ORDERS_REACHED_SELECTOR, address(testPool)));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(address(testPool), _getOrderType(), extraOrder);
  }

  function test_submit_order_succeeds_after_cleanup_frees_slots() public {
    uint256 maxOrders = ITypedStructuredDataValidatorMock(dataValidatorProxy).MAX_ORDERS_PER_POOL();
    uint256 shortExpiry = block.timestamp + 1 hours;
    uint256 longExpiry = block.timestamp + 1 days;

    // Submit max orders with short expiry
    for (uint256 i = 0; i < maxOrders; i++) {
      bytes memory typedData = _buildOrderTypedData(shortExpiry, i);
      _submitOrder(typedData);
    }

    // Warp past expiry
    vm.warp(shortExpiry + 1);

    // Now submit should succeed because cleanup will free all slots
    bytes memory newOrder = _buildOrderTypedData(longExpiry, maxOrders);
    _submitOrder(newOrder);

    // Should only have 1 order (all expired ones cleaned up)
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      1,
      "Should have 1 order after cleanup"
    );
  }
}
