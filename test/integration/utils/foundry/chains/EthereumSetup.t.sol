// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {BackboneSetup} from "../BackboneSetup.t.sol";

abstract contract EthereumSetup is BackboneSetup {
  uint256 public forkBlockNumber;

  constructor(
    uint256 _forkBlockNumber
  )
    BackboneSetup(
      IAssetHandler.Asset({
        asset: EthereumConfig.USDC,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: EthereumConfig.USDC_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: EthereumConfig.WETH,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: EthereumConfig.WETH_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: EthereumConfig.DAI,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: EthereumConfig.DAI_CHAINLINK_ORACLE
      })
    )
  {
    forkBlockNumber = _forkBlockNumber;
  }

  function setUp() public virtual override {
    vm.createSelectFork("ethereum", forkBlockNumber);

    super.setUp();
  }
}
