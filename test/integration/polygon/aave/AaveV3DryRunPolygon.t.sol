// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestPolygon, AaveV3TestPolygonSharedData} from "test/integration/polygon/aave/AaveV3TestPolygon.t.sol";
import {DeploymentDryRunPolygon} from "test/integration/utils/foundry/dryRun/DeploymentDryRunPolygon.t.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {Governance} from "contracts/Governance.sol";

contract AaveV3DryRunPolygon is DeploymentDryRunPolygon {
  constructor() DeploymentDryRunPolygon(AaveV3TestPolygonSharedData.FORK_BLOCK_NUMBER, getVaultsToCheck()) {}

  function setUp() public override {
    super.setUp();

    AaveV3TestPolygon aaveV3Test = new AaveV3TestPolygon();
    aaveV3Test.setUp();
    aaveV3Test.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);

    // Extra steps not included in `deployIntegration`:
    address latestPoolLogic = address(new PoolLogic());
    address latestPoolManagerLogic = address(new PoolManagerLogic());
    Governance governance = Governance(poolFactory.governanceAddress());
    vm.startPrank(poolFactory.owner());
    poolFactory.setLogic(latestPoolLogic, latestPoolManagerLogic);
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.LENDING_ENABLED), aaveV3Test.erc20Guard());
  }

  function getVaultsToCheck() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](4);
    torosVaults[0] = PolygonConfig.BTCBULL3X;
    torosVaults[1] = PolygonConfig.ETHBULL3X;
    torosVaults[2] = 0x6aABe7861FfbCFBE8c6D925971DE2C69A381136d; // Formadores Wealth Growth
    torosVaults[3] = 0x82ad6ed56B110De24518CE0AC0E6196dd23558Ab; // Xeron

    return torosVaults;
  }
}
