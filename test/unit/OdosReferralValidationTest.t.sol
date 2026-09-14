// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolFactory} from "contracts/interfaces/IPoolFactory.sol";
import {IPoolManagerLogic} from "contracts/interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {ITransactionTypes} from "contracts/interfaces/ITransactionTypes.sol";
import {IOdosRouterV2} from "contracts/interfaces/odos/IOdosRouterV2.sol";
import {IOdosRouterV3} from "contracts/interfaces/odos/IOdosRouterV3.sol";
import {OdosSharedContractGuard} from "contracts/guards/contractGuards/odos/OdosSharedContractGuard.sol";
import {OdosV2ContractGuard} from "contracts/guards/contractGuards/odos/OdosV2ContractGuard.sol";
import {OdosV3ContractGuard} from "contracts/guards/contractGuards/odos/OdosV3ContractGuard.sol";
import {SlippageAccumulator} from "contracts/utils/SlippageAccumulator.sol";

/// @notice Referral validation tests for the Odos V2/V3 contract guards, swap and swapCompact paths.
///         No fork needed: the guards are real, everything they call is mocked; the test contract
///         acts as the pool logic so calling txGuard directly passes the caller check.
contract OdosReferralValidationTest is Test {
  uint64 private constant SMALL_FEE = 2e14; // 0.02% of the router's FEE_DENOM (1e18)
  uint64 private constant MAX_ROUTER_FEE = 2e16; // FEE_DENOM / 50, the max referral fee the V3 router itself accepts
  uint32 private constant V2_FEE_THRESHOLD = uint32(1 << 31); // Odos V2 REFERRAL_WITH_FEE_THRESHOLD

  address private constant FACTORY = address(0xFAC);
  address private constant POOL_MANAGER_LOGIC = address(0x100);
  address private constant TOKEN_IN = address(0x200);
  address private constant TOKEN_OUT = address(0x300);
  address private constant EXECUTOR = address(0x400);
  address private constant ROUTER = address(0x500);
  address private constant FEE_RECIPIENT = address(0x600); // any manager-chosen recipient

  OdosV2ContractGuard private v2;
  OdosV3ContractGuard private v3;

  function setUp() public {
    vm.etch(FACTORY, hex"ff");
    vm.mockCall(FACTORY, abi.encodeWithSelector(IPoolFactory.isPool.selector), abi.encode(true));

    vm.etch(POOL_MANAGER_LOGIC, hex"ff");
    vm.mockCall(
      POOL_MANAGER_LOGIC,
      abi.encodeWithSelector(IPoolManagerLogic.poolLogic.selector),
      abi.encode(address(this))
    );
    vm.mockCall(
      POOL_MANAGER_LOGIC,
      abi.encodeWithSelector(IHasSupportedAsset.isSupportedAsset.selector),
      abi.encode(true)
    );

    vm.etch(TOKEN_IN, hex"ff");
    vm.mockCall(TOKEN_IN, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(uint256(0)));
    vm.etch(TOKEN_OUT, hex"ff");
    vm.mockCall(TOKEN_OUT, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(uint256(0)));

    SlippageAccumulator slippageAccumulator = new SlippageAccumulator(FACTORY, 6 hours, 5e4);
    v2 = new OdosV2ContractGuard(address(slippageAccumulator));
    v3 = new OdosV3ContractGuard(address(slippageAccumulator));
  }

  function _tokenInfo() private view returns (IOdosRouterV2.SwapTokenInfo memory) {
    return
      IOdosRouterV2.SwapTokenInfo({
        inputToken: TOKEN_IN,
        inputAmount: 1e6,
        inputReceiver: EXECUTOR,
        outputToken: TOKEN_OUT,
        outputQuote: 1e18,
        outputMin: 1,
        outputReceiver: address(this) // must be the pool logic
      });
  }

  function _v3SwapData(uint64 _code, uint64 _fee, address _feeRecipient) private view returns (bytes memory) {
    return
      abi.encodeWithSelector(
        v3.odosSwapSelector(),
        _tokenInfo(),
        bytes(hex"0102030405"),
        EXECUTOR,
        IOdosRouterV3.SwapReferralInfo({code: _code, fee: _fee, feeRecipient: _feeRecipient})
      );
  }

  function _v2SwapData(uint32 _code) private view returns (bytes memory) {
    return abi.encodeWithSelector(v2.odosSwapSelector(), _tokenInfo(), bytes(hex"0102030405"), EXECUTOR, _code);
  }

  /// @dev abi.encodePacked equivalent of the router's compact token layout (inline / null addresses only).
  ///      Built in chunks: a single encodePacked with all 15 values goes stack-too-deep on 0.7.6.
  function _compactTokenPart() private view returns (bytes memory) {
    bytes memory tokens = abi.encodePacked(
      IOdosRouterV2.swapCompact.selector,
      uint16(1),
      TOKEN_IN, // inputToken (inline)
      uint16(1),
      TOKEN_OUT // outputToken (inline)
    );
    bytes memory amounts = abi.encodePacked(
      uint8(4),
      uint32(1e6), // inputAmount: 1-byte length + value
      uint8(4),
      uint32(1e6), // quote: 1-byte length + value
      uint24(0) // slippage
    );
    bytes memory receivers = abi.encodePacked(
      uint16(1),
      EXECUTOR, // executor (inline)
      uint16(0), // inputReceiver: null -> executor
      uint16(1),
      address(this) // outputReceiver (inline)
    );
    return abi.encodePacked(tokens, amounts, receivers);
  }

  function _v3CompactData(
    uint64 _code,
    uint8 _feeStatus,
    uint64 _fee,
    address _feeRecipient
  ) private view returns (bytes memory) {
    bytes memory withoutFee = abi.encodePacked(_compactTokenPart(), _code, _feeStatus);
    return _feeStatus == 0 ? withoutFee : abi.encodePacked(withoutFee, _fee, _feeRecipient);
  }

  function _v2CompactData(uint32 _code) private view returns (bytes memory) {
    return abi.encodePacked(_compactTokenPart(), _code);
  }

  function _assertGuardPasses(OdosSharedContractGuard _guard, bytes memory _data) private {
    (uint16 txType, ) = _guard.txGuard(POOL_MANAGER_LOGIC, ROUTER, _data);
    assertEq(uint256(txType), uint256(ITransactionTypes.TransactionType.Exchange));
  }

  /* ========== V3 swap ========== */

  function test_v3_swap_passes_with_no_referral_fee() public {
    _assertGuardPasses(v3, _v3SwapData(0, 0, address(0)));
  }

  function test_v3_swap_passes_with_zero_fee_and_tracking_code_any_recipient() public {
    // With fee 0 the router transfers nothing, so code and recipient are irrelevant.
    _assertGuardPasses(v3, _v3SwapData(12345, 0, FEE_RECIPIENT));
  }

  function test_v3_swap_reverts_with_small_fee() public {
    bytes memory data = _v3SwapData(0, SMALL_FEE, FEE_RECIPIENT);
    vm.expectRevert("referral fee not allowed");
    v3.txGuard(POOL_MANAGER_LOGIC, ROUTER, data);
  }

  function test_v3_swap_reverts_with_max_router_fee() public {
    bytes memory data = _v3SwapData(0, MAX_ROUTER_FEE, FEE_RECIPIENT);
    vm.expectRevert("referral fee not allowed");
    v3.txGuard(POOL_MANAGER_LOGIC, ROUTER, data);
  }

  function test_v3_swap_reverts_with_minimal_fee() public {
    bytes memory data = _v3SwapData(0, 1, FEE_RECIPIENT);
    vm.expectRevert("referral fee not allowed");
    v3.txGuard(POOL_MANAGER_LOGIC, ROUTER, data);
  }

  /* ========== V3 swapCompact ========== */

  function test_v3_compact_passes_with_no_fee_block() public {
    _assertGuardPasses(v3, _v3CompactData(0, 0, 0, address(0)));
  }

  function test_v3_compact_passes_with_fee_block_holding_zero_fee() public {
    _assertGuardPasses(v3, _v3CompactData(12345, 1, 0, FEE_RECIPIENT));
  }

  function test_v3_compact_reverts_with_small_fee() public {
    bytes memory data = _v3CompactData(0, 1, SMALL_FEE, FEE_RECIPIENT);
    vm.expectRevert("referral fee not allowed");
    v3.txGuard(POOL_MANAGER_LOGIC, ROUTER, data);
  }

  function test_v3_compact_reverts_with_max_router_fee() public {
    bytes memory data = _v3CompactData(0, 1, MAX_ROUTER_FEE, FEE_RECIPIENT);
    vm.expectRevert("referral fee not allowed");
    v3.txGuard(POOL_MANAGER_LOGIC, ROUTER, data);
  }

  /* ========== V2 swap / swapCompact ========== */

  function test_v2_swap_passes_for_feeless_referral_code() public {
    _assertGuardPasses(v2, _v2SwapData(V2_FEE_THRESHOLD));
  }

  function test_v2_swap_reverts_for_fee_bearing_referral_code() public {
    bytes memory data = _v2SwapData(V2_FEE_THRESHOLD + 1);
    vm.expectRevert("referral fee not allowed");
    v2.txGuard(POOL_MANAGER_LOGIC, ROUTER, data);
  }

  function test_v2_compact_passes_for_feeless_referral_code() public {
    _assertGuardPasses(v2, _v2CompactData(V2_FEE_THRESHOLD));
  }

  function test_v2_compact_reverts_for_fee_bearing_referral_code() public {
    bytes memory data = _v2CompactData(V2_FEE_THRESHOLD + 1);
    vm.expectRevert("referral fee not allowed");
    v2.txGuard(POOL_MANAGER_LOGIC, ROUTER, data);
  }
}
