// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";
import {GmxPerpMarketAssetGuard} from "contracts/guards/assetGuards/gmx/GmxPerpMarketAssetGuard.sol";
import {GmxExchangeRouterContractGuard} from "contracts/guards/contractGuards/gmx/GmxExchangeRouterContractGuard.sol";
import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {GmxTestSharedData} from "test/integration/arbitrum/gmx/GmxTestSharedData.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";

contract GmxTestDryRunArbitrum is DeploymentDryRunArbitrum, IntegrationDeployer {
  constructor() DeploymentDryRunArbitrum(GmxTestSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    this.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);
  }

  function getTorosVaults() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](19);
    torosVaults[0] = ArbitrumConfig.BTCBULL3X;
    torosVaults[1] = ArbitrumConfig.BTCBULL2X;
    torosVaults[2] = ArbitrumConfig.BTCBEAR1X;
    torosVaults[3] = ArbitrumConfig.ETHBULL3X;
    torosVaults[4] = ArbitrumConfig.ETHBULL2X;
    torosVaults[5] = ArbitrumConfig.ETHBEAR1X;
    torosVaults[6] = ArbitrumConfig.SOLBULL3X;
    torosVaults[7] = ArbitrumConfig.SOLBULL2X;
    torosVaults[8] = ArbitrumConfig.SOLBEAR1X;
    torosVaults[9] = ArbitrumConfig.USDy;
    torosVaults[10] = ArbitrumConfig.ETHy;
    torosVaults[11] = ArbitrumConfig.BTCBULL4X;
    torosVaults[12] = ArbitrumConfig.ETHBULL4X;
    torosVaults[13] = ArbitrumConfig.BTCy;
    torosVaults[14] = ArbitrumConfig.SUIBULL2X;
    torosVaults[15] = ArbitrumConfig.SUI1X;
    torosVaults[16] = ArbitrumConfig.SOL1X;
    torosVaults[17] = ArbitrumConfig.DOGEBULL2X;
    torosVaults[18] = ArbitrumConfig.DOGE1X;

    return torosVaults;
  }

  function deployIntegration(
    PoolFactory _poolFactory,
    address _nftTracker,
    address _slippageAccumulator,
    address /* _usdPriceAggregator */
  ) external override {
    Governance governance = Governance(_poolFactory.governanceAddress());
    AssetHandler assetHandler = AssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    GmxExchangeRouterContractGuard gmxExchangeRouterContractGuard = new GmxExchangeRouterContractGuard(
      GmxTestSharedData.getGmxContractGuardConfig(),
      GmxTestSharedData.getDHedgeVaultsWhitelist(),
      GmxTestSharedData.getVirtualTokenResolver(),
      _slippageAccumulator,
      _nftTracker
    );

    governance.setContractGuard(GmxTestSharedData.GMX_EXCHANGE_ROUTER, address(gmxExchangeRouterContractGuard));

    GmxPerpMarketAssetGuard gmxPerpMarketAssetGuard = new GmxPerpMarketAssetGuard(
      GmxTestSharedData.GMX_EXCHANGE_ROUTER
    );
    governance.setAssetGuard(GmxTestSharedData.GMX_PEPRS_MARKET_ASSET_TYPE, address(gmxPerpMarketAssetGuard));

    AssetHandler.Asset[] memory assets = GmxTestSharedData.getAdditonalAssetSetupData();
    assetHandler.addAssets(assets);
    vm.stopPrank();
  }
}
