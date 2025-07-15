// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {AaveV3TestOptimism, AaveV3TestOptimismSharedData} from "test/integration/ovm/aaveV3/AaveV3TestOptimism.t.sol";
import {DeploymentDryRunOptimism} from "test/integration/utils/foundry/dryRun/DeploymentDryRunOptimism.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {Governance} from "contracts/Governance.sol";
import {FlatMoneyCollateralAssetGuard} from "contracts/guards/assetGuards/flatMoney/FlatMoneyCollateralAssetGuard.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";

contract AaveV3DryRunOptimism is DeploymentDryRunOptimism {
  constructor() DeploymentDryRunOptimism(AaveV3TestOptimismSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    AaveV3TestOptimism aaveV3Test = new AaveV3TestOptimism();
    aaveV3Test.setUp();
    aaveV3Test.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);

    // Extra steps not included in `deployIntegration`:
    address latestPoolLogic = address(new PoolLogic());
    address latestPoolManagerLogic = address(new PoolManagerLogic());
    address latestPoolFactory = address(new PoolFactory());
    FlatMoneyCollateralAssetGuard flatMoneyCollateralGuard = new FlatMoneyCollateralAssetGuard(
      OptimismConfig.FLAT_MONEY_V2_ORDER_ANNOUNCEMENT_MODULE
    );
    Governance governance = Governance(poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(poolFactory.getAssetHandler());
    vm.startPrank(poolFactory.owner());
    proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(poolFactory))), latestPoolFactory);
    poolFactory.setLogic(latestPoolLogic, latestPoolManagerLogic);
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.SNX_SYNTH), aaveV3Test.erc20Guard());
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.LENDING_ENABLED), aaveV3Test.erc20Guard());
    governance.setAssetGuard(
      uint16(BackboneSetup.AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      address(flatMoneyCollateralGuard)
    );
    assetHandler.addAsset(
      OptimismConfig.WBTC,
      uint16(BackboneSetup.AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      OptimismConfig.WBTC_CHAINLINK_ORACLE
    );
    assetHandler.addAsset(
      OptimismConfig.sUSD,
      uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK),
      0xcD139d422824A79109890e95F7e9a389B5704Bfe // TWAP currently set to sUSD
    );
  }

  function getTorosVaults() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](11);
    torosVaults[0] = OptimismConfig.BTCBULL4X;
    torosVaults[1] = OptimismConfig.BTCBULL3X;
    torosVaults[2] = OptimismConfig.BTCBULL2X;
    torosVaults[3] = OptimismConfig.BTCBEAR1X;
    torosVaults[4] = OptimismConfig.ETHBULL3X;
    torosVaults[5] = OptimismConfig.ETHBULL2X;
    torosVaults[6] = OptimismConfig.ETHBEAR1X;
    torosVaults[7] = OptimismConfig.USDy;
    torosVaults[8] = OptimismConfig.ETHy;
    torosVaults[9] = OptimismConfig.USDmny;
    torosVaults[10] = OptimismConfig.USDpy;

    return torosVaults;
  }
}
