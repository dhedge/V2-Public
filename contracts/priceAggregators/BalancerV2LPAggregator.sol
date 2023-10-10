// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/uniswapV2/IUniswapV2Pair.sol";
import "../interfaces/balancer/IBalancerWeightedPool.sol";
import "../interfaces/balancer/IBalancerV2Vault.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()
import "../interfaces/IHasAssetInfo.sol";
import "../utils/DhedgeMath.sol";
import "../utils/BalancerLib.sol";

/**
 * @title Balancer-v2 LP aggregator. For dHEDGE LP Price Feeds.
 * @notice You can use this contract for lp token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract BalancerV2LPAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  struct PriceDeviationParams {
    uint256 maxPriceDeviation; // Threshold of spot prices deviation: 10ˆ16 represents a 1% deviation. Must be between 1 and 10ˆ18.
    // solhint-disable-next-line var-name-mixedcase
    uint256 K; // Constant K=1/ (w1ˆw1 * .. * wn^wn)
    uint256 powerPrecision; // Precision for power math function.
    uint256[][] approximationMatrix; // Approximation matrix for gas optimization
  }

  address public factory;
  IBalancerV2Vault public vault;
  IBalancerWeightedPool public pool;
  bytes32 public poolId;
  address[] public tokens;
  uint8[] public tokenDecimals;
  uint256[] public weights;
  PriceDeviationParams public params;

  constructor(
    address _factory,
    IBalancerWeightedPool _pool,
    PriceDeviationParams memory _params
  ) {
    require(_factory != address(0), "_factory address cannot be 0");
    require(address(_pool) != address(0), "_pool address cannot be 0");

    factory = _factory;
    vault = IBalancerV2Vault(_pool.getVault());
    pool = _pool;
    poolId = _pool.getPoolId();

    (tokens, , ) = vault.getPoolTokens(poolId);
    weights = pool.getNormalizedWeights();

    uint256 length = tokens.length;
    for (uint256 i = 0; i < length; i++) {
      tokenDecimals.push(IERC20Extended(tokens[i]).decimals());
    }

    require(_params.maxPriceDeviation < BalancerLib.BONE, "Invalid Price Deviation");
    require(_params.powerPrecision >= 1 && _params.powerPrecision <= BalancerLib.BONE, "Invalid Power Precision");
    require(
      _params.approximationMatrix.length == 0 || _params.approximationMatrix[0].length == length + 1,
      "Invalid Approx Matrix"
    );

    params = _params;
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
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
  function latestRoundData()
    external
    view
    override
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    uint256 answer = 0;
    uint256[] memory usdTotals = _getUSDBalances();

    if (_hasDeviation(usdTotals)) {
      answer = _getWeightedGeometricMean(usdTotals);
    } else {
      answer = _getArithmeticMean(usdTotals);
    }

    return (0, int256(answer.div(10**10)), 0, block.timestamp, 0);
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
      usdBalances[index] = _getTokenPrice(tokens[index]).mul(balances[index]).div(10**tokenDecimals[index]);
    }
  }

  /**
   * Returns true if there is a price deviation.
   * @param usdTotals Balance of each token in usd.
   */
  function _hasDeviation(uint256[] memory usdTotals) internal view returns (bool) {
    uint256 length = tokens.length;
    for (uint256 i = 0; i < length; i++) {
      for (uint256 o = 0; o < length; o++) {
        if (i != o) {
          uint256 priceDeviation = usdTotals[i].mul(weights[o]).div(usdTotals[o]).div(weights[i]);
          if (
            priceDeviation > (BalancerLib.BONE + params.maxPriceDeviation) ||
            priceDeviation < (BalancerLib.BONE - params.maxPriceDeviation)
          ) {
            return true;
          }
        }
      }
    }
    return false;
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
    return BalancerLib.bdiv(totalUsd, pool.totalSupply());
  }

  /**
   * Calculates the price of the pool token using the formula of weighted geometric mean.
   * @param usdTotals Balance of each token in usd.
   */
  function _getWeightedGeometricMean(uint256[] memory usdTotals) internal view returns (uint256) {
    uint256 mult = BalancerLib.BONE;
    uint256 length = tokens.length;
    for (uint256 i = 0; i < length; i++) {
      mult = BalancerLib.bmul(mult, _getWeightedUSDBalanceByToken(i, usdTotals[i]));
    }
    return BalancerLib.bdiv(BalancerLib.bmul(mult, params.K), pool.totalSupply());
  }

  /**
   * Returns the weighted token balance in ethers by calculating the balance in ether of the token to the power of its weight.
   * @param index Token index.
   * @param usdTotal Balance of index token in usd.
   */
  function _getWeightedUSDBalanceByToken(uint256 index, uint256 usdTotal) internal view returns (uint256) {
    uint256 weight = weights[index];
    (uint256 base, uint256 result) = _getClosestBaseAndExponetation(index, usdTotal);

    if (base == 0 || usdTotal < BalancerLib.MAX_BPOW_BASE) {
      if (usdTotal < BalancerLib.MAX_BPOW_BASE) {
        return BalancerLib.bpowApprox(usdTotal, weight, params.powerPrecision);
      } else {
        return
          BalancerLib.bmul(
            usdTotal,
            BalancerLib.bpowApprox(
              BalancerLib.bdiv(BalancerLib.BONE, usdTotal),
              (BalancerLib.BONE - weight),
              params.powerPrecision
            )
          );
      }
    } else {
      return
        BalancerLib.bmul(
          result,
          BalancerLib.bpowApprox(BalancerLib.bdiv(usdTotal, base), weight, params.powerPrecision)
        );
    }
  }

  /**
   * Using the matrix approximation, returns a near base and exponentiation result, for num ^ weights[index]
   * @param index Token index.
   * @param num Base to approximate.
   */
  function _getClosestBaseAndExponetation(uint256 index, uint256 num) internal view returns (uint256, uint256) {
    for (uint256 i = 0; i < params.approximationMatrix.length; i++) {
      if (params.approximationMatrix[i][0] >= num) {
        return (params.approximationMatrix[i][0], params.approximationMatrix[i][index + 1]);
      }
    }
    return (0, 0);
  }
}
