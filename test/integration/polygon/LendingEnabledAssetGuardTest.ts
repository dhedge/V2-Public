import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract } from "ethers";
import { artifacts, ethers } from "hardhat";
import { polygonChainData } from "../../../config/chainData/polygon-data";
import { PoolLogic, PoolManagerLogic } from "../../../types";
import { units } from "../../TestHelpers";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { getAccountTokens } from "../utils/getAccountTokens/index";

const { BigNumber } = ethers;

const { aaveV2, assets, assetsBalanceOfSlot } = polygonChainData;
const usdcAmount = units(100, 6);

describe("LendingEnabledAssetGuard", function () {
  let USDC: Contract, manager: SignerWithAddress;
  let PoolLogic: PoolLogic, PoolManagerLogic: PoolManagerLogic;
  let poolFactory: Contract;

  beforeEach(async function () {
    [, manager] = await ethers.getSigners();

    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    PoolManagerLogic = deployments.poolManagerLogic;
    PoolLogic = deployments.poolLogic;

    USDC = deployments.assets.USDC;
    getAccountTokens(usdcAmount, assets.usdc, assetsBalanceOfSlot.usdc);
  });

  it("cannot remove asset with open aave position", async () => {
    const managerFee = BigNumber.from("0"); // 0%;
    // Create the fund we're going to use for testing
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      managerFee,
      BigNumber.from("0"),
      [
        [assets.wmatic, true],
        [assets.usdc, true],
        [aaveV2.lendingPool, false],
      ],
    );
    const funds = await poolFactory.getDeployedFunds();
    const poolLogicProxy = await PoolLogic.attach(funds[0]);
    // Deposit
    await USDC.approve(poolLogicProxy.address, usdcAmount);
    await poolLogicProxy.deposit(assets.usdc, usdcAmount);

    const IERC20 = await artifacts.readArtifact("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    // approve usdc
    const approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, usdcAmount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const ILendingPool = await artifacts.readArtifact("ILendingPool");
    const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);
    // deposit
    const depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, usdcAmount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    const poolManagerLogicProxy = await PoolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());
    const poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal((0).toString());
    expect(await poolManagerLogicManagerProxy.assetBalance(assets.usdc)).to.be.equal((0).toString());

    await expect(poolManagerLogicManagerProxy.changeAssets([], [assets.usdc])).to.be.revertedWith(
      "withdraw Aave collateral first",
    );
  });
});
