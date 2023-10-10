// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/synthetix/ISynthetix.sol";
import "../../interfaces/synthetix/ISynthAddressProxy.sol";
import "../../interfaces/uniswapV2/IUniswapV2RouterSwapOnly.sol";
import "../../interfaces/uniswapV2/IUniswapV2Router.sol";

library EasySwapperStructs {
  struct WithdrawProps {
    IUniswapV2RouterSwapOnly swapRouter;
    SynthetixProps synthetixProps;
    IERC20Extended weth;
    IERC20Extended nativeAssetWrapper;
  }

  struct SynthetixProps {
    ISynthetix snxProxy;
    IERC20Extended swapSUSDToAsset; // usdc or dai
    ISynthAddressProxy sUSDProxy;
  }
}
