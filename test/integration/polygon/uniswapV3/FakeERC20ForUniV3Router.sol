// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IV3SwapRouter} from "contracts/interfaces/uniswapV3/IV3SwapRouter.sol";
import {IGuard} from "contracts/interfaces/guards/IGuard.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";

contract FakeERC20ForUniV3Router {
  address public immutable uniV3RouterContractGuard;

  bool public done;

  mapping(address => uint256) public balances;

  constructor(address _uniV3RouterContractGuard) {
    uniV3RouterContractGuard = _uniV3RouterContractGuard;
  }

  function balanceOf(address account) public view returns (uint256) {
    return balances[account];
  }

  function transfer(address to, uint256 value) public returns (bool) {
    if (to == PolygonConfig.UNISWAP_V3_ROUTER && !done) {
      done = true;
      bytes memory path = abi.encodePacked(PolygonConfig.WBTC, uint24(500), PolygonConfig.WETH);
      IV3SwapRouter.ExactInputParams memory inputParams = IV3SwapRouter.ExactInputParams(path, address(this), 0, 0);
      bytes memory cd = abi.encodeWithSelector(IV3SwapRouter.exactInput.selector, inputParams);
      IGuard(uniV3RouterContractGuard).txGuard(address(this), address(this), cd); // Reenter to clear slippage acc data
    }
    balances[to] += value;
    return true;
  }

  function transferFrom(address, address to, uint256 value) public returns (bool) {
    balances[to] += value;
    return true;
  }

  function poolLogic() external view returns (address) {
    return address(this);
  }

  function isSupportedAsset(address) external pure returns (bool) {
    return true;
  }
}
