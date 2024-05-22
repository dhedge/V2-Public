import { ethers, upgrades } from "hardhat";

import { createFund } from "../../utils/createFund";
import { IBackboneDeployments, IERC20Path } from "../../utils/deployContracts/deployBackboneContracts";
import { DhedgeNftTrackerStorage, IERC20, IERC721Enumerable, IERC20__factory } from "../../../../types";
import { getAccountToken, transferTokensFromExistingAddress } from "../../utils/getAccountTokens";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { ISynthetixV3TestsParams } from "./SynthetixV3Test";
import { VaultSettingStruct } from "../../../../types/SynthetixV3ContractGuard";
import { units } from "../../../testHelpers";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

// Windows that don't make sense to make tests pass
const FAKE_WINDOWS = {
  delegationWindow: {
    start: {
      dayOfWeek: 1,
      hour: 0,
    },
    end: {
      dayOfWeek: 7,
      hour: 23,
    },
  },
  undelegationWindow: {
    start: {
      dayOfWeek: 1,
      hour: 0,
    },
    end: {
      dayOfWeek: 7,
      hour: 23,
    },
  },
};

// Windows for testing real periods
const REAL_WINDOWS = {
  delegationWindow: {
    start: {
      dayOfWeek: 2,
      hour: 0,
    },
    end: {
      dayOfWeek: 4,
      hour: 12,
    },
  },
  undelegationWindow: {
    start: {
      dayOfWeek: 4,
      hour: 12,
    },
    end: {
      dayOfWeek: 5,
      hour: 0,
    },
  },
};

// $50k and 10%
const PROD_WITHDRAWAL_LIMIT = { usdValue: units(50_000), percent: units(1, 17) };
// $50 and 10%
const TEST_WITHDRAWAL_LIMIT = { usdValue: units(50), percent: units(1, 17) };

