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
//
// TODO: Intended for whitelisted vaults only. Not open to any vault.

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/synthetix/IPerpsV2Market.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../interfaces/IHasSupportedAsset.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";

/// @title Transaction guard for A Synthetix PerpsV2 Market
contract SynthetixPerpsV2MarketContractGuard is TxDataUtils, IGuard {
  using SafeMath for uint256;
  using SafeMath for uint128;
  using SignedSafeMath for int128;

  event PerpsV2MarketEvent(address fundAddress, address perpsV2Market);

  address public immutable susdProxy;
  mapping(address => bool) public isPoolWhitelisted;

  // Maximum 2.1x leverage is allowed (2x with some additional margin to avoid reverts)
  // This is because of withdrawal processing where the the partial closure of the position is delayed
  // This causes a temporary increase in leverage and increased risk of liquidation
  uint256 public constant MAX_LEVERAGE = 2.1e18; // 18 decimals

  constructor(address _susdProxy, address[] memory _whitelistedDHedgePools) {
    susdProxy = _susdProxy;
    for (uint256 i = 0; i < _whitelistedDHedgePools.length; i++) {
      isPoolWhitelisted[_whitelistedDHedgePools[i]] = true;
    }
  }

  /// @notice Transaction guard for a Synthetix PerpsV2 Market
  /// @dev It supports the functions for managing margin and creating/modifying positions
  /// @param _poolManagerLogic the pool manager logic
  /// @param to the PerpsV2 market
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType,
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);

    // The pool the manager is operating against
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    // Only whitelisted pools can use perps v2

    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    require(poolManagerLogicAssets.isSupportedAsset(to), "unsupported asset");
    require(poolManagerLogicAssets.isSupportedAsset(susdProxy), "susd must be enabled asset");

    if (method == IPerpsV2Market.submitOffchainDelayedOrder.selector) {
      require(isPoolWhitelisted[poolLogic], "pool not whitelisted for perps");

      int256 sizeDelta = abi.decode(getParams(data), (int256));

      _maxLeverageCheck(poolLogic, to, sizeDelta);

      emit PerpsV2MarketEvent(poolLogic, to);
      txType = uint16(ITransactionTypes.TransactionType.KwentaPerpsV2Market);
    } else if (method == IPerpsV2Market.submitOffchainDelayedOrderWithTracking.selector) {
      require(isPoolWhitelisted[poolLogic], "pool not whitelisted for perps");

      int256 sizeDelta = abi.decode(getParams(data), (int256));

      _maxLeverageCheck(poolLogic, to, sizeDelta);

      emit PerpsV2MarketEvent(poolLogic, to);
      txType = uint16(ITransactionTypes.TransactionType.KwentaPerpsV2Market);
    } else if (
      // These functions have been removed since only offchain Perps v2 orders are now supported
      // method == IPerpsV2Market.modifyPosition.selector ||
      // method == IPerpsV2Market.modifyPositionWithTracking.selector ||
      // method == IPerpsV2Market.submitDelayedOrder.selector ||
      // method == IPerpsV2Market.submitDelayedOrderWithTracking.selector ||
      // method == IPerpsV2Market.closePosition.selector ||
      // method == IPerpsV2Market.closePositionWithTracking.selector ||
      method == IPerpsV2Market.transferMargin.selector ||
      method == IPerpsV2Market.withdrawAllMargin.selector ||
      method == IPerpsV2Market.cancelDelayedOrder.selector ||
      method == IPerpsV2Market.cancelOffchainDelayedOrder.selector
    ) {
      emit PerpsV2MarketEvent(poolLogic, to);
      txType = uint16(ITransactionTypes.TransactionType.KwentaPerpsV2Market);
    }

    return (txType, false);
  }

  function _maxLeverageCheck(
    address poolLogic,
    address to,
    int256 sizeDelta
  ) internal view {
    IPerpsV2Market.Position memory position = IPerpsV2Market(to).positions(poolLogic);
    uint256 newPositionValue;
    int256 newPositionSize = position.size.add(sizeDelta);
    (uint256 fillPrice, ) = IPerpsV2Market(to).fillPrice(sizeDelta);

    if (newPositionSize >= 0) {
      newPositionValue = uint256(newPositionSize).mul(fillPrice).div(1e18);
    } else {
      newPositionValue = uint256(-newPositionSize).mul(fillPrice).div(1e18);
    }

    require(newPositionValue < position.margin.mul(MAX_LEVERAGE).div(1e18), "leverage must be less than 2x");
  }
}
