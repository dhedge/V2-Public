//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import {IManaged} from "./interfaces/IManaged.sol";

/// @notice Role manage contract
contract Managed is IManaged {
  using SafeMathUpgradeable for uint256;

  event ManagerUpdated(address newManager, string newManagerName);

  address public override manager;
  string public override managerName;

  address[] private _memberList;
  mapping(address => uint256) private _memberPosition;

  address public override trader;

  /// @notice Initialize of the managed contract
  /// @param _newManager The address of the new manager
  /// @param _newManagerName The name of the new manager
  function _initialize(address _newManager, string memory _newManagerName) internal {
    require(_newManager != address(0), "Invalid manager");
    manager = _newManager;
    managerName = _newManagerName;
  }

  modifier onlyManager() {
    require(msg.sender == manager, "only manager");
    _;
  }

  modifier onlyManagerOrTrader() {
    require(msg.sender == manager || msg.sender == trader, "only manager or trader");
    _;
  }

  /// @notice Return boolean if the address is a member of the list
  /// @param _member The address of the member
  /// @return True if the address is a member of the list, false otherwise
  function _isMemberAllowed(address _member) internal view returns (bool) {
    return _memberPosition[_member] != 0;
  }

  /// @notice Get a list of members
  /// @return members Array of member addresses
  function getMembers() external view returns (address[] memory members) {
    members = _memberList;
  }

  /// @notice change the manager address
  /// @param _newManager The address of the new manager
  /// @param _newManagerName The name of the new manager
  function changeManager(address _newManager, string memory _newManagerName) external onlyManager {
    require(_newManager != address(0), "Invalid manager");
    manager = _newManager;
    managerName = _newManagerName;
    emit ManagerUpdated(_newManager, _newManagerName);
  }

  /// @notice add a list of members
  /// @param _members Array of member addresses
  function addMembers(address[] memory _members) external onlyManager {
    for (uint256 i = 0; i < _members.length; i++) {
      if (_isMemberAllowed(_members[i])) continue;

      _addMember(_members[i]);
    }
  }

  /// @notice remove a list of members
  /// @param _members Array of member addresses
  function removeMembers(address[] memory _members) external onlyManager {
    for (uint256 i = 0; i < _members.length; i++) {
      if (!_isMemberAllowed(_members[i])) continue;

      _removeMember(_members[i]);
    }
  }

  /// @notice add a member
  /// @param _member The address of the member
  function addMember(address _member) external onlyManager {
    if (_isMemberAllowed(_member)) return;

    _addMember(_member);
  }

  /// @notice remove a member
  /// @param _member The address of the member
  function removeMember(address _member) external onlyManager {
    if (!_isMemberAllowed(_member)) return;

    _removeMember(_member);
  }

  /// @notice Set the address of the trader
  /// @param _newTrader The address of the new trader
  function setTrader(address _newTrader) external onlyManager {
    require(_newTrader != address(0), "Invalid trader");
    trader = _newTrader;
  }

  /// @notice Remove the trader
  function removeTrader() external onlyManager {
    trader = address(0);
  }

  /// @notice Return the number of members
  /// @return numOfMembers The number of members
  function numberOfMembers() external view returns (uint256 numOfMembers) {
    numOfMembers = _memberList.length;
  }

  function _addMember(address _member) internal {
    _memberList.push(_member);
    _memberPosition[_member] = _memberList.length;
  }

  function _removeMember(address _member) internal {
    uint256 length = _memberList.length;
    uint256 index = _memberPosition[_member].sub(1);

    address lastMember = _memberList[length.sub(1)];

    _memberList[index] = lastMember;
    _memberPosition[lastMember] = index.add(1);
    _memberPosition[_member] = 0;

    _memberList.pop();
  }
}
