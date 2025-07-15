// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {BackboneSetup} from "../BackboneSetup.t.sol";

abstract contract BaseSetup is BackboneSetup {
  uint256 public forkBlockNumber;

  constructor(
    uint256 _forkBlockNumber
  )
    BackboneSetup(
      IAssetHandler.Asset({
        asset: BaseConfig.USDC,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: BaseConfig.USDC_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: BaseConfig.WETH,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: BaseConfig.WETH_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: BaseConfig.DAI,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: BaseConfig.DAI_CHAINLINK_ORACLE
      })
    )
  {
    forkBlockNumber = _forkBlockNumber;
  }

  function setUp() public virtual override {
    vm.createSelectFork("base", forkBlockNumber);

    super.setUp();
  }
}
