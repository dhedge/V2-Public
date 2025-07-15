// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {BackboneSetup} from "../BackboneSetup.t.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";

abstract contract PolygonSetup is BackboneSetup {
  uint256 public forkBlockNumber;

  constructor(
    uint256 _forkBlockNumber
  )
    BackboneSetup(
      IAssetHandler.Asset({
        asset: PolygonConfig.USDC,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: PolygonConfig.USDC_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: PolygonConfig.WETH,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: PolygonConfig.WETH_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: PolygonConfig.DAI,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: PolygonConfig.DAI_CHAINLINK_ORACLE
      })
    )
  {
    forkBlockNumber = _forkBlockNumber;
  }

  function setUp() public virtual override {
    vm.createSelectFork("polygon", forkBlockNumber);

    super.setUp();
  }
}
