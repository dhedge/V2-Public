import { expect } from "chai";

import { polygonChainData } from "../../../config/chainData/polygon-data";
const { assets } = polygonChainData;

import { PoolFactory } from "../../../types";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { utils } from "../utils/utils";

describe("MaticX Price Aggregator Test", function () {
  let poolFactory: PoolFactory;
  let snapId: string;

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  beforeEach(async function () {
    snapId = await utils.evmTakeSnap();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
  });

  it("MaticX Price Aggregator", async () => {
    const maticXPrice = await poolFactory.getAssetPrice(assets.maticX);
    console.log("maticXPrice = ", maticXPrice.toString());

    const maticPrice = await poolFactory.getAssetPrice(assets.wmatic);
    console.log("maticPrice = ", maticPrice.toString());

    expect(maticXPrice.gt(maticPrice)).to.equal(true);
  });
});
