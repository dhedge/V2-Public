//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/stargate/IStargateRouter.sol";
import "../../interfaces/stargate/IStargateFactory.sol";
import "../../interfaces/stargate/IStargatePool.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";

/// @title Transaction guard for the Stargate router
contract StargateRouterContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  using SafeMathUpgradeable for uint256;

  /// @notice Transaction guard for the Stargate router
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    view
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    IStargateFactory stargateFactory = IStargateFactory(IStargateRouter(to).factory());

    if (method == IStargateRouter.addLiquidity.selector) {
      (uint256 poolId, , address mintTo) = abi.decode(getParams(data), (uint256, uint256, address));

      IStargatePool stargatePool = IStargatePool(stargateFactory.getPool(poolId));

      require(poolManagerLogicAssets.isSupportedAsset(address(stargatePool)), "stargate pool not enabled");
      require(mintTo == poolLogic, "recipient is not pool");

      txType = uint16(TransactionType.AddLiquiditySingle);
    } else if (method == IStargateRouter.instantRedeemLocal.selector) {
      (uint256 poolId, , address withdrawTo) = abi.decode(getParams(data), (uint256, uint256, address));

      IStargatePool stargatePool = IStargatePool(stargateFactory.getPool(poolId));
      address underlyingAsset = stargatePool.token();

      require(poolManagerLogicAssets.isSupportedAsset(underlyingAsset), "underlying asset not enabled");
      require(withdrawTo == poolLogic, "recipient is not pool");

      txType = uint16(TransactionType.RemoveLiquiditySingle);
    }

    return (txType, false);
  }
}
