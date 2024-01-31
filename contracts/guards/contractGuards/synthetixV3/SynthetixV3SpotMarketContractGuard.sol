// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/synthetixV3/IAtomicOrderModule.sol";
import "../../../interfaces/synthetixV3/ISpotMarketFactoryModule.sol";
import "../../../interfaces/synthetixV3/ISynthetixV3ContractGuard.sol";
import "../../../interfaces/synthetixV3/IWrapperModule.sol";
import "../../../interfaces/IERC20Extended.sol";
import "../../../interfaces/IHasGuardInfo.sol";
import "../../../interfaces/IPoolLogic.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";
import "../../../utils/synthetixV3/libraries/SynthetixV3Structs.sol";
import "../../../utils/TxDataUtils.sol";

contract SynthetixV3SpotMarketContractGuard is IGuard, TxDataUtils, ITransactionTypes {
  using SafeMath for uint256;

  address public immutable snxV3Core;

  ISpotMarketFactoryModule public immutable snxSpotMarket;

  mapping(address => SynthetixV3Structs.AllowedMarket) public allowedMarkets;

  /// @dev Address is required to get its contract guard which stores the whitelist of dHEDGE vaults
  /// @param _snxV3Core Synthetix V3 core address
  /// @param _allowedMarkets Synthetix markets ids allowed for trading
  constructor(
    address _snxV3Core,
    address _snxSpotMarket,
    SynthetixV3Structs.AllowedMarket[] memory _allowedMarkets
  ) {
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
  /// @notice Supports only 1:1 synths buy/sell and collateral wrap/unwrap
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @dev Only available for SynthetixV3 whitelisted vaults
  /// @dev Includes synths wrapping/unwrapping and buying/selling
  /// @dev Matching values like amount and minAmountReceived in the transactions will guarantee the 1:1 swap
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    ISynthetixV3ContractGuard coreContractGuard = ISynthetixV3ContractGuard(
      IHasGuardInfo(IPoolLogic(poolLogic).factory()).getContractGuard(snxV3Core)
    );

    require(coreContractGuard.isVaultWhitelisted(poolLogic), "dhedge vault not whitelisted");

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == IWrapperModule.wrap.selector) {
      (uint128 marketId, uint256 wrapAmount, uint256 minAmountReceived) = abi.decode(
        params,
        (uint128, uint256, uint256)
      );

      SynthetixV3Structs.AllowedMarket storage allowedMarket = _validateMarketId(marketId);
      uint8 decimals = IERC20Extended(allowedMarket.collateralAsset).decimals();
      wrapAmount = wrapAmount.mul(10**(18 - decimals));

      require(wrapAmount == minAmountReceived, "amounts don't match");

      txType = uint16(TransactionType.SynthetixV3Wrap);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IWrapperModule.unwrap.selector) {
      (uint128 marketId, uint256 unwrapAmount, uint256 minAmountReceived) = abi.decode(
        params,
        (uint128, uint256, uint256)
      );

      SynthetixV3Structs.AllowedMarket storage allowedMarket = _validateMarketId(marketId);
      uint8 decimals = IERC20Extended(allowedMarket.collateralAsset).decimals();
      minAmountReceived = minAmountReceived.mul(10**(18 - decimals));

      require(unwrapAmount == minAmountReceived, "amounts don't match");

      txType = uint16(TransactionType.SynthetixV3Unwrap);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IAtomicOrderModule.buy.selector || method == IAtomicOrderModule.buyExactIn.selector) {
      (uint128 marketId, uint256 usdAmount, uint256 minSynthAmount) = abi.decode(params, (uint128, uint256, uint256));

      _validateMarketId(marketId);

      require(usdAmount == minSynthAmount, "amounts don't match");

      txType = uint16(TransactionType.SynthetixV3BuySynth);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IAtomicOrderModule.sell.selector || method == IAtomicOrderModule.sellExactIn.selector) {
      (uint128 marketId, uint256 synthAmount, uint256 minUsdAmount) = abi.decode(params, (uint128, uint256, uint256));

      _validateMarketId(marketId);

      require(synthAmount == minUsdAmount, "amounts don't match");

      txType = uint16(TransactionType.SynthetixV3SellSynth);

      emit SynthetixV3Event(poolLogic, txType);
    }

    return (txType, false);
  }

  function _validateMarketId(uint128 _marketId)
    internal
    view
    returns (SynthetixV3Structs.AllowedMarket storage allowedMarket)
  {
    require(_marketId > 0, "invalid marketId");
    address synthAddress = snxSpotMarket.getSynth(_marketId);
    allowedMarket = allowedMarkets[synthAddress];
    require(allowedMarket.marketId == _marketId, "market not allowed");
  }
}
