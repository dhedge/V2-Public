// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ClosedContractGuard} from "contracts/guards/contractGuards/ClosedContractGuard.sol";
import {GPv2SettlementContractGuard} from "contracts/guards/contractGuards/cowSwap/GPv2SettlementContractGuard.sol";
import {IGPv2Settlement} from "contracts/interfaces/cowSwap/IGPv2Settlement.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {CowSwapOrderTypeHashLib} from "contracts/validators/cowSwap/CowSwapOrderTypeHashLib.sol";
import {TypedStructuredDataValidatorTestSetup} from "test/integration/common/core/TypedStructuredDataValidatorTestSetup.t.sol";
import {ITypedStructuredDataValidatorMock} from "test/integration/common/odos/ITypedStructuredDataValidatorMock.sol";

/// @dev Validates the CoWSwap PreSign flow:
///      1. Submit order to TypedStructuredDataValidator for validation
///      2. Call GPv2Settlement.setPreSignature(orderUid, true) through pool
///
///      Note: Unlike Odos orders that use ERC-1271, CoWSwap PreSign orders
///      don't require the pool to implement isValidSignature. The setPreSignature
///      call itself authorizes the order for execution.
abstract contract CowSwapTestSetup is TypedStructuredDataValidatorTestSetup {
  // ============ Error Selectors (from CowSwapOrderValidator) ============
  bytes4 internal constant DOMAIN_NAME_MISMATCH_SELECTOR = bytes4(keccak256("DomainNameMismatch()"));
  bytes4 internal constant DOMAIN_VERSION_MISMATCH_SELECTOR = bytes4(keccak256("DomainVersionMismatch()"));
  bytes4 internal constant DOMAIN_CHAIN_MISMATCH_SELECTOR = bytes4(keccak256("DomainChainMismatch()"));
  bytes4 internal constant DOMAIN_VERIFYING_CONTRACT_MISMATCH_SELECTOR =
    bytes4(keccak256("DomainVerifyingContractMismatch()"));
  bytes4 internal constant INVALID_RECEIVER_SELECTOR = bytes4(keccak256("InvalidReceiver()"));
  bytes4 internal constant UNSUPPORTED_SELL_TOKEN_SELECTOR = bytes4(keccak256("UnsupportedSellToken()"));
  bytes4 internal constant UNSUPPORTED_BUY_TOKEN_SELECTOR = bytes4(keccak256("UnsupportedBuyToken()"));
  bytes4 internal constant INVALID_SELL_TOKEN_BALANCE_SELECTOR = bytes4(keccak256("InvalidSellTokenBalance()"));
  bytes4 internal constant INVALID_BUY_TOKEN_BALANCE_SELECTOR = bytes4(keccak256("InvalidBuyTokenBalance()"));
  bytes4 internal constant INVALID_ORDER_KIND_SELECTOR = bytes4(keccak256("InvalidOrderKind()"));
  bytes4 internal constant ORDER_EXPIRED_SELECTOR = bytes4(keccak256("OrderExpired()"));
  bytes4 internal constant ORDER_RATE_TOO_UNFAVORABLE_SELECTOR = bytes4(keccak256("OrderRateTooUnfavorable()"));
  bytes4 internal constant NON_ZERO_FEE_AMOUNT_SELECTOR = bytes4(keccak256("NonZeroFeeAmount()"));

  /// @dev Marker value indicating an order is pre-signed (from GPv2Signing.sol)
  uint256 private constant PRE_SIGNED = uint256(keccak256("GPv2Signing.Scheme.PreSign"));

  /// @dev GPv2Settlement contract address (parameterized for different chains)
  address public gpv2Settlement;

  /// @dev GPv2VaultRelayer contract address (parameterized for different chains)
  address public gpv2VaultRelayer;

  constructor(address _gpv2Settlement, address _gpv2VaultRelayer) {
    gpv2Settlement = _gpv2Settlement;
    gpv2VaultRelayer = _gpv2VaultRelayer;
  }

  function setUp() public virtual override {
    super.setUp();

    vm.label(gpv2Settlement, "GPv2Settlement");
    vm.label(gpv2VaultRelayer, "GPv2VaultRelayer");
  }

  // ============ Abstract Method Implementations ============

  function _setupValidationConfig() internal virtual override {
    // Configure CoWSwap validation
    // 100 bps = 1% max unfavorable deviation from oracle rate
    bytes memory cowSwapConfig = abi.encode(gpv2Settlement, 100);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).setValidationConfig(
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      cowSwapConfig
    );
  }

  function _setupProtocolGuards() internal virtual override {
    address gpv2SettlementGuard = address(new GPv2SettlementContractGuard(address(poolFactoryProxy)));

    // Set the guard for GPv2Settlement contract
    governance.setContractGuard(gpv2Settlement, gpv2SettlementGuard);

    // GPv2VaultRelayer Security Analysis:
    // ===================================
    // Unlike Permit2 which has two-layer security (ERC20 approval + internal allowance requiring signature),
    // GPv2VaultRelayer uses a different but equally strong protection: the `onlyCreator` modifier.
    //
    // Key security points:
    // 1. GPv2VaultRelayer.transferFromAccounts() can ONLY be called by its `creator` (immutable, set at deployment)
    // 2. The `creator` is GPv2Settlement itself (deployed it in constructor: `vaultRelayer = new GPv2VaultRelayer()`)
    // 3. GPv2Settlement only calls transferFromAccounts() from settle(), which requires:
    //    - Caller is an authorized solver (onlySolver modifier)
    //    - Valid order signature (ECDSA, EIP-1271, or PreSign)
    //
    // For dHEDGE pools (smart contracts), order signing options are:
    // - ECDSA (Eip712/EthSign): Impossible - pools have no private keys
    // - EIP-1271: Impossible - PoolLogic has no isValidSignature function
    // - PreSign: Only option - requires pool to call setPreSignature(), guarded by GPv2SettlementContractGuard
    //
    // Therefore, tokens cannot be swept even with max approval to GPv2VaultRelayer because:
    // - No one except GPv2Settlement can call transferFromAccounts()
    // - GPv2Settlement only transfers for valid signed orders
    // - The only way to "sign" for a pool is PreSign, which goes through our guard validation
    //
    // Set ClosedContractGuard for GPv2VaultRelayer (required for token approvals)
    ClosedContractGuard closedGuard = new ClosedContractGuard();
    governance.setContractGuard(gpv2VaultRelayer, address(closedGuard));
  }

  function _buildOrderTypedData(uint256 expiry, uint256 index) internal view virtual override returns (bytes memory) {
    // Use slightly different buyAmount to make orders unique
    uint256 buyAmount = 0.33 ether + (index * 0.001 ether);
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      1000e6,
      buyAmount,
      uint32(expiry),
      CowSwapOrderTypeHashLib.KIND_SELL
    );
    return abi.encode(typedData);
  }

  function _getOrderHash(bytes memory typedData) internal view virtual override returns (bytes32) {
    CowSwapOrderTypeHashLib.CowSwapTypedData memory decoded = abi.decode(
      typedData,
      (CowSwapOrderTypeHashLib.CowSwapTypedData)
    );
    return CowSwapOrderTypeHashLib.getDigest(decoded);
  }

  function _getOrderInputToken(bytes memory typedData) internal pure virtual override returns (address) {
    CowSwapOrderTypeHashLib.CowSwapTypedData memory decoded = abi.decode(
      typedData,
      (CowSwapOrderTypeHashLib.CowSwapTypedData)
    );
    return decoded.order.sellToken;
  }

  function _getOrderOutputToken(bytes memory typedData) internal pure virtual override returns (address) {
    CowSwapOrderTypeHashLib.CowSwapTypedData memory decoded = abi.decode(
      typedData,
      (CowSwapOrderTypeHashLib.CowSwapTypedData)
    );
    return decoded.order.buyToken;
  }

  function _getOrderType()
    internal
    pure
    virtual
    override
    returns (ITypedStructuredDataValidatorMock.StructuredDataSupported)
  {
    return ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER;
  }

  // ============ Test: Submit order and call setPreSignature ============

  function test_setPreSignature_succeeds_after_validation() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Build typed data using CowSwapOrderTypeHashLib
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    // Step 1: Manager submits order for validation
    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    // Step 2: Compute order hash using CowSwapOrderTypeHashLib
    // We use CowSwapOrderTypeHashLib here because CowSwapHashValidationTest FFI tests have verified it produces the same digest as the CoWSwap API
    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);

    // Verify the hash is validated
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Order hash should be validated"
    );

    // Step 3: Build orderUid
    bytes memory orderUid = abi.encodePacked(orderDigest, address(testPool), validTo);

    // Step 4: Manager approves sell token for VaultRelayer (required for order execution)
    vm.prank(manager);
    testPool.execTransaction(
      usdcData.asset,
      abi.encodeWithSelector(IERC20.approve.selector, gpv2VaultRelayer, type(uint256).max)
    );

    // Step 5: Manager calls setPreSignature through pool
    bytes memory setPreSignatureData = abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true);

    vm.prank(manager);
    testPool.execTransaction(gpv2Settlement, setPreSignatureData);

    // Step 6: Verify pre-signature was set
    uint256 preSignatureValue = IGPv2Settlement(gpv2Settlement).preSignature(orderUid);
    assertEq(preSignatureValue, PRE_SIGNED, "Order should be pre-signed");
  }

  function test_setPreSignature_reverts_for_non_validated_order() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Create a fake order digest that was never validated
    bytes32 fakeOrderDigest = keccak256("fake order");
    bytes memory orderUid = abi.encodePacked(fakeOrderDigest, address(testPool), validTo);

    // Try to call setPreSignature without validating the order first
    bytes memory setPreSignatureData = abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true);

    vm.prank(manager);
    vm.expectRevert("GPv2Guard: order not validated");
    testPool.execTransaction(gpv2Settlement, setPreSignatureData);
  }

  function test_setPreSignature_reverts_for_wrong_owner() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Build valid order and get its digest
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);

    // Build orderUid with WRONG owner
    address wrongOwner = makeAddr("wrongOwner");
    bytes memory orderUid = abi.encodePacked(orderDigest, wrongOwner, validTo);

    bytes memory setPreSignatureData = abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true);

    vm.prank(manager);
    vm.expectRevert("GPv2Guard: owner must be pool");
    testPool.execTransaction(gpv2Settlement, setPreSignatureData);
  }

  function test_setPreSignature_reverts_for_expired_order() public {
    uint32 validTo = uint32(block.timestamp - 1); // Already expired

    // Even if somehow an expired order got validated, the guard should reject it
    bytes32 fakeDigest = keccak256("expired order");
    bytes memory orderUid = abi.encodePacked(fakeDigest, address(testPool), validTo);

    bytes memory setPreSignatureData = abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true);

    vm.prank(manager);
    vm.expectRevert("GPv2Guard: order expired");
    testPool.execTransaction(gpv2Settlement, setPreSignatureData);
  }

  function test_invalidateOrder_succeeds_for_pool_order() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // First, set up a pre-signed order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    bytes memory orderUid = abi.encodePacked(orderDigest, address(testPool), validTo);

    // Pre-sign the order
    bytes memory setPreSignatureData = abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true);
    vm.prank(manager);
    testPool.execTransaction(gpv2Settlement, setPreSignatureData);

    // Now invalidate the order
    bytes memory invalidateData = abi.encodeWithSelector(IGPv2Settlement.invalidateOrder.selector, orderUid);
    vm.prank(manager);
    testPool.execTransaction(gpv2Settlement, invalidateData);

    // Verify order is invalidated (filledAmount = MAX)
    uint256 filledAmountValue = IGPv2Settlement(gpv2Settlement).filledAmount(orderUid);
    assertEq(filledAmountValue, type(uint256).max, "Order should be invalidated");
  }

  // ============ Fill Tracking Tests ============

  function test_is_order_filled_returns_false_for_unfilled_order() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Submit an order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);

    // Check that isOrderFilled returns false for unfilled order
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isOrderFilled(address(testPool), orderDigest),
      "Unfilled order should return false"
    );
  }

  function test_is_order_filled_returns_true_after_order_invalidated() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Submit and pre-sign an order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    bytes memory orderUid = abi.encodePacked(orderDigest, address(testPool), validTo);

    // Pre-sign the order (required to invalidate it later)
    bytes memory setPreSignatureData = abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true);
    vm.prank(manager);
    testPool.execTransaction(gpv2Settlement, setPreSignatureData);

    // Invalidate the order (sets filledAmount to MAX)
    bytes memory invalidateData = abi.encodeWithSelector(IGPv2Settlement.invalidateOrder.selector, orderUid);
    vm.prank(manager);
    testPool.execTransaction(gpv2Settlement, invalidateData);

    // Check that isOrderFilled returns true after invalidation
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isOrderFilled(address(testPool), orderDigest),
      "Invalidated order should be considered filled"
    );
  }

  function test_has_active_order_with_token_returns_false_after_order_filled() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Submit and pre-sign an order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    bytes memory orderUid = abi.encodePacked(orderDigest, address(testPool), validTo);

    // Before fill: hasActiveOrderWithToken should return true
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        typedData.order.sellToken
      ),
      "Should have active order with sell token before fill"
    );
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        typedData.order.buyToken
      ),
      "Should have active order with buy token before fill"
    );

    // Pre-sign and then invalidate (simulate fill by setting filledAmount to MAX)
    vm.prank(manager);
    testPool.execTransaction(
      gpv2Settlement,
      abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true)
    );
    vm.prank(manager);
    testPool.execTransaction(
      gpv2Settlement,
      abi.encodeWithSelector(IGPv2Settlement.invalidateOrder.selector, orderUid)
    );

    // After fill: hasActiveOrderWithToken should return false (order is filled, even before expiry)
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        typedData.order.sellToken
      ),
      "Should NOT have active order with sell token after fill"
    );
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        typedData.order.buyToken
      ),
      "Should NOT have active order with buy token after fill"
    );
  }

  function test_cleanup_removes_filled_orders_on_submit() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Submit first order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData1 = _buildTypedData(validTo);

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData1)
    );

    bytes32 orderDigest1 = CowSwapOrderTypeHashLib.getDigest(typedData1);
    bytes memory orderUid1 = abi.encodePacked(orderDigest1, address(testPool), validTo);

    // Pre-sign and invalidate first order (mark as filled)
    vm.prank(manager);
    testPool.execTransaction(
      gpv2Settlement,
      abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid1, true)
    );
    vm.prank(manager);
    testPool.execTransaction(
      gpv2Settlement,
      abi.encodeWithSelector(IGPv2Settlement.invalidateOrder.selector, orderUid1)
    );

    // Verify first order is still in the pool's order list (not cleaned up yet)
    bytes32[] memory ordersBefore = ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(
      address(testPool)
    );
    assertEq(ordersBefore.length, 1, "Should have 1 order before cleanup");

    // Submit second order - this triggers cleanup
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData2 = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      500e6, // Different amount to get unique hash
      0.17 ether,
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData2)
    );

    // Verify first order was cleaned up, only second order remains
    bytes32[] memory ordersAfter = ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(
      address(testPool)
    );
    assertEq(ordersAfter.length, 1, "Should have 1 order after cleanup");

    bytes32 orderDigest2 = CowSwapOrderTypeHashLib.getDigest(typedData2);
    assertEq(ordersAfter[0], orderDigest2, "Remaining order should be the second one");
  }

  function test_cowswap_fill_info_for_sell_order() public {
    uint32 validTo = uint32(block.timestamp + 1 days);
    uint256 sellAmount = 1000e6;
    uint256 buyAmount = 0.33 ether;

    // Submit a sell order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      sellAmount,
      buyAmount,
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);

    // For sell orders, targetFillAmount should be sellAmount
    uint256 targetFillAmount = ITypedStructuredDataValidatorMock(dataValidatorProxy).cowSwapFillInfo(
      address(testPool),
      orderDigest
    );
    assertEq(targetFillAmount, sellAmount, "Target fill amount should be sellAmount for sell orders");
  }

  function test_cowswap_fill_info_for_buy_order() public {
    uint32 validTo = uint32(block.timestamp + 1 days);
    uint256 sellAmount = 1 ether;
    uint256 buyAmount = 3000e6;

    // Submit a buy order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      wethData.asset,
      usdcData.asset,
      sellAmount,
      buyAmount,
      validTo,
      CowSwapOrderTypeHashLib.KIND_BUY
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);

    // For buy orders, targetFillAmount should be buyAmount
    uint256 targetFillAmount = ITypedStructuredDataValidatorMock(dataValidatorProxy).cowSwapFillInfo(
      address(testPool),
      orderDigest
    );
    assertEq(targetFillAmount, buyAmount, "Target fill amount should be buyAmount for buy orders");
  }

  // ============ Cancel Order Tests ============

  function test_cancel_order_succeeds_after_gpv2_invalidate_order() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Submit and pre-sign an order
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    bytes memory orderUid = abi.encodePacked(orderDigest, address(testPool), validTo);

    // Pre-sign the order
    vm.prank(manager);
    testPool.execTransaction(
      gpv2Settlement,
      abi.encodeWithSelector(IGPv2Settlement.setPreSignature.selector, orderUid, true)
    );

    // Try to cancel before invalidation - should fail
    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_STILL_ACTIVE_SELECTOR, address(testPool), orderDigest));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderDigest);

    // Verify order is still tracked
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Order should still be validated before invalidation"
    );

    // Invalidate the order on GPv2Settlement (sets filledAmount to MAX)
    vm.prank(manager);
    testPool.execTransaction(
      gpv2Settlement,
      abi.encodeWithSelector(IGPv2Settlement.invalidateOrder.selector, orderUid)
    );

    // Now cancel should succeed (order is invalidated on GPv2Settlement)
    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).cancelOrder(address(testPool), orderDigest);

    // Verify order is removed from tracking
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Order should NOT be validated after cancel"
    );
    assertEq(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).getPoolOrderHashes(address(testPool)).length,
      0,
      "Should have 0 orders after cancel"
    );

    // Tokens should no longer be locked
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        typedData.order.sellToken
      ),
      "Sell token should not be locked after cancel"
    );
    assertFalse(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).hasActiveOrderWithToken(
        address(testPool),
        typedData.order.buyToken
      ),
      "Buy token should not be locked after cancel"
    );
  }

  // ============ Validator Tests: Domain Validation ============

  function test_submit_order_reverts_for_wrong_domain_name() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    typedData.domain.name = "Wrong Protocol";

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(DOMAIN_NAME_MISMATCH_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_wrong_domain_version() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    typedData.domain.version = "v3";

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(DOMAIN_VERSION_MISMATCH_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_wrong_chain_id() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    typedData.domain.chainId = 999999; // Wrong chain

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(DOMAIN_CHAIN_MISMATCH_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_wrong_verifying_contract() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    typedData.domain.verifyingContract = address(0xDEAD);

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(DOMAIN_VERIFYING_CONTRACT_MISMATCH_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  // ============ Validator Tests: Order Validation ============

  function test_submit_order_reverts_for_invalid_receiver() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    typedData.order.receiver = address(0xDEAD); // Not pool, not address(0)

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(INVALID_RECEIVER_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_unsupported_sell_token() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      address(0xDEAD), // Unsupported sell token
      wethData.asset,
      1000e18,
      0.4 ether,
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(UNSUPPORTED_SELL_TOKEN_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_unsupported_buy_token() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      address(0xDEAD), // Unsupported buy token
      1000e6,
      1000e18,
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(UNSUPPORTED_BUY_TOKEN_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_invalid_sell_token_balance() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    // Use BALANCE_INTERNAL (keccak256("internal")) which is not allowed
    typedData.order.sellTokenBalance = keccak256("internal");

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(INVALID_SELL_TOKEN_BALANCE_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_invalid_buy_token_balance() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    // Use BALANCE_INTERNAL (keccak256("internal")) which is not allowed
    typedData.order.buyTokenBalance = keccak256("internal");

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(INVALID_BUY_TOKEN_BALANCE_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_invalid_order_kind() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    typedData.order.kind = bytes32("invalid");

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(INVALID_ORDER_KIND_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_expired_order() public {
    uint32 validTo = uint32(block.timestamp - 1); // Already expired

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_EXPIRED_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_non_zero_fee_amount() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);
    // Set non-zero feeAmount (not allowed - fee should be handled by CoWSwap protocol)
    typedData.order.feeAmount = 1e6; // 1 USDC fee

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(NON_ZERO_FEE_AMOUNT_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  function test_submit_order_reverts_for_non_manager() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(validTo);

    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_CALLER_SELECTOR, owner));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  // ============ Validator Tests: SELL Order Rate ============
  // SELL order: sellAmount is exact, buyAmount is minimum acceptable

  // --- USDC → WETH (sell USDC, buy WETH) ---

  function test_submit_order_sell_usdc_for_weth_favorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Favorable (take-profit): asking for MORE WETH than market rate
    // At ~$3000/ETH, 1000 USDC should get ~0.33 WETH, but we ask for 1 WETH
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      1000e6, // Sell 1000 USDC
      1 ether, // Buy 1 WETH - favorable limit order
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Favorable sell USDC for WETH should be validated"
    );
  }

  function test_submit_order_sell_usdc_for_weth_fair_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Fair rate: 1000 USDC for ~0.33 WETH (at ~$3000/ETH, within 1% deviation)
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      1000e6, // Sell 1000 USDC
      0.33 ether, // Buy 0.33 WETH - fair rate
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Fair rate sell USDC for WETH should be validated"
    );
  }

  function test_submit_order_sell_usdc_for_weth_unfavorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Unfavorable: selling 1000 USDC for only 0.01 WETH (~$30) - massive loss
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      1000e6, // Sell 1000 USDC
      0.01 ether, // Buy only 0.01 WETH - unfavorable
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_RATE_TOO_UNFAVORABLE_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  // --- WETH → USDC (sell WETH, buy USDC) ---

  function test_submit_order_sell_weth_for_usdc_favorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Favorable (take-profit): asking for MORE USDC than market rate
    // At ~$3000/ETH, 0.4 WETH should get ~1200 USDC, but we ask for 5000 USDC
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      wethData.asset,
      usdcData.asset,
      0.4 ether, // Sell 0.4 WETH
      5000e6, // Buy 5000 USDC - favorable limit order
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Favorable sell WETH for USDC should be validated"
    );
  }

  function test_submit_order_sell_weth_for_usdc_fair_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Fair rate: 0.4 WETH for ~1200 USDC (at ~$3000/ETH, within 1% deviation)
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      wethData.asset,
      usdcData.asset,
      0.4 ether, // Sell 0.4 WETH
      1200e6, // Buy 1200 USDC - fair rate
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Fair rate sell WETH for USDC should be validated"
    );
  }

  function test_submit_order_sell_weth_for_usdc_unfavorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Unfavorable: selling 1 WETH (~$3000) for only 100 USDC - massive loss
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      wethData.asset,
      usdcData.asset,
      1 ether, // Sell 1 WETH
      100e6, // Buy only 100 USDC - unfavorable
      validTo,
      CowSwapOrderTypeHashLib.KIND_SELL
    );

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_RATE_TOO_UNFAVORABLE_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  // ============ Validator Tests: BUY Order Rate ============
  // BUY order: buyAmount is exact, sellAmount is maximum willing to pay

  // --- Buy WETH with USDC ---

  function test_submit_order_buy_weth_with_usdc_favorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Favorable (limit buy): want to buy 1 WETH, paying only 500 USDC
    // Will only fill if ETH price drops significantly
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      500e6, // Pay up to 500 USDC
      1 ether, // Buy 1 WETH - favorable limit
      validTo,
      CowSwapOrderTypeHashLib.KIND_BUY
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Favorable buy WETH with USDC should be validated"
    );
  }

  function test_submit_order_buy_weth_with_usdc_fair_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Fair rate: buy 0.33 WETH, paying up to 1000 USDC (at ~$3000/ETH)
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      1000e6, // Pay up to 1000 USDC
      0.33 ether, // Buy 0.33 WETH - fair rate
      validTo,
      CowSwapOrderTypeHashLib.KIND_BUY
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Fair rate buy WETH with USDC should be validated"
    );
  }

  function test_submit_order_buy_weth_with_usdc_unfavorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Unfavorable: buy 0.1 WETH (~$300), paying up to 10000 USDC - massive overpay
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      usdcData.asset,
      wethData.asset,
      10000e6, // Pay up to 10000 USDC - overpaying!
      0.1 ether, // Buy 0.1 WETH
      validTo,
      CowSwapOrderTypeHashLib.KIND_BUY
    );

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_RATE_TOO_UNFAVORABLE_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  // --- Buy USDC with WETH ---

  function test_submit_order_buy_usdc_with_weth_favorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Favorable (limit buy): want to buy 3000 USDC, paying only 0.1 WETH
    // Will only fill if ETH price rises significantly
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      wethData.asset,
      usdcData.asset,
      0.1 ether, // Pay up to 0.1 WETH
      3000e6, // Buy 3000 USDC - favorable limit
      validTo,
      CowSwapOrderTypeHashLib.KIND_BUY
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Favorable buy USDC with WETH should be validated"
    );
  }

  function test_submit_order_buy_usdc_with_weth_fair_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Fair rate: buy 1200 USDC, paying up to 0.4 WETH (at ~$3000/ETH)
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      wethData.asset,
      usdcData.asset,
      0.4 ether, // Pay up to 0.4 WETH
      1200e6, // Buy 1200 USDC - fair rate
      validTo,
      CowSwapOrderTypeHashLib.KIND_BUY
    );

    vm.prank(manager);
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );

    bytes32 orderDigest = CowSwapOrderTypeHashLib.getDigest(typedData);
    assertTrue(
      ITypedStructuredDataValidatorMock(dataValidatorProxy).isValidatedHash(address(testPool), orderDigest),
      "Fair rate buy USDC with WETH should be validated"
    );
  }

  function test_submit_order_buy_usdc_with_weth_unfavorable_rate() public {
    uint32 validTo = uint32(block.timestamp + 1 days);

    // Unfavorable: buy 100 USDC, paying up to 5 WETH (~$15000) - massive overpay
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedDataWithParams(
      wethData.asset,
      usdcData.asset,
      5 ether, // Pay up to 5 WETH - overpaying!
      100e6, // Buy 100 USDC
      validTo,
      CowSwapOrderTypeHashLib.KIND_BUY
    );

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(ORDER_RATE_TOO_UNFAVORABLE_SELECTOR));
    ITypedStructuredDataValidatorMock(dataValidatorProxy).submit(
      address(testPool),
      ITypedStructuredDataValidatorMock.StructuredDataSupported.COWSWAP_ORDER,
      abi.encode(typedData)
    );
  }

  // ============ Helper Functions ============

  function _getChainId() internal pure returns (uint256 chainId) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      chainId := chainid()
    }
  }

  /// @dev Build typed data using CowSwapOrderTypeHashLib structs
  /// Default order: Sell 1000 USDC for 0.33 WETH (fair rate at ~$3000/ETH)
  function _buildTypedData(uint32 validTo) internal view returns (CowSwapOrderTypeHashLib.CowSwapTypedData memory) {
    return
      _buildTypedDataWithParams(
        usdcData.asset,
        wethData.asset,
        1000e6,
        0.33 ether,
        validTo,
        CowSwapOrderTypeHashLib.KIND_SELL
      );
  }

  /// @dev Build typed data with custom parameters
  function _buildTypedDataWithParams(
    address sellToken,
    address buyToken,
    uint256 sellAmount,
    uint256 buyAmount,
    uint32 validTo,
    bytes32 kind
  ) internal view returns (CowSwapOrderTypeHashLib.CowSwapTypedData memory) {
    return
      CowSwapOrderTypeHashLib.CowSwapTypedData({
        domain: CowSwapOrderTypeHashLib.EIP712Domain({
          name: "Gnosis Protocol",
          version: "v2",
          chainId: _getChainId(),
          verifyingContract: gpv2Settlement
        }),
        order: CowSwapOrderTypeHashLib.GPv2Order({
          sellToken: sellToken,
          buyToken: buyToken,
          receiver: address(testPool),
          sellAmount: sellAmount,
          buyAmount: buyAmount,
          validTo: validTo,
          appData: bytes32(0),
          feeAmount: 0,
          kind: kind,
          partiallyFillable: false,
          sellTokenBalance: CowSwapOrderTypeHashLib.BALANCE_ERC20,
          buyTokenBalance: CowSwapOrderTypeHashLib.BALANCE_ERC20
        })
      });
  }
}
