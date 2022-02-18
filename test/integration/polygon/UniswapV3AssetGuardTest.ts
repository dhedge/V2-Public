import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { Wallet } from "ethers";
import {} from "@nomiclabs/hardhat-ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { describe, it } from "mocha";
import { assets, assetsBalanceOfSlot, uniswapV3 } from "../../../config/chainData/polygon-data";
import {
  IERC20__factory,
  INonfungiblePositionManager,
  INonfungiblePositionManager__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { IDeployments } from "../utils/deployContracts";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { getAccountToken } from "../utils/getAccountTokens";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
const deadLine = Math.floor(Date.now() / 1000 + 100000000);

const mintAsUser = async (nonfungiblePositionManager: INonfungiblePositionManager, user: Wallet) => {
  await getAccountToken(units(1), user.address, assets.weth, assetsBalanceOfSlot.weth);
  await getAccountToken(units(2000, 6), user.address, assets.usdc, assetsBalanceOfSlot.usdc);
  // Approve nft manager to take tokens
  const usdcContract = await await ethers.getContractAt("IERC20", assets.usdc);
  await usdcContract.connect(user).approve(uniswapV3.nonfungiblePositionManager, units(200, 6));
  const wethContract = await ethers.getContractAt("IERC20", assets.weth);
  await wethContract.connect(user).approve(uniswapV3.nonfungiblePositionManager, units(0.1));
  // Minting a very small position here relative to the positions that the pool mints
  await nonfungiblePositionManager.connect(user).mint({
    token0: assets.usdc,
    token1: assets.weth,
    fee: 10000,
    tickLower: -414400,
    tickUpper: -253200,
    amount0Desired: units(200, 6),
    amount1Desired: units(0.1),
    amount0Min: 0,
    amount1Min: 0,
    recipient: user.address,
    deadline: deadLine,
  });
};

const mintAsPool = async (poolLogicProxy: PoolLogic, manager: SignerWithAddress) => {
  let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(2000, 6)]);
  await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(1)]);
  await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

  let mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
    [
      assets.usdc,
      assets.weth,
      10000,
      -414400,
      -253200,
      units(2000, 6),
      units(1),
      0,
      0,
      poolLogicProxy.address,
      deadLine,
    ],
  ]);

  await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI);
};

describe("UniswapV3AssetGuardTest", function () {
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;
  let nonfungiblePositionManager: INonfungiblePositionManager;
  let deployments: IDeployments;
  let user: Wallet;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();

    nonfungiblePositionManager = await ethers.getContractAt(
      "INonfungiblePositionManager",
      uniswapV3.nonfungiblePositionManager,
    );

    deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;

    await getAccountToken(units(6), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
    await getAccountToken(units(12000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });

  beforeEach(async function () {
    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
      { asset: uniswapV3.nonfungiblePositionManager, isDeposit: false },
    ]);
    poolLogicProxy = funds.poolLogicProxy;

    await deployments.assets.USDC.approve(poolLogicProxy.address, units(6000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(6000, 6));
    await deployments.assets.WETH.approve(poolLogicProxy.address, units(3));
    await poolLogicProxy.deposit(assets.weth, units(3));

    await poolFactory.setExitCooldown(0);
    // We don't use a  getSigners signer here because they're shared across all integration tests
    user = ethers.Wallet.createRandom().connect(ethers.provider);
    logicOwner.sendTransaction({
      to: user.address,
      value: ethers.utils.parseEther("1"),
    });
  });

  // What we want to test here is if a nft position gets transferred directly
  // to a pool that we only count the first three that the pool mints
  // not matter what order they are created.
  describe("Ensure balance is calculated for first three LP positions", () => {
    it("User mints, manager mints 3x, User direct transfer", async () => {
      // Setup
      await mintAsUser(nonfungiblePositionManager, user);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);
      // Act
      const tokenPriceBefore = await poolLogicProxy.tokenPrice();
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(user.address, 0);
      await nonfungiblePositionManager.connect(user).transferFrom(user.address, poolLogicProxy.address, tokenId);

      // Assert
      expect(await nonfungiblePositionManager.balanceOf(user.address)).to.equal(0);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(4);
      expect(await poolLogicProxy.tokenPrice()).to.equal(tokenPriceBefore);
    });

    it("Manager mints 3x, User mints, User direct transfer", async () => {
      // Setup
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsUser(nonfungiblePositionManager, user);
      // Act
      const tokenPriceBefore = await poolLogicProxy.tokenPrice();
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(user.address, 0);
      await nonfungiblePositionManager.connect(user).transferFrom(user.address, poolLogicProxy.address, tokenId);

      // Assert
      expect(await nonfungiblePositionManager.balanceOf(user.address)).to.equal(0);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(4);
      expect(await poolLogicProxy.tokenPrice()).to.equal(tokenPriceBefore);
    });
  });
});
