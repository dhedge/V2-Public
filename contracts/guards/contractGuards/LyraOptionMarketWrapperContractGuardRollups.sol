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
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./LyraOptionMarketWrapperContractGuard.sol";
import "../../interfaces/IERC20Extended.sol";
import "../../utils/TxDataUtils.sol";
import "../../utils/tracker/DhedgeNftTrackerStorage.sol";
import "../../interfaces/guards/ITxTrackingGuard.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/lyra/IOptionMarket.sol";
import "../../interfaces/lyra/IOptionMarketViewer.sol";
import "../../interfaces/lyra/IOptionMarketWrapper.sol";
import "../../interfaces/lyra/ISynthetixAdapter.sol";
import "../../interfaces/lyra/IShortCollateral.sol";
import "../../interfaces/synthetix/IAddressResolver.sol";
import "../../interfaces/lyra/ILyraRegistry.sol";

/// @title Transaction guard for Lyra OptionMarketWrapper (rollups)
/// here we support the rollup functions mentioned in https://github.com/lyra-finance/lyra-protocol/blob/master/contracts/periphery/Wrapper/OptionMarketWrapper.sol
contract LyraOptionMarketWrapperContractGuardRollups is LyraOptionMarketWrapperContractGuard {
  using SafeMathUpgradeable for uint256;

  constructor(
    ILyraRegistry _lyraRegistry,
    address _nftTracker,
    uint256 _maxPositionCount
  )
    LyraOptionMarketWrapperContractGuard(_lyraRegistry, _nftTracker, _maxPositionCount)
  // solhint-disable-next-line no-empty-blocks
  {

  }

  /// @notice Transaction guard for OptionMarketWrapper - used for Toros
  /// @dev It supports close/open/forceClose position
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  ) public override returns (uint16 txType, bool isPublic) {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    require(poolManagerLogicAssets.isSupportedAsset(to), "lyra not enabled");

    settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic());

    bytes4 method = getMethod(data);
    if (
      method == IOptionMarketWrapper.openLong.selector ||
      method == IOptionMarketWrapper.addLong.selector ||
      method == IOptionMarketWrapper.openShort.selector ||
      method == IOptionMarketWrapper.addShort.selector
    ) {
      uint256 params = abi.decode(getParams(data), (uint256));
      (IOptionMarketWrapper.OptionPositionParams memory optionPositionParams, ) = _getOptionParam(method, params);
      _checkSupportedAsset(
        poolManagerLogicAssets,
        optionPositionParams.optionType,
        address(optionPositionParams.optionMarket)
      );
      txType = 26;

      settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic());
    } else if (
      method == IOptionMarketWrapper.reduceLong.selector ||
      method == IOptionMarketWrapper.closeLong.selector ||
      method == IOptionMarketWrapper.reduceShort.selector ||
      method == IOptionMarketWrapper.closeShort.selector
    ) {
      uint256 params = abi.decode(getParams(data), (uint256));
      (IOptionMarketWrapper.OptionPositionParams memory optionPositionParams, bool isForceClose) = _getOptionParam(
        method,
        params
      );
      _checkSupportedAsset(
        poolManagerLogicAssets,
        optionPositionParams.optionType,
        address(optionPositionParams.optionMarket)
      );
      txType = (isForceClose) ? 28 : 27;

      settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic());
    } else {
      (txType, isPublic) = super.txGuard(_poolManagerLogic, to, data);
    }

    return (txType, isPublic);
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev It supports close/open/forceClose position
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  function afterTxGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  ) public override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(data);
    if (
      method == IOptionMarketWrapper.openLong.selector ||
      method == IOptionMarketWrapper.addLong.selector ||
      method == IOptionMarketWrapper.reduceLong.selector ||
      method == IOptionMarketWrapper.closeLong.selector ||
      method == IOptionMarketWrapper.openShort.selector ||
      method == IOptionMarketWrapper.addShort.selector ||
      method == IOptionMarketWrapper.reduceShort.selector ||
      method == IOptionMarketWrapper.closeShort.selector
    ) {
      uint256 params = abi.decode(getParams(data), (uint256));
      (IOptionMarketWrapper.OptionPositionParams memory optionPositionParams, ) = _getOptionParam(method, params);
      afterTxGuardHandle(to, poolLogic, address(optionPositionParams.optionMarket), optionPositionParams.positionId);
    } else {
      super.afterTxGuard(_poolManagerLogic, to, data);
    }
  }

  function _getOptionParam(bytes4 method, uint256 params)
    internal
    view
    returns (IOptionMarketWrapper.OptionPositionParams memory optionPositionParams, bool isForceClose)
  {
    if (method == IOptionMarketWrapper.openLong.selector) {
      address inputAsset = _getOptionInputAsset(params);
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(_getOptionMarket(params)),
        strikeId: _parseUint32(params >> 32),
        positionId: 0,
        iterations: _parseUint8(params >> 24),
        currentCollateral: 0,
        setCollateralTo: 0,
        optionType: uint8(params >> 16) > 0 ? IOptionMarket.OptionType.LONG_CALL : IOptionMarket.OptionType.LONG_PUT,
        amount: _parseUint64Amount(params >> 128),
        minCost: 0,
        maxCost: _parseUint32Amount(params >> 64),
        inputAmount: _convertDecimal(_parseUint32(params >> 96), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
    } else if (method == IOptionMarketWrapper.addLong.selector) {
      address optionMarket = _getOptionMarket(params);
      address inputAsset = _getOptionInputAsset(params);
      IOptionMarketWrapper.OptionMarketContracts memory c = IOptionMarketWrapper(marketWrapper()).marketContracts(
        IOptionMarket(optionMarket)
      );
      IOptionToken.OptionPosition memory position = c.optionToken.positions(uint256(uint32(params >> 24)));
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(optionMarket),
        strikeId: position.strikeId,
        positionId: position.positionId,
        iterations: _parseUint8(params >> 16),
        currentCollateral: 0,
        setCollateralTo: 0,
        optionType: position.optionType,
        amount: _parseUint64Amount(params >> 120),
        minCost: 0,
        maxCost: _parseUint32Amount(params >> 56),
        inputAmount: _convertDecimal(_parseUint32(params >> 88), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
    } else if (method == IOptionMarketWrapper.reduceLong.selector) {
      address optionMarket = _getOptionMarket(params);
      address inputAsset = _getOptionInputAsset(params);
      IOptionMarketWrapper.OptionMarketContracts memory c = IOptionMarketWrapper(marketWrapper()).marketContracts(
        IOptionMarket(optionMarket)
      );
      IOptionToken.OptionPosition memory position = c.optionToken.positions(uint256(uint32(params >> 32)));
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(optionMarket),
        strikeId: position.strikeId,
        positionId: position.positionId,
        iterations: _parseUint8(params >> 16),
        currentCollateral: 0,
        setCollateralTo: 0,
        optionType: position.optionType,
        amount: _parseUint64Amount(params >> 96),
        minCost: _parseUint32Amount(params >> 160),
        maxCost: type(uint256).max,
        inputAmount: _convertDecimal(_parseUint32(params >> 64), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
      isForceClose = (uint8(params >> 24) > 0);
    } else if (method == IOptionMarketWrapper.closeLong.selector) {
      address optionMarket = _getOptionMarket(params);
      address inputAsset = _getOptionInputAsset(params);
      IOptionMarketWrapper.OptionMarketContracts memory c = IOptionMarketWrapper(marketWrapper()).marketContracts(
        IOptionMarket(optionMarket)
      );
      IOptionToken.OptionPosition memory position = c.optionToken.positions(uint256(uint32(params >> 32)));
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(optionMarket),
        strikeId: position.strikeId,
        positionId: position.positionId,
        iterations: _parseUint8(params >> 16),
        currentCollateral: 0,
        setCollateralTo: 0,
        optionType: position.optionType,
        amount: position.amount,
        minCost: _parseUint32Amount(params >> 96),
        maxCost: type(uint256).max,
        inputAmount: _convertDecimal(_parseUint32(params >> 64), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
      isForceClose = (uint8(params >> 24) > 0);
    } else if (method == IOptionMarketWrapper.openShort.selector) {
      address inputAsset = _getOptionInputAsset(params);
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(_getOptionMarket(params)),
        strikeId: uint256(uint32(params >> 32)),
        positionId: 0,
        iterations: _parseUint8(params >> 24),
        currentCollateral: 0,
        setCollateralTo: _parseUint64Amount(params >> 192),
        optionType: IOptionMarket.OptionType(uint8(params >> 16)),
        amount: _parseUint64Amount(params >> 128),
        minCost: _parseUint32Amount(params >> 64),
        maxCost: type(uint256).max,
        inputAmount: _convertDecimal(_parseUint32(params >> 96), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
    } else if (method == IOptionMarketWrapper.addShort.selector) {
      address optionMarket = _getOptionMarket(params);
      address inputAsset = _getOptionInputAsset(params);
      IOptionMarketWrapper.OptionMarketContracts memory c = IOptionMarketWrapper(marketWrapper()).marketContracts(
        IOptionMarket(optionMarket)
      );
      IOptionToken.OptionPosition memory position = c.optionToken.positions(uint256(uint32(params >> 24)));
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(optionMarket),
        strikeId: position.strikeId,
        positionId: position.positionId,
        iterations: _parseUint8(params >> 16),
        setCollateralTo: _parseUint64Amount(params >> 184),
        currentCollateral: position.collateral,
        optionType: position.optionType,
        amount: _parseUint64Amount(params >> 120),
        minCost: _parseUint32Amount(params >> 88),
        maxCost: type(uint256).max,
        inputAmount: _convertDecimal(_parseUint32(params >> 56), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
    } else if (method == IOptionMarketWrapper.reduceShort.selector) {
      address optionMarket = _getOptionMarket(params);
      address inputAsset = _getOptionInputAsset(params);
      IOptionMarketWrapper.OptionMarketContracts memory c = IOptionMarketWrapper(marketWrapper()).marketContracts(
        IOptionMarket(optionMarket)
      );
      IOptionToken.OptionPosition memory position = c.optionToken.positions(uint256(uint32(params >> 32)));
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(optionMarket),
        strikeId: position.strikeId,
        positionId: position.positionId,
        iterations: _parseUint8(params >> 16),
        setCollateralTo: _parseUint64Amount(params >> 196),
        currentCollateral: position.collateral,
        optionType: position.optionType,
        amount: _parseUint64Amount(params >> 128),
        minCost: 0,
        maxCost: _parseUint32Amount(params >> 96),
        inputAmount: _convertDecimal(_parseUint32(params >> 64), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
      isForceClose = (uint8(params >> 24) > 0);
    } else if (method == IOptionMarketWrapper.closeShort.selector) {
      address optionMarket = _getOptionMarket(params);
      address inputAsset = _getOptionInputAsset(params);
      IOptionMarketWrapper.OptionMarketContracts memory c = IOptionMarketWrapper(marketWrapper()).marketContracts(
        IOptionMarket(optionMarket)
      );
      IOptionToken.OptionPosition memory position = c.optionToken.positions(uint256(uint32(params >> 32)));
      optionPositionParams = IOptionMarketWrapper.OptionPositionParams({
        optionMarket: IOptionMarket(optionMarket),
        strikeId: position.strikeId,
        positionId: position.positionId,
        iterations: _parseUint8(params >> 16),
        currentCollateral: position.collateral,
        setCollateralTo: 0,
        optionType: position.optionType,
        amount: position.amount,
        minCost: 0,
        maxCost: _parseUint32Amount(params >> 96),
        inputAmount: _convertDecimal(_parseUint32(params >> 64), inputAsset),
        inputAsset: IERC20(inputAsset)
      });
      isForceClose = (uint8(params >> 24) > 0);
    } else {
      revert("invalid method");
    }
  }

  function _parseUint8(uint256 inp) internal pure returns (uint256) {
    return uint256(uint8(inp));
  }

  function _parseUint32Amount(uint256 inp) internal pure returns (uint256) {
    return _parseUint32(inp) * 1e16;
  }

  function _parseUint32(uint256 inp) internal pure returns (uint256) {
    return uint256(uint32(inp));
  }

  function _parseUint64Amount(uint256 inp) internal pure returns (uint256) {
    return uint256(uint64(inp)) * 1e10;
  }

  function _convertDecimal(uint256 amount, address inputAsset) internal view returns (uint256 newAmount) {
    newAmount = amount * (10**(IERC20Extended(inputAsset).decimals() - 2));
  }

  function _getOptionMarket(uint256 params) internal view returns (address) {
    return IOptionMarketWrapper(marketWrapper()).idToMarket(uint8(params));
  }

  function _getOptionInputAsset(uint256 params) internal view returns (address) {
    return IOptionMarketWrapper(marketWrapper()).idToERC(uint8(params >> 8));
  }
}
