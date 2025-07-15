// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {SkyPSM3ContractGuardTestSetup} from "test/integration/common/sky/SkyPSM3ContractGuardTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";

contract SkyPSM3ContractGuardTestBase is SkyPSM3ContractGuardTestSetup, BaseSetup {
  uint256 private testForkBlockNumber = 27176457;
  address private skyPSM3 = 0x1601843c5E9bC251A3272907010AFa41Fa18347E;
  address private susdsUsdsPriceAggregator = 0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E;

  IAssetHandler.Asset private usdsData =
    IAssetHandler.Asset({
      asset: 0x820C137fa70C8691f0e44Dc420a5e53c168921Dc,
      assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
      aggregator: 0x2330aaE3bca5F05169d5f4597964D44522F62930
    });

  IAssetHandler.Asset private susdsData =
    IAssetHandler.Asset({
      asset: 0x5875eEE11Cf8398102FdAd704C9E96607675467a,
      assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
      aggregator: address(0) // need to deploy it in the test
    });

  constructor()
    SkyPSM3ContractGuardTestSetup(skyPSM3, usdsData, susdsData, susdsUsdsPriceAggregator)
    BaseSetup(testForkBlockNumber)
  {}

  function setUp() public override(SkyPSM3ContractGuardTestSetup, BaseSetup) {
    super.setUp();
  }
}
