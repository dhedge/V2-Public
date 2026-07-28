// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmDelegatee} from "contracts/interfaces/dytm/IDytmDelegatee.sol";
import {IDytmAccountSplitterAndMerger} from "contracts/interfaces/dytm/IDytmAccountSplitterAndMerger.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {DytmOfficeContractGuardMergeTestSetup} from "test/integration/common/dytm/DytmOfficeContractGuardMergeTestSetup.t.sol";

/// @title DytmOfficeContractGuardMergeTest
/// @notice Tests the manager-initiated DYTM `MERGE_ACCOUNTS` path on `DytmOfficeContractGuard`.
///         Verifies the guard's pre-tx validation rejects every value-hiding/abuse shape, and that
///         the happy `isolated → main user account` merge updates the NFT market tracker so the
///         merged value becomes visible to `DytmOfficeAssetGuard.getBalance`.
contract DytmOfficeContractGuardMergeTest is DytmOfficeContractGuardMergeTestSetup, EthereumSetup {
  uint88 internal constant NON_WHITELISTED_MARKET_ID = 999;
  uint64 internal constant FULL_FRACTION = 1e18;

  constructor() EthereumSetup(24724485) {}

  function setUp() public override(DytmOfficeContractGuardMergeTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    DytmOfficeContractGuardMergeTestSetup.setUp();

    // Model that the pool's main account holds collateral on TEST_MARKET_ID. A real merge folds the
    // source's collateral INTO main, so post-merge main genuinely has a position and DYTM's periphery
    // returns a real health factor. Without a non-zero collateral hint the mock periphery treats main
    // as drained and returns the no-debt sentinel (HF = max), bypassing the armed post-merge HF —
    // the revert tests would see HF = max and pass the floor. The mock splitter doesn't move
    // collateral itself, so we seed the hint here to stand in for main's post-merge holdings.
    mockOffice.setEscrowTokenIdHint(_escrowTokenId(GOOGLON, TEST_MARKET_ID));
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Reverts: value-hiding & malformed merges
  // ═══════════════════════════════════════════════════════════════════════════════

  /// @notice The critical guard rule: manager cannot use the pool's main user account as the
  ///         merge SOURCE. Otherwise value would move out of `getBalance`'s tracked view into an
  ///         isolated account it doesn't sum (a self-rug / value-hiding primitive).
  function test_dytmMerge_rejectsMainAsSource_revertsValueHidingAttempt() public {
    bytes memory call = _encodeMergeCall({
      _sourceAccount: _toUserAccount(address(dytmTestPool)), // main: USER_ACCOUNT — disallowed
      _recipientAccount: _isolatedAccount(7),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("merge source must be isolated");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice DelegationCall to anything other than the pool itself or the configured
  ///         accountSplitterAndMerger is rejected.
  function test_dytmMerge_rejectsInvalidDelegatee() public {
    DytmParamStructs.DelegationCallParams memory params = DytmParamStructs.DelegationCallParams({
      delegatee: IDytmDelegatee(address(0xBAD)),
      callbackData: ""
    });
    bytes memory call = abi.encodeWithSelector(IDytmOffice.delegationCall.selector, params);

    vm.prank(manager);
    vm.expectRevert("invalid delegatee");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice The merger-delegatee path only accepts `MERGE_ACCOUNTS`. A `SPLIT_ACCOUNT` op routed
  ///         through this branch must be rejected — manager-initiated splits are not authorized.
  function test_dytmMerge_rejectsSplitOpThroughMergerDelegatee() public {
    bytes memory data = abi.encode(
      IDytmAccountSplitterAndMerger.SplitAccountParams({
        sourceAccount: _toUserAccount(address(dytmTestPool)),
        market: TEST_MARKET_ID,
        fraction: FULL_FRACTION
      })
    );
    bytes memory callbackData = abi.encode(
      IDytmAccountSplitterAndMerger.CallbackData({
        operation: IDytmAccountSplitterAndMerger.Operation.SPLIT_ACCOUNT,
        data: data
      })
    );
    DytmParamStructs.DelegationCallParams memory params = DytmParamStructs.DelegationCallParams({
      delegatee: IDytmDelegatee(address(mockSplitter)),
      callbackData: callbackData
    });
    bytes memory call = abi.encodeWithSelector(IDytmOffice.delegationCall.selector, params);

    vm.prank(manager);
    vm.expectRevert("merge op only");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice The merge's market must be on the contract guard's whitelist.
  function test_dytmMerge_rejectsNonWhitelistedMarket() public {
    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(3),
      _recipientAccount: _isolatedAccount(4),
      _market: NON_WHITELISTED_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("invalid market");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice The dust-exfiltration guard: a merge whose recipient is an EXTERNAL user account must
  ///         revert. DYTM does not enforce caller-owns-both for collateral, so without this check a
  ///         manager could route a collateral-only dust account's collateral to an account it
  ///         controls outside the pool.
  function test_dytmMerge_rejectsExternalUserRecipient_revertsExfiltration() public {
    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(81), // pool-owned dust source
      _recipientAccount: _toUserAccount(address(0xBAD)), // external EOA — not the pool
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("merge recipient not pool-owned");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice Same exfiltration path via an isolated account owned by someone other than the pool
  ///         must also revert. This is the case the collateral same-owner gap specifically enables.
  function test_dytmMerge_rejectsForeignIsolatedRecipient_revertsExfiltration() public {
    // Register the recipient isolated account as owned by an external address.
    mockOffice.setAccountOwner(_isolatedAccount(92), address(0xBAD));

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(91),
      _recipientAccount: _isolatedAccount(92),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("merge recipient not pool-owned");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Happy path: isolated → main adds market to tracker
  // ═══════════════════════════════════════════════════════════════════════════════

  /// @notice Merging an isolated dust account INTO the pool's main user account must add the
  ///         merged market to the NFT tracker, so `DytmOfficeAssetGuard.getBalance` picks up the
  ///         merged value.
  function test_dytmMerge_isolatedIntoMain_addsMarketToTracker() public {
    // Sanity: market is not tracked yet (no supply has happened on the test pool).
    assertFalse(
      dytmOfficeContractGuard.isValidOwnedTokenId(address(dytmTestPool), uint256(TEST_MARKET_ID)),
      "market should not be tracked pre-merge"
    );

    // Post-merge HF must clear the 1.01e18 floor; pre-HF defaults to max (no debt — real
    // periphery sentinel) so the percentage check is skipped.
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 2e18);

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(11),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(address(mockOffice), call);

    assertTrue(
      dytmOfficeContractGuard.isValidOwnedTokenId(address(dytmTestPool), uint256(TEST_MARKET_ID)),
      "merged market should be tracked post-merge"
    );
  }

  /// @notice Merging two pool-owned isolated accounts does NOT add anything to the tracker — the
  ///         result is still an isolated account invisible to `getBalance`. Manager can subsequently
  ///         merge the consolidated isolated account into main if desired.
  function test_dytmMerge_isolatedIntoIsolated_doesNotTouchTracker() public {
    assertFalse(
      dytmOfficeContractGuard.isValidOwnedTokenId(address(dytmTestPool), uint256(TEST_MARKET_ID)),
      "market should not be tracked pre-merge"
    );

    // Recipient isolated account must be pool-owned for the guard to authorize the merge.
    mockOffice.setAccountOwner(_isolatedAccount(22), address(dytmTestPool));

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(21),
      _recipientAccount: _isolatedAccount(22),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(address(mockOffice), call);

    assertFalse(
      dytmOfficeContractGuard.isValidOwnedTokenId(address(dytmTestPool), uint256(TEST_MARKET_ID)),
      "isolated-to-isolated merge must not add market to tracker"
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HF degradation cap on merge-into-main
  // ═══════════════════════════════════════════════════════════════════════════════

  /// @notice The percentage check is skipped when main had no prior position on the merge market
  ///         (pre-merge HF == type(uint256).max from the periphery — the no-debt sentinel).
  ///         The absolute 1.01e18 floor still applies.
  function test_dytmMerge_intoMain_noPriorPosition_skipsPercentageCheck() public {
    // Periphery default: HF=max (no debt) — what the real periphery returns for an account
    // with no position. Arm the splitter to set HF=2e18 post-merge (well above the 1.01 floor).
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 2e18);

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(31),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice When main had a finite pre-merge HF, a merge that drops HF by ≤ 5% must pass.
  function test_dytmMerge_intoMain_within5PercentDrop_passes() public {
    _setMainPositionHF(2e18); // pre-merge HF
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 1.91e18); // 4.5% drop, within cap

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(41),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice The critical regression: a merge that drops main's HF by > 5% must revert.
  function test_dytmMerge_intoMain_over5PercentDrop_reverts() public {
    _setMainPositionHF(2e18); // pre-merge HF
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 1.85e18); // 7.5% drop, over cap

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(51),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("merge HF degradation too high");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice Even within the 5% bound, the absolute 1.01e18 floor on the post-merge HF must hold.
  function test_dytmMerge_intoMain_belowAbsoluteFloor_reverts() public {
    _setMainPositionHF(1.02e18); // pre-merge HF (just above floor)
    // 1% drop → 1.0098e18: within the 5% relative cap, but below 1.01e18 absolute floor.
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 1.0098e18);

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(61),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("health factor too low");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice Sentinel: main had no debt pre-merge (HF == type(uint256).max). Percentage check
  ///         skipped; absolute floor still enforced.
  function test_dytmMerge_intoMain_noDebtPreMerge_skipsPercentageCheck() public {
    _setMainPositionHF(type(uint256).max);
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 2e18);

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(71),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Supported-asset entry check on merge-into-main
  // ═══════════════════════════════════════════════════════════════════════════════

  /// @notice Merge into main must revert when the post-merge position holds a collateral
  ///         asset the pool does not support.
  function test_dytmMerge_intoMain_unsupportedCollateral_reverts() public {
    // WETH is registered in the asset handler but not a supported asset of the test pool.
    mockOffice.setEscrowTokenIdHint(_escrowTokenId(wethData.asset, TEST_MARKET_ID));
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 2e18); // clears the HF gates

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(101),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("unsupported asset");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice Merge into main must revert when the post-merge position carries debt in an
  ///         asset the pool does not support.
  function test_dytmMerge_intoMain_unsupportedDebt_reverts() public {
    // Collateral stays GOOGLON (supported, seeded in setUp); debt is WETH (unsupported).
    mockOffice.setDebtIdHint((uint256(TEST_MARKET_ID) << 160) | uint256(uint160(wethData.asset)));
    mockSplitter.armPostCallbackHF(address(mockPeriphery), 2e18);

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(102),
      _recipientAccount: _toUserAccount(address(dytmTestPool)),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    vm.expectRevert("unsupported asset");
    dytmTestPool.execTransaction(address(mockOffice), call);
  }

  /// @notice Isolated → isolated merges skip the supported-asset check by design: nothing
  ///         enters the accounted position, and the eventual merge into main gets checked.
  function test_dytmMerge_isolatedIntoIsolated_unsupportedAssets_allowed() public {
    mockOffice.setEscrowTokenIdHint(_escrowTokenId(wethData.asset, TEST_MARKET_ID));
    mockOffice.setAccountOwner(_isolatedAccount(112), address(dytmTestPool));

    bytes memory call = _encodeMergeCall({
      _sourceAccount: _isolatedAccount(111),
      _recipientAccount: _isolatedAccount(112),
      _market: TEST_MARKET_ID
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(address(mockOffice), call);

    assertFalse(
      dytmOfficeContractGuard.isValidOwnedTokenId(address(dytmTestPool), uint256(TEST_MARKET_ID)),
      "isolated-to-isolated merge must not add market to tracker"
    );
  }

  // ───────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────────

  /// @dev Write a position into the mock periphery with the given HF; other fields are zeroed.
  function _setMainPositionHF(uint256 _hf) internal {
    DytmParamStructs.AccountPosition memory pos;
    pos.healthFactor = _hf;
    pos.isHealthy = true;
    mockPeriphery.setPosition(pos);
  }

  /// @dev Build an ISOLATED_ACCOUNT id: high 96 bits = count, low 160 bits = 0.
  function _isolatedAccount(uint96 _count) internal pure returns (uint256) {
    return uint256(_count) << 160;
  }

  function _encodeMergeCall(
    uint256 _sourceAccount,
    uint256 _recipientAccount,
    uint88 _market
  ) internal view returns (bytes memory) {
    bytes memory data = abi.encode(
      IDytmAccountSplitterAndMerger.MergeAccountsParams({
        sourceAccount: _sourceAccount,
        recipientAccount: _recipientAccount,
        market: _market,
        fraction: FULL_FRACTION
      })
    );
    bytes memory callbackData = abi.encode(
      IDytmAccountSplitterAndMerger.CallbackData({
        operation: IDytmAccountSplitterAndMerger.Operation.MERGE_ACCOUNTS,
        data: data
      })
    );
    DytmParamStructs.DelegationCallParams memory params = DytmParamStructs.DelegationCallParams({
      delegatee: IDytmDelegatee(address(mockSplitter)),
      callbackData: callbackData
    });
    return abi.encodeWithSelector(IDytmOffice.delegationCall.selector, params);
  }
}
