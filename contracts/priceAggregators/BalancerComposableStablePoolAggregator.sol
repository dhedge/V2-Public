// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/balancer/IBalancerComposablePool.sol";
import "../interfaces/balancer/IBalancerV2Vault.sol";
import "../interfaces/IHasAssetInfo.sol";
import "../interfaces/IERC20Extended.sol";
import "../utils/BalancerLib.sol";

/**
 * @title Balancer-v2 Composable Stable Pool aggregator. For dHEDGE LP Price Feeds.
 * @notice You can use this contract for lp token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 * @dev https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/pool-stable/contracts/ComposableStablePool.sol
 */
contract BalancerComposableStablePoolAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  address public factory;
  IBalancerV2Vault public vault;
  IBalancerComposablePool public pool;
  bytes32 public poolId;
  address[] public tokens;
  uint8[] public tokenDecimals;

  constructor(address _factory, IBalancerComposablePool _pool) {
    require(_factory != address(0), "_factory address cannot be 0");
    require(address(_pool) != address(0), "_pool address cannot be 0");

    factory = _factory;
    pool = _pool;
    vault = IBalancerV2Vault(_pool.getVault());
    poolId = _pool.getPoolId();
    (tokens, , ) = IBalancerV2Vault(vault).getPoolTokens(poolId);

    for (uint256 i = 0; i < tokens.length; i++) {
      tokenDecimals.push(IERC20Extended(tokens[i]).decimals());
    }
  }

  /* ========== VIEWS ========== */

  function decimals() public pure override returns (uint8) {
    return 8;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of a given balancer-v2 lp token (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
   */
  function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
    uint256 answer = 0;
    uint256[] memory usdTotals = _getUSDBalances();

    answer = _getArithmeticMean(usdTotals); // 18 decimals

    return (0, int256(answer.div(10 ** 10)), 0, block.timestamp, 0); // answer in 8 decimals
  }

  /* ========== INTERNAL ========== */

  function _getTokenPrice(address token) internal view returns (uint256) {
    return IHasAssetInfo(factory).getAssetPrice(token);
  }

  /**
   * @notice Get USD balances for each tokens of the pool.
   * @return usdBalances Balance of each token in usd. (in 18 decimals)
   */
  function _getUSDBalances() internal view returns (uint256[] memory usdBalances) {
    usdBalances = new uint256[](tokens.length);
    (, uint256[] memory balances, ) = vault.getPoolTokens(poolId);

    for (uint256 index = 0; index < tokens.length; index++) {
      // Composable pool, ignore the Balancer pool token
      if (tokens[index] != address(pool)) {
        usdBalances[index] = _getTokenPrice(tokens[index]).mul(balances[index]).div(10 ** tokenDecimals[index]);
      }
    }
  }

  /**
   * Calculates the price of the pool token using the formula of weighted arithmetic mean.
   * @param usdTotals Balance of each token in usd.
   */
  function _getArithmeticMean(uint256[] memory usdTotals) internal view returns (uint256) {
    uint256 totalUsd = 0;
    for (uint256 i = 0; i < tokens.length; i++) {
      totalUsd = totalUsd.add(usdTotals[i]);
    }
    return totalUsd.mul(10 ** 18).div(pool.getActualSupply());
  }
}
