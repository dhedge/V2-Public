// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/balancer/IBalancerV2Vault.sol";
import "../interfaces/balancer/IBalancerPool.sol";

// library with helper methods for oracles that are concerned with computing average prices
library EasySwapperBalancerV2Helpers {
  using SafeMathUpgradeable for uint160;
  using SafeMathUpgradeable for uint256;

  // natspec to come
  function unrollBalancerLpAndGetUnsupportedLpAssets(
    address poolManagerLogic,
    address balancerPool,
    address withdrawalAsset
  ) internal view returns (address[] memory assets) {
    IBalancerV2Vault vault = IBalancerPool(balancerPool).getVault();
    bytes32 poolId = IBalancerPool(balancerPool).getPoolId();
    // struct ExitPoolRequest {
    //   address[] assets;
    //   uint256[] minAmountsOut;
    //   bytes userData;
    //   bool toInternalBalance;
    // }
    // Not sure if/how to initialise all these fields ^^
    IBalancerV2Vault.ExitPoolRequest memory request;

    (address[] memory tokens, , , ) = vault.getPoolTokens(poolId);

    bool hasWithdrawalAsset;
    bool hasSupportedAsset;
    uint256 supportedAssetIndex;
    for (uint8 i = 0; i < tokens.length; ++i) {
      if (withdrawalAsset == tokens[i]) {
        hasWithdrawalAsset = true;
        break;
      }
      if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokens[i])) {
        hasSupportedAsset = true;
        supportedAssetIndex = i;
      }
    }

    if (hasWithdrawalAsset || hasSupportedAsset) {
      request.assets = new address[](1)[0] = hasWithdrawalAsset ? withdrawalAsset : tokens[supportedAssetIndex];
      assets = new address[](0);
    } else {
      request.assets = tokens;
      assets = tokens;
    }

    //   function exitPool(
    //   bytes32 poolId,
    //   address sender,
    //   address payable recipient,
    //   ExitPoolRequest memory request
    // ) external;
    vault.exitPool(poolId, address(this), address(this), request);
  }
}
