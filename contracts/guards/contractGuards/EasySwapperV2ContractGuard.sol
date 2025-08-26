//
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
// Copyright (c) 2024 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {ISwapper} from "../../interfaces/flatMoney/swapper/ISwapper.sol";
import {ISwapDataConsumingGuard} from "../../interfaces/guards/ISwapDataConsumingGuard.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {IEasySwapperV2} from "../../swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "../../swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {EasySwapperV2} from "../../swappers/easySwapperV2/EasySwapperV2.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

contract EasySwapperV2ContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  using SafeMath for uint256;

  uint256 private immutable _swapSlippageTolerance;

  uint256 private immutable _swapSlippageToleranceDenominator;

  constructor(
    address _slippageAccumulator,
    uint256 _slippageTolerance,
    uint256 _slippageToleranceDenominator
  ) SlippageAccumulatorUser(_slippageAccumulator) {
    require(_slippageToleranceDenominator >= _slippageTolerance, "invalid tolerance");

    _swapSlippageTolerance = _slippageTolerance;
    _swapSlippageToleranceDenominator = _slippageToleranceDenominator;
  }

  /// @notice Used for managers trading dHEDGE Vaults inside dHEDGE Vaults (e.g. trading Toros leveraged tokens)
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to EasySwapperV2 address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == EasySwapperV2.zapDepositWithCustomCooldown.selector) {
      (address dHedgeVault, EasySwapperV2.SingleInSingleOutData memory swapData) = abi.decode(
        getParams(_data),
        (address, EasySwapperV2.SingleInSingleOutData)
      );

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dHedgeVault), "unsupported destination asset");

      IHasAssetInfo poolFactory = IHasAssetInfo(IPoolLogic(poolLogic).factory());

      // Validation step to ensure addresses in swap data are valid assets dHEDGE supports
      require(
        poolFactory.isValidAsset(address(swapData.srcData.token)) &&
          poolFactory.isValidAsset(address(swapData.destData.destToken)),
        "invalid swap assets"
      );

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: address(swapData.srcData.token),
        dstAsset: dHedgeVault,
        srcAmount: _getBalance(address(swapData.srcData.token), poolLogic),
        dstAmount: _getBalance(dHedgeVault, poolLogic)
      });

      txType = uint16(TransactionType.EasySwapperV2Deposit);
    } else if (method == EasySwapperV2.depositWithCustomCooldown.selector) {
      (address dHedgeVault, address vaultDepositToken) = abi.decode(getParams(_data), (address, address));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dHedgeVault), "unsupported destination asset");

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: vaultDepositToken,
        dstAsset: dHedgeVault,
        srcAmount: _getBalance(vaultDepositToken, poolLogic),
        dstAmount: _getBalance(dHedgeVault, poolLogic)
      });

      txType = uint16(TransactionType.EasySwapperV2Deposit);
    }
    // To use EasySwapperV2 withdraw functions, manager must enable an "asset" which is designed to track tokens which are located
    // in the pool's withdrawal vault after `initWithdrawal` is executed. This "asset" is EasySwapperV2 address itself.
    else if (method == EasySwapperV2.initWithdrawal.selector) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "unsupported destination asset");

      (, , IPoolLogic.ComplexAsset[] memory complexAssetsData) = abi.decode(
        getParams(_data),
        (address, uint256, IPoolLogic.ComplexAsset[])
      );

      for (uint256 i; i < complexAssetsData.length; ++i) {
        // Simple hard stop to prevent managers from setting slippage tolerance for withdrawing from aave positions too high
        require(
          complexAssetsData[i].slippageTolerance <= _swapSlippageTolerance &&
            complexAssetsData[i].slippageTolerance != 0,
          "beyond allowed slippage"
        );

        // If length is 0, it won't be picked up at PoolLogic. If non empty data provided for different than aave position asset, tx will revert
        if (complexAssetsData[i].withdrawData.length > 0) {
          ISwapDataConsumingGuard.ComplexAssetSwapData memory swapData = abi.decode(
            complexAssetsData[i].withdrawData,
            (ISwapDataConsumingGuard.ComplexAssetSwapData)
          );

          // Must equal to slippage tolerance set in ComplexAsset
          require(swapData.slippageTolerance == complexAssetsData[i].slippageTolerance, "slippage tolerance mismatch");

          IHasAssetInfo poolFactory = IHasAssetInfo(IPoolLogic(poolLogic).factory());

          require(poolFactory.isValidAsset(address(swapData.destData.destToken)), "invalid dst asset");

          ISwapper.SrcTokenSwapDetails[] memory srcData = abi.decode(
            swapData.srcData,
            (ISwapper.SrcTokenSwapDetails[])
          );

          for (uint256 j; j < srcData.length; ++j) {
            require(poolFactory.isValidAsset(address(srcData[j].token)), "invalid src asset");
          }
        }
      }

      txType = uint16(TransactionType.EasySwapperV2InitWithdraw);
    } else if (
      method == bytes4(keccak256("completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)"))
    ) {
      IWithdrawalVault.MultiInSingleOutData memory swapData = abi.decode(
        getParams(_data),
        (IWithdrawalVault.MultiInSingleOutData)
      );

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(swapData.destData.destToken)),
        "unsupported destination asset"
      );

      IHasAssetInfo poolFactory = IHasAssetInfo(IPoolLogic(poolLogic).factory());
      uint256 totalSrcValueD18;

      // Validation step to ensure addresses in swap data are valid assets dHEDGE supports
      for (uint256 i; i < swapData.srcData.length; ++i) {
        require(poolFactory.isValidAsset(address(swapData.srcData[i].token)), "invalid src asset");

        totalSrcValueD18 = totalSrcValueD18.add(
          slippageAccumulator.assetValue(address(swapData.srcData[i].token), swapData.srcData[i].amount)
        );
      }

      uint256 dstValueD18 = slippageAccumulator.assetValue(
        address(swapData.destData.destToken),
        swapData.destData.minDestAmount
      );

      require(
        dstValueD18 >=
          totalSrcValueD18.mul(_swapSlippageToleranceDenominator.sub(_swapSlippageTolerance)).div(
            _swapSlippageToleranceDenominator
          ),
        "swap slippage too high"
      );

      txType = uint16(TransactionType.EasySwapperV2CompleteWithdrawSingle);
    } else if (method == bytes4(keccak256("completeWithdrawal()"))) {
      IWithdrawalVault.TrackedAsset[] memory trackedAssets = IEasySwapperV2(_to).getTrackedAssets(poolLogic);

      for (uint256 i; i < trackedAssets.length; ++i) {
        require(
          IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(trackedAssets[i].token),
          "unsupported destination asset"
        );
      }

      txType = uint16(TransactionType.EasySwapperV2CompleteWithdrawMultiple);
    }

    return (txType, false);
  }

  /// @dev For functions that require swap data, for extra security ensure that destination asset remains supported
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to EasySwapperV2 address
  /// @param _data Transaction data
  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    bytes4 method = getMethod(_data);

    if (method == EasySwapperV2.zapDepositWithCustomCooldown.selector) {
      address dHedgeVault = abi.decode(getParams(_data), (address));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dHedgeVault), "unsupported destination asset");
    } else if (
      method == bytes4(keccak256("completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)"))
    ) {
      IWithdrawalVault.MultiInSingleOutData memory swapData = abi.decode(
        getParams(_data),
        (IWithdrawalVault.MultiInSingleOutData)
      );

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(swapData.destData.destToken)),
        "unsupported destination asset"
      );
    } else if (method == EasySwapperV2.initWithdrawal.selector) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "unsupported destination asset");
    }

    if (
      method == EasySwapperV2.zapDepositWithCustomCooldown.selector ||
      method == EasySwapperV2.depositWithCustomCooldown.selector
    ) SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
  }
}
