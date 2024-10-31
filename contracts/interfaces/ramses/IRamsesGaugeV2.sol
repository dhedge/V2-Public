// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IRamsesGaugeV2 {
  /// @notice Returns an array of reward token addresses.
  /// @return An array of reward token addresses.
  function getRewardTokens() external view returns (address[] memory);

  /// @notice Returns the amount of rewards earned for an NFP.
  /// @param token The address of the token for which to retrieve the earned rewards.
  /// @param tokenId The identifier of the specific NFP for which to retrieve the earned rewards.
  /// @return reward The amount of rewards earned for the specified NFP and tokens.
  function earned(address token, uint256 tokenId) external view returns (uint256 reward);

  function getReward(uint256 tokenId, address[] memory tokens) external;
}
