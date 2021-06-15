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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

contract Managed {
  using SafeMathUpgradeable for uint256;

  event ManagerUpdated(address newManager, string newManagerName);

  address public manager;
  string public managerName;

  address[] private _memberList;
  mapping(address => uint256) private _memberPosition;

  address private _trader;

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

  function isMemberAllowed(address member) public view returns (bool) {
    return _memberPosition[member] != 0;
  }

  function getMembers() public view returns (address[] memory) {
    return _memberList;
  }

  function changeManager(address newManager, string memory newManagerName) public onlyManager {
    require(newManager != address(0), "Invalid manager");
    manager = newManager;
    managerName = newManagerName;
    emit ManagerUpdated(newManager, newManagerName);
  }

  function addMembers(address[] memory members) public onlyManager {
    for (uint256 i = 0; i < members.length; i++) {
      if (isMemberAllowed(members[i])) continue;

      _addMember(members[i]);
    }
  }

  function removeMembers(address[] memory members) public onlyManager {
    for (uint256 i = 0; i < members.length; i++) {
      if (!isMemberAllowed(members[i])) continue;

      _removeMember(members[i]);
    }
  }

  function addMember(address member) public onlyManager {
    if (isMemberAllowed(member)) return;

    _addMember(member);
  }

  function removeMember(address member) public onlyManager {
    if (!isMemberAllowed(member)) return;

    _removeMember(member);
  }

  function trader() public view returns (address) {
    return _trader;
  }

  function setTrader(address newTrader) public onlyManager {
    require(newTrader != address(0), "Invalid trader");
    _trader = newTrader;
  }

  function removeTrader() public onlyManager {
    _trader = address(0);
  }

  function numberOfMembers() public view returns (uint256) {
    return _memberList.length;
  }

  function _addMember(address member) internal {
    _memberList.push(member);
    _memberPosition[member] = _memberList.length;
  }

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
