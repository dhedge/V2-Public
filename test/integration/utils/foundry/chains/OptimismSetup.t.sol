// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {BackboneSetup} from "../BackboneSetup.t.sol";

abstract contract OptimismSetup is BackboneSetup {
  uint256 public forkBlockNumber;

  constructor(
    uint256 _forkBlockNumber
  )
    BackboneSetup(
      IAssetHandler.Asset({
        asset: OptimismConfig.USDC,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: OptimismConfig.USDC_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: OptimismConfig.WETH,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: OptimismConfig.WETH_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: OptimismConfig.DAI,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: OptimismConfig.DAI_CHAINLINK_ORACLE
      })
    )
  {
    forkBlockNumber = _forkBlockNumber;
  }

  function setUp() public virtual override {
    vm.createSelectFork("optimism", forkBlockNumber);

    super.setUp();
  }
}
