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
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/lyra/IOptionMarket.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/ITransactionTypes.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/synthetix/ISynth.sol";
import "./LyraOptionMarketWrapperContractGuard.sol";

/// @title Transaction guard for A Lyra Options Market
contract LyraOptionMarketContractGuard is LyraOptionMarketWrapperContractGuard {
  using SafeMath for uint256;

  event LyraOptionsMarketEvent(address fundAddress, address optionsMarket);

  constructor(
    ILyraRegistry _lyraRegistry,
    address _nftTracker,
    uint256 _maxPositionCount
  )
    LyraOptionMarketWrapperContractGuard(_lyraRegistry, _nftTracker, _maxPositionCount) // solhint-disable-next-line no-empty-blocks
  {}

  /// @notice Transaction guard for a Lyra Option Market
  /// @dev It supports the functions for opening, closing, addingCollateral and Liquidating
  /// @param _poolManagerLogic the pool manager logic
  /// @param to the option market
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    public
    virtual
    override
    returns (
      uint16 txType,
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    // The pool the manager is operating against
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    require(poolManagerLogicAssets.isSupportedAsset(marketWrapper()), "lyra not enabled");

    settleExpiredAndFilterActivePositions(IPoolManagerLogic(_poolManagerLogic).poolLogic(), to); // use the guardedContract input for the NFT tracker removeData function

    if (method == IOptionMarket.closePosition.selector) {
      IOptionMarket.TradeInputParameters memory params = abi.decode(
        getParams(data),
        (IOptionMarket.TradeInputParameters)
      );

      _checkSupportedAsset(poolManagerLogicAssets, params.optionType, address(to));
      txType = uint16(ITransactionTypes.TransactionType.LyraClosePosition);
      emit LyraOptionsMarketEvent(poolLogic, to);
    } else if (method == IOptionMarket.forceClosePosition.selector) {
      IOptionMarket.TradeInputParameters memory params = abi.decode(
        getParams(data),
        (IOptionMarket.TradeInputParameters)
      );
      _checkSupportedAsset(poolManagerLogicAssets, params.optionType, address(to));

      txType = uint16(ITransactionTypes.TransactionType.LyraForceClosePosition);
      emit LyraOptionsMarketEvent(poolLogic, to);
    } else if (method == IOptionMarket.openPosition.selector) {
      IOptionMarket.TradeInputParameters memory params = abi.decode(
        getParams(data),
        (IOptionMarket.TradeInputParameters)
      );
      _checkSupportedAsset(poolManagerLogicAssets, params.optionType, address(to));

      txType = uint16(ITransactionTypes.TransactionType.LyraOpenPosition);
      emit LyraOptionsMarketEvent(poolLogic, to);
    } else if (method == IOptionMarket.addCollateral.selector) {
      (uint256 positionId, ) = abi.decode(getParams(data), (uint256, uint256));
      IOptionMarketViewer.OptionMarketAddresses memory optionMarketAddresses = marketViewer().marketAddresses(to);
      require(IOptionToken(optionMarketAddresses.optionToken).ownerOf(positionId) == poolLogic, "not position owner");

      txType = uint16(ITransactionTypes.TransactionType.LyraAddCollateral);
      emit LyraOptionsMarketEvent(poolLogic, to);
    } else if (method == IOptionMarket.liquidatePosition.selector) {
      emit LyraOptionsMarketEvent(poolLogic, to);
      (, address rewardBeneficiary) = abi.decode(getParams(data), (uint256, address));

      require(rewardBeneficiary == poolLogic, "reward beneficiary not pool");
      txType = uint16(ITransactionTypes.TransactionType.LyraLiquidatePosition);
    }

    return (txType, false);
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev It supports close/open/forceClose position
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  function afterTxGuard(address _poolManagerLogic, address to, bytes calldata data) public virtual override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(data);

    if (
      method == IOptionMarket.closePosition.selector ||
      method == IOptionMarket.forceClosePosition.selector ||
      method == IOptionMarket.openPosition.selector
    ) {
      IOptionMarket.TradeInputParameters memory params = abi.decode(
        getParams(data),
        (IOptionMarket.TradeInputParameters)
      );

      afterTxGuardHandle(to, poolLogic, address(to), params.positionId);
    } else if (method == IOptionMarket.addCollateral.selector) {
      (uint256 positionId, ) = abi.decode(getParams(data), (uint256, uint256));
      // will call the super.afterTxGuardHandle
      afterTxGuardHandle(to, poolLogic, address(to), positionId);
    } else if (method == IOptionMarket.liquidatePosition.selector) {
      (uint256 positionId, ) = abi.decode(getParams(data), (uint256, address));
      afterTxGuardHandle(to, poolLogic, address(to), positionId);
    }
  }
}
