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
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./interfaces/IManaged.sol";

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

/// @notice Role manage contract
contract Managed is IManaged{
  using SafeMathUpgradeable for uint256;

  event ManagerUpdated(address newManager, string newManagerName);

  address public override manager;
  string public override managerName;

  address[] private _memberList;
  mapping(address => uint256) private _memberPosition;

  address private _trader;

  /// @notice Initialize of the managed contract
  /// @param newManager The address of the new manager
  /// @param newManagerName The name of the new manager
  function initialize(address newManager, string memory newManagerName) internal {
    require(newManager != address(0), "Invalid manager");
    manager = newManager;
    managerName = newManagerName;
  }

  modifier onlyManager() {
    require(msg.sender == manager, "only manager");
    _;
  }

  modifier onlyManagerOrTrader() {
    require(msg.sender == manager || msg.sender == _trader, "only manager or trader");
    _;
  }

  /// @notice Return boolean if the address is a member of the list
  /// @param member The address of the member
  /// @return Ture if the address is a member of the list, false otherwise
  function isMemberAllowed(address member) public override view returns (bool) {
    return _memberPosition[member] != 0;
  }

  /// @notice Get a list of members
  /// @return members Array of member addresses
  function getMembers() external view returns (address[] memory members) {
    members = _memberList;
  }

  /// @notice change the manager address
  /// @param newManager The address of the new manager
  /// @param newManagerName The name of the new manager
  function changeManager(address newManager, string memory newManagerName) external onlyManager {
    require(newManager != address(0), "Invalid manager");
    manager = newManager;
    managerName = newManagerName;
    emit ManagerUpdated(newManager, newManagerName);
  }

  /// @notice add a list of members
  /// @param members Array of member addresses
  function addMembers(address[] memory members) external onlyManager {
    for (uint256 i = 0; i < members.length; i++) {
      if (isMemberAllowed(members[i])) continue;

      _addMember(members[i]);
    }
  }

  /// @notice remove a list of members
  /// @param members Array of member addresses
  function removeMembers(address[] memory members) external onlyManager {
    for (uint256 i = 0; i < members.length; i++) {
      if (!isMemberAllowed(members[i])) continue;

      _removeMember(members[i]);
    }
  }

  /// @notice add a member
  /// @param member The address of the member
  function addMember(address member) external onlyManager {
    if (isMemberAllowed(member)) return;

    _addMember(member);
  }

  /// @notice remove a member
  /// @param member The address of the member
  function removeMember(address member) external onlyManager {
    if (!isMemberAllowed(member)) return;

    _removeMember(member);
  }

  /// @notice Return the address of the trader
  /// @return Address of the trader
  function trader() external override view returns (address) {
    return _trader;
  }

  /// @notice Set the address of the trader
  /// @param newTrader The address of the new trader
  function setTrader(address newTrader) external onlyManager {
    require(newTrader != address(0), "Invalid trader");
    _trader = newTrader;
  }

  /// @notice Remove the trader 
  function removeTrader() external onlyManager {
    _trader = address(0);
  }

  /// @notice Return the number of members
  /// @return _numberOfMembers The number of members
  function numberOfMembers() external view returns (uint256 _numberOfMembers) {
    _numberOfMembers = _memberList.length;
  }

  /// @notice Add member internal call
  /// @param member The address of the member
  function _addMember(address member) internal {
    _memberList.push(member);
    _memberPosition[member] = _memberList.length;
  }

  /// @notice Remove member internal call
  /// @param member The address of the member
  function _removeMember(address member) internal {
    uint256 length = _memberList.length;
    uint256 index = _memberPosition[member].sub(1);

    address lastMember = _memberList[length.sub(1)];

    _memberList[index] = lastMember;
    _memberPosition[lastMember] = index.add(1);
    _memberPosition[member] = 0;

    _memberList.pop();
  }

}
