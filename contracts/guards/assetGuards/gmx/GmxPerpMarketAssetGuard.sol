// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {IGmxDataStore} from "../../../interfaces/gmx/IGmxDataStore.sol";
import {IGmxExchangeRouterContractGuard} from "../../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {IGmxDeposit} from "../../../interfaces/gmx/IGmxDeposit.sol";
import {IGmxWithdrawal} from "../../../interfaces/gmx/IGmxWithdrawal.sol";
import {IGmxReader} from "../../../interfaces/gmx/IGmxReader.sol";
import {IGmxReferralStorage} from "../../../interfaces/gmx/IGmxReferralStorage.sol";
import {GmxDataStoreLib} from "../../../utils/gmx/GmxDataStoreLib.sol";
import {IGmxMarket} from "../../../interfaces/gmx/IGmxMarket.sol";
import {Order} from "../../../interfaces/gmx/IGmxOrder.sol";
import {IGmxPosition} from "../../../interfaces/gmx/IGmxPosition.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {OutsidePositionWithdrawalHelper} from "../OutsidePositionWithdrawalHelper.sol";
import {GmxPriceLib} from "../../../utils/gmx/GmxPriceLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Guard} from "../ERC20Guard.sol";
import {IPoolFactory} from "../../../interfaces/IPoolFactory.sol";
import {GmxPosition} from "../../../utils/gmx/GmxPosition.sol";
import {GmxClaimableCollateralTrackerLib} from "../../../utils/gmx/GmxClaimableCollateralTrackerLib.sol";
import {GmxPositionCollateralAmountLib} from "../../../utils/gmx/GmxPositionCollateralAmountLib.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {GmxStructs} from "../../../utils/gmx/GmxStructs.sol";

