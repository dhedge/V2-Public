// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGmxMarket} from "../../interfaces/gmx/IGmxMarket.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IGmxExchangeRouterContractGuard} from "../../interfaces/gmx/IGmxExchangeRouterContractGuard.sol";
import {Order} from "../../interfaces/gmx/IGmxOrder.sol";
import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";
import {GmxDataStoreLib} from "./GmxDataStoreLib.sol";
import {IGmxDeposit} from "../../interfaces/gmx/IGmxDeposit.sol";

library GmxHelperLib {
  using GmxDataStoreLib for IGmxDataStore;
  function checkMarketsAndTokensSupportedForClaiming(
    address exchangeRouterContractGuard,
    address poolManagerLogic,
    address[] memory tokens,
    address[] memory markets
  ) public view {
    require(tokens.length == markets.length, "invalid length");
    for (uint256 i; i < tokens.length; ++i) {
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(markets[i]), "invalid market");
      IGmxMarket.Props memory marketInfo = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard)
        .reader()
        .getMarket({
          _dataStore: IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore(),
          _market: markets[i]
        });
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(markets[i]), "invalid market");
      require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(tokens[i]), "unsupported token");
      require(tokens[i] == marketInfo.longToken || tokens[i] == marketInfo.shortToken, "invalid token");
    }
  }

  function validateCancelOrder(
    address exchangeRouterContractGuard,
    address poolManagerLogic,
    bytes memory params
  ) external view {
    IGmxDataStore dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
    bytes32 key = abi.decode(params, (bytes32));
    Order.Props memory order = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).reader().getOrder(
      dataStore,
      key
    );
    require(
      IHasSupportedAsset(poolManagerLogic).isSupportedAsset(order.addresses.initialCollateralToken),
      "unsupported token"
    );
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(dataStore.wnt()), "unsupported wnt");
  }

  function validateCancelDeposit(
    address exchangeRouterContractGuard,
    address poolManagerLogic,
    bytes memory params
  ) external view {
    IGmxDataStore dataStore = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).dataStore();
    bytes32 key = abi.decode(params, (bytes32));
    IGmxDeposit.Props memory deposit = IGmxExchangeRouterContractGuard(exchangeRouterContractGuard).reader().getDeposit(
      dataStore,
      key
    );
    require(
      IHasSupportedAsset(poolManagerLogic).isSupportedAsset(deposit.addresses.initialLongToken),
      "unsupported token"
    );
    require(
      IHasSupportedAsset(poolManagerLogic).isSupportedAsset(deposit.addresses.initialShortToken),
      "unsupported token"
    );
    require(IHasSupportedAsset(poolManagerLogic).isSupportedAsset(dataStore.wnt()), "unsupported wnt");
  }
}
