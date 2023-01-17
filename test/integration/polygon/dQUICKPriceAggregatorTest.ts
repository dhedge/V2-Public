import { ethers } from "hardhat";
import { expect } from "chai";

import { units } from "../../TestHelpers";
import { polygonChainData } from "../../../config/chainData/polygon-data";
const { assets, quickswap } = polygonChainData;

import { PoolFactory } from "../../../types";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { utils } from "../utils/utils";

describe("dQUICK Price Aggregator Test", function () {
  let poolFactory: PoolFactory;
  let snapId: string;

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async function () {
    snapId = await utils.evmTakeSnap();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
  });

  it("dQUICK Price Aggregator", async function () {
    const dQUICKPrice = await poolFactory.getAssetPrice(quickswap.dQUICK);
    console.log("dQUICKPrice = ", dQUICKPrice.toString());

    const quickPrice = await poolFactory.getAssetPrice(assets.quick);
    console.log("quickPrice = ", quickPrice.toString());

    const dQUICK = await ethers.getContractAt("IDragonLair", quickswap.dQUICK);
    const dQUICKRate = await dQUICK.dQUICKForQUICK(units(1));
    console.log("dQUICKRate = ", dQUICKRate.toString());
    console.log(
      "quickPrice.mul(dQUICKRate).div(units(1, 18)) = ",
      quickPrice.mul(dQUICKRate).div(units(1, 18)).toString(),
    );

    expect(dQUICKPrice).to.equal(quickPrice.mul(dQUICKRate).div(units(1, 28)).mul(units(1, 10)));
  });
});
