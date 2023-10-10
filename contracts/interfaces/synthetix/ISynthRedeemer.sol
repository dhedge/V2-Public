// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISynthRedeemer {
  // Rate of redemption - 0 for none
  function redemptions(address synthProxy) external view returns (uint256 redeemRate);

  // sUSD balance of deprecated token holder
  function balanceOf(IERC20 synthProxy, address account) external view returns (uint256 balanceOfInsUSD);

  // Full sUSD supply of token
  function totalSupply(IERC20 synthProxy) external view returns (uint256 totalSupplyInsUSD);

  function redeem(IERC20 synthProxy) external;

  function redeemAll(IERC20[] calldata synthProxies) external;

  function redeemPartial(IERC20 synthProxy, uint256 amountOfSynth) external;

  // Restricted to Issuer
  function deprecate(IERC20 synthProxy, uint256 rateToRedeem) external;
}
