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
import "../IGuard.sol";
import "../../utils/TxDataUtils.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IManaged.sol";

contract UniswapV3SwapGuard is TxDataUtils, IGuard {
    using Path for bytes;
    using SafeMath for uint256;

    // transaction guard for Uniswap Swap Router
    function txGuard(address pool, bytes calldata data)
        external
        override
        returns (bool)
    {
        bytes4 method = getMethod(data);

        if (method == bytes4(keccak256("exactInput((bytes,address,uint256,uint256,uint256))"))) {
        
            address toAddress = convert32toAddress(getInput(data, 2)); // receiving address of the trade
            uint256 offset = uint256(getInput(data, 0)).div(32); // dynamic Struct/tuple (abiencoder V2)
            bytes memory path = getBytes(data, 0, offset); // requires an offset due to dynamic Struct/tuple in calldata (abiencoder V2)
            address srcAsset = path.getFirstPool().toAddress(0);
            uint256 srcAmount = uint256(getInput(data, 4));
            address dstAsset;
            bool hasMultiplePools = path.hasMultiplePools();
            IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(pool);
            
            require(hasMultiplePools, "trade invalid");
            

            // check that all swap path assets are supported
            // srcAsset -> while loop(path assets) -> dstAsset
            // TODO: consider a better way of doing this

            // check that source asset is supported
            require(
                poolManagerLogic.isSupportedAsset(srcAsset),
                "unsupported source asset"
            );
            
            address asset;

            // check that path assets are valid by dhedge protocol
            while(hasMultiplePools) {
                path = path.skipToken();
                asset = path.getFirstPool().toAddress(0); // gets asset from swap path
                hasMultiplePools = path.hasMultiplePools();
  
                require(
                    poolManagerLogic.validateAsset(asset),
                    "invalid path asset"
                );
            }
            
            // check that destination asset is supported (if it's a valid address)
            (,dstAsset,) = path.decodeFirstPool(); // gets the destination asset
            if (dstAsset == address(0)) { // if the remaining path is just trailing zeros, use the last path asset instead
                dstAsset = asset;
            } else {
                require(
                    poolManagerLogic.isSupportedAsset(dstAsset),
                    "unsupported destination asset"
                );
            }

            require(pool == toAddress, "recipient is not pool");

            emit Exchange(
                address(poolManagerLogic), // TODO: should this be poolLogic address instead?
                srcAsset,
                srcAmount,
                dstAsset,
                block.timestamp
            );

            return true;
        }

        if (method == bytes4(keccak256("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"))) {
        
            address srcAsset = convert32toAddress(getInput(data, 0));
            address dstAsset = convert32toAddress(getInput(data, 1));
            address toAddress = convert32toAddress(getInput(data, 3)); // receiving address of the trade
            uint256 srcAmount = uint256(getInput(data, 5));
            IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(pool);

            require(
                poolManagerLogic.isSupportedAsset(srcAsset),
                "unsupported source asset"
            );
            
            require(
                poolManagerLogic.isSupportedAsset(dstAsset),
                "unsupported destination asset"
            );
            
            require(pool == toAddress, "recipient is not pool");

            emit Exchange(
                address(poolManagerLogic), // TODO: should this be poolLogic address instead?
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
