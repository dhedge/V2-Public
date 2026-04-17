// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PlasmaConfig} from "test/integration/utils/foundry/config/PlasmaConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {BackboneSetup} from "../BackboneSetup.t.sol";

abstract contract PlasmaSetup is BackboneSetup {
  uint256 public forkBlockNumber;

  constructor(
    uint256 _forkBlockNumber
  )
    BackboneSetup(
      IAssetHandler.Asset({
        asset: PlasmaConfig.USDT, // USDT is used instead of USDC on Plasma, mind it might cause issues in tests
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: PlasmaConfig.USDT_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: PlasmaConfig.WETH,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: PlasmaConfig.WETH_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: PlasmaConfig.USDe, // USDe is used instead of DAI on Plasma, mind it might cause issues in tests
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: PlasmaConfig.USDe_CHAINLINK_ORACLE
      })
    )
  {
    forkBlockNumber = _forkBlockNumber;
  }

  function setUp() public virtual override {
    vm.createSelectFork("plasma", forkBlockNumber);

    super.setUp();
  }
}
