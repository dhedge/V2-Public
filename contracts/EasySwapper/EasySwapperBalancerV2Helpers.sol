// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "../interfaces/IERC20Extended.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/IHasAssetInfo.sol";
import "../interfaces/balancer/IBalancerV2Vault.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IRewardsOnlyGauge.sol";
import "../interfaces/balancer/IRewardsContract.sol";
import "../interfaces/IPoolManagerLogic.sol";

library EasySwapperBalancerV2Helpers {
  function unrollBalancerGaugeAndGetUnsupportedLpAssets(
    address poolManagerLogic,
    address balancerGauge,
    address withdrawalAsset,
    address weth
  ) internal returns (address[] memory assets) {
    address lpToken = IRewardsOnlyGauge(balancerGauge).lp_token();
    address[] memory lpAssets;
    // If the pool also has the LP enabled, it will be unrolled upstream
    // beceause it has a lower assetType, so we skip.
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(lpToken)) {
      lpAssets = unrollBalancerLpAndGetUnsupportedLpAssets(poolManagerLogic, lpToken, withdrawalAsset, weth);
    }

    uint256 rewardCount = IRewardsContract(IRewardsOnlyGauge(balancerGauge).reward_contract()).reward_count();
    assets = new address[](lpAssets.length + rewardCount);
    for (uint256 i = 0; i < rewardCount; i++) {
      assets[i] = IRewardsOnlyGauge(balancerGauge).reward_tokens(i);
    }

    for (uint256 i = 0; i < lpAssets.length; i++) {
      assets[rewardCount + i] = lpAssets[i];
    }
  }

  /// @notice Unrolls a multi asset balancer lp
  /// @dev Either unrolls to a single asset or all assets in the lp
  /// @param poolManagerLogic poolManagerLogic of the pool the swapper is withdrawing from
  /// @param balancerPool address of the LP
  /// @param withdrawalAsset the asset the user wants to withdraw to
  /// @param weth the address of weth
  function unrollBalancerLpAndGetUnsupportedLpAssets(
    address poolManagerLogic,
    address balancerPool,
    address withdrawalAsset,
    address weth
  ) internal returns (address[] memory assets) {
    uint256 balance = IERC20Extended(balancerPool).balanceOf(address(this));
    if (balance > 0) {
      IBalancerV2Vault vault = IBalancerV2Vault(IBalancerPool(balancerPool).getVault());
      bytes32 poolId = IBalancerPool(balancerPool).getPoolId();

      (address[] memory tokens, , ) = vault.getPoolTokens(poolId);
      address[] memory filteredTokens = filterLPAsset(tokens, balancerPool);

      uint8 withdrawalAssetIndex;
      uint8 hasWethIndex;
      uint8 supportedAssetIndex;

      for (uint8 i = 0; i < filteredTokens.length; ++i) {
        if (withdrawalAsset == filteredTokens[i]) {
          withdrawalAssetIndex = i + 1;
          // We break here because this is the optimal outcome
          break;
        } else if (weth == filteredTokens[i]) {
          hasWethIndex = i + 1;
        } else if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(filteredTokens[i])) {
          supportedAssetIndex = i + 1;
        }
      }

      bytes memory userData;
      if (withdrawalAssetIndex > 0) {
        userData = abi.encode(
          IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
          balance,
          withdrawalAssetIndex - 1
        );
        assets = new address[](0);
      } else if (hasWethIndex > 0) {
        userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, balance, hasWethIndex - 1);
        assets = new address[](0);
      } else if (supportedAssetIndex > 0) {
        userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, balance, 0);
        assets = new address[](0);
      } else {
        userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, balance);
        assets = filteredTokens;
      }

      vault.exitPool(
        poolId,
        address(this),
        payable(address(this)),
        IBalancerV2Vault.ExitPoolRequest({
          assets: tokens,
          minAmountsOut: new uint256[](tokens.length),
          userData: userData,
          toInternalBalance: false
        })
      );
    }
  }

  /// @notice Composable pools include the lpAsset in the pool but don't count it as apart of the asset array when encoding userData
  /// @param assets all the assets in the pool
  /// @param lpAsset the lpAsset to filter
  /// @return newAssets all the assets in the pool except the lpAsset
  function filterLPAsset(address[] memory assets, address lpAsset) internal pure returns (address[] memory newAssets) {
    newAssets = new address[](assets.length);
    uint256 hits = 0;

    for (uint256 i = 0; i < assets.length; i++) {
      if (assets[i] != lpAsset) {
        newAssets[hits] = assets[i];
        hits++;
      }
    }
    uint256 reduceLength = newAssets.length - hits;
    assembly {
      mstore(newAssets, sub(mload(newAssets), reduceLength))
    }
  }
}
