import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect, use } from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { DhedgeEasySwapper, PoolFactory, PoolLogic } from "../../../types";
import { units } from "../../TestHelpers";
import { aave, assets, assetsBalanceOfSlot, quickswap } from "../polygon-data";
import { getAccountToken } from "../utils/getAccountTokens";

use(solidity);

describe("DhedgeEasySwapper", function () {
  let logicOwner: SignerWithAddress;
  let dhedgeEasySwapper: DhedgeEasySwapper;
  let poolFactory: PoolFactory;

  const ETHBEAR2X = "0xf4b3a195587d2735b656b7ffe9060f478faf1b32";
  const ETHBULL3X = "0x3e5f7e9e7dc3bc3086ccebd5eb59a0a4a29d881b";
  const BTCBEAR2X = "0xcc940b5c6136994bed41bff5d88b170929921e9e";
  const BTCBULL3X = "0xc8fa09426ce1aeac1bc28751f1f6c8d74fa53f3c";

  before(async function () {
    [logicOwner] = await ethers.getSigners();

    const poolFactoryProxy = "0xfdc7b8bFe0DD3513Cc669bB8d601Cb83e2F69cB0";
    const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";

    poolFactory = await ethers.getContractAt("PoolFactory", poolFactoryProxy);

    // Take over ownership of the poolFactoryProxy
    // const owner = await ethers.provider.getStorageAt(poolFactoryProxy, 101);
    await ethers.provider.send("hardhat_setStorageAt", [
      poolFactoryProxy,
      BigNumber.from(101).toHexString(),
      "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    ]);
    await ethers.provider.send("evm_mine", []); // Just mines to the next block

    ///
    /// ONCE Prod is updated below can be removed
    ///

    // Take over ownership of the proxyAdmin
    const proxyAdmin = await ethers.getContractAt("ProxyAdmin", proxyAdminAddress);
    await ethers.provider.send("hardhat_setStorageAt", [
      proxyAdminAddress,
      "0x0",
      "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    ]);
    await ethers.provider.send("evm_mine", []); // Just mines to the next block
    expect(await poolFactory.owner()).to.equal(logicOwner.address);

    const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
    const newPoolFactory = await PoolFactoryContract.deploy();
    await newPoolFactory.deployed();

    await proxyAdmin.upgrade(poolFactoryProxy, newPoolFactory.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await PoolPerformance.deploy();
    await poolPerformance.deployed();

    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    const poolLogic = await PoolLogic.deploy();
    await poolLogic.deployed();
    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    const poolManagerLogic = await PoolManagerLogic.deploy();
    await poolManagerLogic.deployed();

    await poolFactory.setLogic(poolLogic.address, await poolManagerLogic.address);

    ///
    /// ONCE Prod is updated above can be removed ^^^
    ///

    const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
    dhedgeEasySwapper = await DhedgeEasySwapper.deploy(quickswap.router, assets.weth);
    await dhedgeEasySwapper.deployed();

    // AavelendingPool
    await dhedgeEasySwapper.setAssetToSkip(aave.lendingPool, true);

    await poolFactory.addTransferWhitelist(dhedgeEasySwapper.address);
    expect(await poolFactory.isTransferWhitelisted(dhedgeEasySwapper.address, dhedgeEasySwapper.address)).to.be.true;
  });

  describe("allowedPools", () => {
    it("only approved pools can use Swapper", async () => {
      expect(dhedgeEasySwapper.deposit(ETHBEAR2X, assets.usdc, units(1, 6), assets.usdc, 0)).to.be.revertedWith(
        "Pool is not allowed.",
      );
    });
  });

  describe("ETHBEAR2X", () => {
    let shortEthTorosPool: PoolLogic;
    before(async () => {
      shortEthTorosPool = await ethers.getContractAt("PoolLogic", ETHBEAR2X);
      await dhedgeEasySwapper.setPoolAllowed(ETHBEAR2X, true);
    });

    it("can deposit and withdraw - no swap on the way in", async () => {
      // TokenPrice is in 10**18
      // But usdc is in 10**6
      const tokenPrice = await shortEthTorosPool.tokenPrice();
      const costOf1TokenInUSDC = tokenPrice.div(10 ** 12);
      const USDC = await ethers.getContractAt("IERC20", assets.usdc);
      await USDC.approve(dhedgeEasySwapper.address, costOf1TokenInUSDC);

      // deposit the cost of 1 token
      await dhedgeEasySwapper.deposit(
        ETHBEAR2X,
        assets.usdc,
        costOf1TokenInUSDC,
        assets.usdc,
        // 1% slippage
        units(1).div(100).mul(99),
      );
      // Make sure we received very close to one token
      const balance = await shortEthTorosPool.balanceOf(logicOwner.address);
      // Should have 1 toros token
      expect(balance).closeTo(units(1), units(1).div(1000).toNumber());
      expect(await USDC.balanceOf(logicOwner.address)).to.equal(0);

      // Withdraw all

      await shortEthTorosPool.approve(dhedgeEasySwapper.address, balance);
      await dhedgeEasySwapper.withdraw(ETHBEAR2X, balance, assets.usdc, costOf1TokenInUSDC.div(100).mul(95));

      // All tokens were withdrawn
      const balanceAfterWithdraw = await shortEthTorosPool.balanceOf(logicOwner.address);
      expect(balanceAfterWithdraw).to.equal(0);

      // Check we received back funds close to what we deposited
      const fundsReturned = await USDC.balanceOf(logicOwner.address);
      const difference = costOf1TokenInUSDC.div(costOf1TokenInUSDC.sub(fundsReturned));
      console.log("Slippage", 100 / difference.toNumber());
      // Funds returned should be close to funds in
      expect(fundsReturned).closeTo(
        costOf1TokenInUSDC,
        // 2% - in and out slippage is quite a bit 605570-595902
        costOf1TokenInUSDC.div(50).toNumber(),
      );
    });

    it("can deposit and withdraw - swap on the way in", async () => {
      const oneEth = units(1);
      await getAccountToken(oneEth, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
      const WETH = await ethers.getContractAt("IERC20", assets.weth);
      await WETH.approve(dhedgeEasySwapper.address, oneEth);
      expect(await WETH.balanceOf(logicOwner.address)).to.equal(oneEth);

      // TODO: improve this test by calculating the number of tokens we should receive for 1 eth
      await dhedgeEasySwapper.deposit(ETHBEAR2X, assets.weth, oneEth, assets.usdc, 0);
      const balance = await shortEthTorosPool.balanceOf(logicOwner.address);
      expect(balance > BigNumber.from(0)).to.be.true;
      expect(await WETH.balanceOf(logicOwner.address)).to.equal(0);

      await shortEthTorosPool.approve(dhedgeEasySwapper.address, balance);
      await dhedgeEasySwapper.withdraw(ETHBEAR2X, balance, assets.weth, 0);
      const balanceAfterWithdraw = await shortEthTorosPool.balanceOf(logicOwner.address);
      expect(balanceAfterWithdraw).to.equal(0);

      // Check we received back funds close to what we deposited
      const fundsReturned = await WETH.balanceOf(logicOwner.address);

      const difference = oneEth.div(oneEth.sub(fundsReturned));
      console.log("Slippage", 100 / difference.toNumber());
      // Funds returned should be close to funds in
      expect(fundsReturned).to.closeTo(
        oneEth,
        // 2%
        oneEth.div(50) as unknown as number,
      );
    });
  });
});
