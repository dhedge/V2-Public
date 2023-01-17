import { expect } from "chai";
import { ethers } from "hardhat";
import { DhedgeStakingV2NFTJson } from "../../../types";
import { utils } from "../../integration/utils/utils";
import { BigNumber } from "ethers";
import { units } from "../../TestHelpers";
import * as fs from "fs";

describe("Dhedge DHT Staking V2", () => {
  let dhedgeStakingV2NFTJson: DhedgeStakingV2NFTJson;

  beforeEach(async () => {
    const DhedgeStakingV2NFTJson = await ethers.getContractFactory("DhedgeStakingV2NFTJson");
    dhedgeStakingV2NFTJson = await DhedgeStakingV2NFTJson.deploy();
    await dhedgeStakingV2NFTJson.deployed();
  });

  describe("tokenURI", () => {
    it.skip("lots of svgs", async () => {
      const tokenId = BigNumber.from(0);
      const currentTokenPrice = units(1);
      for (let i = 0; i < 100; i++) {
        const tokenURI = await dhedgeStakingV2NFTJson.tokenJson(
          tokenId,
          {
            dhtAmount: units(100),
            claimedReward: units(0),
            dhtStakeStartTime: (await utils.currentBlockTimestamp()) - 86400 * 4,
            dhedgePoolAddress: ethers.Wallet.createRandom().address,
            dhedgePoolAmount: units(21105).div(100),
            // dhedgePoolAmount: units(1).div(1000),
            dhedgePoolStakeStartTime: (await utils.currentBlockTimestamp()) - 86400 * 4,
            dhedgePoolRemainingExitCooldownAtStakeTime: BigNumber.from(0),
            reward: BigNumber.from(0),
            stakeStartTokenPrice: BigNumber.from(0),
            unstaked: false,
            unstakeTime: BigNumber.from(0),
            rewardParamsEmissionsRate: BigNumber.from(1500),
            vdhtAccruedAtUnstake: units(100),
            stakeFinishTokenPrice: BigNumber.from(1),
          },
          units(100),
          units(50),
          "DHPT",
          currentTokenPrice,
          "0x8c92e38eca8210f4fcbf17f0951b198dd7668292",
          ethers.Wallet.createRandom().address,
        );
        expect(tokenURI.includes("data:application/json;base64,")).to.be.true;
        const buff = Buffer.from(tokenURI.replace("data:application/json;base64,", ""), "base64");
        const jsonRaw = buff.toString("ascii");
        const meta = JSON.parse(jsonRaw);

        fs.writeFileSync(__dirname + "/nft_image" + i + ".svg", meta["image_data"]);
      }
    });
    // https://github.com/Uniswap/v3-periphery/blob/de4e437ae97ba21d71a856167968ea05a05853fe/contracts/libraries/NFTSVG.sol
    // https://github.com/Uniswap/v3-periphery/blob/de4e437ae97ba21d71a856167968ea05a05853fe/contracts/NonfungibleTokenPositionDescriptor.sol
    // https://github.com/Uniswap/v3-periphery/blob/de4e437ae97ba21d71a856167968ea05a05853fe/contracts/libraries/NFTDescriptor.sol
    it("Returns correct metadata", async () => {
      const tokenId = BigNumber.from(0);
      const currentTokenPrice = units(1);
      const tokenURI = await dhedgeStakingV2NFTJson.tokenJson(
        tokenId,
        {
          dhtAmount: units(100),
          claimedReward: units(0),
          dhtStakeStartTime: (await utils.currentBlockTimestamp()) - 86400 * 4,
          dhedgePoolAddress: "0x10a297326186585432adb12e4b23b4b2460f64e6",
          dhedgePoolAmount: units(21105).div(100),
          // dhedgePoolAmount: units(1).div(1000),
          dhedgePoolStakeStartTime: (await utils.currentBlockTimestamp()) - 86400 * 4,
          dhedgePoolRemainingExitCooldownAtStakeTime: BigNumber.from(0),
          reward: BigNumber.from(0),
          stakeStartTokenPrice: BigNumber.from(0),
          unstaked: false,
          unstakeTime: BigNumber.from(0),
          rewardParamsEmissionsRate: BigNumber.from(1500),
          vdhtAccruedAtUnstake: units(100),
          stakeFinishTokenPrice: BigNumber.from(1),
        },
        units(100),
        units(50),
        "DHPT",
        currentTokenPrice,
        "0x8c92e38eca8210f4fcbf17f0951b198dd7668292",
        "0x51150F973c2b0537642f5AE8911A49567598808f",
      );
      expect(tokenURI.includes("data:application/json;base64,")).to.be.true;
      const buff = Buffer.from(tokenURI.replace("data:application/json;base64,", ""), "base64");
      const jsonRaw = buff.toString("ascii");
      const meta = JSON.parse(jsonRaw);
      expect(meta["name"]).to.equal("DHT Stake: " + tokenId);
      expect(meta["description"]).to.equal("vDHT Accruing DHT stake");
      expect(meta["attributes"]).to.deep.equals([
        { trait_type: "Staked DHT", value: 100000000000000000000 },
        { trait_type: "vDHT", value: 100000000000000000000 },
      ]);
      expect(meta["image_data"]).to.equal(
        "<?xml version='1.0' encoding='UTF-8'?> <svg width='599' height='844' font-family='Arial' viewBox='0 0 599 844' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'><g id='Group'><linearGradient id='linearGradient1' x1='14.8' y1='14.5' x2='584.4' y2='14.5' gradientUnits='userSpaceOnUse'><stop offset='1e-05' stop-color='#8fa0d0' stop-opacity='1'/><stop offset='1' stop-color='#e65093' stop-opacity='1'/></linearGradient><path id='Path' fill='url(#linearGradient1)' stroke='none' d='M 40.100006 828.700012 C 26.199997 828.700012 14.800003 817.400024 14.800003 803.400024 L 14.800003 39.799988 C 14.800003 25.900024 26.100006 14.5 40.100006 14.5 L 559.099976 14.5 C 573 14.5 584.400024 25.799988 584.400024 39.799988 L 584.400024 803.5 C 584.400024 817.400024 573.099976 828.799988 559.099976 828.799988 L 40.100006 828.799988 Z'/><path id='path1' fill='url(#linearGradient1)' stroke='none' d='M 559.099976 29 C 565 29 569.900024 33.799988 569.900024 39.799988 L 569.900024 803.5 C 569.900024 809.400024 565.099976 814.299988 559.099976 814.299988 L 40.100006 814.299988 C 34.199997 814.299988 29.300003 809.5 29.300003 803.5 L 29.300003 39.799988 C 29.300003 33.900024 34.100006 29 40.100006 29 L 559.099976 29 M 559.099976 0 L 40.100006 0 C 18.100006 0 0.300003 17.799988 0.300003 39.799988 L 0.300003 803.5 C 0.300003 825.5 18.100006 843.299988 40.100006 843.299988 L 559.099976 843.299988 C 581.099976 843.299988 598.900024 825.5 598.900024 803.5 L 598.900024 39.799988 C 598.900024 17.799988 581.099976 0 559.099976 0 L 559.099976 0 Z'/> </g> <path id='path2' fill='none' stroke='#000000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M 235 227.799988 C 235 275.848755 196.048767 314.799988 148 314.799988 C 99.951233 314.799988 61 275.848755 61 227.799988 C 61 179.751221 99.951233 140.799988 148 140.799988 C 196.048767 140.799988 235 179.751221 235 227.799988 Z'/> <g id='g1'> <path id='path3' fill='none' stroke='#000000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M 235 227.799988 C 235 275.848755 196.048767 314.799988 148 314.799988 C 99.951233 314.799988 61 275.848755 61 227.799988 C 61 179.751221 99.951233 140.799988 148 140.799988 C 196.048767 140.799988 235 179.751221 235 227.799988 Z'/> <path id='path4' fill='none' stroke='#000000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M 118.100006 146 C 118.100006 146 64.100006 212.099976 109.700012 305.700012'/> <path id='path5' fill='none' stroke='#000000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M 149 140.799988 L 146.299988 314.799988'/> <path id='path6' fill='none' stroke='#000000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M 177.200012 309.299988 C 177.200012 309.299988 231.200012 243.200012 185.600006 149.599976'/> <path id='path7' fill='none' stroke='#000000' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' d='M 227.899994 191.799988 C 227.899994 191.799988 158.899994 141.5 67.899994 192.299988'/> <path id='path8' fill='none' stroke='#000000' stroke-width='2.0158' stroke-linecap='round' stroke-linejoin='round' d='M 67.299988 260 C 67.299988 260 137.399994 310.200012 229.799988 259.299988'/> <path id='path9' fill='none' stroke='#000000' stroke-width='1.4931' stroke-linecap='round' stroke-linejoin='round' d='M 232.399994 212 C 232.399994 212 159.299988 185.599976 62.899994 212.299988'/> <path id='path10' fill='none' stroke='#000000' stroke-width='1.4931' stroke-linecap='round' stroke-linejoin='round' d='M 63.100006 247.799988 C 63.100006 247.799988 136.200012 274.200012 232.600006 247.5'/> <path id='path11' fill='none' stroke='#000000' stroke-width='2.9743' stroke-linecap='round' stroke-linejoin='round' d='M 568.400024 717.900024 L 204.5 296.099976'/> </g> <g id='g2'> <path id='path12' fill='#000000' stroke='none' d='M 88.899994 779.099976 C 88.899994 778.599976 88.899994 778.200012 88.899994 777.799988 C 88.899994 760.900024 88.899994 744 88.899994 727.099976 C 88.899994 726.099976 89.200012 725.700012 90.100006 725.299988 C 93.399994 724 96.600006 722.599976 99.899994 721.200012 C 100.200012 721.099976 100.5 721 101 720.799988 C 101 721.200012 101 721.599976 101 721.900024 C 101 739 101 756.200012 101 773.299988 C 101 774.099976 100.799988 774.5 100 774.799988 C 96.700012 776 93.399994 777.299988 90.100006 778.599976 C 89.700012 778.799988 89.399994 779 88.899994 779.099976 Z'/> <path id='path13' fill='#000000' stroke='none' d='M 122.399994 783.5 C 119.399994 782 116.5 780.5 113.600006 779.099976 C 113.600006 779.099976 113.5 779.099976 113.5 779.099976 C 110.799988 777.5 110.600006 776.799988 110.600006 774.400024 C 110.700012 764.700012 110.700012 755 110.700012 745.299988 C 110.700012 744.900024 110.700012 744.5 110.700012 743.900024 C 111.799988 744.400024 112.899994 744.799988 113.899994 745.299988 C 116.399994 746.400024 119 747.599976 121.5 748.700012 C 122 748.900024 122.5 749.200012 122.399994 749.900024 C 122.399994 760.799988 122.399994 771.700012 122.399994 782.700012 C 122.399994 782.900024 122.399994 783.099976 122.399994 783.5 Z'/> <path id='path14' fill='#000000' stroke='none' d='M 67.200012 787.900024 C 67.200012 787.400024 67.200012 787 67.200012 786.700012 C 67.200012 778 67.200012 769.200012 67.200012 760.5 C 67.200012 759.700012 67.399994 759.299988 68.200012 759 C 71.600006 757.5 75 755.900024 78.399994 754.400024 C 78.5 754.299988 78.700012 754.299988 79 754.200012 C 79 754.599976 79 754.900024 79 755.299988 C 79 764.200012 79 773.200012 79 782.099976 C 79 782.900024 78.799988 783.200012 78.100006 783.5 C 74.700012 785 71.299988 786.400024 67.899994 787.900024 C 67.799988 787.900024 67.600006 787.900024 67.200012 787.900024 Z'/> </g> <path id='path15' fill='none' stroke='#000000' stroke-width='0.9801' stroke-linecap='round' stroke-linejoin='round' d='M 296.899994 140.799988 C 296.899994 164.382568 277.782562 183.5 254.200012 183.5 C 230.617432 183.5 211.5 164.382568 211.5 140.799988 C 211.5 117.217407 230.617432 98.099976 254.200012 98.099976 C 277.782562 98.099976 296.899994 117.217407 296.899994 140.799988 Z'/> <g id='g3'> <path id='path16' fill='none' stroke='#000000' stroke-width='0.9801' stroke-linecap='round' stroke-linejoin='round' d='M 296.899994 140.799988 C 296.899994 164.382568 277.782562 183.5 254.200012 183.5 C 230.617432 183.5 211.5 164.382568 211.5 140.799988 C 211.5 117.217407 230.617432 98.099976 254.200012 98.099976 C 277.782562 98.099976 296.899994 117.217407 296.899994 140.799988 Z'/> <path id='path17' fill='none' stroke='#000000' stroke-width='0.9991' stroke-linecap='round' stroke-linejoin='round' d='M 238.5 99.900024 C 238.5 99.900024 211.5 132.900024 234.299988 179.700012'/> <path id='path18' fill='none' stroke='#000000' stroke-width='0.9801' stroke-linecap='round' stroke-linejoin='round' d='M 254.700012 98.099976 L 253.399994 183.400024'/> <path id='path19' fill='none' stroke='#000000' stroke-width='0.9991' stroke-linecap='round' stroke-linejoin='round' d='M 268 181.5 C 268 181.5 295 148.5 272.200012 101.700012'/> <path id='path20' fill='none' stroke='#000000' stroke-width='0.9801' stroke-linecap='round' stroke-linejoin='round' d='M 293.399994 123.099976 C 293.399994 123.099976 259.600006 98.5 215 123.400024'/> <path id='path21' fill='none' stroke='#000000' stroke-width='0.9879' stroke-linecap='round' stroke-linejoin='round' d='M 214.700012 156.599976 C 214.700012 156.599976 249 181.200012 294.299988 156.299988'/> <path id='path22' fill='none' stroke='#000000' stroke-width='0.7344' stroke-linecap='round' stroke-linejoin='round' d='M 295 132.799988 C 295 132.799988 259 119.799988 211.600006 132.900024'/> <path id='path23' fill='none' stroke='#000000' stroke-width='0.7317' stroke-linecap='round' stroke-linejoin='round' d='M 212.600006 150.599976 C 212.600006 150.599976 248.399994 163.599976 295.700012 150.5'/></g><text id='ETHBull3x---' xml:space='preserve'><tspan x='64' y='457' font-size='28' fill='#000000' xml:space='preserve'>DHPT</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><text id='TVL' xml:space='preserve'><tspan x='64' y='495' font-size='32' font-weight='700' fill='#000000' xml:space='preserve'>$211.05</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><text id='DHT-TIME-STAKED-' xml:space='preserve'><tspan x='265' y='229' font-size='24' fill='#000000' xml:space='preserve'>DHT TIME STAKED:</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><text id='4-Days--' xml:space='preserve'><tspan x='265' y='272' font-size='32' font-weight='700' fill='#000000' xml:space='preserve'>4 Days</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><text id='DHTVDHT---' xml:space='preserve'><tspan x='64' y='547' font-size='28' fill='#000000' xml:space='preserve'>DHT:VDHT</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><text id='dht:vdht' xml:space='preserve'><tspan x='64' y='585' font-size='32' font-weight='700' fill='#000000' xml:space='preserve'>100:100</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><text id='Rewards---' xml:space='preserve'><tspan x='64' y='636' font-size='28' fill='#000000' xml:space='preserve'>Rewards:</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><text id='10-DHT--' xml:space='preserve'><tspan x='64' y='674' font-size='32' font-weight='700' fill='#000000' xml:space='preserve'>50DHT</tspan><tspan font-size='12' fill='#000000' xml:space='preserve'></tspan></text><defs><path id='path24' d='M 109.299988 814.5 L 38 814.400024 C 38 814.400024 29.5 811.900024 29.300003 804 C 29.100006 794.799988 29.300003 443.5 29.300003 443.5'/></defs><defs><path id='path25' d='M 494 29.299988 L 558 29.099976 C 558 29.099976 570 27.200012 570 43.5 C 570 61.700012 569.700012 406.299988 569.700012 406.299988'/></defs><text id='---' xml:space='preserve'><textPath xlink:href='#path24' startOffset='1'><tspan font-size='12' fill='#000000' baseline-shift='2' xml:space='preserve'></tspan><tspan font-size='18' fill='#000000' baseline-shift='2' xml:space='preserve'>0x51150f973c2b0537642f5ae8911a49567598808f</tspan><tspan font-size='12' fill='#000000' baseline-shift='2' xml:space='preserve'></tspan></textPath></text><text id='text2' xml:space='preserve'><textPath xlink:href='#path25' startOffset='1'><tspan font-size='12' fill='#000000' baseline-shift='2' xml:space='preserve'></tspan><tspan font-size='18.4567' fill='#000000' baseline-shift='2' xml:space='preserve'>0x8c92e38eca8210f4fcbf17f0951b198dd7668292</tspan><tspan font-size='12' fill='#000000' baseline-shift='2' xml:space='preserve'></tspan></textPath></text></svg>",
      );
    });
  });
});
