import { ethers } from "hardhat";
import { Address } from "../../../../deployment-scripts/types";
import { IDeployments } from "../../utils/deployContracts/deployContracts";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { utils } from "../../utils/utils";

export const deployArrakis = async (
  deployments: IDeployments,
  arrakisData: {
    v1RouterStaking: Address;
    usdcWethGauge: Address;
  },
) => {
  const ArrakisV1RouterStakingGuard = await ethers.getContractFactory("ArrakisV1RouterStakingGuard");
  const arrakisV1RouterStakingGuard = await ArrakisV1RouterStakingGuard.deploy();
  await arrakisV1RouterStakingGuard.deployed();

  const ArrakisLiquidityGaugeV4ContractGuard = await ethers.getContractFactory("ArrakisLiquidityGaugeV4ContractGuard");
  const arrakisLiquidityGaugeV4Guard = await ArrakisLiquidityGaugeV4ContractGuard.deploy();
  await arrakisLiquidityGaugeV4Guard.deployed();

  const ArrakisLiquidityGaugeV4AssetGuard = await ethers.getContractFactory("ArrakisLiquidityGaugeV4AssetGuard");
  const arrakisLiquidityGaugeV4AssetGuard = await ArrakisLiquidityGaugeV4AssetGuard.deploy(arrakisData.v1RouterStaking);
  await arrakisLiquidityGaugeV4AssetGuard.deployed();

  await deployments.governance.setAssetGuard(9, arrakisLiquidityGaugeV4AssetGuard.address);

  await deployments.governance.setContractGuard(arrakisData.v1RouterStaking, arrakisV1RouterStakingGuard.address);
  await deployments.governance.setContractGuard(arrakisData.usdcWethGauge, arrakisLiquidityGaugeV4Guard.address);

  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  const asset = assetSetting(arrakisData.usdcWethGauge, 9, usdPriceAggregator.address);
  deployments.assetHandler.addAssets([asset]);
};

export const arrakisRewardsFinished = async (usdcWethGauge: Address, rewardsTokenAddress: Address) => {
  const gauge = await ethers.getContractAt("ILiquidityGaugeV4", usdcWethGauge);
  const rewardsTokenRewardData = await gauge.reward_data(rewardsTokenAddress);
  return (
    rewardsTokenRewardData.period_finish.lt(await utils.currentBlockTimestamp()) || rewardsTokenRewardData.rate.eq(0)
  );
};
