// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "../guards/assetGuards/LyraOptionMarketWrapperAssetGuard.sol";
import "../guards/contractGuards/LyraOptionMarketWrapperContractGuard.sol";

import "../interfaces/IERC20Extended.sol";
import "../interfaces/IHasAssetInfo.sol";
import "../interfaces/synthetix/ISynthAddressProxy.sol";
import "../interfaces/lyra/IOptionMarketViewer.sol";
import "../interfaces/IPoolLogic.sol";
import "../interfaces/IHasSupportedAsset.sol";

import "./EasySwapperSwap.sol";
import "./EasySwapperStructs.sol";
import "./EasySwapperSynthetixHelpers.sol";

library EasySwapperSynthetixHelpers {
  /// @notice Determines which assets the swapper will have received when withdrawing from the pool
  /// @dev The pool unrolls lyra assets into the underlying assets and transfers them directly to the withdrawer, we need to know which assets the swapper received
  /// @param lyraOptionMarketWrapper the address of the lyra option market wrapper contract
  /// @param poolLogic used to determine if a rewardds token would have been received
  function getLyraWithdrawAssets(
    address lyraOptionMarketWrapper,
    address poolLogic,
    IERC20Extended withdrawalAsset,
    EasySwapperStructs.WithdrawProps memory withdrawProps
  ) internal returns (address[] memory assets) {
    address poolFactory = IPoolLogic(poolLogic).factory();
    IOptionMarketViewer marketViewer = LyraOptionMarketWrapperAssetGuard(
      IHasGuardInfo(poolFactory).getAssetGuard(lyraOptionMarketWrapper) // lyraAssetGuard
    ).marketViewer();
    LyraOptionMarketWrapperContractGuard.OptionPosition[] memory positions = LyraOptionMarketWrapperContractGuard(
      IHasGuardInfo(poolFactory).getContractGuard(lyraOptionMarketWrapper) // lyraContractGuard
    ).getOptionPositions(poolLogic);

    assets = new address[](positions.length * 2);
    uint256 hits = 0;

    for (uint256 i = 0; i < positions.length; i++) {
      IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer.marketAddresses(
        positions[i].optionMarket
      );

      address[] memory assetOutQuote = EasySwapperSynthetixHelpers.getSynthetixOut(
        address(optionMarketAddresses.quoteAsset),
        withdrawalAsset,
        IHasAssetInfo(poolFactory),
        withdrawProps
      );
      if (assetOutQuote.length > 0) {
        assets[hits] = address(assetOutQuote[0]);
        hits++;
      }
      address[] memory assetOutBase = EasySwapperSynthetixHelpers.getSynthetixOut(
        address(optionMarketAddresses.baseAsset),
        withdrawalAsset,
        IHasAssetInfo(poolFactory),
        withdrawProps
      );
      if (assetOutBase.length > 0) {
        assets[hits] = address(assetOutBase[0]);
        hits++;
      }
    }

    uint256 reduceLength = assets.length - hits;
    assembly {
      mstore(assets, sub(mload(assets), reduceLength))
    }
  }

  /// @notice The logic for swapping synths to the withdrawalAsset
  /// @dev If withdrawing to a synth swap to it using Synthetix swap, otherwise swap to sUSD and then swap to withdrawalAsset
  /// @param synthAsset the address of the synth
  /// @param withdrawalAsset The withrawers expected out asset
  /// @return assets the intermidiary asset that the synth is exchanged to, that needs to be swapped upstream
  function getSynthetixOut(
    address synthAsset,
    IERC20Extended withdrawalAsset,
    IHasAssetInfo poolFactory,
    EasySwapperStructs.WithdrawProps memory withdrawProps
  ) internal returns (address[] memory assets) {
    uint256 balance = IERC20Extended(synthAsset).balanceOf(address(this));
    if (balance > 0) {
      // If withdrawalAsset is synth asset
      // We swap directly to the withdrawalAsset
      uint256 assetType = poolFactory.getAssetType(address(withdrawalAsset));
      if (assetType == 1 || assetType == 14) {
        if (synthAsset != address(withdrawalAsset)) {
          withdrawProps.synthetixProps.snxProxy.exchange(
            ISynthAddressProxy(synthAsset).target().currencyKey(),
            balance,
            ISynthAddressProxy(address(withdrawalAsset)).target().currencyKey()
          );
        }
        // Otherwise we swap first to sUSD (has most liquidity)
        // Then swap to the swapSUSDToAsset which shoudl be configured to an
        // asset that has good liquidity
      } else {
        if (address(withdrawProps.synthetixProps.sUSDProxy) != synthAsset) {
          withdrawProps.synthetixProps.snxProxy.exchange(
            ISynthAddressProxy(synthAsset).target().currencyKey(),
            balance,
            withdrawProps.synthetixProps.sUSDProxy.target().currencyKey()
          );
        }
        EasySwapperSwap.swapThat(
          withdrawProps.swapRouter,
          IERC20Extended(address(withdrawProps.synthetixProps.sUSDProxy)),
          withdrawProps.synthetixProps.swapSUSDToAsset
        );
        assets = new address[](1);
        assets[0] = address(withdrawProps.synthetixProps.swapSUSDToAsset);
      }
    }
  }
}