export const deploySynthethixV3Infrastructure = async (
  deployments: IBackboneDeployments,
  deploymentParams: ISynthetixV3TestsParams,
) => {
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
      deploymentParams.systemAssets.collateral.address,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      deploymentParams.systemAssets.collateral.usdPriceFeed,
    ),
    assetSetting(
      deploymentParams.systemAssets.debt.address,
      AssetType["Chainlink direct USD price feed with 8 decimals"],
      deploymentParams.systemAssets.debt.usdPriceFeed,
    ),
    assetSetting(
      deploymentParams.synthetixV3Core,
      AssetType["Synthetix V3 Position Asset"],
      usdPriceAggregator.address,
    ),
  ]);

  if (deploymentParams.systemAssets.tokenToCollateral) {
    await deployments.assetHandler.addAssets([
      assetSetting(
        deploymentParams.systemAssets.tokenToCollateral.address,
        AssetType["Chainlink direct USD price feed with 8 decimals"],
        deploymentParams.systemAssets.tokenToCollateral.usdPriceFeed,
      ),
    ]);
  }

  if (deploymentParams.systemAssets.extraRewardTokens) {
    await deployments.assetHandler.addAssets(
      deploymentParams.systemAssets.extraRewardTokens.map(({ address, usdPriceFeed }) =>
        assetSetting(address, AssetType["Chainlink direct USD price feed with 8 decimals"], usdPriceFeed),
      ),
    );
  }

  const assets = [
    {
      asset: deploymentParams.systemAssets.collateral.address,
      isDeposit: true,
    },
    {
      asset: deploymentParams.systemAssets.debt.address,
      isDeposit: true,
    },
    {
      asset: deploymentParams.synthetixV3Core,
      isDeposit: false,
    },
  ];
  const supportedAssets = deploymentParams.systemAssets.tokenToCollateral
    ? [
        ...assets,
        {
          asset: deploymentParams.systemAssets.tokenToCollateral.address,
          isDeposit: true,
        },
      ]
    : assets;
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

  const WeeklyWindowsHelper = await ethers.getContractFactory("WeeklyWindowsHelper");
  const weeklyWindowsHelper = await WeeklyWindowsHelper.deploy();
  await weeklyWindowsHelper.deployed();
  const SynthetixV3ContractGuard = await ethers.getContractFactory("SynthetixV3ContractGuard", {
    libraries: {
      WeeklyWindowsHelper: weeklyWindowsHelper.address,
    },
  });
  const coreContractGuardParams: [string, VaultSettingStruct[], string] = [
    dhedgeNftTrackerStorage.address,
    [
      {
        poolLogic: poolProxies.poolLogicProxy.address,
        collateralAsset: deploymentParams.systemAssets.collateral.address,
        debtAsset: deploymentParams.systemAssets.debt.address,
        snxLiquidityPoolId: deploymentParams.allowedLiquidityPoolId,
      },
    ],
    deploymentParams.synthetixV3Core,
  ];
  // This is to test core guard logic, but do not care about periods when specific actions are allowed (fake weekly windows params)
  const synthetixV3ContractGuard = await SynthetixV3ContractGuard.deploy(
    ...coreContractGuardParams,
    FAKE_WINDOWS,
    PROD_WITHDRAWAL_LIMIT,
  );
  await synthetixV3ContractGuard.deployed();
  // This is to test guard logic related to weekly windows, thus production windows params are used
  const synthetixV3ContractGuardWithRealWindows = await SynthetixV3ContractGuard.deploy(
    ...coreContractGuardParams,
    REAL_WINDOWS,
    PROD_WITHDRAWAL_LIMIT,
  );
  await synthetixV3ContractGuardWithRealWindows.deployed();
  // This is only to test "undelegation limit breached" revert, when total value of the vault to test is too low for the production limit values
  const synthetixV3ContractGuardWithTestWithdrawalParams = await SynthetixV3ContractGuard.deploy(
    ...coreContractGuardParams,
    REAL_WINDOWS,
    TEST_WITHDRAWAL_LIMIT,
  );
  await synthetixV3ContractGuardWithTestWithdrawalParams.deployed();

  await deployments.governance.setContractGuard(deploymentParams.synthetixV3Core, synthetixV3ContractGuard.address);

  const SynthetixV3SpotMarketContractGuard = await ethers.getContractFactory("SynthetixV3SpotMarketContractGuard");
  const synthetixV3SpotMarketContractGuard = await SynthetixV3SpotMarketContractGuard.deploy(
    deploymentParams.synthetixV3Core,
    deploymentParams.synthetixV3SpotMarket,
    deploymentParams.allowedMarketIds,
  );
  await synthetixV3SpotMarketContractGuard.deployed();

  await deployments.governance.setContractGuard(
    deploymentParams.synthetixV3SpotMarket,
    synthetixV3SpotMarketContractGuard.address,
  );

  const SynthetixV3AssetGuard = await ethers.getContractFactory("SynthetixV3AssetGuard");
  const synthetixV3AssetGuard = await SynthetixV3AssetGuard.deploy(deploymentParams.synthetixV3SpotMarket);
  await synthetixV3AssetGuard.deployed();

  const assetType = AssetType["Synthetix V3 Position Asset"];
  await deployments.governance.setAssetGuard(assetType, synthetixV3AssetGuard.address);

  const COLLATERAL_ASSET = <IERC20>(
    await ethers.getContractAt(IERC20Path, deploymentParams.systemAssets.collateral.address)
  );
  const DEBT_ASSET = <IERC20>await ethers.getContractAt(IERC20Path, deploymentParams.systemAssets.debt.address);
  const accountNFT = <IERC721Enumerable>(
    await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol:IERC721Enumerable",
      deploymentParams.synthetixAccountNFT,
    )
  );

  await deployments.poolFactory.setExitCooldown(0);

  // Fund owner with collateral
  if (deploymentParams.collateralSource === "setBalance") {
    await getAccountToken(
      deploymentParams.systemAssets.collateral.ownerBalanceTotal,
      deployments.owner.address,
      deploymentParams.systemAssets.collateral.proxyTargetTokenState,
      deploymentParams.systemAssets.collateral.balanceOfSlot,
    );
  } else if (deploymentParams.collateralSource === "transferFrom" && deploymentParams.transferCollateralFrom) {
    await transferTokensFromExistingAddress(
      deploymentParams.transferCollateralFrom,
      deployments.owner.address,
      deploymentParams.systemAssets.collateral.address,
      deploymentParams.systemAssets.collateral.ownerBalanceTotal,
    );
  }
  // Deposit collateral into dhedge pool
  await COLLATERAL_ASSET.approve(
    poolProxies.poolLogicProxy.address,
    deploymentParams.systemAssets.collateral.balanceToThePool,
  );
  await poolProxies.poolLogicProxy.deposit(
    deploymentParams.systemAssets.collateral.address,
    deploymentParams.systemAssets.collateral.balanceToThePool,
  );
  // Manager approves collateral to be spent by SynthetixV3Core
  await poolProxies.poolLogicProxy
    .connect(deployments.manager)
    .execTransaction(
      deploymentParams.systemAssets.collateral.address,
      iERC20.encodeFunctionData("approve", [
        deploymentParams.synthetixV3Core,
        deploymentParams.systemAssets.collateral.balanceToThePool,
      ]),
    );

  return {
    whitelistedPool: poolProxies,
    COLLATERAL_ASSET,
    DEBT_ASSET,
    synthetixV3CoreAddress: deploymentParams.synthetixV3Core,
    accountNFT,
    dhedgeNftTrackerStorage,
    allowedLiquidityPoolId: deploymentParams.allowedLiquidityPoolId,
    synthetixV3AssetGuardAddress: synthetixV3AssetGuard.address,
    collateralBalanceInPool: deploymentParams.systemAssets.collateral.balanceToThePool,
    collateralBalanceInOwner: deploymentParams.systemAssets.collateral.ownerBalanceTotal.sub(
      deploymentParams.systemAssets.collateral.balanceToThePool,
    ),
    synthetixV3ContractGuard,
    iERC20,
    synthetixV3ContractGuardWithRealWindows,
    weeklyWindowsHelper,
    synthetixV3ContractGuardWithTestWithdrawalParams,
  };
};
