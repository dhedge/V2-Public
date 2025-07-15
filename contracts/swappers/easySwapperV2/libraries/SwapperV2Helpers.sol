// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeERC20} from "../../../utils/SafeERC20.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

import {SynthetixPerpsV2MarketAssetGuard} from "../../../guards/assetGuards/SynthetixPerpsV2MarketAssetGuard.sol";
import {PancakeNonfungiblePositionGuard} from "../../../guards/contractGuards/pancake/PancakeNonfungiblePositionGuard.sol";
import {ICompoundV3Comet} from "../../../interfaces/compound/ICompoundV3Comet.sol";
import {IPancakeNonfungiblePositionManager} from "../../../interfaces/pancake/IPancakeNonfungiblePositionManager.sol";
import {IPActionMiscV3} from "../../../interfaces/pendle/IPActionMiscV3.sol";
import {IPPrincipalToken} from "../../../interfaces/pendle/IPPrincipalToken.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IFToken} from "../../../interfaces/fluid/IFToken.sol";
import {IEasySwapperV2} from "../interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "../interfaces/IWithdrawalVault.sol";
import {PendlePTHandlerLib} from "../../../utils/pendle/PendlePTHandlerLib.sol";

import "../../../interfaces/pendle/IPAllActionTypeV3.sol" as IPAllActionTypeV3;

library SwapperV2Helpers {
  using SafeERC20 for IERC20;

  function synthetixPerpsV2Helper(address _asset, address _poolFactory) internal view returns (address sUSDAddress) {
    sUSDAddress = SynthetixPerpsV2MarketAssetGuard(IHasGuardInfo(_poolFactory).getAssetGuard(_asset)).susdProxy();
  }

  function getUnrolledAssets(address _asset, address _dHedgeVault) internal view returns (address[] memory assets) {
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = IEasySwapperV2(_asset).getTrackedAssets(_dHedgeVault);
    uint256 assetsLength = trackedAssets.length;
    assets = new address[](assetsLength);

    for (uint256 i; i < assetsLength; ++i) {
      assets[i] = trackedAssets[i].token;
    }
  }

  /// @dev It's possible to disable base token of CompoundV3Comet asset, while having positive balance of it,
  ///      hence this helper is required for WithdrawalVault to pick base token after withdrawing from CompoundV3Comet asset
  function getCompoundV3BaseAsset(address _compoundV3CometAsset) internal view returns (address baseAsset) {
    baseAsset = ICompoundV3Comet(_compoundV3CometAsset).baseToken();
  }

  function getPancakeCLPositionAssets(
    address _pool,
    address _pancakenNftPositionManager
  ) internal view returns (address[] memory assets) {
    uint256[] memory tokenIds = PancakeNonfungiblePositionGuard(
      IHasGuardInfo(IPoolLogic(_pool).factory()).getContractGuard(_pancakenNftPositionManager)
    ).getOwnedTokenIds(_pool);

    assets = new address[](tokenIds.length * 2);

    for (uint256 i; i < tokenIds.length; ++i) {
      (, , address token0, address token1, , , , , , , , ) = IPancakeNonfungiblePositionManager(
        _pancakenNftPositionManager
      ).positions(tokenIds[i]);

      assets[i * 2] = token0;
      assets[i * 2 + 1] = token1;
    }
  }

  function getFluidTokenUnderlying(address _fToken) internal view returns (address underlying) {
    underlying = IFToken(_fToken).asset();
  }

  function unrollPendlePT(address _pool, address _principalToken) internal returns (address underlying) {
    uint256 ptBalance = IPPrincipalToken(_principalToken).balanceOf(address(this));

    if (ptBalance == 0) return underlying;

    address market;
    // Worst case scenario is revert down here if the asset guard does not contain necessary data
    (market, underlying) = PendlePTHandlerLib.getPTAssociatedData(_principalToken, _pool);

    bool expired = IPPrincipalToken(_principalToken).isExpired();

    IERC20(_principalToken).safeIncreaseAllowance(PendlePTHandlerLib.ROUTER_V4, ptBalance);

    // If exiting to underlying token, slippage check is not required, hence passing 0 as minTokenOut both times
    // See source code to prove tha above:
    // ActionMiscV3::exitPostExpToToken https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/router/ActionMiscV3.sol#L302
    // ActionMiscV3::exitPreExpToToken https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/router/ActionMiscV3.sol#L221
    if (expired) {
      IPActionMiscV3(PendlePTHandlerLib.ROUTER_V4).exitPostExpToToken(
        address(this),
        market,
        ptBalance,
        0,
        IPAllActionTypeV3.createTokenOutputSimple(underlying, 0)
      );
    } else {
      IPActionMiscV3(PendlePTHandlerLib.ROUTER_V4).exitPreExpToToken(
        address(this),
        market,
        ptBalance,
        0,
        0,
        IPAllActionTypeV3.createTokenOutputSimple(underlying, 0),
        IPAllActionTypeV3.createEmptyLimitOrderData()
      );
    }
  }
}
