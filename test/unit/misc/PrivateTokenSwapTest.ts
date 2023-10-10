import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { units } from "../../testHelpers";
import { PrivateTokenSwap, IERC20 } from "../../../types";

describe("PrivateTokenSwap Test", () => {
  let usdc: IERC20, dht: IERC20, privateTokenSwap: PrivateTokenSwap;
  let owner: SignerWithAddress, user: SignerWithAddress;

  const dhtAmount = units(200);
  const usdcAmount = units(15, 6);
  const exchangeRate = units(75, 15); // 0.075

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    const Usdc = await ethers.getContractFactory("TestUSDC");
    const ERC20Asset = await ethers.getContractFactory("ERC20Asset");
    usdc = await Usdc.deploy("1000");
    await usdc.deployed();
    dht = await ERC20Asset.deploy("dHedge DAO token", "DHT");
    await dht.deployed();

    const PrivateTokenSwap = await ethers.getContractFactory("PrivateTokenSwap");
    privateTokenSwap = await PrivateTokenSwap.deploy(
      dht.address, // _originalToken
      usdc.address, // _exchangeToken
      exchangeRate,
      user.address, // _user
    );

    await privateTokenSwap.deployed();

    await dht.transfer(privateTokenSwap.address, dhtAmount);
    await usdc.transfer(privateTokenSwap.address, usdcAmount);
  });

  it("check contract balances", async () => {
    const dhtBalance = await dht.balanceOf(privateTokenSwap.address);
    const usdcBalance = await usdc.balanceOf(privateTokenSwap.address);
    expect(dhtBalance).to.equal(dhtAmount);
    expect(usdcBalance).to.equal(usdcAmount);
  });

  it("check exchange rate", async () => {
    const exchangeRateAdjusted = await privateTokenSwap.getExchangeRateAdjusted();
    expect(exchangeRateAdjusted).to.equal("75000");
  });

  it("change exchange rate", async () => {
    const newExchangeRate = units(50, 15); // 0.05
    await expect(privateTokenSwap.connect(user).setExchangeRate(newExchangeRate)).to.be.revertedWith(
      "Ownable: caller is not the owner",
    );
    await privateTokenSwap.connect(owner).setExchangeRate(newExchangeRate);
    expect(await privateTokenSwap.exchangeRate()).to.equal(newExchangeRate);
  });

  it("withdraw with owner", async () => {
    const userDhtBalanceBefore = await dht.balanceOf(user.address);
    expect(userDhtBalanceBefore).to.equal(0);
    await expect(privateTokenSwap.connect(owner).withdraw()).to.be.revertedWith("Only user can interact");
  });

  it("withdraw", async () => {
    const userDhtBalanceBefore = await dht.balanceOf(user.address);
    await privateTokenSwap.connect(user).withdraw();
    const userDhtBalanceAfter = await dht.balanceOf(user.address);

    expect(userDhtBalanceBefore).to.equal(0);
    expect(userDhtBalanceAfter).to.equal(dhtAmount);
  });

  it("swap", async () => {
    await privateTokenSwap.connect(user).withdraw();

    const userDhtBalanceBefore = await dht.balanceOf(user.address);
    const userUsdcBalanceBefore = await usdc.balanceOf(user.address);
    const contractDhtBalanceBefore = await dht.balanceOf(privateTokenSwap.address);
    const contractUsdcBalanceBefore = await usdc.balanceOf(privateTokenSwap.address);

    await dht.connect(user).approve(privateTokenSwap.address, dhtAmount);
    await privateTokenSwap.connect(user).swapAll();

    const userDhtBalanceAfter = await dht.balanceOf(user.address);
    const userUsdcBalanceAfter = await usdc.balanceOf(user.address);
    const contractDhtBalanceAfter = await dht.balanceOf(privateTokenSwap.address);
    const contractUsdcBalanceAfter = await usdc.balanceOf(privateTokenSwap.address);

    expect(userDhtBalanceBefore).to.equal(dhtAmount);
    expect(userDhtBalanceAfter).to.equal(0);
    expect(userUsdcBalanceBefore).to.equal(0);
    expect(userUsdcBalanceAfter).to.equal(usdcAmount);

    expect(contractDhtBalanceBefore).to.equal(0);
    expect(contractDhtBalanceAfter).to.equal(dhtAmount);
    expect(contractUsdcBalanceBefore).to.equal(usdcAmount);
    expect(contractUsdcBalanceAfter).to.equal(0);
  });

  it("can't withdraw after swap", async () => {
    await privateTokenSwap.connect(user).withdraw();

    await dht.connect(user).approve(privateTokenSwap.address, dhtAmount);
    await privateTokenSwap.connect(user).swapAll();

    await expect(privateTokenSwap.connect(user).withdraw()).to.be.revertedWith("No exchange token balance");
  });

  it("swap with additional USDC in contract", async () => {
    const usdcAmountAdditional = units(5, 6);
    await usdc.transfer(privateTokenSwap.address, usdcAmountAdditional);

    await privateTokenSwap.connect(user).withdraw();

    const userDhtBalanceBefore = await dht.balanceOf(user.address);
    const userUsdcBalanceBefore = await usdc.balanceOf(user.address);
    const contractDhtBalanceBefore = await dht.balanceOf(privateTokenSwap.address);
    const contractUsdcBalanceBefore = await usdc.balanceOf(privateTokenSwap.address);

    await dht.connect(user).approve(privateTokenSwap.address, dhtAmount);
    await privateTokenSwap.connect(user).swapAll();

    const userDhtBalanceAfter = await dht.balanceOf(user.address);
    const userUsdcBalanceAfter = await usdc.balanceOf(user.address);
    const contractDhtBalanceAfter = await dht.balanceOf(privateTokenSwap.address);
    const contractUsdcBalanceAfter = await usdc.balanceOf(privateTokenSwap.address);

    expect(userDhtBalanceBefore).to.equal(dhtAmount);
    expect(userDhtBalanceAfter).to.equal(0);
    expect(userUsdcBalanceBefore).to.equal(0);
    expect(userUsdcBalanceAfter).to.equal(usdcAmount);

    expect(contractDhtBalanceBefore).to.equal(0);
    expect(contractDhtBalanceAfter).to.equal(dhtAmount);
    expect(contractUsdcBalanceBefore).to.equal(usdcAmount.add(usdcAmountAdditional));
    expect(contractUsdcBalanceAfter).to.equal(usdcAmountAdditional);
  });

  it("swap with additional DHT in contract", async () => {
    const dhtAmountAdditional = units(100);
    await dht.transfer(privateTokenSwap.address, dhtAmountAdditional);

    await privateTokenSwap.connect(user).withdraw();

    const userDhtBalanceBefore = await dht.balanceOf(user.address);
    const userUsdcBalanceBefore = await usdc.balanceOf(user.address);
    const contractDhtBalanceBefore = await dht.balanceOf(privateTokenSwap.address);
    const contractUsdcBalanceBefore = await usdc.balanceOf(privateTokenSwap.address);

    await dht.connect(user).approve(privateTokenSwap.address, dhtAmount);
    await privateTokenSwap.connect(user).swapAll();

    const userDhtBalanceAfter = await dht.balanceOf(user.address);
    const userUsdcBalanceAfter = await usdc.balanceOf(user.address);
    const contractDhtBalanceAfter = await dht.balanceOf(privateTokenSwap.address);
    const contractUsdcBalanceAfter = await usdc.balanceOf(privateTokenSwap.address);

    expect(userDhtBalanceBefore).to.equal(dhtAmount);
    expect(userDhtBalanceAfter).to.equal(0);
    expect(userUsdcBalanceBefore).to.equal(0);
    expect(userUsdcBalanceAfter).to.equal(usdcAmount);

    expect(contractDhtBalanceBefore).to.equal(dhtAmountAdditional);
    expect(contractDhtBalanceAfter).to.equal(dhtAmount.add(dhtAmountAdditional));
    expect(contractUsdcBalanceBefore).to.equal(usdcAmount);
    expect(contractUsdcBalanceAfter).to.equal(0);

    await expect(privateTokenSwap.connect(user).withdraw()).to.be.revertedWith("No exchange token balance");
  });

  it("forceWithdraw", async () => {
    const ownerDhtBalance = await dht.balanceOf(owner.address);
    const ownerUsdcBalance = await usdc.balanceOf(owner.address);

    await privateTokenSwap.withdrawAdmin(dht.address, await dht.balanceOf(privateTokenSwap.address));
    await privateTokenSwap.withdrawAdmin(usdc.address, await usdc.balanceOf(privateTokenSwap.address));

    const contractDhtBalanceAfter = await dht.balanceOf(privateTokenSwap.address);
    const contractUsdcBalanceAfter = await usdc.balanceOf(privateTokenSwap.address);

    expect(await dht.balanceOf(owner.address)).to.equal(dhtAmount.add(ownerDhtBalance));
    expect(await usdc.balanceOf(owner.address)).to.equal(usdcAmount.add(ownerUsdcBalance));
    expect(contractDhtBalanceAfter).to.equal(0);
    expect(contractUsdcBalanceAfter).to.equal(0);
  });
});
