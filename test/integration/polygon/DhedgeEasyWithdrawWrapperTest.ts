import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect, use } from "chai";
import { solidity } from "ethereum-waffle";
import { ethers } from "hardhat";

import { Contract } from "ethers";

import { units } from "../../TestHelpers";
import { assets, assetsBalanceOfSlot, sushi } from "../polygon-data";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { IERC20 } from "../../../types";

use(solidity);

describe("DhedgeEasyWithdrawWrapper", function () {
  let logicOwner: SignerWithAddress;
  let torosWrapper: Contract;
  let USDC: IERC20;

  before(async function () {
    [logicOwner] = await ethers.getSigners();
    // const deployments = await deployPolygonContracts();
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    USDC = await ethers.getContractAt("IERC20", assets.usdc);
  });

  describe("Toros Short Boi", () => {
    beforeEach(async function () {
      const DhedgeEasyWithdrawWrapper = await ethers.getContractFactory("DhedgeEasyWithdrawWrapper");

      // Short ETH
      const torosPoolAddress = "0xf4b3a195587d2735b656b7ffe9060f478faf1b32";
      torosWrapper = await DhedgeEasyWithdrawWrapper.deploy(
        "wrappedToros",
        "WTRS",
        torosPoolAddress,
        assets.usdc,
        assets.usdc,
        sushi.router,
        assets.weth,
      );
      await torosWrapper.deployed();
    });

    it("can deposit", async () => {
      await USDC.approve(torosWrapper.address, units(10000, 6));
      await torosWrapper.deposit(units(10000, 6));
      expect((await torosWrapper.balanceOf(logicOwner.address)) > 0).to.be.true;
    });
  });
});
