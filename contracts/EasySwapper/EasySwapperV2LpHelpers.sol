// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/IHasSupportedAsset.sol";
import "../interfaces/uniswapv2/IUniswapV2Pair.sol";

library EasySwapperV2LpHelpers {
  using SafeMathUpgradeable for uint256;

  /// @notice Unrolls univ2 compatible LP to the underlying assets
  /// @dev Returns the underlying asset addresses so that can be swapped upstream
  /// @param lpAddress The address of the lp asset
  /// @return assets the assets in the v2 lp, that need to be swapped upstream
  function unrollLpsAndGetUnsupportedLpAssets(address lpAddress) internal returns (address[] memory assets) {
    uint256 bal = IERC20Extended(lpAddress).balanceOf(address(this));
    if (bal > 0) {
      address token0 = IUniswapV2Pair(lpAddress).token0();
      address token1 = IUniswapV2Pair(lpAddress).token1();
      IERC20Extended(lpAddress).transfer(lpAddress, bal);
      IUniswapV2Pair(lpAddress).burn(address(this));

      assets = new address[](2);
      assets[0] = token0;
      assets[1] = token1;
    }
  }
}
