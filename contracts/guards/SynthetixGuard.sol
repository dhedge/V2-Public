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

import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

import "./IGuard.sol";
import "../utils/TxDataUtils.sol";
import "../interfaces/ISynth.sol";
import "../interfaces/ISynthetix.sol";
import "../interfaces/IAddressResolver.sol";
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";

contract SynthetixGuard is TxDataUtils, IGuard {
    using SafeMath for uint256;

    bytes32 private constant _SYNTHETIX_KEY = "Synthetix";

    IAddressResolver public addressResolver;

    constructor(IAddressResolver _addressResolver) public {
        addressResolver = _addressResolver;
    }

    function txGuard(address pool, bytes calldata data)
        external
        override
        returns (bool)
    {
        bytes4 method = getMethod(data);

        if (method == bytes4(keccak256("exchangeWithTracking(bytes32,uint256,bytes32,address,bytes32)"))) {
            bytes32 srcKey = getInput(data, 0);
            bytes32 srcAmount = getInput(data, 1);
            bytes32 dstKey = getInput(data, 2);

            address srcAsset = getAssetProxy(srcKey);
            address dstAsset = getAssetProxy(dstKey);
            
            IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(pool);
            require(
                poolManagerLogic.isAssetSupported(srcAsset),
                "unsupported destination asset"
            );
            require(
                poolManagerLogic.isAssetSupported(dstAsset),
                "unsupported destination asset"
            );

            emit Exchange(
                address(poolManagerLogic),
                srcAsset,
                uint256(srcAmount),
                dstAsset,
                block.timestamp
            );

            return true;
        }

        return false;
    }

    function getAssetProxy(bytes32 key) public view returns (address) {
        address synth =
            ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY)).synths(key);
        require(synth != address(0), "invalid key");
        address proxy = ISynth(synth).proxy();
        require(proxy != address(0), "invalid proxy");
        return proxy;
    }
}
