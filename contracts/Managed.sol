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
// MIT License
// ===========
//
// Copyright (c) 2020 dHEDGE DAO
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

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";


contract Managed is Initializable {
    using SafeMath for uint256;

    event ManagerUpdated(address newManager, string newManagerName);

    address private _manager;
    string private _managerName;

    address[] private _memberList;
    mapping(address => uint256) private _memberPosition;

    function initialize(address manager, string memory managerName)
        internal
        initializer
    {
        _manager = manager;
        _managerName = managerName;
    }

    modifier onlyManager() {
        require(msg.sender == _manager, "only manager");
        _;
    }

    function managerName() public view returns (string memory) {
        return _managerName;
    }

    function manager() public view returns (address) {
        return _manager;
    }

    function isMemberAllowed(address member) public view returns (bool) {
        return _memberPosition[member] != 0;
    }

    function getMembers() public view returns (address[] memory) {
        return _memberList;
    }

    function changeManager(address newManager, string memory newManagerName)
        public
        onlyManager
    {
        _manager = newManager;
        _managerName = newManagerName;
        emit ManagerUpdated(newManager, newManagerName);
    }

    function addMembers(address[] memory members) public onlyManager {
        for (uint256 i = 0; i < members.length; i++) {
            if (isMemberAllowed(members[i]))
                continue;

            _addMember(members[i]);
        }
    }

    function removeMembers(address[] memory members) public onlyManager {
        for (uint256 i = 0; i < members.length; i++) {
            if (!isMemberAllowed(members[i]))
                continue;

            _removeMember(members[i]);
        }
    }

    function addMember(address member) public onlyManager {
        if (isMemberAllowed(member))
            return;

        _addMember(member);
    }

    function removeMember(address member) public onlyManager {
        if (!isMemberAllowed(member))
            return;

        _removeMember(member);
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

    uint256[50] private __gap;
}
