// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestBase, AaveV3TestBaseSharedData} from "test/integration/base/aaveV3/AaveV3TestBase.t.sol";
import {DeploymentDryRunBase} from "test/integration/utils/foundry/dryRun/DeploymentDryRunBase.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {Governance} from "contracts/Governance.sol";
import {FlatMoneyCollateralAssetGuard} from "contracts/guards/assetGuards/flatMoney/FlatMoneyCollateralAssetGuard.sol";
import {RewardAssetGuard} from "contracts/guards/assetGuards/RewardAssetGuard.sol";

contract AaveV3DryRunBase is DeploymentDryRunBase {
  constructor() DeploymentDryRunBase(AaveV3TestBaseSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    AaveV3TestBase aaveV3Test = new AaveV3TestBase();
    aaveV3Test.setUp();
    aaveV3Test.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);

    // Extra steps not included in `deployIntegration`:
    address latestPoolLogic = address(new PoolLogic());
    address latestPoolManagerLogic = address(new PoolManagerLogic());
    FlatMoneyCollateralAssetGuard flatMoneyCollateralGuard = new FlatMoneyCollateralAssetGuard(
      BaseConfig.FLAT_MONEY_V1_DELAYED_ORDER
    );
    RewardAssetGuard.RewardAssetSetting[] memory rewardAssetSettings = new RewardAssetGuard.RewardAssetSetting[](1);
    uint16[] memory linkedAssetTypes = new uint16[](2);
    linkedAssetTypes[0] = uint16(BackboneSetup.AssetTypeIncomplete.VELODROME_V2_LP);
    linkedAssetTypes[1] = uint16(BackboneSetup.AssetTypeIncomplete.VELODROME_CL);
    rewardAssetSettings[0] = RewardAssetGuard.RewardAssetSetting({
      rewardToken: BaseConfig.AERO,
      linkedAssetTypes: linkedAssetTypes,
      linkedAssets: new address[](0)
    });
    RewardAssetGuard rewardAssetGuard = new RewardAssetGuard(rewardAssetSettings);
    Governance governance = Governance(poolFactory.governanceAddress());
    vm.startPrank(poolFactory.owner());
    poolFactory.setLogic(latestPoolLogic, latestPoolManagerLogic);
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.LENDING_ENABLED), aaveV3Test.erc20Guard());
    governance.setAssetGuard(
      uint16(BackboneSetup.AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      address(flatMoneyCollateralGuard)
    );
    governance.setAssetGuard(200, address(rewardAssetGuard));
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
