// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice Membership of a private pool comes from two sources: an explicit member list the
/// manager curates, and optionally an NFT collection whose holders are members automatically.
contract PoolMembershipTest is PoolUnitTestSetup {
  address internal memberOne = makeAddr("memberOne");
  address internal memberTwo = makeAddr("memberTwo");
  address internal memberThree = makeAddr("memberThree");
  address internal nftCollection = makeAddr("nftCollection");

  /* ========== EXPLICIT MEMBERS ========== */

  function test_a_fresh_pool_has_no_members() public view {
    assertEq(fundManagerLogic.numberOfMembers(), 0);
    assertFalse(fundManagerLogic.isMemberAllowed(memberOne));
  }

  function test_manager_can_add_and_remove_a_member() public {
    vm.startPrank(manager);

    fundManagerLogic.addMember(memberOne);
    assertEq(fundManagerLogic.numberOfMembers(), 1);
    assertTrue(fundManagerLogic.isMemberAllowed(memberOne));

    fundManagerLogic.removeMember(memberOne);
    assertEq(fundManagerLogic.numberOfMembers(), 0);
    assertFalse(fundManagerLogic.isMemberAllowed(memberOne));

    vm.stopPrank();
  }

  function test_manager_can_add_members_in_bulk() public {
    vm.prank(manager);
    fundManagerLogic.addMembers(_threeMembers());

    assertEq(fundManagerLogic.numberOfMembers(), 3);
    assertTrue(fundManagerLogic.isMemberAllowed(memberOne));
    assertTrue(fundManagerLogic.isMemberAllowed(memberTwo));
    assertTrue(fundManagerLogic.isMemberAllowed(memberThree));
  }

  function test_adding_an_existing_member_does_not_double_count() public {
    vm.startPrank(manager);
    fundManagerLogic.addMember(memberOne);
    fundManagerLogic.addMembers(_threeMembers());
    vm.stopPrank();

    assertEq(fundManagerLogic.numberOfMembers(), 3);
  }

  function test_manager_can_remove_members_in_bulk() public {
    vm.startPrank(manager);
    fundManagerLogic.addMembers(_threeMembers());
    fundManagerLogic.removeMembers(_threeMembers());
    vm.stopPrank();

    assertEq(fundManagerLogic.numberOfMembers(), 0);
    assertFalse(fundManagerLogic.isMemberAllowed(memberTwo));
  }

  function test_revert_addMember_when_not_manager() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.addMember(memberOne);
  }

  /* ========== NFT COLLECTION MEMBERSHIP ========== */

  function test_revert_setNftMembershipCollectionAddress_when_not_manager() public {
    vm.prank(investor);
    vm.expectRevert(bytes("dh4"));
    fundManagerLogic.setNftMembershipCollectionAddress(nftCollection);
  }

  function test_manager_can_set_and_clear_the_nft_collection() public {
    // Validation probes the collection's balanceOf against the pool manager logic itself.
    _mockNftBalance(address(fundManagerLogic), 0);

    vm.startPrank(manager);

    fundManagerLogic.setNftMembershipCollectionAddress(nftCollection);
    assertEq(fundManagerLogic.nftMembershipCollectionAddress(), nftCollection);

    fundManagerLogic.setNftMembershipCollectionAddress(address(0));
    assertEq(fundManagerLogic.nftMembershipCollectionAddress(), address(0));

    vm.stopPrank();
  }

  function test_revert_setting_a_collection_that_has_no_balanceOf() public {
    // The pool factory is a real contract but exposes no balanceOf, so it cannot gate membership.
    vm.prank(manager);
    vm.expectRevert("Invalid collection");
    fundManagerLogic.setNftMembershipCollectionAddress(address(poolFactoryProxy));
  }

  function test_holding_a_collection_nft_makes_an_address_a_member() public {
    _setNftCollection();
    _mockNftBalance(memberOne, 1);

    assertTrue(fundManagerLogic.isMemberAllowed(memberOne));
  }

  function test_not_holding_a_collection_nft_does_not_make_an_address_a_member() public {
    _setNftCollection();
    _mockNftBalance(memberOne, 0);

    assertFalse(fundManagerLogic.isMemberAllowed(memberOne));
  }

  /// @dev The two sources are additive: setting a collection must not revoke members the manager
  /// added by hand.
  function test_explicit_members_stay_members_alongside_a_collection() public {
    vm.prank(manager);
    fundManagerLogic.addMember(memberOne);

    _setNftCollection();
    _mockNftBalance(memberOne, 0);

    assertTrue(fundManagerLogic.isMemberAllowed(memberOne));
  }

  /* ========== HELPERS ========== */

  function _setNftCollection() internal {
    // Validation probes the collection's balanceOf against the pool manager logic itself.
    _mockNftBalance(address(fundManagerLogic), 0);

    vm.prank(manager);
    fundManagerLogic.setNftMembershipCollectionAddress(nftCollection);
  }

  function _mockNftBalance(address _holder, uint256 _balance) internal {
    vm.mockCall(nftCollection, abi.encodeWithSelector(IERC20.balanceOf.selector, _holder), abi.encode(_balance));
  }

  function _threeMembers() internal view returns (address[] memory members) {
    members = new address[](3);
    members[0] = memberOne;
    members[1] = memberTwo;
    members[2] = memberThree;
  }
}
