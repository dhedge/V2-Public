// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {FlatMoneyV2PerpMarketTestOptimism} from "test/integration/ovm/flatMoney/FlatMoneyV2PerpMarketTestOptimism.t.sol";
import {FlatMoneyV2PerpMarketTestSharedData} from "test/integration/ovm/flatMoney/FlatMoneyV2PerpMarketTestSharedData.sol";
import {DeploymentDryRunOptimism} from "test/integration/utils/foundry/dryRun/DeploymentDryRunOptimism.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {Governance} from "contracts/Governance.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";
import {ERC20Guard} from "contracts/guards/assetGuards/ERC20Guard.sol";
import {AaveLendingPoolGuardV3L2Pool} from "contracts/guards/contractGuards/AaveLendingPoolGuardV3L2Pool.sol";

contract FlatMoneyV2PerpMarketDryRunOptimism is DeploymentDryRunOptimism {
  constructor() DeploymentDryRunOptimism(FlatMoneyV2PerpMarketTestSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    FlatMoneyV2PerpMarketTestOptimism flatMoneyV2PerpMarketTest = new FlatMoneyV2PerpMarketTestOptimism();
    flatMoneyV2PerpMarketTest.setUp();
    // Here WBTC asset type is being changed from 4 to 22
    flatMoneyV2PerpMarketTest.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);

    Governance governance = Governance(poolFactory.governanceAddress());
    vm.startPrank(poolFactory.owner());

    AaveLendingPoolAssetGuard aaveLendingPoolAssetGuard = new AaveLendingPoolAssetGuard(
      OptimismConfig.AAVE_V3_LENDING_POOL,
      OptimismConfig.SWAPPER,
      OptimismConfig.LEGACY_ONCHAIN_SWAP_ROUTER,
      address(0),
      address(0),
      1,
      10000,
      10000
    );
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.AAVE_V3), address(aaveLendingPoolAssetGuard));

    ERC20Guard erc20Guard = new ERC20Guard();
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), address(erc20Guard));
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.SNX_SYNTH), address(erc20Guard));
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.LENDING_ENABLED), address(erc20Guard));
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.SNX_SYNTH_LENDING_ENABLED), address(erc20Guard));

    AaveLendingPoolGuardV3L2Pool aaveLendingPoolGuardV3L2Pool = new AaveLendingPoolGuardV3L2Pool();
    governance.setContractGuard(OptimismConfig.AAVE_V3_LENDING_POOL, address(aaveLendingPoolGuardV3L2Pool));
  }

  function getTorosVaults() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](11);
    torosVaults[0] = OptimismConfig.ETHBULL3X;
    torosVaults[1] = OptimismConfig.ETHBULL2X;
    torosVaults[2] = OptimismConfig.ETHBEAR1X;
    torosVaults[3] = OptimismConfig.BTCBEAR1X;
    torosVaults[4] = OptimismConfig.USDy;
    torosVaults[5] = OptimismConfig.ETHy;
    torosVaults[6] = OptimismConfig.USDmny;
    torosVaults[7] = OptimismConfig.USDpy;
    torosVaults[8] = OptimismConfig.BTCBULL4X;
    torosVaults[9] = OptimismConfig.BTCBULL3X;
    torosVaults[10] = OptimismConfig.BTCBULL2X;

    return torosVaults;
  }
}
