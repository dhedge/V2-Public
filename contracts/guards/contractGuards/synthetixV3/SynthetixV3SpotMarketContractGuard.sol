// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IAtomicOrderModule} from "../../../interfaces/synthetixV3/IAtomicOrderModule.sol";
import {ISpotMarketConfigurationModule} from "../../../interfaces/synthetixV3/ISpotMarketConfigurationModule.sol";
import {ISpotMarketFactoryModule} from "../../../interfaces/synthetixV3/ISpotMarketFactoryModule.sol";
import {ISynthetixV3ContractGuard} from "../../../interfaces/synthetixV3/ISynthetixV3ContractGuard.sol";
import {IWrapperModule} from "../../../interfaces/synthetixV3/IWrapperModule.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SynthetixV3Structs} from "../../../utils/synthetixV3/libraries/SynthetixV3Structs.sol";
import {PrecisionHelper} from "../../../utils/PrecisionHelper.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";

contract SynthetixV3SpotMarketContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  using SafeMath for uint256;
  using PrecisionHelper for address;

  address public immutable snxV3Core;

  ISpotMarketFactoryModule public immutable snxSpotMarket;

  mapping(address => SynthetixV3Structs.AllowedMarket) public allowedMarkets;

  struct WrapOrUnwrapData {
    uint256 inputAmount;
    uint256 outputAmount;
    address fromAsset;
    address toAsset;
    IHasSupportedAsset poolManagerLogicAssets;
    IHasAssetInfo dhedgeFactoryValidAssets;
  }

  /// @dev Address is required to get its contract guard which stores the whitelist of dHEDGE vaults
  /// @param _snxV3Core Synthetix V3 core address
  /// @param _snxSpotMarket Synthetix V3 spot market address
  /// @param _slippageAccumulator Slippage accumulator address
  /// @param _allowedMarkets Synthetix markets ids allowed for trading
  constructor(
    address _snxV3Core,
    address _snxSpotMarket,
    address _slippageAccumulator,
    SynthetixV3Structs.AllowedMarket[] memory _allowedMarkets
  ) SlippageAccumulatorUser(_slippageAccumulator) {
    require(_snxV3Core != address(0), "invalid snxV3Core");
    require(_snxSpotMarket != address(0), "invalid snxSpotMarket");

    snxV3Core = _snxV3Core;
    snxSpotMarket = ISpotMarketFactoryModule(_snxSpotMarket);

    for (uint256 i; i < _allowedMarkets.length; ++i) {
      require(
        ISpotMarketFactoryModule(_snxSpotMarket).getSynth(_allowedMarkets[i].marketId) ==
          _allowedMarkets[i].collateralSynth,
        "invalid market config"
      );
      require(_allowedMarkets[i].collateralAsset != address(0), "invalid collateral address");
      allowedMarkets[_allowedMarkets[i].collateralSynth] = _allowedMarkets[i];
    }
  }

  /// @notice Transaction guard for Synthetix V3 Spot Market
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @dev Only available for SynthetixV3 whitelisted vaults
  /// @dev Includes synths wrapping/unwrapping and buying/selling
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");
    address dhedgeFactory = IPoolLogic(poolLogic).factory();

    ISynthetixV3ContractGuard coreContractGuard = ISynthetixV3ContractGuard(
      IHasGuardInfo(dhedgeFactory).getContractGuard(snxV3Core)
    );

    require(coreContractGuard.isVaultWhitelisted(poolLogic), "dhedge vault not whitelisted");

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    if (method == IWrapperModule.wrap.selector) {
      (uint128 marketId, uint256 wrapAmount, uint256 minAmountReceived) = abi.decode(
        params,
        (uint128, uint256, uint256)
      );

      SynthetixV3Structs.AllowedMarket storage allowedMarket = _validateMarketId(marketId);

      wrapAmount = wrapAmount.mul(allowedMarket.collateralAsset.getPrecisionForConversion());

      _wrapOrUnWrapCheck(
        WrapOrUnwrapData({
          inputAmount: wrapAmount,
          outputAmount: minAmountReceived,
          fromAsset: allowedMarket.collateralAsset,
          toAsset: allowedMarket.collateralSynth,
          poolManagerLogicAssets: poolManagerLogicAssets,
          dhedgeFactoryValidAssets: IHasAssetInfo(dhedgeFactory)
        })
      );

      txType = uint16(TransactionType.SynthetixV3Wrap);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IWrapperModule.unwrap.selector) {
      (uint128 marketId, uint256 unwrapAmount, uint256 minAmountReceived) = abi.decode(
        params,
        (uint128, uint256, uint256)
      );

      SynthetixV3Structs.AllowedMarket storage allowedMarket = _validateMarketId(marketId);

      unwrapAmount = unwrapAmount.div(allowedMarket.collateralAsset.getPrecisionForConversion());

      _wrapOrUnWrapCheck(
        WrapOrUnwrapData({
          inputAmount: unwrapAmount,
          outputAmount: minAmountReceived,
          fromAsset: allowedMarket.collateralSynth,
          toAsset: allowedMarket.collateralAsset,
          poolManagerLogicAssets: poolManagerLogicAssets,
          dhedgeFactoryValidAssets: IHasAssetInfo(dhedgeFactory)
        })
      );

      txType = uint16(TransactionType.SynthetixV3Unwrap);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IAtomicOrderModule.buy.selector || method == IAtomicOrderModule.buyExactIn.selector) {
      (uint128 marketId, uint256 usdAmount, uint256 minSynthAmount) = abi.decode(params, (uint128, uint256, uint256));

      SynthetixV3Structs.AllowedMarket storage allowedMarket = _validateMarketId(marketId);

      _atomicSwapCheck(
        allowedMarket,
        SlippageAccumulator.SwapData({
          srcAsset: IAtomicOrderModule(snxV3Core).getUsdToken(),
          dstAsset: allowedMarket.collateralSynth,
          srcAmount: usdAmount,
          dstAmount: minSynthAmount
        }),
        poolManagerLogicAssets,
        poolLogic
      );

      txType = uint16(TransactionType.SynthetixV3BuySynth);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IAtomicOrderModule.sell.selector || method == IAtomicOrderModule.sellExactIn.selector) {
      (uint128 marketId, uint256 synthAmount, uint256 minUsdAmount) = abi.decode(params, (uint128, uint256, uint256));

      SynthetixV3Structs.AllowedMarket storage allowedMarket = _validateMarketId(marketId);

      _atomicSwapCheck(
        allowedMarket,
        SlippageAccumulator.SwapData({
          srcAsset: allowedMarket.collateralSynth,
          dstAsset: IAtomicOrderModule(snxV3Core).getUsdToken(),
          srcAmount: synthAmount,
          dstAmount: minUsdAmount
        }),
        poolManagerLogicAssets,
        poolLogic
      );

      txType = uint16(TransactionType.SynthetixV3SellSynth);

      emit SynthetixV3Event(poolLogic, txType);
    }

    return (txType, false);
  }

  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    bytes4 method = getMethod(_data);

    if (
      method == IAtomicOrderModule.buy.selector ||
      method == IAtomicOrderModule.buyExactIn.selector ||
      method == IAtomicOrderModule.sell.selector ||
      method == IAtomicOrderModule.sellExactIn.selector
    ) {
      SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
    }
  }

  function _wrapOrUnWrapCheck(WrapOrUnwrapData memory _wrapOrUnwrapData) internal view {
    bool isFromAssetValid = _wrapOrUnwrapData.dhedgeFactoryValidAssets.isValidAsset(_wrapOrUnwrapData.fromAsset);
    if (isFromAssetValid) {
      require(
        _wrapOrUnwrapData.poolManagerLogicAssets.isSupportedAsset(_wrapOrUnwrapData.fromAsset),
        "unsupported asset"
      );
      require(
        _wrapOrUnwrapData.poolManagerLogicAssets.isSupportedAsset(_wrapOrUnwrapData.toAsset),
        "unsupported asset"
      );
    }

    _validateAmounts(_wrapOrUnwrapData.inputAmount, _wrapOrUnwrapData.outputAmount);
  }

  function _atomicSwapCheck(
    SynthetixV3Structs.AllowedMarket storage _allowedMarket,
    SlippageAccumulator.SwapData memory _swapData,
    IHasSupportedAsset _poolManagerLogic,
    address _poolLogic
  ) internal {
    require(_allowedMarket.atomicSwapSettings.isAtomicSwapAllowed, "atomic swap not allowed");

    require(_poolManagerLogic.isSupportedAsset(_swapData.dstAsset), "unsupported asset");

    if (_allowedMarket.atomicSwapSettings.isOneToOneSwap) {
      _validateAmounts(_swapData.srcAmount, _swapData.dstAmount);
    } else {
      (uint256 atomicFixedFee, , , ) = ISpotMarketConfigurationModule(address(snxSpotMarket)).getMarketFees(
        _allowedMarket.marketId
      );

      require(atomicFixedFee == 0, "atomicFixedFee is not 0");

      _swapData.srcAmount = _getBalance(_swapData.srcAsset, _poolLogic);
      _swapData.dstAmount = _getBalance(_swapData.dstAsset, _poolLogic);
      intermediateSwapData = _swapData;
    }
  }

  function _validateAmounts(uint256 _amountIn, uint256 _amountOut) internal pure {
    require(
      // allow 1 wei difference for rounding
      _amountIn > 0 && (_amountIn == _amountOut || _amountIn.sub(1) == _amountOut),
      "amounts don't match"
    );
  }

  function _validateMarketId(
    uint128 _marketId
  ) internal view returns (SynthetixV3Structs.AllowedMarket storage allowedMarket) {
    require(_marketId > 0, "invalid marketId");
    address synthAddress = snxSpotMarket.getSynth(_marketId);
    allowedMarket = allowedMarkets[synthAddress];
    require(allowedMarket.marketId == _marketId, "market not allowed");
  }
}
