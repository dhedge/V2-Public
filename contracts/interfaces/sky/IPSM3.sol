// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.6;

interface IPSM3 {
  /**********************************************************************************************/
  /*** Swap functions                                                                         ***/
  /**********************************************************************************************/

  /**
   *  @dev    Swaps a specified amount of assetIn for assetOut in the PSM. The amount swapped is
   *          converted based on the current value of the two assets used in the swap. This
   *          function will revert if there is not enough balance in the PSM to facilitate the
   *          swap. Both assets must be supported in the PSM in order to succeed.
   *  @param  assetIn      Address of the ERC-20 asset to swap in.
   *  @param  assetOut     Address of the ERC-20 asset to swap out.
   *  @param  amountIn     Amount of the asset to swap in.
   *  @param  minAmountOut Minimum amount of the asset to receive.
   *  @param  receiver     Address of the receiver of the swapped assets.
   *  @param  referralCode Referral code for the swap.
   *  @return amountOut    Resulting amount of the asset that will be received in the swap.
   */
  function swapExactIn(
    address assetIn,
    address assetOut,
    uint256 amountIn,
    uint256 minAmountOut,
    address receiver,
    uint256 referralCode
  ) external returns (uint256 amountOut);

  /**
   *  @dev    Swaps a derived amount of assetIn for a specific amount of assetOut in the PSM. The
   *          amount swapped is converted based on the current value of the two assets used in
   *          the swap. This function will revert if there is not enough balance in the PSM to
   *          facilitate the swap. Both assets must be supported in the PSM in order to succeed.
   *  @param  assetIn      Address of the ERC-20 asset to swap in.
   *  @param  assetOut     Address of the ERC-20 asset to swap out.
   *  @param  amountOut    Amount of the asset to receive from the swap.
   *  @param  maxAmountIn  Max amount of the asset to use for the swap.
   *  @param  receiver     Address of the receiver of the swapped assets.
   *  @param  referralCode Referral code for the swap.
   *  @return amountIn     Resulting amount of the asset swapped in.
   */
  function swapExactOut(
    address assetIn,
    address assetOut,
    uint256 amountOut,
    uint256 maxAmountIn,
    address receiver,
    uint256 referralCode
  ) external returns (uint256 amountIn);

  /**********************************************************************************************/
  /*** Liquidity provision functions                                                          ***/
  /**********************************************************************************************/

  /**
   *  @dev    Deposits an amount of a given asset into the PSM. Must be one of the supported
   *          assets in order to succeed. The amount deposited is converted to shares based on
   *          the current exchange rate.
   *  @param  asset           Address of the ERC-20 asset to deposit.
   *  @param  receiver        Address of the receiver of the resulting shares from the deposit.
   *  @param  assetsToDeposit Amount of the asset to deposit into the PSM.
   *  @return newShares       Number of shares minted to the user.
   */
  function deposit(address asset, address receiver, uint256 assetsToDeposit) external returns (uint256 newShares);

  /**
   *  @dev    Withdraws an amount of a given asset from the PSM up to `maxAssetsToWithdraw`.
   *          Must be one of the supported assets in order to succeed. The amount withdrawn is
   *          the minimum of the balance of the PSM, the max amount, and the max amount of assets
   *          that the user's shares can be converted to.
   *  @param  asset               Address of the ERC-20 asset to withdraw.
   *  @param  receiver            Address of the receiver of the withdrawn assets.
   *  @param  maxAssetsToWithdraw Max amount that the user is willing to withdraw.
   *  @return assetsWithdrawn     Resulting amount of the asset withdrawn from the PSM.
   */
  function withdraw(
    address asset,
    address receiver,
    uint256 maxAssetsToWithdraw
  ) external returns (uint256 assetsWithdrawn);
}
