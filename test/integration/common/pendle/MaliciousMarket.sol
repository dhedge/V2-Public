// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PendleRouterV4ContractGuard} from "contracts/guards/contractGuards/pendle/PendleRouterV4ContractGuard.sol";
import {IPActionSwapPTV3} from "contracts/interfaces/pendle/IPActionSwapPTV3.sol";
import "contracts/interfaces/pendle/IPAllActionTypeV3.sol" as IPAllActionTypeV3;

contract MaliciousMarket {
  address public PT;
  address public receiver;
  address public someSupportedToken;
  address public pendleContractGuard;

  constructor(address _pt, address _receiver, address _someSupportedToken, address _pendleContractGuard) {
    PT = _pt;
    receiver = _receiver;
    someSupportedToken = _someSupportedToken;
    pendleContractGuard = _pendleContractGuard;
  }

  function SY() external view returns (address) {
    return address(this);
  }

  function swapExactPtForSy(address, uint256, bytes memory data) external returns (uint256 netSyOut, uint256 netSyFee) {
    IERC20(PT).transfer(receiver, IERC20(PT).balanceOf(address(this)));

    data = abi.encodeWithSelector(
      IPActionSwapPTV3.swapExactPtForToken.selector,
      address(this),
      address(this),
      0,
      IPAllActionTypeV3.createTokenOutputSimple(someSupportedToken, 0),
      IPAllActionTypeV3.createEmptyLimitOrderData()
    );

    PendleRouterV4ContractGuard(pendleContractGuard).txGuard(address(this), address(0), data); // Reentering here.

    return (1e18, 0);
  }

  function readTokens() external view returns (address, address, address) {
    return (address(this), PT, address(this));
  }

  function poolLogic() external view returns (address) {
    return address(this);
  }

  function isSupportedAsset(address) external pure returns (bool) {
    return true;
  }

  function redeem(address, uint256, address, uint256, bool) external pure returns (uint256 amountTokenOut) {
    return 1e18;
  }

  function transferFrom(address, address, uint256) external pure returns (bool) {
    return true;
  }
}
