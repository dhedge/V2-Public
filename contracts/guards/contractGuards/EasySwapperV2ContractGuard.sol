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
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {IEasySwapperV2} from "../../swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "../../swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {EasySwapperV2} from "../../swappers/easySwapperV2/EasySwapperV2.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

contract EasySwapperV2ContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  using SafeMath for uint256;

  uint256 public constant MAX_BPS = 10_000;

  /// @dev Explicit selectors for overloaded functions (non-referral variants)
  bytes4 private constant ZAP_DEPOSIT_CUSTOM_COOLDOWN_SELECTOR =
    bytes4(
      keccak256("zapDepositWithCustomCooldown(address,((address,uint256,(bytes32,bytes)),(address,uint256)),uint256)")
    );
  bytes4 private constant DEPOSIT_CUSTOM_COOLDOWN_SELECTOR =
    bytes4(keccak256("depositWithCustomCooldown(address,address,uint256,uint256)"));

  /// @dev Explicit selectors for overloaded functions (referral variants with bytes _referralData)
  bytes4 private constant ZAP_DEPOSIT_CUSTOM_COOLDOWN_REFERRAL_SELECTOR =
    bytes4(
      keccak256(
        "zapDepositWithCustomCooldown(address,((address,uint256,(bytes32,bytes)),(address,uint256)),uint256,bytes)"
      )
    );
  bytes4 private constant DEPOSIT_CUSTOM_COOLDOWN_REFERRAL_SELECTOR =
    bytes4(keccak256("depositWithCustomCooldown(address,address,uint256,uint256,bytes)"));

  uint256 private immutable _swapSlippageTolerance;

  /// @param _slippageAccumulator Slippage accumulator address
  /// @param _slippageTolerance Should match with precision used in PoolLogic (e.g. 100 = 1%)
  constructor(address _slippageAccumulator, uint256 _slippageTolerance) SlippageAccumulatorUser(_slippageAccumulator) {
    require(_slippageTolerance < MAX_BPS && _slippageTolerance > 0, "invalid tolerance");

    _swapSlippageTolerance = _slippageTolerance;
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
    address poolLogic = _accessControl(_poolManagerLogic);
    bytes4 method = getMethod(_data);

    if (method == ZAP_DEPOSIT_CUSTOM_COOLDOWN_SELECTOR || method == ZAP_DEPOSIT_CUSTOM_COOLDOWN_REFERRAL_SELECTOR) {
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

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(swapData.srcData.token)),
        "unsupported source asset"
      );

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: address(swapData.srcData.token),
        dstAsset: dHedgeVault,
        srcAmount: _getBalance(address(swapData.srcData.token), poolLogic),
        dstAmount: _getBalance(dHedgeVault, poolLogic)
      });

      txType = uint16(TransactionType.EasySwapperV2Deposit);
    } else if (method == DEPOSIT_CUSTOM_COOLDOWN_SELECTOR || method == DEPOSIT_CUSTOM_COOLDOWN_REFERRAL_SELECTOR) {
      (address dHedgeVault, address vaultDepositToken) = abi.decode(getParams(_data), (address, address));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dHedgeVault), "unsupported destination asset");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(vaultDepositToken), "unsupported source asset");

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

      (address dHedgeVault, , IPoolLogic.ComplexAsset[] memory complexAssetsData) = abi.decode(
        getParams(_data),
        (address, uint256, IPoolLogic.ComplexAsset[])
      );

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dHedgeVault), "unsupported source asset");

      for (uint256 i; i < complexAssetsData.length; ++i) {
        // Simple hard stop to prevent managers from setting slippage tolerance for withdrawing from aave positions too high
        require(complexAssetsData[i].slippageTolerance <= _swapSlippageTolerance, "beyond allowed slippage");
        require(complexAssetsData[i].slippageTolerance != 0, "0 slippage not allowed");

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
      (IWithdrawalVault.MultiInSingleOutData memory swapData, uint256 expectedDestTokenAmount) = abi.decode(
        getParams(_data),
        (IWithdrawalVault.MultiInSingleOutData, uint256)
      );

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "unsupported source asset");

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(swapData.destData.destToken)),
        "unsupported destination asset"
      );

      IHasAssetInfo poolFactory = IHasAssetInfo(IPoolLogic(poolLogic).factory());

      // Validation step to ensure addresses in swap data are valid assets dHEDGE supports
      for (uint256 i; i < swapData.srcData.length; ++i) {
        require(poolFactory.isValidAsset(address(swapData.srcData[i].token)), "invalid src asset");
      }

      // Calculate total source value from actual tracked assets in the withdrawal vault
      // Exclude destToken if already present (it won't be swapped, just transferred)
      IWithdrawalVault.TrackedAsset[] memory trackedAssets = IEasySwapperV2(_to).getTrackedAssets(poolLogic);
      uint256 totalSrcValueD18;
      uint256 preExistingDestBalance;

      for (uint256 i; i < trackedAssets.length; ++i) {
        if (trackedAssets[i].token == address(swapData.destData.destToken)) {
          preExistingDestBalance = trackedAssets[i].balance;
        } else {
          totalSrcValueD18 = totalSrcValueD18.add(
            slippageAccumulator.assetValue(trackedAssets[i].token, trackedAssets[i].balance)
          );
        }
      }

      // Only check slippage on the actual swap output, excluding pre-existing destToken balance
      uint256 expectedSwapOutput = expectedDestTokenAmount.sub(preExistingDestBalance);
      uint256 dstValueD18 = slippageAccumulator.assetValue(address(swapData.destData.destToken), expectedSwapOutput);

      require(
        dstValueD18 >= totalSrcValueD18.mul(MAX_BPS.sub(_swapSlippageTolerance)).div(MAX_BPS),
        "swap slippage too high"
      );

      txType = uint16(TransactionType.EasySwapperV2CompleteWithdrawSingle);
    } else if (method == bytes4(keccak256("completeWithdrawal()"))) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "unsupported source asset");

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
    bytes memory params = getParams(_data);

    if (method == ZAP_DEPOSIT_CUSTOM_COOLDOWN_SELECTOR || method == ZAP_DEPOSIT_CUSTOM_COOLDOWN_REFERRAL_SELECTOR) {
      (address dHedgeVault, EasySwapperV2.SingleInSingleOutData memory swapData) = abi.decode(
        params,
        (address, EasySwapperV2.SingleInSingleOutData)
      );

      _verifySwapAfterTxGuard(address(swapData.srcData.token), dHedgeVault, _poolManagerLogic, _to);
    } else if (method == DEPOSIT_CUSTOM_COOLDOWN_SELECTOR || method == DEPOSIT_CUSTOM_COOLDOWN_REFERRAL_SELECTOR) {
      (address dHedgeVault, address vaultDepositToken) = abi.decode(params, (address, address));

      _verifySwapAfterTxGuard(vaultDepositToken, dHedgeVault, _poolManagerLogic, _to);
    } else if (method == EasySwapperV2.initWithdrawal.selector) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "unsupported destination asset");

      address dHedgeVault = abi.decode(params, (address));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(dHedgeVault), "unsupported source asset");
    } else if (
      method == bytes4(keccak256("completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)"))
    ) {
      IWithdrawalVault.MultiInSingleOutData memory swapData = abi.decode(
        params,
        (IWithdrawalVault.MultiInSingleOutData)
      );

      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(swapData.destData.destToken)),
        "unsupported destination asset"
      );

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "unsupported source asset");
    }
  }

  function _verifySwapAfterTxGuard(
    address _srcToken,
    address _dHedgeVault,
    address _poolManagerLogic,
    address _to
  ) internal {
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_srcToken), "unsupported source asset");

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_dHedgeVault), "unsupported destination asset");

    SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, "");
  }
}
