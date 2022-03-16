// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IHasAssetInfo.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IPoolLogic.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IPoolFactory.sol";
import "./EasySwapperV3Helpers.sol";
import "./EasySwapperV2LpHelpers.sol";
import "./EasySwapperBalancerV2Helpers.sol";

// library with helper methods for oracles that are concerned with computing average prices
library EasySwapperWithdrawer {
  using SafeMathUpgradeable for uint160;
  using SafeMathUpgradeable for uint256;
  using SafeERC20 for IERC20;

  event Withdraw(
    address pool,
    uint256 fundTokenAmount,
    address withdrawalAsset,
    uint256 amountWithdrawnInWithdrawalAsset
  );

  /// @notice withdraw underlying value of tokens in expectedWithdrawalAssetOfUser
  /// @dev Swaps the underlying pool withdrawal assets to expectedWithdrawalAssetOfUser
  /// @param fundTokenAmount the amount to withdraw
  /// @param withdrawalAsset must have direct pair to all pool.supportedAssets on swapRouter
  /// @param expectedAmountOut the amount of value in the withdrawalAsset expected (slippage protection)
  function withdraw(
    address pool,
    uint256 fundTokenAmount,
    IERC20 withdrawalAsset,
    uint256 expectedAmountOut,
    IUniswapV2Router swapRouter,
    IERC20 weth,
    IUniswapV2Router assetType2Router,
    IUniswapV2Router assetType5Router
  ) external {
    IERC20(pool).safeTransferFrom(msg.sender, address(this), fundTokenAmount);
    IPoolLogic(pool).withdraw(fundTokenAmount);

    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic())
      .getSupportedAssets();

    // What in all mother of hell is going on here?
    // Before we start swapping into our withdrawalAsset
    // We must unroll quick lps, sushi lps and balancer lps.
    // We must also return the assets these lp's are unrolled to
    // So that we can swap them also into our withdrawalAsset.
    // We also must detect which assets the pool had v3 lp in and
    // swap those into our withdrawalAsset.

    // Also be aware that we must unroll out sushi lps before any
    // withdrawing takes place because the pool might be lp'ing assetType 4
    // assets and those are ordered after Sushi lp :\

    // 0 = Chainlink direct USD price feed with 8 decimals
    // 1 = Synthetix synth with Chainlink direct USD price feed
    // 2 = Sushi LP tokens
    // 3 = Aave Lending Pool Asset
    // 4 = Lending Enable Asset
    // 5 = Quick LP tokens
    // 6 = _______________
    // 7 - Uniswap V3 NFT Position Asset

    // We support balancer lp's with upto 5 assets :\
    // ie. USDC-LINK-WETH-BAL-AAVE
    address[] memory allBasicErc20s = new address[](supportedAssets.length * 5);
    uint8 hits;

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      address asset = supportedAssets[i].asset;
      uint16 assetType = IHasAssetInfo(IPoolLogic(pool).factory()).getAssetType(asset);
      address[] memory unrolledAssets;

      // if asset == balancer somehow
      bool isBalancer = IBalancerPool(asset).getVault() != address(0);

      if (isBalancer) {
        unrolledAssets = EasySwapperBalancerV2Helpers.unrollBalancerLpAndGetUnsupportedLpAssets(
          IPoolLogic(pool).poolManagerLogic(),
          asset, // BHPT
          address(withdrawalAsset)
        );
      }
      // Sushi V2 lp and Quick V2 lp
      else if (assetType == 2 || assetType == 5) {
        unrolledAssets = EasySwapperV2LpHelpers.unrollLpsAndGetUnsupportedLpAssets(
          IPoolLogic(pool).poolManagerLogic(),
          assetType == 2 ? assetType2Router : assetType5Router,
          asset
        );
      }
      // Uni V3 Lp - already unrolled
      else if (assetType == 7) {
        unrolledAssets = EasySwapperV3Helpers.getUnsupportedV3Assets(IPoolLogic(pool).poolManagerLogic(), asset, pool);
      } else {
        allBasicErc20s[hits] = asset;
        hits++;
      }

      // Push any unrolledAssets into the allBasics array
      for (uint8 y = 0; y < unrolledAssets.length; ++y) {
        if (unrolledAssets[i] != weth && unrolledAssets[i] != withdrawalAsset) {
          allBasicErc20s[hits] = unrolledAssets[i];
          hits++;
        }
      }
    }

    uint256 reduceLength = allBasicErc20s.length.sub(hits);
    assembly {
      mstore(allBasicErc20s, sub(mload(allBasicErc20s), reduceLength))
    }

    for (uint256 i = 0; i < allBasicErc20s.length; i++) {
      IERC20 from = IERC20(allBasicErc20s[i]);
      swapThat(swapRouter, from, withdrawalAsset);
    }

    // Pools that have aave enabled withdraw weth to the user. This isnt in supportedAssets somestimes :(
    swapThat(swapRouter, weth, withdrawalAsset);

    uint256 balanceAfterSwaps = withdrawalAsset.balanceOf(address(this));
    require(balanceAfterSwaps >= expectedAmountOut, "Withdraw Slippage detected");
    withdrawalAsset.safeTransfer(msg.sender, balanceAfterSwaps);
    emit Withdraw(pool, fundTokenAmount, address(withdrawalAsset), balanceAfterSwaps);
  }

  /// @notice Swaps from an asset to the expectedWithdrawalAssetOfUser
  /// @dev get on the floor
  /// @param from asset to swap from
  function swapThat(
    IUniswapV2Router swapRouter,
    IERC20 from,
    IERC20 to
  ) internal {
    if (from == to) {
      return;
    }

    uint256 balance = from.balanceOf(address(this));
    if (balance == 0) {
      return;
    }

    from.approve(address(swapRouter), balance);

    address[] memory path = new address[](2);
    path[0] = address(from);
    path[1] = address(to);

    swapRouter.swapExactTokensForTokens(balance, 0, path, address(this), uint256(-1));
  }
}
