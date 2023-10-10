import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IBalancerMerkleOrchard__factory, IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { createFund } from "../../utils/createFund";
import { polygonChainData } from "../../../../config/chainData/polygonData";
const { assets, assetsBalanceOfSlot, balancer } = polygonChainData;
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";

describe("Balancer V2 Rewards Claiming Test", function () {
  let USDC: IERC20, BALANCER: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iBalancerMerkleOrchard = new ethers.utils.Interface(IBalancerMerkleOrchard__factory.abi);

  let snapId: string;
  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();

    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    BALANCER = deployments.assets.BALANCER!;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(10000), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;
    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
  });

  it("should be able to claim rewards on Balancer.", async () => {
    const claimDistributionsTx = iBalancerMerkleOrchard.encodeFunctionData("claimDistributions", [
      poolLogicProxy.address,
      [],
      [BALANCER.address],
    ]);

    const wrongClaimerClaimDistributionsTx = iBalancerMerkleOrchard.encodeFunctionData("claimDistributions", [
      manager.address,
      [],
      [BALANCER.address],
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction(balancer.merkleOrchard, claimDistributionsTx),
    ).to.be.revertedWith("enable reward token");
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: BALANCER.address, isDeposit: false }], []); // enable reward token

    await expect(
      poolLogicProxy.connect(manager).execTransaction(balancer.merkleOrchard, wrongClaimerClaimDistributionsTx),
    ).to.be.revertedWith("sender is not pool");

    await poolLogicProxy.connect(manager).execTransaction(balancer.merkleOrchard, claimDistributionsTx);
    // No rewards check because the merkle rewards are created weekly by Balancer. Just needs to be able to execute.
  });
});
