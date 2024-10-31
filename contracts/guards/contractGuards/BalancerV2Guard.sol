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
// Copyright (c) 2021 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TxDataUtils} from "../../utils/TxDataUtils.sol";
import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IBalancerV2Vault} from "../../interfaces/balancer/IBalancerV2Vault.sol";

/// @notice Transaction guard for Balancer V2 Vault
contract BalancerV2Guard is TxDataUtils, IGuard {
  event JoinPool(address fundAddress, bytes32 poolId, address[] assets, uint256[] maxAmountsIn, uint256 time);

  event ExitPool(address fundAddress, bytes32 poolId, address[] assets, uint256[] minAmountsOut, uint256 time);

  /// @notice Transaction guard for Balancer V2 Vault
  /// @param poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogic);

    bytes4 method = getMethod(data);

    if (method == IBalancerV2Vault.joinPool.selector) {
      (bytes32 poolId, address sender, address recipient, IBalancerV2Vault.JoinPoolRequest memory joinPoolRequest) = abi
        .decode(getParams(data), (bytes32, address, address, IBalancerV2Vault.JoinPoolRequest));
      address pool = IBalancerV2Vault(to).getPool(poolId);

      require(poolManagerLogicAssets.isSupportedAsset(pool), "unsupported lp asset");
      require(poolLogic == sender && poolLogic == recipient, "sender or recipient is not pool");

      emit JoinPool(poolLogic, poolId, joinPoolRequest.assets, joinPoolRequest.maxAmountsIn, block.timestamp);

      txType = 16; // `Join Pool` type
    } else if (method == IBalancerV2Vault.exitPool.selector) {
      (bytes32 poolId, address sender, address recipient, IBalancerV2Vault.ExitPoolRequest memory exitPoolRequest) = abi
        .decode(getParams(data), (bytes32, address, address, IBalancerV2Vault.ExitPoolRequest));
      address pool = IBalancerV2Vault(to).getPool(poolId);

      address[] memory assetsWithoutLp = _filterLPAsset(exitPoolRequest.assets, pool);
      IBalancerV2Vault.ExitKind kind = abi.decode(exitPoolRequest.userData, (IBalancerV2Vault.ExitKind));
      if (kind == IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT) {
        (, , uint256 tokenIndex) = abi.decode(exitPoolRequest.userData, (IBalancerV2Vault.ExitKind, uint256, uint256));

        require(poolManagerLogicAssets.isSupportedAsset(assetsWithoutLp[tokenIndex]), "unsupported asset");
      } else if (kind == IBalancerV2Vault.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT) {
        uint256 assetLength = assetsWithoutLp.length;
        for (uint256 i = 0; i < assetLength; i++) {
          require(poolManagerLogicAssets.isSupportedAsset(assetsWithoutLp[i]), "unsupported asset");
        }
      } else if (kind == IBalancerV2Vault.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT) {
        (, uint256[] memory amountsOut, ) = abi.decode(
          exitPoolRequest.userData,
          (IBalancerV2Vault.ExitKind, uint256[], uint256)
        );

        uint256 assetLength = assetsWithoutLp.length;
        for (uint256 i = 0; i < assetLength; i++) {
          if (amountsOut[i] > 0) {
            require(poolManagerLogicAssets.isSupportedAsset(assetsWithoutLp[i]), "unsupported asset");
          }
        }
      }

      require(poolManagerLogicAssets.isSupportedAsset(pool), "unsupported lp asset");
      require(poolLogic == sender && poolLogic == recipient, "sender or recipient is not pool");

      emit ExitPool(poolLogic, poolId, exitPoolRequest.assets, exitPoolRequest.minAmountsOut, block.timestamp);

      txType = 17; // `Exit Pool` type
    }

    require(poolLogic == msg.sender, "Caller not authorised");

    return (txType, false);
  }

  /// @dev Composable pools include the lpAsset in the pool but don't count it as apart of the asset array when encoding userData
  /// @param assets all the assets in the pool
  /// @param lpAsset the lpAsset to filter
  /// @return newAssets all the assets in the pool except the lpAsset
  function _filterLPAsset(address[] memory assets, address lpAsset) internal pure returns (address[] memory newAssets) {
    newAssets = new address[](assets.length);
    uint256 hits = 0;

    for (uint256 i = 0; i < assets.length; i++) {
      if (assets[i] != lpAsset) {
        newAssets[hits] = assets[i];
        hits++;
      }
    }
    uint256 reduceLength = newAssets.length - hits;
    assembly {
      mstore(newAssets, sub(mload(newAssets), reduceLength))
    }
  }
}
