// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ERC20Guard} from "../ERC20Guard.sol";

/// @title HyperliquidERC20Guard
/// @notice ERC20 asset guard for Hyperliquid integrated pools.
/// @dev Must be used for USDC and like-wise assets which need to use Chainlink oracles for pricing on HyperEVM.
/// @dev [!WARNING] This guard must be modified to account for balance of HyperCore in case used for
///      any spot asset other than USDC. For USDC, the balance is accounted for in the HyperliquidPositionGuard.
/// @author dHEDGE DAO
contract HyperliquidERC20Guard is ERC20Guard {
  address private constant _USDC_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

  /// @inheritdoc ERC20Guard
  /// @dev USDC can never be removed once added: it is the payout asset of every Hyperliquid asset guard
  ///      (`OutsidePositionWithdrawalHelper._calculateWithdrawBalance` requires it to be enabled) and the
  ///      denomination `HyperliquidPositionGuard` values the Core account in.
  function removeAssetCheck(address pool, address asset) public view override {
    require(asset != _USDC_ADDRESS, "cannot remove HL core asset");

    super.removeAssetCheck(pool, asset);
  }
}
