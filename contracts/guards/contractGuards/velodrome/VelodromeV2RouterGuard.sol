// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/velodrome/IVelodromeV2Router.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/IHasSupportedAsset.sol";
import "../../../interfaces/ITransactionTypes.sol";

contract VelodromeV2RouterGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Transaction guard for Velodrome V2 Router
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
  ) external view override returns (uint16 txType, bool) {
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);
    address defaultFactory = IVelodromeV2Router(_to).defaultFactory();

    if (method == IVelodromeV2Router.addLiquidity.selector) {
      (address tokenA, address tokenB, bool stable, , , , , address recipient, ) = abi.decode(
        params,
        (address, address, bool, uint256, uint256, uint256, uint256, address, uint256)
      );

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IVelodromeV2Router(_to).poolFor(tokenA, tokenB, stable, defaultFactory);

      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");
      require(poolManagerLogic.poolLogic() == recipient, "recipient is not pool");

      txType = uint16(TransactionType.AddLiquidity);
    } else if (method == IVelodromeV2Router.removeLiquidity.selector) {
      (address tokenA, address tokenB, bool stable, , , , address recipient, ) = abi.decode(
        params,
        (address, address, bool, uint256, uint256, uint256, address, uint256)
      );

      require(poolManagerLogicAssets.isSupportedAsset(tokenA), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(tokenB), "unsupported asset: tokenB");

      address pair = IVelodromeV2Router(_to).poolFor(tokenA, tokenB, stable, defaultFactory);

      require(poolManagerLogicAssets.isSupportedAsset(pair), "unsupported lp asset");
      require(poolManagerLogic.poolLogic() == recipient, "recipient is not pool");

      txType = uint16(TransactionType.RemoveLiquidity);
    }

    return (txType, false);
  }
}
