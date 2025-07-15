import { ethers, network } from "hardhat";
import { baseChainData } from "../../../../config/chainData/baseData";
import { VaultSettingStruct } from "../../../../types/SynthetixV3ContractGuard";
import { FAKE_WINDOWS, PROD_WITHDRAWAL_LIMIT } from "../../common/synthetixV3/synthetixV3TestDeploymentHelpers";
import { IERC721Enumerable, IRewardsManagerModule, IRewardsManagerModule__factory } from "../../../../types";
import { expect } from "chai";
import { getBalance } from "../../utils/getAccountTokens";

const poolToTest = baseChainData.torosPools.sUSDCy;
const distributorsData = [
  {
    distributor: "0x7A1b3DB73E5B8c58EDC8A821890005064f2B83Fd",
    allowedPoolId: 1,
    collateralType: baseChainData.assets.susdc,
    rewardToken: baseChainData.assets.snx,
  },
  {
    distributor: "0xa7163fE9788BF14CcDac854131CAc2C17d1a1676",
    allowedPoolId: 1,
    collateralType: baseChainData.assets.susdc,
    rewardToken: baseChainData.assets.usdc,
  },
];

const IRewardsManagerModule = new ethers.utils.Interface(IRewardsManagerModule__factory.abi);

describe("onchain claim test", () => {
  it("can claim pool reward", async function () {
    // onchain prod pools tested in the test environment

    // fix for https://github.com/NomicFoundation/hardhat/issues/5511#issuecomment-2223269012
    await ethers.provider.send("evm_mine", []);

    const poolLogic = await ethers.getContractAt("PoolLogic", poolToTest);
    const poolManagerLogicAddress = await poolLogic.poolManagerLogic();
    const poolManagerLogic = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);
    const factoryAddress = await poolManagerLogic.factory();
    const factory = await ethers.getContractAt("PoolFactory", factoryAddress);
    const governance = await ethers.getContractAt("Governance", await factory.governanceAddress());
    const governaceOwner = await governance.owner();

    // set up synthetixV3Core guard for claimPoolReward
    const currentGuard = await governance.contractGuards(baseChainData.synthetixV3.core);
    const realWhiteListParams = await (
      await ethers.getContractAt("SynthetixV3ContractGuard", currentGuard)
    ).dHedgeVaultsWhitelist(poolLogic.address);
    const realNftracker = await (await ethers.getContractAt("SynthetixV3ContractGuard", currentGuard)).nftTracker();
    const WeeklyWindowsHelper = await ethers.getContractFactory("WeeklyWindowsHelper");
    const weeklyWindowsHelper = await WeeklyWindowsHelper.deploy();
    await weeklyWindowsHelper.deployed();
    const SynthetixV3ContractGuard = await ethers.getContractFactory("SynthetixV3ContractGuard", {
      libraries: {
        WeeklyWindowsHelper: weeklyWindowsHelper.address,
      },
    });
    const coreContractGuardParams: [string, VaultSettingStruct[], string] = [
      realNftracker,
      [
        {
          poolLogic: realWhiteListParams.poolLogic,
          collateralAsset: realWhiteListParams.collateralAsset,
          debtAsset: realWhiteListParams.debtAsset,
          snxLiquidityPoolId: realWhiteListParams.snxLiquidityPoolId,
        },
      ],
      baseChainData.synthetixV3.core,
    ];
    const synthetixV3ContractGuard = await SynthetixV3ContractGuard.deploy(
      ...coreContractGuardParams,
      FAKE_WINDOWS,
      PROD_WITHDRAWAL_LIMIT,
    );
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [governaceOwner],
    });
    const ownerSigner = await ethers.getSigner(governaceOwner);
    await network.provider.send("hardhat_setBalance", [ownerSigner.address, "0x100000000000000"]);

    // set contract guards
    await governance
      .connect(ownerSigner)
      .setContractGuard(baseChainData.synthetixV3.core, synthetixV3ContractGuard.address);

    const managerAddress = await poolManagerLogic.manager();

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [managerAddress],
    });
    const poolManagerSigner = await ethers.getSigner(managerAddress);
    await network.provider.send("hardhat_setBalance", [poolManagerSigner.address, "0x100000000000000"]);
    await network.provider.send("evm_mine", []); // Just mines to the next block
    const accountNFT = <IERC721Enumerable>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol:IERC721Enumerable",
        baseChainData.synthetixV3.accountNFT,
      )
    );
    const accountId = await accountNFT.tokenOfOwnerByIndex(poolLogic.address, 0);

    const snxV3Core = <IRewardsManagerModule>(
      await ethers.getContractAt(IRewardsManagerModule__factory.abi, baseChainData.synthetixV3.core)
    );
    for (const { distributor, allowedPoolId, collateralType, rewardToken } of distributorsData || []) {
      const rewardAmount = await snxV3Core.callStatic.getAvailablePoolRewards(
        accountId,
        allowedPoolId,
        collateralType,
        distributor,
      );

      console.log("rewardAmount", rewardAmount.toString());
      expect(rewardAmount).to.be.gt(0);
      const balanceOfRewardTokenBefore = await getBalance(poolLogic.address, rewardToken);

      // claim reward
      await poolLogic
        .connect(poolManagerSigner)
        .execTransaction(
          baseChainData.synthetixV3.core,
          IRewardsManagerModule.encodeFunctionData("claimPoolRewards", [
            accountId,
            allowedPoolId,
            collateralType,
            distributor,
          ]),
        );

      const balanceOfRewardTokenAfter = await getBalance(poolLogic.address, rewardToken);
      expect(balanceOfRewardTokenAfter).to.be.gt(balanceOfRewardTokenBefore);
    }
  });
});
