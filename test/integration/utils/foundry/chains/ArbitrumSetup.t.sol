// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {BackboneSetup} from "../BackboneSetup.t.sol";

abstract contract ArbitrumSetup is BackboneSetup {
  uint256 public forkBlockNumber;

  constructor(
    uint256 _forkBlockNumber
  )
    BackboneSetup(
      IAssetHandler.Asset({
        asset: ArbitrumConfig.USDC,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: ArbitrumConfig.USDC_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: ArbitrumConfig.WETH,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: ArbitrumConfig.WETH_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: ArbitrumConfig.DAI,
        assetType: uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
        aggregator: ArbitrumConfig.DAI_CHAINLINK_ORACLE
      })
    )
  {
    forkBlockNumber = _forkBlockNumber;
  }

  function setUp() public virtual override {
    vm.createSelectFork("arbitrum", forkBlockNumber);

    super.setUp();
  }
}
