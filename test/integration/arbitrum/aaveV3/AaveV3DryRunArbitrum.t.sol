// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {AaveV3TestArbitrum, AaveV3TestArbitrumSharedData} from "test/integration/arbitrum/aaveV3/AaveV3TestArbitrum.t.sol";
import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {Governance} from "contracts/Governance.sol";
import {FlatMoneyCollateralAssetGuard} from "contracts/guards/assetGuards/flatMoney/FlatMoneyCollateralAssetGuard.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";

contract AaveV3DryRunArbitrum is DeploymentDryRunArbitrum {
  constructor() DeploymentDryRunArbitrum(AaveV3TestArbitrumSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    AaveV3TestArbitrum aaveV3Test = new AaveV3TestArbitrum();
    aaveV3Test.setUp();
    aaveV3Test.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);

    // Extra steps not included in `deployIntegration`:
    address latestPoolLogic = address(new PoolLogic());
    address latestPoolManagerLogic = address(new PoolManagerLogic());
    address latestPoolFactory = address(new PoolFactory());
    FlatMoneyCollateralAssetGuard flatMoneyCollateralGuard = new FlatMoneyCollateralAssetGuard(
      ArbitrumConfig.FLAT_MONEY_V2_ORDER_ANNOUNCEMENT_MODULE
    );
    Governance governance = Governance(poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(poolFactory.getAssetHandler());
    vm.startPrank(poolFactory.owner());
    proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(poolFactory))), latestPoolFactory);
    poolFactory.setLogic(latestPoolLogic, latestPoolManagerLogic);
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.LENDING_ENABLED), aaveV3Test.erc20Guard());
    governance.setAssetGuard(
      uint16(BackboneSetup.AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      address(flatMoneyCollateralGuard)
    );
    assetHandler.addAsset(
      ArbitrumConfig.WBTC,
      uint16(BackboneSetup.AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      0x092e0dA71bbbF4f32749719ac3f42B294ebeCc3d // ChainlinkPythPriceAggregator currently set to WBTC
    );
    assetHandler.addAsset(
      ArbitrumConfig.USDC,
      uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
      0x16228Fcd5c9231486C6A02911d0B0627ab4436D9 // ChainlinkPythPriceAggregator currently set to USDC
    );
  }

  function getTorosVaults() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](18);
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
    torosVaults[11] = ArbitrumConfig.ETHBULL4X;
    torosVaults[12] = ArbitrumConfig.BTCBULL4X;
    torosVaults[13] = ArbitrumConfig.SUIBULL2X;
    torosVaults[14] = ArbitrumConfig.SUI1X;
    torosVaults[15] = ArbitrumConfig.SOL1X;
    torosVaults[16] = ArbitrumConfig.BTCy;
    torosVaults[17] = ArbitrumConfig.DOGEBULL2X;

    return torosVaults;
  }
}
