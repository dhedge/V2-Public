// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/IHasAssetInfo.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IPoolFactory.sol";
import "./EasySwapperV3Helpers.sol";
import "./EasySwapperV2LpHelpers.sol";
import "./EasySwapperSwap.sol";
import "./EasySwapperBalancerV2Helpers.sol";
import "./EasySwapperSynthetixHelpers.sol";
import "./EasySwapperVelodromeLPHelpers.sol";

import "./EasySwapperVelodromeCLHelpers.sol";
import "./EasySwapperArrakisHelpers.sol";
import "./EasySwapperStructs.sol";

library EasySwapperWithdrawer {
  using SafeMathUpgradeable for uint160;
  using SafeMathUpgradeable for uint256;

  event Withdraw(
    address pool,
    uint256 fundTokenAmount,
    address withdrawalAsset,
    uint256 amountWithdrawnInWithdrawalAsset
  );

  /// @notice Withdraw underlying value of tokens into intermediate asset and then swap to susd
  /// @dev Helper function for dsnx
  /// @param recipient Who should receive the withdrawAsset
  /// @param pool dhedgepool to withdraw from
  /// @param fundTokenAmount the dhedgepool amount to withdraw
  /// @param intermediateAsset must have direct pair to all pool.supportedAssets on swapRouter and to SUSD
  /// @param finalAsset must have direct pair to withdrawWithIntermediate
  /// @param expectedAmountFinalAsset the amount of value in susd expected (slippage protection)
  /// @param withdrawProps passed down from the storage of the EasySwapper
  function withdrawWithIntermediate(
    address recipient,
    address pool,
    uint256 fundTokenAmount,
    IERC20Extended intermediateAsset,
    IERC20Extended finalAsset,
    uint256 expectedAmountFinalAsset,
    EasySwapperStructs.WithdrawProps memory withdrawProps
  ) internal {
    withdraw(address(this), pool, fundTokenAmount, intermediateAsset, 0, withdrawProps);

    EasySwapperSwap.swapThat(withdrawProps.swapRouter, intermediateAsset, finalAsset);

    uint256 balanceAfterSwaps = finalAsset.balanceOf(address(this));

    require(balanceAfterSwaps >= expectedAmountFinalAsset, "Withdraw Slippage detected");
    require(finalAsset.transfer(recipient, balanceAfterSwaps), "Final asset transfer failed");

    emit Withdraw(pool, fundTokenAmount, address(finalAsset), balanceAfterSwaps);
  }

  /// @notice withdraw underlying value of tokens in expectedWithdrawalAssetOfUser
  /// @dev Swaps the underlying pool withdrawal assets to expectedWithdrawalAssetOfUser
  /// @param recipient Who should receive the withdrawAsset
  /// @param pool dhedgepool to withdraw from
  /// @param fundTokenAmount the dhedgepool amount to withdraw
  /// @param withdrawalAsset must have direct pair to all pool.supportedAssets on swapRouter
  /// @param expectedAmountOut the amount of value in the withdrawalAsset expected (slippage protection)
  /// @param withdrawProps passed down from the storage of the EasySwapper
  function withdraw(
    address recipient,
    address pool,
    uint256 fundTokenAmount,
    IERC20Extended withdrawalAsset,
    uint256 expectedAmountOut,
    EasySwapperStructs.WithdrawProps memory withdrawProps
  ) internal {
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
    // We also must deal with pools that hold dUSD or toros.
    // We also must deal with pools that holder bal-dusd-usdc

    // We support balancer lp's with upto 5 assets :\
    // ie. USDC-LINK-WETH-BAL-AAVE

    address[] memory allBasicErc20s = new address[](supportedAssets.length * 5);
    uint8 hits;

    // Pools that have aave enabled withdraw weth to the user. This isnt in supportedAssets somestimes :(
    if (!IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(address(withdrawProps.weth))) {
      allBasicErc20s[hits] = address(withdrawProps.weth);
      hits++;
    }

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      address asset = supportedAssets[i].asset;
      uint16 assetType = IHasAssetInfo(IPoolLogic(pool).factory()).getAssetType(asset);
      address[] memory unrolledAssets;

      // erc20 + lendingEnabled
      if (assetType == 0 || assetType == 4 || assetType == 22 || assetType == 200) {
        unrolledAssets = erc20Helper(asset, pool, withdrawalAsset, withdrawProps);
      }
      // Synthetix & Synthetix+LendingEnabled
      else if (assetType == 1 || assetType == 14) {
        // Can only withdraw into single Synth if all assets in pool are synths.
        // Can withdraw into non synth asset if mixed pool
        unrolledAssets = EasySwapperSynthetixHelpers.getSynthetixOut(
          asset,
          withdrawalAsset,
          IHasAssetInfo(IPoolLogic(pool).factory()),
          withdrawProps
        );
      }
      // Sushi V2 lp and Quick V2 lp
      else if (assetType == 2 || assetType == 5) {
        unrolledAssets = EasySwapperV2LpHelpers.unrollLpsAndGetUnsupportedLpAssets(asset);
      }
      // solhint-disable-next-line no-empty-blocks
      else if (assetType == 3 || assetType == 8 || assetType == 27) {
        // Aave do nothing
      }
      // Balancer Lp
      else if (assetType == 6) {
        unrolledAssets = EasySwapperBalancerV2Helpers.unrollBalancerLpAndGetUnsupportedLpAssets(
          IPoolLogic(pool).poolManagerLogic(),
          asset,
          address(withdrawalAsset),
          address(withdrawProps.weth)
        );
      }
      // Uni V3 Lp - already unrolled, just need the assets
      else if (assetType == 7) {
        unrolledAssets = EasySwapperV3Helpers.getUnsupportedV3Assets(pool, asset);
      } else if (assetType == 9) {
        unrolledAssets = EasySwapperArrakisHelpers.getArrakisAssets(asset);
      } else if (assetType == 10) {
        unrolledAssets = EasySwapperBalancerV2Helpers.unrollBalancerGaugeAndGetUnsupportedLpAssets(
          IPoolLogic(pool).poolManagerLogic(),
          asset,
          address(withdrawalAsset),
          address(withdrawProps.weth)
        );
        // Velo V1 and Ramses
      } else if (assetType == 15 || assetType == 20) {
        unrolledAssets = EasySwapperVelodromeLPHelpers.unrollLpAndGetUnsupportedLpAssetsAndRewards(
          IPoolLogic(pool).factory(),
          asset,
          false
        );
        // Velo V2
      } else if (assetType == 25) {
        unrolledAssets = EasySwapperVelodromeLPHelpers.unrollLpAndGetUnsupportedLpAssetsAndRewards(
          IPoolLogic(pool).factory(),
          asset,
          true
        );
        // Velodrome CL
      } else if (assetType == 26) {
        unrolledAssets = EasySwapperVelodromeCLHelpers.getUnsupportedCLAssetsAndRewards(pool, asset);
        // Futures
      } else if (assetType == 101 || assetType == 102) {
        // All futures are settled in sUSD
        unrolledAssets = _arr(address(withdrawProps.synthetixProps.sUSDProxy));
      } else {
        revert("assetType not handled");
      }

      for (uint256 y = 0; y < unrolledAssets.length; y++) {
        allBasicErc20s[hits] = unrolledAssets[y];
        hits++;
      }
    }

    uint256 reduceLength = allBasicErc20s.length.sub(hits);
    assembly {
      mstore(allBasicErc20s, sub(mload(allBasicErc20s), reduceLength))
    }

    for (uint256 i = 0; i < allBasicErc20s.length; i++) {
      EasySwapperSwap.swapThat(withdrawProps.swapRouter, IERC20Extended(allBasicErc20s[i]), withdrawalAsset);
    }

    uint256 balanceAfterSwaps = withdrawalAsset.balanceOf(address(this));
    require(balanceAfterSwaps >= expectedAmountOut, "Withdraw Slippage detected");

    if (recipient != address(this)) {
      if (balanceAfterSwaps > 0) {
        require(withdrawalAsset.transfer(recipient, balanceAfterSwaps), "Withdrawal asset transfer failed");
      }
      emit Withdraw(pool, fundTokenAmount, address(withdrawalAsset), balanceAfterSwaps);
    }
  }

  /// @notice Unrolls internal dhedge pools or returns the asset
  /// @dev Because dhedge assets are type 0 we need to check all type 0 to see if it is a pool
  /// @param asset The address of the asset
  /// @param pool The top level dhedge pool being withdrew from
  /// @return unrolledAssets returns nothing when a dhedge pool, returns erc20 address otherwise
  function erc20Helper(
    address asset,
    address pool,
    IERC20Extended withdrawalAsset,
    EasySwapperStructs.WithdrawProps memory withdrawProps
  ) internal returns (address[] memory unrolledAssets) {
    uint256 balance = IPoolLogic(asset).balanceOf(address(this));
    if (balance > 0) {
      if (IPoolFactory(IPoolLogic(pool).factory()).isPool(asset) == true) {
        EasySwapperWithdrawer.withdraw(address(this), address(asset), balance, withdrawalAsset, 0, withdrawProps);
      } else {
        unrolledAssets = _arr(asset);
      }
    }
  }

  function _arr(address a) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = a;
  }
}
