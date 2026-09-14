// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {DhedgeNftTrackerStorage} from "contracts/utils/tracker/DhedgeNftTrackerStorage.sol";
import {IHasGuardInfo} from "contracts/interfaces/IHasGuardInfo.sol";

/// @notice `DhedgeNftTrackerStorage` is the shared ledger of per-vault NFT positions. Only the
/// contract guard registered for a guarded contract may write to that contract's records.
/// Removals are swap-and-pop, so the surviving order is part of the observable behaviour.
contract DhedgeNftTrackerStorageTest is Test {
  bytes32 internal constant NFT_TYPE = keccak256("LYRA_NFT_TYPE");
  uint256 internal constant MAX_POSITIONS = 3;

  DhedgeNftTrackerStorage internal nftTracker;

  address internal poolFactory = makeAddr("poolFactory");
  address internal pool = makeAddr("pool");
  address internal guardedContract = makeAddr("guardedContract");
  address internal guard = makeAddr("guard");
  address internal impostor = makeAddr("impostor");

  function setUp() public {
    nftTracker = new DhedgeNftTrackerStorage();
    nftTracker.initialize(poolFactory);

    vm.mockCall(
      poolFactory,
      abi.encodeWithSelector(IHasGuardInfo.getContractGuard.selector, guardedContract),
      abi.encode(guard)
    );
  }

  /* ========== ACCESS CONTROL ========== */

  function test_revert_addData_when_caller_is_not_the_registered_guard() public {
    vm.prank(impostor);
    vm.expectRevert("not correct contract guard");
    nftTracker.addData(guardedContract, NFT_TYPE, pool, _bytesData(1));
  }

  function test_revert_removeData_when_caller_is_not_the_registered_guard() public {
    vm.prank(impostor);
    vm.expectRevert("not correct contract guard");
    nftTracker.removeData(guardedContract, NFT_TYPE, pool, 0);
  }

  function test_revert_addUintId_when_caller_is_not_the_registered_guard() public {
    vm.prank(impostor);
    vm.expectRevert("not correct contract guard");
    nftTracker.addUintId(guardedContract, NFT_TYPE, pool, 1e18, MAX_POSITIONS);
  }

  function test_revert_removeUintId_when_caller_is_not_the_registered_guard() public {
    vm.prank(impostor);
    vm.expectRevert("not correct contract guard");
    nftTracker.removeUintId(guardedContract, NFT_TYPE, pool, 0);
  }

  /* ========== RAW DATA ========== */

  function test_guard_can_add_data() public {
    _addData(1);

    assertEq(nftTracker.getDataCount(NFT_TYPE, pool), 1);
    assertEq(nftTracker.getData(NFT_TYPE, pool, 0), _bytesData(1));
    assertEq(nftTracker.getAllData(NFT_TYPE, pool).length, 1);
  }

  function test_guard_can_add_data_repeatedly() public {
    _addData(1);
    _addData(2);

    assertEq(nftTracker.getDataCount(NFT_TYPE, pool), 2);
    assertEq(nftTracker.getData(NFT_TYPE, pool, 0), _bytesData(1));
    assertEq(nftTracker.getData(NFT_TYPE, pool, 1), _bytesData(2));
  }

  function test_revert_removeData_when_index_out_of_range() public {
    vm.prank(guard);
    vm.expectRevert("invalid index");
    nftTracker.removeData(guardedContract, NFT_TYPE, pool, 1);
  }

  function test_removeData_in_the_middle_moves_the_last_entry_into_the_gap() public {
    _addData(1);
    _addData(2);
    _addData(3);

    vm.prank(guard);
    nftTracker.removeData(guardedContract, NFT_TYPE, pool, 1);

    assertEq(nftTracker.getDataCount(NFT_TYPE, pool), 2);
    assertEq(nftTracker.getData(NFT_TYPE, pool, 0), _bytesData(1));
    assertEq(nftTracker.getData(NFT_TYPE, pool, 1), _bytesData(3));
  }

  function test_removeData_at_the_end_leaves_the_rest_in_order() public {
    _addData(1);
    _addData(2);
    _addData(3);

    vm.prank(guard);
    nftTracker.removeData(guardedContract, NFT_TYPE, pool, 2);

    assertEq(nftTracker.getDataCount(NFT_TYPE, pool), 2);
    assertEq(nftTracker.getData(NFT_TYPE, pool, 0), _bytesData(1));
    assertEq(nftTracker.getData(NFT_TYPE, pool, 1), _bytesData(2));
  }

  /* ========== UINT IDS ========== */

  function test_guard_can_add_uint_ids() public {
    _addUintId(1e18);
    _addUintId(2e18);

    assertEq(nftTracker.getDataCount(NFT_TYPE, pool), 2);
    uint256[] memory ids = nftTracker.getAllUintIds(NFT_TYPE, pool);
    assertEq(ids.length, 2);
    assertEq(ids[0], 1e18);
    assertEq(ids[1], 2e18);
  }

  function test_revert_addUintId_beyond_max_positions() public {
    for (uint256 i; i < MAX_POSITIONS; ++i) {
      _addUintId(i + 1);
    }

    vm.prank(guard);
    vm.expectRevert("max position reached");
    nftTracker.addUintId(guardedContract, NFT_TYPE, pool, MAX_POSITIONS + 1, MAX_POSITIONS);
  }

  function test_revert_removeUintId_when_id_is_not_tracked() public {
    vm.prank(guard);
    vm.expectRevert("not found");
    nftTracker.removeUintId(guardedContract, NFT_TYPE, pool, 1);
  }

  function test_removeUintId_in_the_middle_moves_the_last_entry_into_the_gap() public {
    _addUintId(1);
    _addUintId(2);
    _addUintId(3);

    vm.prank(guard);
    nftTracker.removeUintId(guardedContract, NFT_TYPE, pool, 2);

    uint256[] memory ids = nftTracker.getAllUintIds(NFT_TYPE, pool);
    assertEq(ids.length, 2);
    assertEq(ids[0], 1);
    assertEq(ids[1], 3);
  }

  function test_removeUintId_at_the_end_leaves_the_rest_in_order() public {
    _addUintId(1);
    _addUintId(2);
    _addUintId(3);

    vm.prank(guard);
    nftTracker.removeUintId(guardedContract, NFT_TYPE, pool, 3);

    uint256[] memory ids = nftTracker.getAllUintIds(NFT_TYPE, pool);
    assertEq(ids.length, 2);
    assertEq(ids[0], 1);
    assertEq(ids[1], 2);
  }

  /* ========== ISOLATION ========== */

  /// @dev Records are keyed by (nftType, pool), so one vault's positions can never be read or
  /// removed through another's.
  function test_records_are_isolated_per_pool_and_nft_type() public {
    address otherPool = makeAddr("otherPool");
    bytes32 otherNftType = keccak256("OTHER_NFT_TYPE");

    _addUintId(1);

    assertEq(nftTracker.getDataCount(NFT_TYPE, otherPool), 0);
    assertEq(nftTracker.getDataCount(otherNftType, pool), 0);
    assertEq(nftTracker.getDataCount(NFT_TYPE, pool), 1);
  }

  /* ========== HELPERS ========== */

  function _addData(uint256 _value) internal {
    vm.prank(guard);
    nftTracker.addData(guardedContract, NFT_TYPE, pool, _bytesData(_value));
  }

  function _addUintId(uint256 _id) internal {
    vm.prank(guard);
    nftTracker.addUintId(guardedContract, NFT_TYPE, pool, _id, MAX_POSITIONS);
  }

  function _bytesData(uint256 _value) internal pure returns (bytes memory data) {
    data = abi.encode(_value);
  }
}
