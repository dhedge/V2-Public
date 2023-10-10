import { ethers, upgrades } from "hardhat";

import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { IBackboneDeployments, IERC20Path } from "../../utils/deployContracts/deployBackboneContracts";
import { DhedgeNftTrackerStorage, IERC20, IERC721Enumerable, IERC20__factory } from "../../../../types";
import { getAccountToken } from "../../utils/getAccountTokens";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

const deploymentParams = {
  assets: {
    snx: {
      address: ovmChainData.assets.snxProxy,
      usdPriceFeed: ovmChainData.price_feeds.snx,
      balanceOfSlot: ovmChainData.assetsBalanceOfSlot.snx,
      proxyTargetTokenState: ovmChainData.synthetix.SNXProxy_target_tokenState,
    },
    snxUSD: {
      address: ovmChainData.assets.snxUSD,
      usdPriceFeed: ovmChainData.price_feeds.susd, // Using sUSD price feed for snxUSD
    },
  },
  allowedLiquidityPoolId: 1,
  synthetixV3Core: ovmChainData.synthetix.v3Core,
  synthetixAccountNFT: ovmChainData.synthetix.accountNFT,
};

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

export const deploySynthethixV3Infrastructure = async (deployments: IBackboneDeployments) => {
  const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
  const dhedgeNftTrackerStorage = <DhedgeNftTrackerStorage>(
    await upgrades.deployProxy(DhedgeNftTrackerStorage, [deployments.poolFactory.address])
  );
  await dhedgeNftTrackerStorage.deployed();

  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  await usdPriceAggregator.deployed();

  await deployments.assetHandler.addAssets([
    assetSetting(
      deploymentParams.assets.snx.address,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      deploymentParams.assets.snx.usdPriceFeed,
    ),
    assetSetting(
      deploymentParams.assets.snxUSD.address,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      deploymentParams.assets.snxUSD.usdPriceFeed,
    ),
    assetSetting(
      deploymentParams.synthetixV3Core,
      AssetType["Synthetix V3 Position Asset"],
      usdPriceAggregator.address,
    ),
  ]);

  const supportedAssets = [
    {
      asset: deploymentParams.assets.snx.address,
      isDeposit: true,
    },
    {
      asset: deploymentParams.assets.snxUSD.address,
      isDeposit: true,
    },
    {
      asset: deploymentParams.synthetixV3Core,
      isDeposit: false,
    },
  ];
  const poolProxies = await createFund(
    deployments.poolFactory,
    deployments.owner,
    deployments.manager,
    supportedAssets,
    {
      performance: ethers.constants.Zero,
      management: ethers.constants.Zero,
    },
  );

  const SynthetixV3ContractGuard = await ethers.getContractFactory("SynthetixV3ContractGuard");
  const synthetixV3ContractGuard = await SynthetixV3ContractGuard.deploy(
    deploymentParams.assets.snx.address,
    deploymentParams.allowedLiquidityPoolId,
    deploymentParams.assets.snxUSD.address,
    dhedgeNftTrackerStorage.address,
    [poolProxies.poolLogicProxy.address],
  );
  await synthetixV3ContractGuard.deployed();

  await deployments.governance.setContractGuard(deploymentParams.synthetixV3Core, synthetixV3ContractGuard.address);

  const SynthetixV3AssetGuard = await ethers.getContractFactory("SynthetixV3AssetGuard");
  const synthetixV3AssetGuard = await SynthetixV3AssetGuard.deploy();
  await synthetixV3AssetGuard.deployed();

  const assetType = AssetType["Synthetix V3 Position Asset"];
  await deployments.governance.setAssetGuard(assetType, synthetixV3AssetGuard.address);

  const SNX = <IERC20>await ethers.getContractAt(IERC20Path, deploymentParams.assets.snx.address);
  const snxUSD = <IERC20>await ethers.getContractAt(IERC20Path, deploymentParams.assets.snxUSD.address);
  const accountNFT = <IERC721Enumerable>(
    await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol:IERC721Enumerable",
      deploymentParams.synthetixAccountNFT,
    )
  );
  // Fund logic owner with 100_000 SNX
  const TOTAL_SNX_AMOUNT = units(100_000);
  await getAccountToken(
    TOTAL_SNX_AMOUNT,
    deployments.owner.address,
    deploymentParams.assets.snx.proxyTargetTokenState,
    deploymentParams.assets.snx.balanceOfSlot,
  );
  // Deposit 10_000 SNX into pool
  const SNX_AMOUNT = units(10_000);
  await SNX.approve(poolProxies.poolLogicProxy.address, SNX_AMOUNT);
  await poolProxies.poolLogicProxy.deposit(deploymentParams.assets.snx.address, SNX_AMOUNT);
  // Manager approves SNX to be spent by SynthetixV3Core
  await poolProxies.poolLogicProxy
    .connect(deployments.manager)
    .execTransaction(
      deploymentParams.assets.snx.address,
      iERC20.encodeFunctionData("approve", [deploymentParams.synthetixV3Core, SNX_AMOUNT]),
    );

  return {
    whitelistedPool: poolProxies,
    SNX,
    snxUSD,
    synthetixV3CoreAddress: deploymentParams.synthetixV3Core,
    accountNFT,
    dhedgeNftTrackerStorage,
    allowedLiquidityPoolId: deploymentParams.allowedLiquidityPoolId,
    synthetixV3AssetGuardAddress: synthetixV3AssetGuard.address,
    snxBalanceInPool: SNX_AMOUNT,
    synthetixV3ContractGuard,
    iERC20,
  };
};
