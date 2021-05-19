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
import "../interfaces/IPoolManagerLogic.sol";
import "../interfaces/IHasGuardInfo.sol";
import "../interfaces/IManaged.sol";

contract UniswapV2Guard is TxDataUtils, IGuard {
    using SafeMath for uint256;

    // transaction guard for 1inch V3 aggregator
    function txGuard(address pool, bytes calldata data)
        external
        override
        returns (bool)
    {
        bytes4 method = getMethod(data);

        if (method == bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"))) {
            address srcAsset = convert32toAddress(getArrayIndex(data, 2, 0)); // gets the second input (path) first item (token to swap from)
            address dstAsset = convert32toAddress(getArrayLast(data, 2)); // gets second input (path) last item (token to swap to)
            uint256 srcAmount = uint256(getInput(data, 0));
            address toAddress = convert32toAddress(getInput(data, 3));
            uint256 routeLength = getArrayLength(data, 2); // length of the routing addresses

            IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(pool);
            require(
                poolManagerLogic.isSupportedAsset(srcAsset),
                "unsupported source asset"
            );

            // validate Uniswap routing addresses
            for (uint8 i = 1; i < routeLength - 1; i++) {
                require(
                    poolManagerLogic.validateAsset(
                        convert32toAddress(getArrayIndex(data, 2, i))
                    ),
                    "invalid routing asset"
                );
            }

            require(
                poolManagerLogic.isSupportedAsset(dstAsset),
                "unsupported destination asset"
            );

            require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");

            emit Exchange(
                poolManagerLogic.poolLogic(),
                srcAsset,
                uint256(srcAmount),
                dstAsset,
                block.timestamp
            );

            return true;
        }

        return false;
    }
}
