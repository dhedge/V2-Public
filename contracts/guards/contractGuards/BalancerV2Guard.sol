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
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SignedSafeMathUpgradeable.sol";

import "../../utils/TxDataUtils.sol";
import "../../utils/SlippageAccumulator.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/balancer/IBalancerV2Vault.sol";

/// @notice Transaction guard for Balancer V2 Vault
contract BalancerV2Guard is TxDataUtils, IGuard {
  using SignedSafeMathUpgradeable for int256;

  struct SwapData {
    address sender;
    address recipient;
    address srcAsset;
    address dstAsset;
    uint256 srcAmount;
    uint256 dstAmount;
    address to;
  }

  event JoinPool(address fundAddress, bytes32 poolId, address[] assets, uint256[] maxAmountsIn, uint256 time);

  event ExitPool(address fundAddress, bytes32 poolId, address[] assets, uint256[] minAmountsOut, uint256 time);

  SlippageAccumulator private immutable slippageAccumulator;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "Null address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  /// @notice Transaction guard for Balancer V2 Vault
  /// @dev It supports swap functionalities
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
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
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    bytes4 method = getMethod(data);

    if (method == IBalancerV2Vault.swap.selector) {
      (
        IBalancerV2Vault.SingleSwap memory singleSwap,
        IBalancerV2Vault.FundManagement memory funds,
        uint256 limit,

      ) = abi.decode(getParams(data), (IBalancerV2Vault.SingleSwap, IBalancerV2Vault.FundManagement, uint256, uint256));
      if (singleSwap.kind == IBalancerV2Vault.SwapKind.GIVEN_IN) {
        _verifyExchange(
          SwapData(
            funds.sender,
            funds.recipient,
            singleSwap.assetIn,
            singleSwap.assetOut,
            singleSwap.amount,
            limit,
            to
          ),
          poolManagerLogicAssets,
          poolManagerLogic,
          2
        );

        txType = 2; // 'Exchange' type
      } else if (singleSwap.kind == IBalancerV2Vault.SwapKind.GIVEN_OUT) {
        _verifyExchange(
          SwapData(
            funds.sender,
            funds.recipient,
            singleSwap.assetIn,
            singleSwap.assetOut,
            limit,
            singleSwap.amount,
            to
          ),
          poolManagerLogicAssets,
          poolManagerLogic,
          1
        );

        txType = 2; // 'Exchange' type
      }
    } else if (method == IBalancerV2Vault.batchSwap.selector) {
      uint256 swapkind = uint256(getInput(data, 0));
      if (swapkind == uint256(IBalancerV2Vault.SwapKind.GIVEN_IN)) {
        _verifyExchange(
          SwapData(
            convert32toAddress(getInput(data, 3)),
            convert32toAddress(getInput(data, 5)),
            convert32toAddress(getArrayIndex(data, 2, 0)),
            convert32toAddress(getArrayLast(data, 2)),
            uint256(int256(getArrayIndex(data, 7, 0))),
            uint256(int256(0).sub(int256(getArrayLast(data, 7)))),
            to
          ),
          poolManagerLogicAssets,
          poolManagerLogic,
          2
        );

        txType = 2; // 'Exchange' type
      } else if (swapkind == uint256(IBalancerV2Vault.SwapKind.GIVEN_OUT)) {
        _verifyExchange(
          SwapData(
            convert32toAddress(getInput(data, 3)),
            convert32toAddress(getInput(data, 5)),
            convert32toAddress(getArrayIndex(data, 2, 0)),
            convert32toAddress(getArrayLast(data, 2)),
            uint256(int256(getArrayIndex(data, 7, 0))),
            uint256(int256(0).sub(int256(getArrayLast(data, 7)))),
            to
          ),
          poolManagerLogicAssets,
          poolManagerLogic,
          1
        );

        txType = 2; // 'Exchange' type
      }
    } else if (method == IBalancerV2Vault.joinPool.selector) {
      (bytes32 poolId, address sender, address recipient, IBalancerV2Vault.JoinPoolRequest memory joinPoolRequest) = abi
        .decode(getParams(data), (bytes32, address, address, IBalancerV2Vault.JoinPoolRequest));
      address pool = IBalancerV2Vault(to).getPool(poolId);
      address poolLogic = poolManagerLogic.poolLogic();

      require(poolManagerLogicAssets.isSupportedAsset(pool), "unsupported lp asset");
      require(poolLogic == sender && poolLogic == recipient, "sender or recipient is not pool");

      emit JoinPool(poolLogic, poolId, joinPoolRequest.assets, joinPoolRequest.maxAmountsIn, block.timestamp);

      txType = 16; // `Join Pool` type
    } else if (method == IBalancerV2Vault.exitPool.selector) {
      (bytes32 poolId, address sender, address recipient, IBalancerV2Vault.ExitPoolRequest memory exitPoolRequest) = abi
        .decode(getParams(data), (bytes32, address, address, IBalancerV2Vault.ExitPoolRequest));
      address pool = IBalancerV2Vault(to).getPool(poolId);
      address poolLogic = poolManagerLogic.poolLogic();

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

    // Given that there are no return statements above, this tx guard is not used for a public function (callable by anyone).
    // Make sure that it's the `poolLogic` contract of the `poolManagerLogic` which initiates the check on the tx.
    // Else, anyone can increase the slippage impact (updated by the call to SlippageAccumulator).
    // We can trust the poolLogic since it contains check to ensure the caller is authorised.
    require(IPoolManagerLogic(_poolManagerLogic).poolLogic() == msg.sender, "Caller not authorised");

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

  /// @dev Internal function to update cumulative slippage. This is required to avoid stack-too-deep errors.
  /// @param swapData The data used in a swap.
  /// @param poolManagerLogicAssets Contains supported assets mapping.
  /// @param poolManagerLogic The poolManager address.
  /// @param exchangeType Type of exchange (from/to); useful for emitting the correct event.
  function _verifyExchange(
    SwapData memory swapData,
    IHasSupportedAsset poolManagerLogicAssets,
    IPoolManagerLogic poolManagerLogic,
    uint8 exchangeType
  ) internal {
    address poolLogic = poolManagerLogic.poolLogic();
    require(poolManagerLogicAssets.isSupportedAsset(swapData.dstAsset), "unsupported destination asset");

    require(poolLogic == swapData.sender && poolLogic == swapData.recipient, "sender or recipient is not pool");

    slippageAccumulator.updateSlippageImpact(
      SlippageAccumulator.SwapData(
        swapData.srcAsset,
        swapData.dstAsset,
        swapData.srcAmount,
        swapData.dstAmount,
        swapData.to,
        address(poolManagerLogic)
      )
    );

    if (exchangeType == 1) {
      emit ExchangeTo(poolLogic, swapData.srcAsset, swapData.dstAsset, swapData.dstAmount, block.timestamp);
    } else if (exchangeType == 2) {
      emit ExchangeFrom(poolLogic, swapData.srcAsset, swapData.srcAmount, swapData.dstAsset, block.timestamp);
    }
  }
}
