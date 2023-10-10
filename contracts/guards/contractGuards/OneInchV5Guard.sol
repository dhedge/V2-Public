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
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../utils/TxDataUtils.sol";
import "../../utils/SlippageAccumulator.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/uniswapV2/IUniswapV2Pair.sol";
import "../../interfaces/uniswapV3/IUniswapV3Pool.sol";
import "../../interfaces/oneInch/IAggregationRouterV5.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";

/// @notice Transaction guard for OneInchV5Router
contract OneInchV5Guard is TxDataUtils, IGuard {
  struct SwapData {
    address srcAsset;
    address dstAsset;
    uint256 srcAmount;
    uint256 dstAmount;
    address to;
  }

  uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255;

  SlippageAccumulator private immutable slippageAccumulator;

  constructor(address _slippageAccumulator) {
    require(_slippageAccumulator != address(0), "Null address");

    slippageAccumulator = SlippageAccumulator(_slippageAccumulator);
  }

  /// @notice Transaction guard for OneInchV5
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

    if (method == IAggregationRouterV5.swap.selector) {
      (, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, ) = abi.decode(
        getParams(data),
        (address, IAggregationRouterV5.SwapDescription, bytes, bytes)
      );

      require(permit.length == 0, "swap without permit");

      _verifyExchange(
        SwapData(desc.srcToken, desc.dstToken, desc.amount, desc.minReturnAmount, to),
        poolManagerLogicAssets,
        poolManagerLogic
      );

      require(poolManagerLogic.poolLogic() == desc.dstReceiver, "recipient is not pool");

      txType = 2; // 'Exchange' type
    } else if (method == IAggregationRouterV5.unoswap.selector) {
      (address srcAsset, uint256 srcAmount, uint256 amountOutMin, bytes32[] memory pools) = abi.decode(
        getParams(data),
        (address, uint256, uint256, bytes32[])
      );

      address dstAsset = srcAsset;
      for (uint8 i = 0; i < pools.length; i++) {
        address pool = convert32toAddress(pools[i]);
        address token0 = IUniswapV2Pair(pool).token0();
        address token1 = IUniswapV2Pair(pool).token1();
        if (dstAsset == token0) {
          dstAsset = token1;
        } else if (dstAsset == token1) {
          dstAsset = token0;
        } else {
          require(false, "invalid path");
        }
      }

      _verifyExchange(
        SwapData(srcAsset, dstAsset, srcAmount, amountOutMin, to),
        poolManagerLogicAssets,
        poolManagerLogic
      );

      txType = 2; // 'Exchange' type
    } else if (method == IAggregationRouterV5.uniswapV3Swap.selector) {
      (uint256 srcAmount, uint256 amountOutMin, uint256[] memory pools) = abi.decode(
        getParams(data),
        (uint256, uint256, uint256[])
      );

      address srcAsset = (pools[0] & _ONE_FOR_ZERO_MASK == 0)
        ? IUniswapV3Pool(pools[0]).token0()
        : IUniswapV3Pool(pools[0]).token1();
      address dstAsset = srcAsset;
      for (uint8 i = 0; i < pools.length; i++) {
        address token0 = IUniswapV3Pool(pools[i]).token0();
        address token1 = IUniswapV3Pool(pools[i]).token1();
        if (dstAsset == token0) {
          dstAsset = token1;
        } else if (dstAsset == token1) {
          dstAsset = token0;
        } else {
          require(false, "invalid path");
        }
      }

      _verifyExchange(
        SwapData(srcAsset, dstAsset, srcAmount, amountOutMin, to),
        poolManagerLogicAssets,
        poolManagerLogic
      );

      txType = 2; // 'Exchange' type
    } else if (method == IAggregationRouterV5.uniswapV3SwapTo.selector) {
      uint256 srcAmount;
      uint256 amountOutMin;
      address srcAsset;
      address dstAsset;

      {
        address toAddress;
        uint256[] memory pools;

        (toAddress, srcAmount, amountOutMin, pools) = abi.decode(
          getParams(data),
          (address, uint256, uint256, uint256[])
        );

        srcAsset = (pools[0] & _ONE_FOR_ZERO_MASK == 0)
          ? IUniswapV3Pool(pools[0]).token0()
          : IUniswapV3Pool(pools[0]).token1();
        dstAsset = srcAsset;
        for (uint8 i = 0; i < pools.length; i++) {
          address token0 = IUniswapV3Pool(pools[i]).token0();
          address token1 = IUniswapV3Pool(pools[i]).token1();
          if (dstAsset == token0) {
            dstAsset = token1;
          } else if (dstAsset == token1) {
            dstAsset = token0;
          } else {
            require(false, "invalid path");
          }
        }

        require(poolManagerLogic.poolLogic() == toAddress, "recipient is not pool");
      }

      _verifyExchange(
        SwapData(srcAsset, dstAsset, srcAmount, amountOutMin, to),
        poolManagerLogicAssets,
        poolManagerLogic
      );

      txType = 2; // 'Exchange' type
    }

    // Given that there are no return statements above, this tx guard is not used for a public function (callable by anyone).
    // Make sure that it's the `poolLogic` contract of the `poolManagerLogic` which initiates the check on the tx.
    // Else, anyone can increase the slippage impact (updated by the call to SlippageAccumulator).
    // We can trust the poolLogic since it contains check to ensure the caller is authorised.
    require(IPoolManagerLogic(_poolManagerLogic).poolLogic() == msg.sender, "Caller not authorised");

    return (txType, false);
  }

  /// @dev Internal function to update cumulative slippage. This is required to avoid stack-too-deep errors.
  /// @param swapData The data used in a swap.
  /// @param poolManagerLogicAssets Contains supported assets mapping.
  /// @param poolManagerLogic The poolManager address.
  function _verifyExchange(
    SwapData memory swapData,
    IHasSupportedAsset poolManagerLogicAssets,
    IPoolManagerLogic poolManagerLogic
  ) internal {
    require(poolManagerLogicAssets.isSupportedAsset(swapData.dstAsset), "unsupported destination asset");

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

    emit ExchangeFrom(
      poolManagerLogic.poolLogic(),
      swapData.srcAsset,
      swapData.srcAmount,
      swapData.dstAsset,
      block.timestamp
    );
  }
}
