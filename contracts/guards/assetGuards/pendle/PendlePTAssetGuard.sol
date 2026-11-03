// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPMarket} from "../../../interfaces/pendle/IPMarket.sol";
import {IStandardizedYield} from "../../../interfaces/pendle/IStandardizedYield.sol";
import {ERC20Guard} from "../ERC20Guard.sol";
import {AddAssetCheckGuard} from "../shared/AddAssetCheckGuard.sol";

/// @notice Core features are identical to ERC20Guard, with the addition of onchain storage for
///         PT associated data, to workaround unrolling PTs during single asset withdrawals.
/// @dev Asset type = 37
contract PendlePTAssetGuard is ERC20Guard, AddAssetCheckGuard {
  struct PTAssociatedData {
    address market;
    address yieldToken;
    address yt;
  }

  mapping(address => PTAssociatedData) public ptAssociatedData;

  constructor(address[] memory _knownPendleMarkets) {
    for (uint256 i; i < _knownPendleMarkets.length; ++i) {
      require(_knownPendleMarkets[i] != address(0), "invalid market");

      (address sy, address pt, address yt) = IPMarket(_knownPendleMarkets[i]).readTokens();

      ptAssociatedData[pt] = PTAssociatedData({
        market: _knownPendleMarkets[i],
        yieldToken: IStandardizedYield(sy).yieldToken(),
        yt: yt
      });
    }
  }

  function _addAssetCheck(address, IHasSupportedAsset.Asset calldata _asset) internal view override {
    PTAssociatedData memory ptData = ptAssociatedData[_asset.asset];

    require(ptData.market != address(0), "unknown PT");
  }
}
