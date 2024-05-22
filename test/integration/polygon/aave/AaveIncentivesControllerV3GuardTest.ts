import { expect } from "chai";
import { ethers } from "hardhat";

import { polygonChainData } from "../../../../config/chainData/polygonData";
import versionsUntyped from "../../../../publish/polygon/prod/versions.json";
import { IVersions } from "../../../../deployment/types";
import { IAaveIncentivesControllerV3__factory } from "../../../../types";
import { utils } from "../../utils/utils";
import { IERC20Path } from "../../utils/deployContracts/deployBackboneContracts";

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const POOL_TO_TEST = "0x46b1adc3b1ca80ae3c003649efae4039544f02e9"; // https://dhedge.org/vault/0x46b1adc3b1ca80ae3c003649efae4039544f02e9 AlgoTraveler MATIC
const POOL_TO_TEST_ADDRESSES_PARAMS = [
  "0x80cA0d8C38d2e2BcbaB66aA1648Bd1C7160500FE",
  "0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8",
  "0xEA1132120ddcDDA2F119e99Fa7A27a0d036F7Ac9",
];
const REWARD_TOKEN_ADDRESS = polygonChainData.assets.stMatic;

describe("Polygon AaveIncentivesControllerV3Guard Test", () => {
  utils.beforeAfterReset(beforeEach, afterEach);

  it("should allow claiming rewards from Aave V3 RewardsController", async () => {
    const poolLogic = await ethers.getContractAt("PoolLogic", POOL_TO_TEST);
    const poolManagerLogicAddress = await poolLogic.poolManagerLogic();

    const poolManagerLogic = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);
    const poolManager = await utils.impersonateAccount(await poolManagerLogic.manager());

    const executeClaimRewardsTx = () =>
      poolLogic
        .connect(poolManager)
        .execTransaction(
          polygonChainData.aaveV3.incentivesController,
          new ethers.utils.Interface(IAaveIncentivesControllerV3__factory.abi).encodeFunctionData("claimRewards", [
            POOL_TO_TEST_ADDRESSES_PARAMS,
            ethers.constants.MaxUint256,
            poolLogic.address,
            REWARD_TOKEN_ADDRESS,
          ]),
        );

    await expect(executeClaimRewardsTx()).to.be.revertedWith("invalid transaction");

    const AaveIncentivesControllerV3Guard = await ethers.getContractFactory("AaveIncentivesControllerV3Guard");
    const aaveIncentivesControllerV3Guard = await AaveIncentivesControllerV3Guard.deploy();
    await aaveIncentivesControllerV3Guard.deployed();

    const governance = await ethers.getContractAt("Governance", versions[latestVersion].contracts.Governance);
    const owner = await utils.impersonateAccount(await governance.owner());
    await governance
      .connect(owner)
      .setContractGuard(polygonChainData.aaveV3.incentivesController, aaveIncentivesControllerV3Guard.address);

    const rewardToken = await ethers.getContractAt(IERC20Path, REWARD_TOKEN_ADDRESS);
    expect(await rewardToken.balanceOf(poolLogic.address)).to.be.eq(0);

    await executeClaimRewardsTx();

    expect(await rewardToken.balanceOf(poolLogic.address)).to.be.gt(0);
  });
});
