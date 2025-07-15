// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestBaseUSR} from "test/integration/base/pendle/PendlePrincipalTokenTestBaseUSR.t.sol";
import {PendlePrincipalTokenTestSharedData} from "test/integration/base/pendle/PendlePrincipalTokenTestSharedData.sol";
import {DeploymentDryRunBase} from "test/integration/utils/foundry/dryRun/DeploymentDryRunBase.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";

contract PendlePrincipalTokenDryRunBase is DeploymentDryRunBase {
  constructor() DeploymentDryRunBase(PendlePrincipalTokenTestSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    PendlePrincipalTokenTestBaseUSR pendlePTTestBaseUSR = new PendlePrincipalTokenTestBaseUSR();
    pendlePTTestBaseUSR.setUp();
    pendlePTTestBaseUSR.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);
  }

  function getTorosVaults() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](9);
    torosVaults[0] = BaseConfig.BTCBULL3X;
    torosVaults[1] = BaseConfig.BTCBULL2X;
    torosVaults[2] = BaseConfig.BTCBEAR1X;
    torosVaults[3] = BaseConfig.STETHBULL4X;
    torosVaults[4] = BaseConfig.STETHBULL3X;
    torosVaults[5] = BaseConfig.STETHBULL2X;
    torosVaults[6] = BaseConfig.USDy;
    torosVaults[7] = BaseConfig.ETHy;
    torosVaults[8] = BaseConfig.USDmny;

    return torosVaults;
  }
}
