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

pragma solidity ^0.6.2;

import "./InitializableUpgradeabilityProxy.sol";
import "./HasLogic.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

contract ProxyFactory is OwnableUpgradeSafe, HasLogic {
    event ProxyCreated(address proxy);

    address private _logic;

    function __ProxyFactory_init(address poolLogic) public initializer {
        OwnableUpgradeSafe.__Ownable_init();

        _logic = poolLogic;
    }

    function setLogic(address logic) public onlyOwner {
        _logic = logic;
    }

    function getLogic() public override view returns (address) {
        return _logic;
    }

    function deploy(bytes memory _data) public returns (address) {
        return _deployProxy(_data);
    }

    function _deployProxy(bytes memory _data) internal returns (address) {
        InitializableUpgradeabilityProxy proxy = _createProxy();
        emit ProxyCreated(address(proxy));
        proxy.initialize(address(this), _data);
        return address(proxy);
    }

    function _createProxy()
        internal
        returns (InitializableUpgradeabilityProxy)
    {
        address payable addr;
        bytes memory code = type(InitializableUpgradeabilityProxy).creationCode;

        assembly {
            addr := create(0, add(code, 0x20), mload(code))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }

        return InitializableUpgradeabilityProxy(addr);
    }
    
    uint256[50] private __gap;
}
