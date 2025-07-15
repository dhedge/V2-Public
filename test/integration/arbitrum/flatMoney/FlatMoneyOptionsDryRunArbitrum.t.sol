// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {FlatMoneyOptionsTestArbitrum} from "test/integration/arbitrum/flatMoney/FlatMoneyOptionsTestArbitrum.t.sol";
import {FlatMoneyOptionsTestSharedData} from "test/integration/arbitrum/flatMoney/FlatMoneyOptionsTestSharedData.sol";
import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {Governance} from "contracts/Governance.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";

contract FlatMoneyOptionsDryRunArbitrum is DeploymentDryRunArbitrum {
  constructor() DeploymentDryRunArbitrum(FlatMoneyOptionsTestSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    FlatMoneyOptionsTestArbitrum flatMoneyOptionsTestArbitrum = new FlatMoneyOptionsTestArbitrum();
    flatMoneyOptionsTestArbitrum.setUp();
    flatMoneyOptionsTestArbitrum.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);

    Governance governance = Governance(poolFactory.governanceAddress());
    vm.startPrank(poolFactory.owner());

    AaveLendingPoolAssetGuard aaveLendingPoolAssetGuard = new AaveLendingPoolAssetGuard(
      ArbitrumConfig.AAVE_V3_LENDING_POOL,
      ArbitrumConfig.SWAPPER,
      ArbitrumConfig.LEGACY_ONCHAIN_SWAP_ROUTER,
      address(0),
      address(0),
      1,
      10000,
      10000
    );
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.AAVE_V3), address(aaveLendingPoolAssetGuard));
  }

  function getTorosVaults() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](10);
    torosVaults[0] = ArbitrumConfig.ETHBULL3X;
    torosVaults[1] = ArbitrumConfig.ETHBULL2X;
    torosVaults[2] = ArbitrumConfig.ETHBEAR1X;
    torosVaults[3] = ArbitrumConfig.BTCBULL3X;
    torosVaults[4] = ArbitrumConfig.BTCBULL2X;
    torosVaults[5] = ArbitrumConfig.BTCBEAR1X;
    torosVaults[6] = ArbitrumConfig.SOLBULL3X;
    torosVaults[7] = ArbitrumConfig.SOLBULL2X;
    torosVaults[8] = ArbitrumConfig.USDy;
    torosVaults[9] = ArbitrumConfig.ETHy;

    return torosVaults;
  }
}
