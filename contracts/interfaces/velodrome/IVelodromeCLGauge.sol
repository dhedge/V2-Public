// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IVelodromeCLGauge {
  /// @notice NonfungiblePositionManager used to create nfts this gauge accepts
  function nft() external view returns (address);

  /// @notice Voter contract gauge receives emissions from
  function voter() external view returns (address);

  /// @notice Address of the emissions token
  function rewardToken() external view returns (address);

  /// @notice Returns the claimable rewards for a given account and tokenId
  /// @dev Throws if account is not the position owner
  /// @dev pool.updateRewardsGrowthGlobal() needs to be called first, to return the correct claimable rewards
  /// @param account The address of the user
  /// @param tokenId The tokenId of the position
  /// @return The amount of claimable reward
  function earned(address account, uint256 tokenId) external view returns (uint256);

  /// @notice Retrieve rewards for all tokens owned by an account
  /// @dev Throws if not called by the voter
  /// @param account The account of the user
  function getReward(address account) external;

  /// @notice Retrieve rewards for a tokenId
  /// @dev Throws if not called by the position owner
  /// @param tokenId The tokenId of the position
  function getReward(uint256 tokenId) external;

  /// @notice Used to deposit a CL position into the gauge
  /// @notice Allows the user to receive emissions instead of fees
  /// @param tokenId The tokenId of the position
  function deposit(uint256 tokenId) external;

  /// @notice Used to withdraw a CL position from the gauge
  /// @notice Allows the user to receive fees instead of emissions
  /// @notice Outstanding emissions will be collected on withdrawal
  /// @param tokenId The tokenId of the position
  function withdraw(uint256 tokenId) external;

  /// @notice Claimable rewards by tokenId
  function rewards(uint256 tokenId) external view returns (uint256);

  /// @notice Used to increase liquidity of a staked position
  /// @param tokenId The tokenId of the position
  /// @param amount0Desired The desired amount of token0 to be staked,
  /// @param amount1Desired The desired amount of token1 to be staked,
  /// @param amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
  /// @param amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
  /// @param deadline The time by which the transaction must be included to effect the change
  /// @return liquidity The new liquidity amount as a result of the increase
  /// @return amount0 The amount of token0 required to obtain new liquidity amount
  /// @return amount1 The amount of token1 required to obtain new liquidity amount
  function increaseStakedLiquidity(
    uint256 tokenId,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 deadline
  ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);

  /// @notice Used to decrease liquidity of a staked position
  /// @param tokenId The tokenId of the position
  /// @param liquidity The amount of liquidity to be unstaked from the gauge
  /// @param amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
  /// @param amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
  /// @param deadline The time by which the transaction must be included to effect the change
  /// @return amount0 The amount of token0 decreased from position
  /// @return amount1 The amount of token1 decreased from position
  function decreaseStakedLiquidity(
    uint256 tokenId,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    uint256 deadline
  ) external returns (uint256 amount0, uint256 amount1);
}
