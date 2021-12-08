import { ethers, artifacts } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, assert, use } from "chai";
import axios from "axios";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { getAccountToken } from "../utils/getAccountTokens";
import { units } from "../../TestHelpers";
import { assets, assetsBalanceOfSlot, price_feeds, sushi } from "../../../config/chainData/polygon-data";
import { MedianTWAPAggregator, IUniswapV2Router__factory } from "../../../types";

use(solidity);

describe("Median TWAP Oracle Test", function () {
  let logicOwner: SignerWithAddress, other: SignerWithAddress;
  let dhedgeMedianTwapAggregator: MedianTWAPAggregator;
  let snapshot: any;
  const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router__factory.abi);

  beforeEach(async function () {
    snapshot = await ethers.provider.send("evm_snapshot", []);
    [logicOwner, other] = await ethers.getSigners();
    const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
    dhedgeMedianTwapAggregator = await MedianTWAPAggregator.deploy(
      sushi.pools.weth_dht.address,
      assets.dht,
      price_feeds.eth,
      1000,
      25,
    );
    await getAccountToken(units(1000, 18), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth); // get WETH
    await getAccountToken(units(1000000, 18), logicOwner.address, assets.dht, assetsBalanceOfSlot.dht); // get DHT

    await dhedgeMedianTwapAggregator.deployed();
  });

  afterEach(async () => {
    await ethers.provider.send("evm_revert", [snapshot]);
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

  it("withdraw balance", async () => {
    const amount = units(100);
    await other.sendTransaction({ value: amount, to: dhedgeMedianTwapAggregator.address });

    await expect(dhedgeMedianTwapAggregator.connect(other).withdraw(amount)).to.revertedWith(
      "Ownable: caller is not the owner",
    );
    await expect(dhedgeMedianTwapAggregator.withdraw(amount.add(1))).to.revertedWith("balance is too low");
    await dhedgeMedianTwapAggregator.withdraw(amount); // can withdraw full balance
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
      25,
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
      25,
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

  it("Stale TWAP price expiry", async () => {
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [2000]);
    await dhedgeMedianTwapAggregator.update();
    await ethers.provider.send("evm_increaseTime", [13000]); // more than 12x of update interval to make the oracle price stale

    await other.sendTransaction({
      to: "0x0000000000000000000000000000000000000000",
      value: ethers.utils.parseEther("0"),
    }); // dummy transaction to increase block time

    const currentBlock = await ethers.provider.getBlockNumber();
    await expect(dhedgeMedianTwapAggregator.latestRoundData()).to.revertedWith("TWAP price expired");
  });

  it("Buying lots of DHT triggers volatility revert", async () => {
    // Make sure volatility works in different twap order scenarios by buying DHT on Sushi
    for (let i = 0; i < 2; i++) {
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();
      if (i == 0) await buyDht(); // loop 0: buy DHT on middle TWAP
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();
      if (i == 1) await buyDht(); // loop 1: buy DHT on last TWAP
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();

      await checkVolatilityRevert(dhedgeMedianTwapAggregator);
    }
  });

  it("Selling lots of DHT triggers volatility revert", async () => {
    // Make sure volatility works in different twap order scenarios by selling DHT on Sushi
    for (let i = 0; i < 2; i++) {
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();
      if (i == 0) await sellDht(); // loop 0: sell DHT on middle TWAP
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();
      if (i == 1) await sellDht(); // loop 1: sell DHT on last TWAP
      await ethers.provider.send("evm_increaseTime", [2000]);
      await dhedgeMedianTwapAggregator.update();

      await checkVolatilityRevert(dhedgeMedianTwapAggregator);
    }
  });

  const checkVolatilityRevert = async (dhedgeMedianTwapAggregator: MedianTWAPAggregator) => {
    // check that trades made a significant enough price impact
    const pricePercentIncrease = await getPricePercentIncrease(dhedgeMedianTwapAggregator);
    assert(pricePercentIncrease > 5, "Test price change is too small. Increase swap amount");

    // should get oracle price if low volatility
    await dhedgeMedianTwapAggregator.setVolatilityTripLimit(pricePercentIncrease + 1);
    await dhedgeMedianTwapAggregator.latestRoundData();

    // should revert getting oracle price if high volatility
    await dhedgeMedianTwapAggregator.setVolatilityTripLimit(pricePercentIncrease - 1);
    await expect(dhedgeMedianTwapAggregator.latestRoundData()).to.revertedWith("price volatility too high");
  };

  const buyDht = async () => {
    const WETH = await ethers.getContractAt("IERC20", assets.weth);
    const IUniswapV2Router = await artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    const sourceAmount = units(100);
    await WETH.approve(sushi.router, sourceAmount);
    await sushiswapRouter.swapExactTokensForTokens(
      sourceAmount,
      0,
      [assets.weth, assets.dht],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
  };

  const sellDht = async () => {
    const DHT = await ethers.getContractAt("IERC20", assets.dht);
    const IUniswapV2Router = await artifacts.readArtifact("IUniswapV2Router");
    const sushiswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, sushi.router);
    const dhtBalance = await DHT.balanceOf(logicOwner.address);
    const sourceAmount = units(100000);
    await DHT.approve(sushi.router, sourceAmount);
    await sushiswapRouter.swapExactTokensForTokens(
      sourceAmount,
      0,
      [assets.dht, assets.weth],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
  };
});

const getPricePercentIncrease = async (dhedgeMedianTwapAggregator: MedianTWAPAggregator) => {
  const twapLastIndex = await dhedgeMedianTwapAggregator.twapLastIndex();
  const twap1 = await dhedgeMedianTwapAggregator.twaps(twapLastIndex);
  const twap2 = await dhedgeMedianTwapAggregator.twaps(Number(twapLastIndex) - 1);
  const twap3 = await dhedgeMedianTwapAggregator.twaps(Number(twapLastIndex) - 2);

  return Math.max(
    twap1.mul(100).div(twap2).sub(100).toNumber(),
    twap2.mul(100).div(twap3).sub(100).toNumber(),
    twap3.mul(100).div(twap1).sub(100).toNumber(),
  );
};

const getTokenPriceFromCoingecko = async (tokenAddr: string) => {
  const apiUrl = `https://api.coingecko.com/api/v3/simple/token_price/polygon-pos?contract_addresses=${tokenAddr}&vs_currencies=usd`;
  const response = await axios.get(apiUrl);
  return response.data[tokenAddr.toLocaleLowerCase()].usd;
};
