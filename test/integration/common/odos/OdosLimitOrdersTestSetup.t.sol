// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {ClosedContractGuard} from "contracts/guards/contractGuards/ClosedContractGuard.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {ITypedStructuredDataValidatorMock} from "test/integration/common/odos/ITypedStructuredDataValidatorMock.sol";
import {IOdosLimitOrderRouter} from "test/integration/common/odos/IOdosLimitOrderRouter.sol";
import {OdosLimitOrderTypeHashLib} from "contracts/validators/odos/OdosLimitOrderTypeHashLib.sol";

abstract contract OdosLimitOrdersTestSetup is BackboneSetup {
  // These match errors defined in OdosLimitOrderValidator and TypedStructuredDataValidator
  bytes4 internal constant UNSUPPORTED_INPUT_TOKEN_SELECTOR = bytes4(keccak256("UnsupportedInputToken()"));
  bytes4 internal constant UNSUPPORTED_OUTPUT_TOKEN_SELECTOR = bytes4(keccak256("UnsupportedOutputToken()"));
  bytes4 internal constant UNAUTHORIZED_CALLER_SELECTOR = bytes4(keccak256("UnauthorizedCaller(address)"));
  bytes4 internal constant MAX_ORDERS_REACHED_SELECTOR = bytes4(keccak256("MaxOrdersReached(address)"));
  bytes4 internal constant ORDER_NOT_FOUND_SELECTOR = bytes4(keccak256("OrderNotFound(address,bytes32)"));
  bytes4 internal constant INPUT_AMOUNT_MISMATCH_SELECTOR = bytes4(keccak256("InputAmountMismatch()"));
  bytes4 internal constant ORDER_RATE_TOO_UNFAVORABLE_SELECTOR = bytes4(keccak256("OrderRateTooUnfavorable()"));
  bytes4 internal constant ORDER_EXPIRED_SELECTOR = bytes4(keccak256("OrderExpired()"));
  bytes4 internal constant NONCE_ALREADY_USED_SELECTOR = bytes4(keccak256("NonceAlreadyUsed()"));

  /// @dev Mocked filler address for e2e tests
  address internal constant MOCKED_FILLER = address(0xF111E8);

  address public permit2;
  address public odosLimitOrderRouter;
  uint256 public poolManagerPrivateKey = 0xA11CE;
  address public poolManager;

  address public dataValidatorProxy;
  PoolLogic internal testPool;

  constructor(address _permit2, address _odosLimitOrderRouter) {
    permit2 = _permit2;
    odosLimitOrderRouter = _odosLimitOrderRouter;
    poolManager = vm.addr(poolManagerPrivateKey);
  }

  function setUp() public virtual override {
    vm.skip(true, "Skip odos limit order tests. Superseded by CowSwap orders support");

    super.setUp();

    vm.startPrank(owner);
    address dataValidator = deployCode("TypedStructuredDataValidator.sol:TypedStructuredDataValidator");
    dataValidatorProxy = address(new TransparentUpgradeableProxy(dataValidator, proxyAdmin, ""));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).initialize(owner, address(poolFactoryProxy));

    // Encode OdosLimitOrderValidationConfig struct manually
    // Config: verifyingContract, spender, maxUnfavorableDeviationBps
    // 100 bps = 1% max unfavorable deviation from oracle rate
    bytes memory odosValidationConfig = abi.encode(permit2, odosLimitOrderRouter, 100);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).setValidationConfig(
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      odosValidationConfig
    );
    poolFactoryProxy.setDataValidator(dataValidatorProxy);

    ClosedContractGuard closedGuard = new ClosedContractGuard();
    governance.setContractGuard(permit2, address(closedGuard));

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: poolManager,
        _managerName: "Manager",
        _fundName: "OdosLimitOrderTestPool",
        _fundSymbol: "OLOTV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    vm.stopPrank();

    vm.label(address(testPool), "OdosLimitOrderTestPool");

    deal(usdcData.asset, investor, 10000e6);
    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), 10000e6);
    testPool.deposit(usdcData.asset, 10000e6);
    vm.stopPrank();
  }

  function test_submit_order_stores_validated_hash() public {
    uint256 expiry = block.timestamp + 1 days;
    uint256 nonce = 0;
    uint256 salt = 12345;

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset, // input token (sell USDC)
      1000e6, // input amount
      wethData.asset, // output token (buy WETH)
      0.5 ether, // output amount
      expiry,
      nonce,
      salt
    );

    // Manager submits the order for validation
    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );

    // Compute the expected hash
    bytes32 expectedHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, expiry, nonce, salt);

    // Verify hash is stored
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), expectedHash),
      "Hash should be validated"
    );
  }

  // function test_is_valid_signature_returns_correct_magic_value() public {
  //   uint256 expiry = block.timestamp + 1 days;
  //   uint256 nonce = 0;
  //   uint256 salt = 12345;

  //   bytes memory typedData = _buildOdosLimitOrderTypedData(
  //     usdcData.asset,
  //     1000e6,
  //     wethData.asset,
  //     0.5 ether,
  //     expiry,
  //     nonce,
  //     salt
  //   );

  //   // Step 1: Manager submits order for validation
  //   vm.prank(poolManager);
  //   ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
  //     address(testPool),
  //     ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
  //     typedData
  //   );

  //   // Step 2: Compute the hash
  //   bytes32 orderHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, expiry, nonce, salt);

  //   // Step 3: Manager signs the hash
  //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(poolManagerPrivateKey, orderHash);
  //   bytes memory signature = abi.encodePacked(r, s, v);

  //   // Step 4: Verify signature via PoolLogic (simulating what Odos would do)
  //   bytes4 magicValue = testPool.isValidSignature(orderHash, signature);

  //   assertEq(magicValue, IERC1271.isValidSignature.selector, "Should return ERC-1271 magic value");
  // }

  // function test_is_valid_signature_reverts_for_unvalidated_hash() public {
  //   // Create a hash that was never submitted for validation
  //   bytes32 unvalidatedHash = keccak256("random unvalidated hash");

  //   // Manager signs it
  //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(poolManagerPrivateKey, unvalidatedHash);
  //   bytes memory signature = abi.encodePacked(r, s, v);

  //   // Should revert because hash is not validated
  //   vm.expectRevert(bytes("dh34"));
  //   testPool.isValidSignature(unvalidatedHash, signature);
  // }

  // function test_is_valid_signature_reverts_for_non_manager_signer() public {
  //   uint256 expiry = block.timestamp + 1 days;
  //   uint256 nonce = 0;
  //   uint256 salt = 12345;

  //   bytes memory typedData = _buildOdosLimitOrderTypedData(
  //     usdcData.asset,
  //     1000e6,
  //     wethData.asset,
  //     0.5 ether,
  //     expiry,
  //     nonce,
  //     salt
  //   );

  //   // Manager submits order
  //   vm.prank(poolManager);
  //   ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
  //     address(testPool),
  //     ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
  //     typedData
  //   );

  //   bytes32 orderHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, expiry, nonce, salt);

  //   // Someone else signs (not the manager)
  //   uint256 attackerPrivateKey = 0xBAD;
  //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPrivateKey, orderHash);
  //   bytes memory signature = abi.encodePacked(r, s, v);

  //   // Should revert because signer is not manager
  //   vm.expectRevert(bytes("dh33"));
  //   testPool.isValidSignature(orderHash, signature);
  // }

  function test_submit_order_reverts_for_unsupported_input_token() public {
    uint256 expiry = block.timestamp + 1 days;
    address unsupportedToken = address(0xDEAD);

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      unsupportedToken, // unsupported input token
      1000e18,
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(UNSUPPORTED_INPUT_TOKEN_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
  }

  function test_submit_order_reverts_for_unsupported_output_token() public {
    uint256 expiry = block.timestamp + 1 days;
    address unsupportedToken = address(0xDEAD);

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      unsupportedToken, // unsupported output token
      1000e18,
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(UNSUPPORTED_OUTPUT_TOKEN_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
  }

  function test_submit_order_reverts_for_non_manager() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_CALLER_SELECTOR, owner));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
  }

  function test_submit_order_reverts_for_mismatched_input_amount() public {
    uint256 expiry = block.timestamp + 1 days;

    // Build typed data with mismatched amounts:
    // permitted.amount = 1000e6, but witness.input.tokenAmount = 2000e6
    bytes memory typedData = _buildOdosLimitOrderTypedDataWithMismatchedAmount(
      usdcData.asset,
      1000e6, // permitted amount
      2000e6, // witness input amount (different!)
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(INPUT_AMOUNT_MISMATCH_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
  }

  function test_submit_order_reverts_for_unfavorable_rate() public {
    uint256 expiry = block.timestamp + 1 days;

    // Create an order with a very bad rate (selling USDC for way less WETH than market)
    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6, // 1000 USDC (worth ~$1000)
      wethData.asset,
      0.01 ether, // Only 0.01 WETH (worth ~$20-40) - massive loss!
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_RATE_TOO_UNFAVORABLE_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
  }

  function test_submit_order_reverts_for_expired_order() public {
    // Create an order that has already expired
    uint256 expiry = block.timestamp - 1;

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_EXPIRED_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
  }

  function test_submit_order_reverts_for_used_nonce() public {
    uint256 expiry = block.timestamp + 1 days;
    uint256 nonce = 12345;

    // Calculate the bitmap word and bit position for this nonce
    uint256 wordPos = nonce >> 8;
    uint256 bitPos = nonce & 0xFF;

    // Mock Permit2's nonceBitmap to return a bitmap with this nonce marked as used
    vm.mockCall(
      permit2,
      abi.encodeWithSignature("nonceBitmap(address,uint256)", address(testPool), wordPos),
      abi.encode(1 << bitPos)
    );

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      nonce, // nonce
      12345 // salt
    );

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(NONCE_ALREADY_USED_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );

    vm.clearMockedCalls();
  }

  function test_submit_order_allows_favorable_rate() public {
    uint256 expiry = block.timestamp + 1 days;

    // Create an order with a favorable rate (take profit - asking for more WETH than market)
    // If WETH is ~$4000, fair rate for 1000 USDC is ~0.25 ETH
    // Asking for 1 ETH (4x the fair amount) should be allowed - it just won't fill until price moves
    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6, // 1000 USDC
      wethData.asset,
      1 ether, // 1 WETH - favorable/take-profit rate
      expiry,
      0,
      12345
    );

    // This should succeed - favorable rates are always allowed
    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );

    bytes32 orderHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 1 ether, expiry, 0, 12345);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
      "Favorable rate order should be validated"
    );
  }

  function test_has_active_order_with_token_returns_true_for_active_order() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );

    // Both input and output tokens should be marked as having active orders
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), usdcData.asset),
      "Input token should have active order"
    );
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), wethData.asset),
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

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );

    // Before expiry
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), usdcData.asset),
      "Should have active order before expiry"
    );

    // Warp past expiry
    vm.warp(expiry + 1);

    // After expiry
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), usdcData.asset),
      "Should not have active order after expiry"
    );
  }

  // ============ EnumerableSet & Order Management Tests ============

  function test_get_pool_order_hashes_returns_all_hashes() public {
    uint256 expiry = block.timestamp + 1 days;

    // Submit 3 orders with different salts
    bytes32[] memory expectedHashes = new bytes32[](3);
    for (uint256 i = 0; i < 3; i++) {
      bytes memory typedData = _buildOdosLimitOrderTypedData(
        usdcData.asset,
        1000e6,
        wethData.asset,
        0.5 ether,
        expiry,
        i, // nonce
        12345 + i // unique salt
      );

      vm.prank(poolManager);
      ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
        address(testPool),
        ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
        typedData
      );

      expectedHashes[i] = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, expiry, i, 12345 + i);
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

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    // Submit same order twice
    vm.startPrank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
    vm.stopPrank();

    // EnumerableSet should prevent duplicate - only 1 hash stored
    bytes32[] memory storedHashes = ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(
      address(testPool)
    );
    assertEq(storedHashes.length, 1, "Should only have 1 hash (no duplicates)");
  }

  // function test_remove_order_removes_hash_from_set() public {
  //   uint256 expiry = block.timestamp + 1 days;

  //   bytes memory typedData = _buildOdosLimitOrderTypedData(
  //     usdcData.asset,
  //     1000e6,
  //     wethData.asset,
  //     0.5 ether,
  //     expiry,
  //     0,
  //     12345
  //   );

  //   vm.prank(poolManager);
  //   ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
  //     address(testPool),
  //     ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
  //     typedData
  //   );

  //   bytes32 orderHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, expiry, 0, 12345);

  //   // Verify hash is stored and validated
  //   assertEq(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
  //     1,
  //     "Should have 1 hash before removal"
  //   );
  //   assertTrue(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
  //     "Hash should be validated before removal"
  //   );

  //   // Sign the order (to test signature invalidation)
  //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(poolManagerPrivateKey, orderHash);
  //   bytes memory signature = abi.encodePacked(r, s, v);
  //   assertEq(
  //     testPool.isValidSignature(orderHash, signature),
  //     IERC1271.isValidSignature.selector,
  //     "Signature should be valid before removal"
  //   );

  //   // Owner removes the order
  //   vm.prank(owner);
  //   ITypedStructuredDataValidatorMock(dataValidatorProxy).removeOrder(address(testPool), orderHash);

  //   // Verify order hash is removed from tracking
  //   assertEq(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
  //     0,
  //     "Should have 0 hashes after removal"
  //   );

  //   // Verify hash is invalidated (removed from validatedHashes)
  //   assertFalse(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
  //     "Hash should NOT be validated after removal"
  //   );

  //   // Verify signature is now invalid
  //   vm.expectRevert(bytes("dh34"));
  //   testPool.isValidSignature(orderHash, signature);

  //   // Token should no longer be locked
  //   assertFalse(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), usdcData.asset),
  //     "Token should not be locked after order removal"
  //   );
  // }

  function test_remove_order_reverts_for_non_existent_order() public {
    bytes32 nonExistentHash = keccak256("non-existent");

    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(ORDER_NOT_FOUND_SELECTOR, address(testPool), nonExistentHash));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).removeOrder(address(testPool), nonExistentHash);
  }

  // ============ Cancel Order Tests (Manager/Trader) ============

  // function test_cancel_order_manager_can_cancel_order() public {
  //   uint256 expiry = block.timestamp + 1 days;

  //   bytes memory typedData = _buildOdosLimitOrderTypedData(
  //     usdcData.asset,
  //     1000e6,
  //     wethData.asset,
  //     0.5 ether,
  //     expiry,
  //     0,
  //     12345
  //   );

  //   vm.prank(poolManager);
  //   ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
  //     address(testPool),
  //     ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
  //     typedData
  //   );

  //   bytes32 orderHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, expiry, 0, 12345);

  //   // Verify order is active before cancel
  //   assertTrue(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
  //     "Hash should be validated before cancel"
  //   );
  //   assertEq(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
  //     1,
  //     "Should have 1 order before cancel"
  //   );

  //   // Sign the order (to test signature invalidation)
  //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(poolManagerPrivateKey, orderHash);
  //   bytes memory signature = abi.encodePacked(r, s, v);
  //   assertEq(
  //     testPool.isValidSignature(orderHash, signature),
  //     IERC1271.isValidSignature.selector,
  //     "Signature should be valid before cancel"
  //   );

  //   // Manager cancels the order
  //   vm.prank(poolManager);
  //   ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderHash);

  //   // Verify hash is invalidated
  //   assertFalse(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderHash),
  //     "Hash should NOT be validated after cancel"
  //   );

  //   // Verify order is removed from tracking
  //   assertEq(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
  //     0,
  //     "Should have 0 orders after cancel"
  //   );

  //   // Verify signature is now invalid
  //   vm.expectRevert(bytes("dh34"));
  //   testPool.isValidSignature(orderHash, signature);

  //   // Token should no longer be locked
  //   assertFalse(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(address(testPool), usdcData.asset),
  //     "Token should not be locked after cancel"
  //   );
  // }

  function test_cancel_order_reverts_for_non_manager() public {
    uint256 expiry = block.timestamp + 1 days;

    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      0,
      12345
    );

    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );

    bytes32 orderHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, expiry, 0, 12345);

    // Random user tries to cancel - should fail
    vm.prank(investor);
    vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_CALLER_SELECTOR, investor));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderHash);
  }

  function test_cancel_order_reverts_for_non_existent_order() public {
    bytes32 nonExistentHash = keccak256("non-existent");

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_NOT_FOUND_SELECTOR, address(testPool), nonExistentHash));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), nonExistentHash);
  }

  // ============ Auto Cleanup Tests ============

  function test_submit_order_cleans_up_expired_orders() public {
    uint256 shortExpiry = block.timestamp + 1 hours;
    uint256 longExpiry = block.timestamp + 1 days;

    // Submit an order with short expiry
    bytes memory shortExpiryData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      shortExpiry,
      0,
      11111
    );

    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      shortExpiryData
    );

    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      1,
      "Should have 1 order"
    );

    // Warp past short expiry
    vm.warp(shortExpiry + 1);

    // Submit another order - this should trigger cleanup of expired order
    bytes memory longExpiryData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      2000e6,
      wethData.asset,
      1 ether,
      longExpiry,
      1,
      22222
    );

    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      longExpiryData
    );

    // Should only have 1 order (expired one was cleaned up)
    bytes32[] memory hashes = ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(
      address(testPool)
    );
    assertEq(hashes.length, 1, "Should have 1 order after cleanup");

    // The remaining hash should be the long expiry order
    bytes32 expectedHash = _computeOrderHash(usdcData.asset, 2000e6, wethData.asset, 1 ether, longExpiry, 1, 22222);
    assertEq(hashes[0], expectedHash, "Remaining hash should be the long expiry order");

    // Verify expired order's hash is also removed from validatedHashes (defense-in-depth cleanup)
    bytes32 expiredHash = _computeOrderHash(usdcData.asset, 1000e6, wethData.asset, 0.5 ether, shortExpiry, 0, 11111);
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), expiredHash),
      "Expired order hash should be removed from validatedHashes"
    );
  }

  // ============ Max Orders Limit Tests ============

  function test_submit_order_reverts_when_max_orders_reached() public {
    uint256 maxOrders = ITypedStructuredDataValidatorMock(dataValidatorProxy).MAX_ORDERS_PER_POOL();
    uint256 expiry = block.timestamp + 1 days;

    // Submit max orders
    vm.startPrank(poolManager);
    for (uint256 i = 0; i < maxOrders; i++) {
      bytes memory typedData = _buildOdosLimitOrderTypedData(
        usdcData.asset,
        1000e6,
        wethData.asset,
        0.5 ether,
        expiry,
        i, // unique nonce
        i // unique salt
      );

      ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
        address(testPool),
        ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
        typedData
      );
    }
    vm.stopPrank();

    // Verify we're at max
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      maxOrders,
      "Should be at max orders"
    );

    // Try to submit one more - should revert
    bytes memory extraOrder = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      1000e6,
      wethData.asset,
      0.5 ether,
      expiry,
      maxOrders, // next nonce
      maxOrders // next salt
    );

    vm.prank(poolManager);
    vm.expectRevert(abi.encodeWithSelector(MAX_ORDERS_REACHED_SELECTOR, address(testPool)));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      extraOrder
    );
  }

  function test_submit_order_succeeds_after_cleanup_frees_slots() public {
    uint256 maxOrders = ITypedStructuredDataValidatorMock(dataValidatorProxy).MAX_ORDERS_PER_POOL();
    uint256 shortExpiry = block.timestamp + 1 hours;
    uint256 longExpiry = block.timestamp + 1 days;

    // Submit max orders with short expiry
    vm.startPrank(poolManager);
    for (uint256 i = 0; i < maxOrders; i++) {
      bytes memory typedData = _buildOdosLimitOrderTypedData(
        usdcData.asset,
        1000e6,
        wethData.asset,
        0.5 ether,
        shortExpiry,
        i,
        i
      );

      ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
        address(testPool),
        ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
        typedData
      );
    }
    vm.stopPrank();

    // Warp past expiry
    vm.warp(shortExpiry + 1);

    // Now submit should succeed because cleanup will free all slots
    bytes memory newOrder = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      2000e6,
      wethData.asset,
      1 ether,
      longExpiry,
      maxOrders,
      maxOrders
    );

    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      newOrder
    );

    // Should only have 1 order (all expired ones cleaned up)
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      1,
      "Should have 1 order after cleanup"
    );
  }

  // ============ End-to-End Integration Test ============

  /// @notice Test that the pool can approve Permit2 and the approval works correctly
  function test_e2e_pool_can_approve_permit2() public {
    // Get pool balance of USDC
    uint256 poolUsdcBalance = IERC20(usdcData.asset).balanceOf(address(testPool));
    assertTrue(poolUsdcBalance > 0, "Pool should have USDC balance");

    // Manager approves input token for Permit2 (unlimited approval)
    bytes memory approveCalldata = abi.encodeWithSelector(IERC20.approve.selector, permit2, type(uint256).max);

    // Execute approval via testPool
    vm.prank(poolManager);
    testPool.execTransaction(usdcData.asset, approveCalldata);

    // Verify approval
    uint256 allowance = IERC20(usdcData.asset).allowance(address(testPool), permit2);
    assertEq(allowance, type(uint256).max, "Pool should have unlimited approval for Permit2");
  }

  // /// @notice Test the complete flow of submitting an order and having it validated by the real Odos router
  // /// @dev This test verifies that:
  // ///      1. Pool can approve input token for Permit2
  // ///      2. Manager can submit an order via TypedStructuredDataValidator
  // ///      3. The signature computed matches what Permit2 expects
  // ///      4. fillLimitOrderPermit2 progresses through signature validation
  // function test_e2e_fill_limit_order_permit2_signature_validation() public {
  //   // Step 1: Manager approves input token for Permit2
  //   vm.prank(poolManager);
  //   testPool.execTransaction(
  //     usdcData.asset,
  //     abi.encodeWithSelector(IERC20.approve.selector, permit2, type(uint256).max)
  //   );

  //   // Step 2: Submit order and get hash
  //   uint256 expiry = block.timestamp + 1 days;
  //   bytes32 orderHash = _submitOrderAndGetHash(address(testPool), 1000e6, 0.5 ether, expiry, 0, 12345);

  //   // Step 3: Sign and verify
  //   bytes memory signature = _signAndVerifyOrder(testPool, orderHash);

  //   // Step 4: Call router with signed order
  //   _callRouterWithOrder(testPool, signature, 1000e6, 0.5 ether, expiry, 0, 12345);
  // }

  // ============ Helper Functions for Building EIP-712 Typed Data ============

  /// @dev Build the LimitOrder witness struct
  function _buildLimitOrder(
    address inputToken,
    uint256 inputAmount,
    address outputToken,
    uint256 outputAmount,
    uint256 expiry,
    uint256 salt
  ) internal pure returns (OdosLimitOrderTypeHashLib.LimitOrder memory) {
    return
      OdosLimitOrderTypeHashLib.LimitOrder({
        input: OdosLimitOrderTypeHashLib.TokenInfo({tokenAddress: inputToken, tokenAmount: inputAmount}),
        output: OdosLimitOrderTypeHashLib.TokenInfo({tokenAddress: outputToken, tokenAmount: outputAmount}),
        expiry: expiry,
        salt: salt,
        referralCode: 0,
        referralFee: 0,
        referralFeeRecipient: address(0),
        partiallyFillable: false
      });
  }

  /// @dev Build the PermitWitnessTransferFrom struct
  function _buildPermitWitnessTransferFrom(
    address inputToken,
    uint256 inputAmount,
    uint256 expiry,
    uint256 nonce,
    OdosLimitOrderTypeHashLib.LimitOrder memory witness
  ) internal view returns (OdosLimitOrderTypeHashLib.PermitWitnessTransferFrom memory) {
    return
      OdosLimitOrderTypeHashLib.PermitWitnessTransferFrom({
        permitted: OdosLimitOrderTypeHashLib.TokenPermissions({token: inputToken, amount: inputAmount}),
        spender: odosLimitOrderRouter,
        nonce: nonce,
        deadline: expiry,
        witness: witness
      });
  }

  /// @dev Build the EIP712Domain struct
  function _buildEIP712Domain() internal view returns (OdosLimitOrderTypeHashLib.EIP712Domain memory) {
    return
      OdosLimitOrderTypeHashLib.EIP712Domain({name: "Permit2", chainId: _getChainId(), verifyingContract: permit2});
  }

  /// @dev Build the full OdosLimitOrderTypedData structure for testing
  /// @param inputToken Token to sell
  /// @param inputAmount Amount to sell
  /// @param outputToken Token to buy
  /// @param outputAmount Minimum amount to receive
  /// @param expiry Order expiration timestamp
  /// @param nonce Permit2 nonce
  /// @param salt Unique salt for order
  function _buildOdosLimitOrderTypedData(
    address inputToken,
    uint256 inputAmount,
    address outputToken,
    uint256 outputAmount,
    uint256 expiry,
    uint256 nonce,
    uint256 salt
  ) internal view returns (bytes memory) {
    OdosLimitOrderTypeHashLib.LimitOrder memory witness = _buildLimitOrder(
      inputToken,
      inputAmount,
      outputToken,
      outputAmount,
      expiry,
      salt
    );

    OdosLimitOrderTypeHashLib.PermitWitnessTransferFrom memory message = _buildPermitWitnessTransferFrom(
      inputToken,
      inputAmount,
      expiry,
      nonce,
      witness
    );

    OdosLimitOrderTypeHashLib.OdosLimitOrderTypedData memory typedData = OdosLimitOrderTypeHashLib
      .OdosLimitOrderTypedData({domain: _buildEIP712Domain(), message: message});

    return abi.encode(typedData);
  }

  function _buildOdosLimitOrderTypedDataWithMismatchedAmount(
    address inputToken,
    uint256 permittedAmount,
    uint256 witnessInputAmount,
    address outputToken,
    uint256 outputAmount,
    uint256 expiry,
    uint256 nonce,
    uint256 salt
  ) internal view returns (bytes memory) {
    // Build witness with witnessInputAmount
    OdosLimitOrderTypeHashLib.LimitOrder memory witness = _buildLimitOrder(
      inputToken,
      witnessInputAmount, // Use different amount here
      outputToken,
      outputAmount,
      expiry,
      salt
    );

    // Build permit with permittedAmount (different from witness)
    OdosLimitOrderTypeHashLib.PermitWitnessTransferFrom memory message = OdosLimitOrderTypeHashLib
      .PermitWitnessTransferFrom({
        permitted: OdosLimitOrderTypeHashLib.TokenPermissions({token: inputToken, amount: permittedAmount}),
        spender: odosLimitOrderRouter,
        nonce: nonce,
        deadline: expiry,
        witness: witness
      });

    OdosLimitOrderTypeHashLib.OdosLimitOrderTypedData memory typedData = OdosLimitOrderTypeHashLib
      .OdosLimitOrderTypedData({domain: _buildEIP712Domain(), message: message});

    return abi.encode(typedData);
  }

  /// @dev Get chain ID (compatible with Solidity 0.7.6)
  function _getChainId() internal pure returns (uint256 chainId) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      chainId := chainid()
    }
  }

  /// @dev Compute the EIP-712 hash that needs to be signed
  /// This replicates the hash computation from OdosLimitOrderValidator
  function _computeOrderHash(
    address inputToken,
    uint256 inputAmount,
    address outputToken,
    uint256 outputAmount,
    uint256 expiry,
    uint256 nonce,
    uint256 salt
  ) internal view returns (bytes32) {
    bytes32 limitOrderHash = _computeLimitOrderHash(inputToken, inputAmount, outputToken, outputAmount, expiry, salt);
    bytes32 permitHash = _computePermitHash(inputToken, inputAmount, nonce, expiry, limitOrderHash);
    bytes32 domainSeparator = _computeDomainSeparator();

    // Final EIP-712 digest
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));
  }

  function _computeLimitOrderHash(
    address inputToken,
    uint256 inputAmount,
    address outputToken,
    uint256 outputAmount,
    uint256 expiry,
    uint256 salt
  ) internal pure returns (bytes32) {
    bytes32 inputHash = keccak256(abi.encode(OdosLimitOrderTypeHashLib.TOKEN_INFO_TYPEHASH, inputToken, inputAmount));
    bytes32 outputHash = keccak256(
      abi.encode(OdosLimitOrderTypeHashLib.TOKEN_INFO_TYPEHASH, outputToken, outputAmount)
    );

    return
      keccak256(
        abi.encode(
          OdosLimitOrderTypeHashLib.LIMIT_ORDER_TYPEHASH,
          inputHash,
          outputHash,
          expiry,
          salt,
          uint64(0), // referralCode
          uint64(0), // referralFee
          address(0), // referralFeeRecipient
          false // partiallyFillable
        )
      );
  }

  function _computePermitHash(
    address inputToken,
    uint256 inputAmount,
    uint256 nonce,
    uint256 expiry,
    bytes32 limitOrderHash
  ) internal view returns (bytes32) {
    bytes32 tokenPermissionsHash = keccak256(
      abi.encode(OdosLimitOrderTypeHashLib.TOKEN_PERMISSIONS_TYPEHASH, inputToken, inputAmount)
    );

    return
      keccak256(
        abi.encode(
          OdosLimitOrderTypeHashLib.PERMIT_WITNESS_TRANSFER_FROM_TYPEHASH,
          tokenPermissionsHash,
          odosLimitOrderRouter, // spender
          nonce,
          expiry, // deadline
          limitOrderHash
        )
      );
  }

  function _computeDomainSeparator() internal view returns (bytes32) {
    return
      keccak256(
        abi.encode(OdosLimitOrderTypeHashLib.EIP712_DOMAIN_TYPEHASH, keccak256("Permit2"), _getChainId(), permit2)
      );
  }

  // ============ Internal Helper Functions for E2E Test ============

  function _submitOrderAndGetHash(
    address pool,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 expiry,
    uint256 nonce,
    uint256 salt
  ) internal returns (bytes32) {
    bytes memory typedData = _buildOdosLimitOrderTypedData(
      usdcData.asset,
      inputAmount,
      wethData.asset,
      outputAmount,
      expiry,
      nonce,
      salt
    );
    vm.prank(poolManager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      pool,
      ITypedStructuredDataValidatorMock.StructuredDataSupported.ODOS_LIMIT_ORDER,
      typedData
    );
    return _computeOrderHash(usdcData.asset, inputAmount, wethData.asset, outputAmount, expiry, nonce, salt);
  }

  // function _signAndVerifyOrder(PoolLogic pool, bytes32 orderHash) internal view returns (bytes memory) {
  //   assertTrue(
  //     ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(pool), orderHash),
  //     "Hash stored"
  //   );
  //   (uint8 v, bytes32 r, bytes32 s) = vm.sign(poolManagerPrivateKey, orderHash);
  //   bytes memory signature = abi.encodePacked(r, s, v);
  //   assertEq(
  //     pool.isValidSignature(orderHash, signature),
  //     bytes4(IERC1271.isValidSignature.selector),
  //     "Valid signature"
  //   );
  //   return signature;
  // }

  function _callRouterWithOrder(
    PoolLogic pool,
    bytes memory signature,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 expiry,
    uint256 nonce,
    uint256 salt
  ) internal {
    IOdosLimitOrderRouter router = IOdosLimitOrderRouter(odosLimitOrderRouter);

    vm.prank(router.owner());
    router.addAllowedFiller(MOCKED_FILLER);

    assertTrue(router.allowedFillers(MOCKED_FILLER), "Mocked filler should now be allowed");

    _executeFillOrder(pool, router, signature, inputAmount, outputAmount, expiry, nonce, salt);
  }

  function _executeFillOrder(
    PoolLogic pool,
    IOdosLimitOrderRouter router,
    bytes memory signature,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 expiry,
    uint256 nonce,
    uint256 salt
  ) internal {
    IOdosLimitOrderRouter.LimitOrder memory limitOrder = _buildLimitOrderStruct(
      usdcData.asset,
      inputAmount,
      wethData.asset,
      outputAmount,
      expiry,
      salt
    );
    IOdosLimitOrderRouter.LimitOrderContext memory context = _buildContext(inputAmount, address(router));
    IOdosLimitOrderRouter.Permit2Info memory permit2Info = _buildPermit2Info(nonce, expiry, address(pool), signature);

    // Note: This call will revert after Permit2 transfer because we don't have a real Odos executor.
    // The important thing is that:
    // 1. isValidSignature was already verified in _signAndVerifyOrder() to return 0x1626ba7e
    // 2. Permit2 successfully transfers tokens (visible in trace with -vvvv)
    // forge test --match-test "test_e2e_fillLimitOrderPermit2_signatureValidation" -vvvv | grep -E "Transfer"
    // The revert happens in _limitOrderFill when trying to execute the swap with no executor.
    vm.prank(MOCKED_FILLER);
    // solhint-disable-next-line no-empty-blocks
    try router.fillLimitOrderPermit2(limitOrder, context, permit2Info) {} catch {
      // Expected to revert after signature validation and token transfer
      // because we don't have a real Odos executor configured
      emit log_string("fillLimitOrderPermit2 reverted after Permit2 transfer (expected - no executor)");
    }
  }

  function _buildLimitOrderStruct(
    address inputToken,
    uint256 inputAmount,
    address outputToken,
    uint256 outputAmount,
    uint256 expiry,
    uint256 salt
  ) internal pure returns (IOdosLimitOrderRouter.LimitOrder memory) {
    return
      IOdosLimitOrderRouter.LimitOrder({
        input: IOdosLimitOrderRouter.TokenInfo({tokenAddress: inputToken, tokenAmount: inputAmount}),
        output: IOdosLimitOrderRouter.TokenInfo({tokenAddress: outputToken, tokenAmount: outputAmount}),
        expiry: expiry,
        salt: salt,
        referralCode: 0,
        referralFee: 0,
        referralFeeRecipient: address(0),
        partiallyFillable: false
      });
  }

  function _buildContext(
    uint256 currentAmount,
    address inputReceiver
  ) internal pure returns (IOdosLimitOrderRouter.LimitOrderContext memory) {
    return
      IOdosLimitOrderRouter.LimitOrderContext({
        pathDefinition: "",
        odosExecutor: address(0),
        currentAmount: currentAmount,
        inputReceiver: inputReceiver,
        minSurplus: 0,
        orderType: 0
      });
  }

  function _buildPermit2Info(
    uint256 nonce,
    uint256 deadline,
    address orderOwner,
    bytes memory sig
  ) internal view returns (IOdosLimitOrderRouter.Permit2Info memory) {
    return
      IOdosLimitOrderRouter.Permit2Info({
        contractAddress: permit2,
        nonce: nonce,
        deadline: deadline,
        orderOwner: orderOwner,
        signature: sig
      });
  }
}
