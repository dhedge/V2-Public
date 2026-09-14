// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ERC20Guard} from "../ERC20Guard.sol";

import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IHyperliquidCoreWriterContractGuard} from "../../../interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";

/// @title HyperliquidERC20Guard
/// @notice ERC20 asset guard for Hyperliquid integrated pools.
/// @dev Must be used for USDC and like-wise assets which need to use Chainlink oracles for pricing on HyperEVM.
/// @dev [!WARNING] This guard must be modified to account for balance of HyperCore in case used for
///      any spot asset other than USDC. For USDC, the balance is accounted for in the HyperliquidPositionGuard.
/// @author dHEDGE DAO
contract HyperliquidERC20Guard is ERC20Guard {
  address private constant _CORE_WRITER = 0x3333333333333333333333333333333333333333;
  address private constant _USDC_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

  /// @inheritdoc ERC20Guard
  /// @dev Checks if a corewriter action related to any spot asset has been done before allowing the asset to be removed from the pool.
  /// @dev Also blocks removing USDC while the vault still holds the CoreWriter asset. USDC is the payout
  ///      asset of every Hyperliquid asset guard — `OutsidePositionWithdrawalHelper._calculateWithdrawBalance`
  ///      requires it to be enabled — and the denomination `HyperliquidPositionGuard` values the Core spot
  ///      balance in. Note `getBalance` here is the EVM balance only (Core USDC is valued by the position
  ///      guard), so the inherited empty-balance check does NOT stop a removal while the vault holds Core
  ///      USDC or perp equity. Without this, a manager could remove USDC and make EVERY withdrawal revert
  ///      with "withdrawal asset not enabled", stranding depositors until it is re-added.
  function removeAssetCheck(address pool, address asset) public view override {
    IHyperliquidCoreWriterContractGuard contractGuard = _useContractGuard(IPoolLogic(pool).factory());

    super.removeAssetCheck(pool, asset);
    require(!contractGuard.hasPerformedSpotAction(pool), "spot asset action performed");

    if (asset == _USDC_ADDRESS) {
      require(
        !IHasSupportedAsset(IPoolLogic(pool).poolManagerLogic()).isSupportedAsset(_CORE_WRITER),
        "USDC required for HL"
      );
    }
  }

  function _useContractGuard(
    address _poolFactory
  ) internal view returns (IHyperliquidCoreWriterContractGuard contractguard) {
    contractguard = IHyperliquidCoreWriterContractGuard(IHasGuardInfo(_poolFactory).getContractGuard(_CORE_WRITER));
  }
}
