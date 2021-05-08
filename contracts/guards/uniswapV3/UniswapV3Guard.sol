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

import "./Path.sol";
import "../TxDataUtils.sol";
import "../IGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IManaged.sol";

contract UniswapV3Guard is TxDataUtils, IGuard {
    using Path for bytes;
    using SafeMath for uint256;
    
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    
    // event SomeData(
    //     bytes data,
    //     bool hasMultiplePools
    // );

    // transaction guard for 1inch V3 aggregator
    function txGuard(address pool, bytes calldata data)
        external
        override
        returns (bool)
    {
        bytes4 method = getMethod(data);

        if (method == bytes4(0xc04b8d59)) { // ExactInput()
        
            address toAddress = convert32toAddress(getInput(data, 2)); // receiving address of the trade
            bytes memory path = getBytes(data, 0, 32); // requires an offset of 32 bytes due to Struct in calldata (I think)
            address srcAsset = path.getFirstPool().toAddress(0);
            uint256 srcAmount = uint256(getInput(data, 4));
            address dstAsset;
            bool hasMultiplePools = path.hasMultiplePools();
            IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(pool);
            
            require(hasMultiplePools, "trade invalid");
            
            require(
                poolManagerLogic.isAssetSupported(srcAsset),
                "unsupported source asset"
            );
            
            
            while(hasMultiplePools) {
                // emit SomeData(path, hasMultiplePools);
                path = path.skipToken();
                address asset = path.getFirstPool().toAddress(0); // gets asset from swap path
                hasMultiplePools = path.hasMultiplePools();
  
                require(
                    poolManagerLogic.isAssetSupported(asset),
                    "unsupported path asset"
                );
            }
            
            (,dstAsset,) = path.decodeFirstPool(); // gets the destination asset
            
            require(
                poolManagerLogic.isAssetSupported(dstAsset),
                "unsupported destination asset"
            );
            
            require(pool == toAddress, "recipient is not pool");

            emit Exchange(
                address(poolManagerLogic),
                srcAsset,
                srcAmount,
                dstAsset,
                block.timestamp
            );

            return true;
        }

        return false;
    }
}