/// @notice AssetType = 105
contract GmxPerpMarketAssetGuard is OutsidePositionWithdrawalHelper, ERC20Guard, IAddAssetCheckGuard {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using SafeCast for int256;
  using GmxDataStoreLib for IGmxDataStore;

  bytes32 private constant CLAIMABLE_FUNDING_AMOUNT_DATA_STORE_KEY = keccak256(abi.encode("CLAIMABLE_FUNDING_AMOUNT"));
  bytes32 private constant ACCOUNT_DEPOSIT_LIST = keccak256(abi.encode("ACCOUNT_DEPOSIT_LIST"));
  bytes32 private constant ACCOUNT_WITHDRAWAL_LIST = keccak256(abi.encode("ACCOUNT_WITHDRAWAL_LIST"));

  address public immutable gmxExchangeRouter;
  bool public override isAddAssetCheckGuard = true;

  constructor(address _gmxExchangeRouter) {
    gmxExchangeRouter = _gmxExchangeRouter;
  }

  struct GmxGuardData {
    IGmxDataStore dataStore;
    IGmxReader reader;
    address assetHandler;
    address uiFeeReceiver;
    DhedgeNftTrackerStorage nftTracker;
    IGmxReferralStorage referralStorage;
  }

  function addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _asset) external view override {
    require(!_asset.isDeposit, "deposit not supported");
    GmxStructs.PoolSetting memory poolSetting = _useContractGuard(IPoolLogic(_poolLogic).factory())
      .dHedgePoolsWhitelist(_poolLogic);
    require(poolSetting.poolLogic == _poolLogic, "not gmx whitelisted");
  }

  /// @notice Returns the balance of GMX perp leverage positions
  /// @dev Returns the balance to be priced in USD
  /// @param _pool PoolLogic address
  /// @param _asset Asset address (GMX perp market address)
  /// @return balance GMX perp market balance of the pool
  function getBalance(
    address _pool,
    address _asset
  ) public view override(OutsidePositionWithdrawalHelper, ERC20Guard) returns (uint256 balance) {
    address poolFactory = IPoolLogic(_pool).factory();
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(IPoolLogic(_pool).poolManagerLogic());
    GmxGuardData memory guardData;
    GmxPriceLib.GmxPriceDependecies memory priceDependencies;
    {
      IGmxExchangeRouterContractGuard contractguard = _useContractGuard(poolFactory);
      // avoid stack too deep error
      guardData = GmxGuardData({
        dataStore: contractguard.dataStore(),
        reader: contractguard.reader(),
        assetHandler: IPoolFactory(poolFactory).getAssetHandler(),
        uiFeeReceiver: contractguard.feeReceiver(),
        nftTracker: contractguard.nftTracker(),
        referralStorage: IGmxReferralStorage(contractguard.referralStorage())
      });
      priceDependencies = GmxPriceLib.GmxPriceDependecies({
        reader: guardData.reader,
        dataStore: guardData.dataStore,
        assetHandler: guardData.assetHandler,
        virtualTokenResolver: contractguard
      });
    }
    IGmxMarket.Props memory market = guardData.reader.getMarket({_dataStore: guardData.dataStore, _market: _asset});

    // 1. Collateral in the GMX positions, taking into account price impact and profit/loss
    // select positions for the market and collateralAmount > 0
    IGmxPosition.Props[] memory marketPositions = getPositionsForMarket(
      _pool,
      guardData.reader,
      guardData.dataStore,
      _asset
    );

    if (marketPositions.length > 0) {
      bytes32[] memory positionKeys = new bytes32[](marketPositions.length);
      IGmxMarket.MarketPrices memory currentMarketPrices = IGmxMarket.MarketPrices({
        indexTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.indexToken),
        longTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.longToken),
        shortTokenPrice: GmxPriceLib.getTokenMinMaxPrice(priceDependencies, market.shortToken)
      });
      IGmxMarket.MarketPrices[] memory marketPrices = new IGmxMarket.MarketPrices[](marketPositions.length);
      for (uint256 i; i < marketPositions.length; i++) {
        marketPrices[i] = currentMarketPrices;
        positionKeys[i] = GmxPosition.getPositionKey(
          _pool,
          _asset,
          marketPositions[i].addresses.collateralToken,
          marketPositions[i].flags.isLong
        );
      }

      IGmxPosition.PositionInfo[] memory positionInfos = guardData.reader.getPositionInfoList({
        _dataStore: guardData.dataStore,
        _referralStorage: guardData.referralStorage,
        _positionKeys: positionKeys,
        _marketPrices: marketPrices,
        _uiFeeReceiver: guardData.uiFeeReceiver
      });

      // Collateral in the GMX positions, taking into account price impact and profit/loss
      for (uint256 i; i < positionInfos.length; i++) {
        IGmxPosition.PositionInfo memory positionInfo = positionInfos[i];
        uint256 collateralAmount = GmxPositionCollateralAmountLib.getPositionCollateralAmount(positionInfo);
        if (collateralAmount > 0) {
          balance = balance.add(
            _assetValue(poolManagerLogic, positionInfo.position.addresses.collateralToken, collateralAmount)
          );
        }
      }
    }

    // 2. Pending orders: deposited collateral in market increase orders, plus execution fees of all orders
    Order.Props[] memory orders = guardData.reader.getAccountOrders({
      _account: _pool,
      _dataStore: guardData.dataStore,
      _start: 0,
      _end: type(uint256).max
    });

    for (uint256 i; i < orders.length; i++) {
      Order.Props memory order = orders[i];

      if (
        (order.numbers.orderType == Order.OrderType.MarketIncrease && order.addresses.market == _asset) ||
        (order.numbers.orderType == Order.OrderType.MarketSwap && order.addresses.swapPath[0] == _asset) // swapPath length is always 1 for swapOrders
      ) {
        balance = balance.add(
          _assetValue(
            poolManagerLogic,
            order.addresses.initialCollateralToken,
            order.numbers.initialCollateralDeltaAmount
          )
        );
      }
      if (
        (order.numbers.executionFee > 0 && order.addresses.market == _asset) ||
        (order.numbers.executionFee > 0 && order.addresses.swapPath[0] == _asset) // swap order
      ) {
        balance = balance.add(_assetValue(poolManagerLogic, guardData.dataStore.wnt(), order.numbers.executionFee));
      }
    }

    // 3. Funding fees that can be claimed
    uint256 fundingFeesLongToken = _getClaimableFundingFees({
      _dataStore: guardData.dataStore,
      _pool: _pool,
      _market: market.marketToken,
      _token: market.longToken
    });

    if (fundingFeesLongToken != 0) {
      balance = balance.add(_assetValue(poolManagerLogic, market.longToken, fundingFeesLongToken));
    }

    if (market.longToken != market.shortToken) {
      uint256 fundingFeesShortToken = _getClaimableFundingFees({
        _dataStore: guardData.dataStore,
        _pool: _pool,
        _market: market.marketToken,
        _token: market.shortToken
      });

      if (fundingFeesShortToken != 0) {
        balance = balance.add(_assetValue(poolManagerLogic, market.shortToken, fundingFeesShortToken));
      }
    }

    // 4. Collateral in a deposit vault
    bytes32[] memory depositKeys = guardData.dataStore.getBytes32ValuesAt(
      keccak256(abi.encode(ACCOUNT_DEPOSIT_LIST, _pool)),
      0,
      type(uint256).max
    );

    for (uint256 i; i < depositKeys.length; i++) {
      IGmxDeposit.Props memory deposit = guardData.reader.getDeposit({
        _dataStore: guardData.dataStore,
        key: depositKeys[i]
      });
      balance = balance.add(_assetValue(poolManagerLogic, guardData.dataStore.wnt(), deposit.numbers.executionFee));
      balance = balance.add(
        _assetValue(poolManagerLogic, deposit.addresses.initialLongToken, deposit.numbers.initialLongTokenAmount)
      );
      balance = balance.add(
        _assetValue(poolManagerLogic, deposit.addresses.initialShortToken, deposit.numbers.initialShortTokenAmount)
      );
    }

    // 5. LP token balance
    uint256 lpTokenBalance = IERC20(_asset).balanceOf(_pool);
    if (lpTokenBalance > 0) {
      balance = balance.add(
        GmxPriceLib.getMarketLpTokenPrice(priceDependencies, market, false).mul(lpTokenBalance).div(1e18)
      );
    }

    // 6. Market tokens in a withdrawal vault
    balance = balance.add(_balanceWithdrawalVault(_pool, poolManagerLogic, market, priceDependencies));

    // 7. claimable collateral
    balance = balance.add(_balanceClaimableCollateral(_pool, poolManagerLogic, market, guardData));
  }

  /// @notice Returns the decimals of Flat Money leverage positions
  /// @return decimals Decimals of the asset
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Creates transaction data for withdrawing from GMX leverage positions
  /// @dev Leverage position portion is being withdrawn using specially configured asset sitting in the pool outside
  /// @param _pool PoolLogic address
  /// @param _asset Asset address (GMX perp market address)
  /// @param _withdrawPortion Portion to withdraw
  /// @return withdrawAsset Asset address to withdraw
  /// @return withdrawBalance Amount to withdraw
  /// @return transactions Transactions to be executed
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    GmxStructs.PoolSetting memory poolSetting = _useContractGuard(IPoolLogic(_pool).factory()).dHedgePoolsWhitelist(
      _pool
    );

    (withdrawAsset, withdrawBalance, transactions) = _withdrawProcessing(
      _pool,
      _asset,
      _withdrawPortion,
      poolSetting.withdrawalAsset
    );
  }

  function _useContractGuard(
    address _poolFactory
  ) internal view returns (IGmxExchangeRouterContractGuard contractguard) {
    contractguard = IGmxExchangeRouterContractGuard(IHasGuardInfo(_poolFactory).getContractGuard(gmxExchangeRouter));
  }

  function _getClaimableFundingFees(
    IGmxDataStore _dataStore,
    address _pool,
    address _market,
    address _token
  ) internal view returns (uint256 claimableFundingFees) {
    claimableFundingFees = _dataStore.getUint(
      keccak256(abi.encode(CLAIMABLE_FUNDING_AMOUNT_DATA_STORE_KEY, _market, _token, _pool))
    );
  }

  function _assetValue(
    IPoolManagerLogic _poolManagerLogic,
    address _token,
    uint256 _amount
  ) internal view returns (uint256 assetValue) {
    assetValue = _poolManagerLogic.assetValue(_token, _amount);
  }

  function getPositionsForMarket(
    address _account,
    IGmxReader _reader,
    IGmxDataStore _dataStore,
    address _market
  ) internal view returns (IGmxPosition.Props[] memory marketPositions) {
    IGmxPosition.Props[] memory positions = _reader.getAccountPositions({
      _account: _account,
      _dataStore: _dataStore,
      _start: 0,
      _end: type(uint256).max
    });
    marketPositions = new IGmxPosition.Props[](positions.length);
    uint256 index = 0;

    for (uint256 i; i < positions.length; i++) {
      if (positions[i].numbers.collateralAmount > 0 && positions[i].addresses.market == _market) {
        marketPositions[index] = positions[i];
        index++;
      }
    }

    uint256 reduceLength = positions.length.sub(index);
    assembly {
      mstore(marketPositions, sub(mload(marketPositions), reduceLength))
    }
  }

  function _balanceWithdrawalVault(
    address _pool,
    IPoolManagerLogic _poolManagerLogic,
    IGmxMarket.Props memory _market,
    GmxPriceLib.GmxPriceDependecies memory _priceDependencies
  ) internal view returns (uint256 balance) {
    bytes32[] memory withdrawalKeys = _priceDependencies.dataStore.getBytes32ValuesAt(
      keccak256(abi.encode(ACCOUNT_WITHDRAWAL_LIST, _pool)),
      0,
      type(uint256).max
    );

    for (uint256 i; i < withdrawalKeys.length; i++) {
      IGmxWithdrawal.Props memory withdrawal = _priceDependencies.reader.getWithdrawal({
        _dataStore: _priceDependencies.dataStore,
        key: withdrawalKeys[i]
      });
      balance = balance.add(
        _assetValue(_poolManagerLogic, _priceDependencies.dataStore.wnt(), withdrawal.numbers.executionFee)
      );
      balance = balance.add(
        GmxPriceLib
          .getMarketLpTokenPrice(_priceDependencies, _market, false)
          .mul(withdrawal.numbers.marketTokenAmount)
          .div(1e18)
      );
    }
  }

  function _balanceClaimableCollateral(
    address _pool,
    IPoolManagerLogic _poolManagerLogic,
    IGmxMarket.Props memory _market,
    GmxGuardData memory _guardData
  ) internal view returns (uint256 balance) {
    balance = _assetValue(
      _poolManagerLogic,
      _market.longToken,
      GmxClaimableCollateralTrackerLib.getTotalClaimableAmount(
        address(_guardData.nftTracker),
        address(_guardData.dataStore),
        GmxClaimableCollateralTrackerLib.ClaimableCollateralInfo({
          market: _market.marketToken,
          token: _market.longToken,
          account: _pool
        })
      )
    );
    if (_market.longToken != _market.shortToken) {
      balance = balance.add(
        _assetValue(
          _poolManagerLogic,
          _market.shortToken,
          GmxClaimableCollateralTrackerLib.getTotalClaimableAmount(
            address(_guardData.nftTracker),
            address(_guardData.dataStore),
            GmxClaimableCollateralTrackerLib.ClaimableCollateralInfo({
              market: _market.marketToken,
              token: _market.shortToken,
              account: _pool
            })
          )
        )
      );
    }
  }
}
