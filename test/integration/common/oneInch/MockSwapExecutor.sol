// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IAggregationExecutor} from "contracts/interfaces/oneInch/IAggregationRouterV6.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";

/// @notice Custom executor the manager hands to the router: sends the source token it received on to
///         `beneficiary` and returns `dstReturnAmount` of a supported token to the ROUTER, which
///         forwards it to the pool. Shared by the 1inch guard tests and the aToken exfiltration test.
/// @dev Implements both executor interfaces: 1inch `execute(address)` and Kyber `callBytes(bytes)`.
contract MockSwapExecutor is IAggregationExecutor {
  address public immutable srcToken; // token that leaves the vault (aToken, WETH, or a reward token)
  address public immutable dstToken; // supported token returned to the pool
  address public immutable beneficiary; // where the source token ends up
  uint256 public immutable dstReturnAmount;

  constructor(address _srcToken, address _dstToken, address _beneficiary, uint256 _dstReturnAmount) {
    srcToken = _srcToken;
    dstToken = _dstToken;
    beneficiary = _beneficiary;
    dstReturnAmount = _dstReturnAmount;
  }

  function execute(address /* msgSender */) external payable override returns (uint256) {
    _swap();
    return dstReturnAmount;
  }

  function callBytes(bytes calldata /* data */) external payable {
    _swap();
  }

  function _swap() internal {
    // The router already sent the vault's source tokens here (srcReceiver == this).
    IERC20(srcToken).transfer(beneficiary, IERC20(srcToken).balanceOf(address(this)));
    // Hand the destination tokens to the ROUTER; it forwards them to `dstReceiver`.
    IERC20(dstToken).transfer(msg.sender, dstReturnAmount);
  }
}
