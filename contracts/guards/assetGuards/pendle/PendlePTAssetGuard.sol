// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IPMarketFactoryV3} from "../../../interfaces/pendle/IPMarketFactoryV3.sol";
import {IPMarket} from "../../../interfaces/pendle/IPMarket.sol";
import {IStandardizedYield} from "../../../interfaces/pendle/IStandardizedYield.sol";
import {ERC20Guard} from "../ERC20Guard.sol";

/// @notice Core features are identical to ERC20Guard, with the addition of onchain storage for PT associated data, to workaround unrolling PTs during single assset withdrawals
/// @dev Asset type = 37
contract PendlePTAssetGuard is ERC20Guard, IAddAssetCheckGuard {
  struct PTAssociatedData {
    address market;
    address yieldToken;
    address yt;
  }

  bool public override isAddAssetCheckGuard = true;

  IPMarketFactoryV3 public immutable pendleMarketFactoryV3;

  mapping(address => PTAssociatedData) public ptAssociatedData;

  constructor(address _pendleMarketFactoryV3, address[] memory _knownPendleMarkets) {
    require(_pendleMarketFactoryV3 != address(0), "invalid market factory");

    pendleMarketFactoryV3 = IPMarketFactoryV3(_pendleMarketFactoryV3);

    for (uint256 i; i < _knownPendleMarkets.length; ++i) {
      require(IPMarketFactoryV3(_pendleMarketFactoryV3).isValidMarket(_knownPendleMarkets[i]), "invalid market");

      (address sy, address pt, address yt) = IPMarket(_knownPendleMarkets[i]).readTokens();

      ptAssociatedData[pt] = PTAssociatedData({
        market: _knownPendleMarkets[i],
        yieldToken: IStandardizedYield(sy).yieldToken(),
        yt: yt
      });
    }
  }

  function addAssetCheck(address, IHasSupportedAsset.Asset calldata _asset) external view override {
    PTAssociatedData memory ptData = ptAssociatedData[_asset.asset];

    require(ptData.market != address(0), "unknown PT");
  }
}
