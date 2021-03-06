// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/balancer/IBalancerV2Vault.sol";
import "../interfaces/balancer/IBalancerPool.sol";

library EasySwapperBalancerV2Helpers {
  using SafeMathUpgradeable for uint160;
  using SafeMathUpgradeable for uint256;

  // natspec to come
  function unrollBalancerLpAndGetUnsupportedLpAssets(
    address poolManagerLogic,
    address balancerPool,
    address withdrawalAsset,
    address weth
  ) internal returns (address[] memory assets) {
    IBalancerV2Vault vault = IBalancerV2Vault(IBalancerPool(balancerPool).getVault());
    bytes32 poolId = IBalancerPool(balancerPool).getPoolId();

    (address[] memory tokens, , ) = vault.getPoolTokens(poolId);

    bool hasWithdrawalAsset;
    uint8 withdrawalAssetIndex;
    bool hasWeth;
    uint8 hasWethIndex;
    bool hasSupportedAsset;
    uint8 supportedAssetIndex;

    for (uint8 i = 0; i < tokens.length; ++i) {
      if (withdrawalAsset == tokens[i]) {
        hasWithdrawalAsset = true;
        withdrawalAssetIndex = i;
        // We break here because this is the optimal outcome
        break;
      } else if (weth == tokens[i]) {
        hasWeth = true;
        hasWethIndex = i;
      } else if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokens[i])) {
        hasSupportedAsset = true;
        supportedAssetIndex = i;
      }
    }

    uint256 balance = IERC20Extended(balancerPool).balanceOf(address(this));
    bytes memory userData;
    if (hasWithdrawalAsset) {
      userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, balance, withdrawalAssetIndex);
      assets = new address[](0);
    } else if (hasWeth) {
      userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, balance, hasWethIndex);
      assets = new address[](0);
    } else if (hasSupportedAsset) {
      userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, balance, supportedAssetIndex);
      assets = new address[](0);
    } else {
      userData = abi.encode(IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, balance);
      assets = tokens;
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

  function isBalancer(address asset) internal view returns (bool) {
    // Maybe there is a cleaner way to detect if it is a balancer pool?
    // Have to use try catch because some erc20 have a fallback function that reverts
    // Also we set the max gas because contracts that don't have a fallback like wmatic chew the remaining gas
    try IBalancerPool(asset).getVault{gas: 5000}() returns (address balancerVaultAddress) {
      return balancerVaultAddress != address(0);
    } catch {
      return false;
    }
  }
}
