// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import {IPancakeNonfungiblePositionManager} from "./IPancakeNonfungiblePositionManager.sol";

interface IPancakeMasterChefV3 {
  function nonfungiblePositionManager() external view returns (IPancakeNonfungiblePositionManager);
  function sweepToken(address token, uint256 amountMinimum, address recipient) external payable;
  function harvest(uint256 tokenId, address to) external returns (uint256 reward);
  function withdraw(uint256 _tokenId, address _to) external returns (uint256 reward);
}
