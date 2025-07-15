// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {SkyPSM3ContractGuardTestSetup} from "test/integration/common/sky/SkyPSM3ContractGuardTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract SkyPSM3ContractGuardTestArbitrum is SkyPSM3ContractGuardTestSetup, ArbitrumSetup {
  uint256 private testForkBlockNumber = 319124600;
  address private skyPSM3 = 0x2B05F8e1cACC6974fD79A673a341Fe1f58d27266;
  address private susdsUsdsPriceAggregator = 0x84AB0c8C158A1cD0d215BE2746cCa668B79cc287;

  IAssetHandler.Asset private usdsData =
    IAssetHandler.Asset({
      asset: 0x6491c05A82219b8D1479057361ff1654749b876b,
      assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
      aggregator: 0x37833E5b3fbbEd4D613a3e0C354eF91A42B81eeB
    });

  IAssetHandler.Asset private susdsData =
    IAssetHandler.Asset({
      asset: 0xdDb46999F8891663a8F2828d25298f70416d7610,
      assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
      aggregator: address(0) // need to deploy it in the test
    });

  constructor()
    SkyPSM3ContractGuardTestSetup(skyPSM3, usdsData, susdsData, susdsUsdsPriceAggregator)
    ArbitrumSetup(testForkBlockNumber)
  {}

  function setUp() public override(SkyPSM3ContractGuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
