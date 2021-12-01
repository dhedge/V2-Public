import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import axios from "axios";

import { checkAlmostSame, units } from "../../TestHelpers";
import { assets, price_feeds, eth_price_feeds, sushi } from "../polygon-data";
import { MedianTWAPAggregator } from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

use(solidity);

describe("ETHCrossAggregator Test", function () {
  let logicOwner: SignerWithAddress, other: SignerWithAddress;
  let dhedgeMedianTwapAggregator: MedianTWAPAggregator;

  beforeEach(async function () {
    [logicOwner, other] = await ethers.getSigners();
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    dhedgeMedianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.weth_dht.address,
      assets.dht,
      price_feeds.eth,
      1000,
    );
    await dhedgeMedianTwapAggregator.deployed();
  });

  it("check update interval", async () => {
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [200]);
    await expect(dhedgeMedianTwapAggregator.update()).to.revertedWith("period is not passed");
    await ethers.provider.send("evm_increaseTime", [800]);
    await dhedgeMedianTwapAggregator.update();
  });

  it("change update interval", async () => {
    expect(await dhedgeMedianTwapAggregator.updateInterval()).to.equal(1000);
    await dhedgeMedianTwapAggregator.setUpdateInterval(2000);
    expect(await dhedgeMedianTwapAggregator.updateInterval()).to.equal(2000);
  });

  it("incentive for update", async () => {
    const balanceBefore = await logicOwner.getBalance();

    await expect(dhedgeMedianTwapAggregator.updateWithIncentive()).to.revertedWith("failed to send incentive");

    await other.sendTransaction({ value: units(100), to: dhedgeMedianTwapAggregator.address });
    await dhedgeMedianTwapAggregator.updateWithIncentive();

    const balanceAfter = await logicOwner.getBalance();

    expect(balanceBefore).lt(balanceAfter);
  });

  it("try with high gas price", async () => {
    await other.sendTransaction({ value: units(100), to: dhedgeMedianTwapAggregator.address });

    const balanceBefore = await logicOwner.getBalance();
    await dhedgeMedianTwapAggregator.updateWithIncentive({ gasPrice: 1000000000000 });
    const balanceAfter = await logicOwner.getBalance();

    expect(balanceBefore).gt(balanceAfter);
  });

  it("Get Dhedge price", async () => {
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();

    const price = (await dhedgeMedianTwapAggregator.latestRoundData()).answer;
    const priceFromCongecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.dht)).toString(), 8);
    expect(price).to.be.closeTo(priceFromCongecko, price.mul(5).div(100) as any); // 3% diff
  });

  it("Get WETH price", async () => {
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    const wethMedianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.usdc_weth.address,
      assets.weth,
      price_feeds.usdc,
      1000,
    );
    await wethMedianTwapAggregator.deployed();

    await wethMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await wethMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await wethMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await wethMedianTwapAggregator.update();

    const price = (await wethMedianTwapAggregator.latestRoundData()).answer;
    const priceFromCongecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.weth)).toString(), 8);
    expect(price).to.be.closeTo(priceFromCongecko, price.mul(3).div(100) as any); // 3% diff
  });

  it("Get USDC price", async () => {
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    const usdcMedianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.usdc_weth.address,
      assets.usdc,
      price_feeds.eth,
      1000,
    );
    await usdcMedianTwapAggregator.deployed();

    await usdcMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await usdcMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await usdcMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await usdcMedianTwapAggregator.update();

    const price = (await usdcMedianTwapAggregator.latestRoundData()).answer;
    const priceFromCongecko = ethers.utils.parseUnits((await getTokenPriceFromCoingecko(assets.usdc)).toString(), 8);
    expect(price).to.be.closeTo(priceFromCongecko, price.mul(3).div(100) as any); // 3% diff
  });
});

const getTokenPriceFromCoingecko = async (tokenAddr: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/polygon-pos?contract_addresses=${tokenAddr}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddr.toLocaleLowerCase()].usd;
};
