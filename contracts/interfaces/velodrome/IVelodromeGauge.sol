// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IVelodromeGauge {
  function balanceOf(address user) external view returns (uint256);

  function stake() external view returns (address);

  function left(address token) external view returns (uint256);

  function isForPair() external view returns (bool);

  function rewardsListLength() external view returns (uint256);

  function rewards(uint256 index) external view returns (address);

  function earned(address token, address account) external view returns (uint256);

  // solhint-disable-next-line func-name-mixedcase
  function external_bribe() external view returns (address);

  // solhint-disable-next-line func-name-mixedcase
  function internal_bribe() external view returns (address);

  function notifyRewardAmount(address token, uint256 amount) external;

  function getReward(address account, address[] memory tokens) external;

  function claimFees() external returns (uint256 claimed0, uint256 claimed1);

  function deposit(uint256 amount, uint256 tokenId) external;

  function depositAll(uint256 tokenId) external;

  function withdraw(uint256 amount) external;

  function withdrawAll() external;

  function withdrawToken(uint256 amount, uint256 tokenId) external;
}
