import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { units } from "../../TestHelpers";
import { ETHCrossAggregator, IAggregatorV3Interface } from "../../../types";
import { polygonChainData } from "../../../config/chainData/polygon-data";
import { utils } from "../utils/utils";
const { eth_price_feeds, assets, price_feeds } = polygonChainData;

use(solidity);

describe("ETHCrossAggregator Test", function () {
  let ethUsdAggregator: IAggregatorV3Interface;
  let ghstEthAggregator: IAggregatorV3Interface;
  let ghstUsdAggregator: ETHCrossAggregator;

  let snapId: string;
  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  before(async () => {
    snapId = await utils.evmTakeSnap();

    const ETHCrossAggregator = await ethers.getContractFactory("ETHCrossAggregator");
    ghstUsdAggregator = await ETHCrossAggregator.deploy(assets.ghst, eth_price_feeds.ghst, price_feeds.eth);
    ghstUsdAggregator.deployed();

    ethUsdAggregator = await ethers.getContractAt("IAggregatorV3Interface", price_feeds.eth);
    ghstEthAggregator = await ethers.getContractAt("IAggregatorV3Interface", eth_price_feeds.ghst);
  });

  it("Should be able to get Price", async function () {
    const { answer: ethUsdPrice } = await ethUsdAggregator.latestRoundData();
    const { answer: ghstEthPrice } = await ghstEthAggregator.latestRoundData();
    const { answer: ghstUsdPrice } = await ghstUsdAggregator.latestRoundData();

    console.log("ETH/USD price:", ethUsdPrice.toString());
    console.log("GHST/ETH price:", ghstEthPrice.toString());
    console.log("GHST/USD price:", ghstUsdPrice.toString());
    expect(ghstUsdPrice).to.equal(ethUsdPrice.mul(ghstEthPrice).div(units(1)));
  });
});
