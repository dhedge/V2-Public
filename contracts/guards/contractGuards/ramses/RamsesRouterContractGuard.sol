// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/ramses/IRamsesRouter.sol";
import "../../../interfaces/velodrome/IVelodromeRouter.sol";
import "../../../interfaces/IHasSupportedAsset.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";

contract RamsesRouterContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Transaction guard for Ramses Router
  /// @dev It supports addLiquidity and removeLiquidity functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param _to the router address
  /// @param _data the transaction data
  /// @return txType the transaction type of a given transaction data
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes calldata _data
  ) external override returns (uint16 txType, bool) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == IVelodromeRouter.addLiquidity.selector) {
      (address tokenA, address tokenB, bool stable, , , , , address to) = abi.decode(
        params,
        (address, address, bool, uint256, uint256, uint256, uint256, address)
      );

      require(poolLogic == to, "recipient is not pool");
      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IRamsesRouter(_to).pairFor(tokenA, tokenB, stable);

      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      emit AddLiquidity(poolLogic, pair, params, block.timestamp);

      txType = uint16(TransactionType.AddLiquidity);
    } else if (method == IVelodromeRouter.removeLiquidity.selector) {
      (address tokenA, address tokenB, bool stable, , , , address to) = abi.decode(
        params,
        (address, address, bool, uint256, uint256, uint256, address)
      );

      require(poolLogic == to, "recipient is not pool");
      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IRamsesRouter(_to).pairFor(tokenA, tokenB, stable);

      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");

      emit RemoveLiquidity(poolLogic, pair, params, block.timestamp);

      txType = uint16(TransactionType.RemoveLiquidity);
    }

    return (txType, false);
  }
}
