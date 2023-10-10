import { ethers } from "hardhat";

import { IBackboneDeployments, IERC20Path } from "../../utils/deployContracts/deployBackboneContracts";
import { assetSetting, deployBalancerV2LpAggregator } from "../../utils/deployContracts/getChainAssets";
import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { IERC20 } from "../../../../types";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

/*
  These helpers are not chain agnostic yet, but they are chain specific.
  Can be refactored to be chain agnostic if needed.
*/

const balancerV2VaultAddress = arbitrumChainData.balancer.v2Vault;

export const deployBalancerGuards = async (deployments: IBackboneDeployments): Promise<string> => {
  const BalancerV2GaugeAssetGuard = await ethers.getContractFactory("BalancerV2GaugeAssetGuard");
  const balancerV2GaugeAssetGuard = await BalancerV2GaugeAssetGuard.deploy();
  await balancerV2GaugeAssetGuard.deployed();
  await deployments.governance.setAssetGuard(10, balancerV2GaugeAssetGuard.address);

  const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
  const balancerV2Guard = await BalancerV2Guard.deploy(deployments.slippageAccumulator.address);
  await balancerV2Guard.deployed();
  await deployments.governance.setContractGuard(balancerV2VaultAddress, balancerV2Guard.address);

  const BalancerV2GaugeContractGuard = await ethers.getContractFactory("BalancerV2GaugeContractGuard");
  const balancerV2GaugeContractGuard = await BalancerV2GaugeContractGuard.deploy();
  await balancerV2GaugeContractGuard.deployed();

  await deployments.governance.setContractGuard(
    arbitrumChainData.balancer.stable.wstETH_WETH.gauge,
    balancerV2GaugeContractGuard.address,
  );
  return balancerV2VaultAddress;
};

export const deployBalancerAssets = async (deployments: IBackboneDeployments) => {
  const BalancerStablePoolAggregator = await ethers.getContractFactory("BalancerStablePoolAggregator");
  const balancerStablePoolAggregator = await BalancerStablePoolAggregator.deploy(
    deployments.poolFactory.address,
    arbitrumChainData.balancer.stable.wstETH_WETH.pool,
  );
  await balancerStablePoolAggregator.deployed();

  const ETHCrossAggregator = await ethers.getContractFactory("ETHCrossAggregator");
  const ethCrossAggregator = await ETHCrossAggregator.deploy(
    arbitrumChainData.assets.wsteth,
    arbitrumChainData.ethPriceFeeds.wsteth,
    arbitrumChainData.usdPriceFeeds.eth,
  );
  await ethCrossAggregator.deployed();

  const balancerV2LPAggregator = await deployBalancerV2LpAggregator(
    deployments.poolFactory,
    arbitrumChainData.balancer.weighted.wstETH_USDC.pool,
  );
  await balancerV2LPAggregator.deployed();

  await deployments.assetHandler.addAssets([
    assetSetting(arbitrumChainData.assets.wsteth, AssetType["Lending Enable Asset"], ethCrossAggregator.address),
    assetSetting(arbitrumChainData.assets.bal, AssetType["Lending Enable Asset"], arbitrumChainData.usdPriceFeeds.bal),
    assetSetting(
      arbitrumChainData.balancer.stable.wstETH_WETH.pool,
      AssetType["Balancer LP"],
      balancerStablePoolAggregator.address,
    ),
    assetSetting(
      arbitrumChainData.balancer.stable.wstETH_WETH.gauge,
      AssetType["Balancer V2 Gauge Asset"],
      deployments.usdPriceAggregator.address,
    ),
    assetSetting(
      arbitrumChainData.balancer.weighted.wstETH_USDC.pool,
      AssetType["Balancer LP"],
      balancerV2LPAggregator.address,
    ),
  ]);

  const BAL = <IERC20>await ethers.getContractAt(IERC20Path, arbitrumChainData.assets.bal);
  const wstETH = <IERC20>await ethers.getContractAt(IERC20Path, arbitrumChainData.assets.wsteth);
  const wstETH_WETH_STABLE_POOL = await ethers.getContractAt(
    "IBalancerPool",
    arbitrumChainData.balancer.stable.wstETH_WETH.pool,
  );
  const wstETH_WETH_STABLE_POOL_GAUGE = await ethers.getContractAt(
    "IRewardsOnlyGauge",
    arbitrumChainData.balancer.stable.wstETH_WETH.gauge,
  );
  const wstETH_USDC_WEIGHTED_POOL = await ethers.getContractAt(
    "IBalancerWeightedPool",
    arbitrumChainData.balancer.weighted.wstETH_USDC.pool,
  );

  return {
    BAL,
    wstETH,
    wstETH_WETH_STABLE_POOL,
    wstETH_WETH_STABLE_POOL_GAUGE,
    wstETH_USDC_WEIGHTED_POOL,
  };
};
