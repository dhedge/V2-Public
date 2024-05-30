// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IVelodromeCLGauge} from "../../../interfaces/velodrome/IVelodromeCLGauge.sol";
import {IVelodromeNonfungiblePositionManager} from "../../../interfaces/velodrome/IVelodromeNonfungiblePositionManager.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {VelodromeCLPriceLibrary} from "../../../utils/velodrome/VelodromeCLPriceLibrary.sol";
import {AerodromeCLGaugeContractGuard} from "./AerodromeCLGaugeContractGuard.sol";

/// @title Transaction guard for Velodrome CL Gauge contract
contract VelodromeCLGaugeContractGuard is AerodromeCLGaugeContractGuard {
  /// @notice Transaction guard for Velodrome CL Gauge
  /// @dev It supports depositing, withdrawing, increaseStakedLiquidity, decreaseStakedLiquidity and claiming rewards
  /// @param poolManagerLogic the pool manager logic
  /// @param to the gauge address
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) public override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");
    IVelodromeCLGauge velodromeCLGauge = IVelodromeCLGauge(to);
    address nonfungiblePositionManager = velodromeCLGauge.nft();
    address nonfungiblePositionManagerGuard = IHasGuardInfo(IPoolLogic(poolLogic).factory()).getContractGuard(
      nonfungiblePositionManager
    );

    bytes4 method = getMethod(data);
    bytes memory params = getParams(data);

    if (method == IVelodromeCLGauge.increaseStakedLiquidity.selector) {
      uint256 tokenId = abi.decode(params, (uint256));
      super._validateTokenId(nonfungiblePositionManagerGuard, tokenId, poolLogic);

      (, , address tokenA, address tokenB, int24 tickSpacing, , , , , , , ) = IVelodromeNonfungiblePositionManager(
        nonfungiblePositionManager
      ).positions(tokenId);
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokenB), "unsupported asset: tokenB");

      VelodromeCLPriceLibrary.assertFairPrice(
        IPoolLogic(poolLogic).factory(),
        IVelodromeNonfungiblePositionManager(nonfungiblePositionManager).factory(),
        tokenA,
        tokenB,
        tickSpacing
      );

      txType = uint16(TransactionType.VelodromeCLIncreaseLiquidity);
    } else if (method == IVelodromeCLGauge.decreaseStakedLiquidity.selector) {
      uint256 tokenId = abi.decode(params, (uint256));
      super._validateTokenId(nonfungiblePositionManagerGuard, tokenId, poolLogic);

      (, , address tokenA, address tokenB, , , , , , , , ) = IVelodromeNonfungiblePositionManager(
        nonfungiblePositionManager
      ).positions(tokenId);
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokenB), "unsupported asset: tokenB");

      txType = uint16(TransactionType.VelodromeCLDecreaseLiquidity);
    } else {
      (txType, ) = super.txGuard(poolManagerLogic, to, data);
    }

    return (txType, false);
  }
}
