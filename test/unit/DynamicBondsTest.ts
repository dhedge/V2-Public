import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { utils, Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { units, currentBlockTimestamp } from "../testHelpers";
const parseUnits = utils.parseUnits;
const days = (d: number) => d * 3600 * 24;

describe("DynamicBonds Test", () => {
  let usdc: Contract, dht: Contract, dynamicBonds: Contract;
  let owner: SignerWithAddress, treasury: SignerWithAddress, other: SignerWithAddress;

  beforeEach(async () => {
    [owner, treasury, other] = await ethers.getSigners();

    const Usdc = await ethers.getContractFactory("TestUSDC");
    const ERC20Asset = await ethers.getContractFactory("ERC20Asset");
    usdc = await Usdc.deploy("1000000000");
    await usdc.deployed();
    dht = await ERC20Asset.deploy("dHedge DAO token", "DHT");
    await dht.deployed();

    const DynamicBonds = await ethers.getContractFactory("DynamicBonds");
    dynamicBonds = await upgrades.deployProxy(DynamicBonds, [
      usdc.address,
      dht.address,
      treasury.address,
      units(1, 6), // 1 DHT = 1 USDC
      units(100), // 100 DHT
    ]);
    await dynamicBonds.deployed();

    await dht.transfer(dynamicBonds.address, units(1000));
  });

  it("setBondTerms", async () => {
    let bondTerm = await dynamicBonds.bondTerms();
    expect(bondTerm.payoutAvailable).to.equal(0);
    expect(bondTerm.expiryTimestamp).to.equal(0);

    const currentTimestamp = await currentBlockTimestamp();
    await expect(dynamicBonds.setBondTerms(units(200), currentTimestamp)).to.revertedWith(
      "exceed max available payout",
    );
    await expect(dynamicBonds.setBondTerms(units(100), currentTimestamp)).to.revertedWith("invalid expiry timestamp");

    await dynamicBonds.setBondTerms(units(100), currentTimestamp + days(1));
    bondTerm = await dynamicBonds.bondTerms();
    expect(bondTerm.payoutAvailable).to.equal(units(100));
    expect(bondTerm.expiryTimestamp).to.equal(currentTimestamp + days(1));
  });

  it("addBondOptions", async () => {
    let bondOptions = await dynamicBonds.bondOptions();
    expect(bondOptions.length).to.equal(0);

    await expect(dynamicBonds.addBondOptions([[units(1, 6).div(2), days(1)]])).to.revertedWith("too low payout price");

    await dynamicBonds.addBondOptions([[units(10, 6), days(1)]]); // 1 Day, 1 DHT = 10 USDC

    bondOptions = await dynamicBonds.bondOptions();
    expect(bondOptions.length).to.equal(1);
    expect(bondOptions[0].price).to.equal(units(10, 6));
    expect(bondOptions[0].lockPeriod).to.equal(days(1));
  });

  it("updateBondOption", async () => {
    await dynamicBonds.addBondOptions([[units(10, 6), days(1)]]); // 1 Day, 1 DHT = 10 USDC

    let bondOptions = await dynamicBonds.bondOptions();
    expect(bondOptions.length).to.equal(1);
    expect(bondOptions[0].price).to.equal(units(10, 6));
    expect(bondOptions[0].lockPeriod).to.equal(days(1));

    await expect(dynamicBonds.updateBondOption(1, [units(10, 6), days(1)])).to.revertedWith("invalid index");
    await expect(dynamicBonds.updateBondOption(0, [units(1, 6).div(2), days(1)])).to.revertedWith(
      "too low payout price",
    );

    await dynamicBonds.updateBondOption(0, [units(20, 6), days(1)]);
    bondOptions = await dynamicBonds.bondOptions();
    expect(bondOptions.length).to.equal(1);
    expect(bondOptions[0].price).to.equal(units(20, 6));
    expect(bondOptions[0].lockPeriod).to.equal(days(1));
  });

  it("updateBondOptions", async () => {
    await dynamicBonds.addBondOptions([[units(10, 6), days(1)]]); // 1 Day, 1 DHT = 10 USDC
    await dynamicBonds.addBondOptions([[units(5, 6), days(7)]]); // 1 Week, 1 DHT = 5 USDC

    let bondOptions = await dynamicBonds.bondOptions();
    expect(bondOptions.length).to.equal(2);
    expect(bondOptions[0].price).to.equal(units(10, 6));
    expect(bondOptions[0].lockPeriod).to.equal(days(1));
    expect(bondOptions[1].price).to.equal(units(5, 6));
    expect(bondOptions[1].lockPeriod).to.equal(days(7));

    await expect(dynamicBonds.updateBondOptions([0, 1], [[units(10, 6), days(1)]])).to.revertedWith(
      "length doesn't match",
    );
    await expect(dynamicBonds.updateBondOptions([2], [[units(10, 6), days(1)]])).to.revertedWith("invalid index");
    await expect(dynamicBonds.updateBondOptions([0], [[units(1, 6).div(2), days(1)]])).to.revertedWith(
      "too low payout price",
    );

    await dynamicBonds.updateBondOptions([0], [[units(20, 6), days(1)]]);
    bondOptions = await dynamicBonds.bondOptions();
    expect(bondOptions.length).to.equal(2);
    expect(bondOptions[0].price).to.equal(units(20, 6));
    expect(bondOptions[0].lockPeriod).to.equal(days(1));
    expect(bondOptions[1].price).to.equal(units(5, 6));
    expect(bondOptions[1].lockPeriod).to.equal(days(7));
  });

  it("deposit USDC -> lock DHT", async () => {
    await expect(dynamicBonds.deposit(parseUnits("1", 6), units(1, 6), 0)).to.revertedWith("expired");

    const currentTimestamp = await currentBlockTimestamp();
    await dynamicBonds.setBondTerms(units(100), currentTimestamp + days(30));

    await expect(dynamicBonds.deposit(parseUnits("1", 6), units(1000), 0)).to.revertedWith(
      "insufficient available payout",
    );
    await expect(dynamicBonds.deposit(parseUnits("1", 6), units(1), 0)).to.revertedWith("invalid bond option index");

    await dynamicBonds.addBondOptions([[units(10, 6), days(1)]]); // 1 Day, 1 DHT = 10 USDC
    await expect(dynamicBonds.deposit(parseUnits("1", 6).div(2), units(1), 0)).to.revertedWith(
      "deposit amount exceeded",
    );
    await expect(dynamicBonds.deposit(parseUnits("10", 6), units(1), 0)).to.revertedWith(
      "ERC20: transfer amount exceeds allowance",
    );

    // check before deposit
    expect(await usdc.balanceOf(treasury.address)).to.equal(0);
    expect(await dynamicBonds.debtTotal()).to.equal(0);
    expect(await dynamicBonds.depositTotal()).to.equal(0);
    expect((await dynamicBonds.bondTerms()).payoutAvailable).to.equal(units(100));

    await usdc.approve(dynamicBonds.address, parseUnits("10", 6));
    await dynamicBonds.deposit(parseUnits("10", 6), units(1), 0);

    // check after deposit

    const userBonds = await dynamicBonds.getUserBonds(owner.address);
    expect(userBonds.length).to.equal(1);
    expect(userBonds[0].bondId).to.equal(0);
    expect(userBonds[0].bondOwner).to.equal(owner.address);
    expect(userBonds[0].lockAmount).to.equal(units(1));
    expect(userBonds[0].bondOption.price).to.equal(units(10, 6));
    expect(userBonds[0].bondOption.lockPeriod).to.equal(days(1));
    expect(userBonds[0].lockStartedAt).to.equal(await currentBlockTimestamp());
    expect(userBonds[0].claimed).to.equal(false);
    expect(await dynamicBonds.debtTotal()).to.equal(units(1));
    expect(await dynamicBonds.depositTotal()).to.equal(parseUnits("10", 6));
    expect((await dynamicBonds.bondTerms()).payoutAvailable).to.equal(units(99));
    expect(await usdc.balanceOf(treasury.address)).to.equal(parseUnits("10", 6));
  });

  it("deposit USDC -> lock DHT -> claim DHT", async () => {
    const currentTimestamp = await currentBlockTimestamp();
    await dynamicBonds.setBondTerms(units(100), currentTimestamp + days(30));
    await dynamicBonds.addBondOptions([[units(10, 6), days(1)]]); // 1 Day, 1 DHT = 10 USDC
    await usdc.approve(dynamicBonds.address, parseUnits("10", 6));
    await dynamicBonds.deposit(parseUnits("10", 6), units(1), 0);

    await expect(dynamicBonds.claim(1)).to.revertedWith("invalid bond index");
    await expect(dynamicBonds.connect(other).claim(0)).to.revertedWith("unauthorized");
    await expect(dynamicBonds.claim(0)).to.revertedWith("locked");

    await ethers.provider.send("evm_increaseTime", [days(1)]);
    await ethers.provider.send("evm_mine", []);

    // check before claim
    expect(await dynamicBonds.debtTotal()).to.equal(units(1));
    expect(await dht.balanceOf(owner.address)).to.equal(0);

    await dynamicBonds.claim(0);

    const bond = await dynamicBonds.bonds(0);
    expect(bond.bondOwner).to.equal(owner.address);
    expect(bond.claimed).to.equal(true);
    expect(await dht.balanceOf(owner.address)).to.equal(units(1));
    expect(await dynamicBonds.debtTotal()).to.equal(0);

    await expect(dynamicBonds.claim(0)).to.revertedWith("already claimed");
  });

  it("forceWithdraw", async () => {
    expect(await dht.balanceOf(owner.address)).to.equal(0);

    await dynamicBonds.forceWithdraw(dht.address, await dht.balanceOf(dynamicBonds.address));

    expect(await dht.balanceOf(owner.address)).to.equal(units(1000));
  });

  it("setTreasury", async () => {
    expect(await dynamicBonds.treasury()).to.equal(treasury.address);
    await dynamicBonds.setTreasury(other.address);
    expect(await dynamicBonds.treasury()).to.equal(other.address);
  });

  it("setMinBondPrice", async () => {
    expect(await dynamicBonds.minBondPrice()).to.equal(units(1, 6));
    await dynamicBonds.setMinBondPrice(units(2, 6));
    expect(await dynamicBonds.minBondPrice()).to.equal(units(2, 6));
  });

  it("setMaxPayoutAvailable", async () => {
    expect(await dynamicBonds.maxPayoutAvailable()).to.equal(units(100));
    await dynamicBonds.setMaxPayoutAvailable(units(200));
    expect(await dynamicBonds.maxPayoutAvailable()).to.equal(units(200));
  });
});
