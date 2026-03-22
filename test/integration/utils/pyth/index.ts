import axios from "axios";
import { IPyth, IPyth__factory } from "../../../../types";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export const updatePythPriceFeed = async (contract: string, priceFeedId: string, signer: SignerWithAddress) => {
  const params = {
    ids: [priceFeedId],
  };
  try {
    const { data } = await axios.get("https://hermes.pyth.network/v2/updates/price/latest", {
      params,
    });

    const iPyth = <IPyth>await ethers.getContractAt(IPyth__factory.abi, contract);

    // Get the update fee from the Pyth contract
    const updateFee = await iPyth.getUpdateFee([`0x${data.binary.data}`]);

    await iPyth.connect(signer).updatePriceFeeds([`0x${data.binary.data}`], {
      value: updateFee,
    });
  } catch (err: unknown) {
    console.log("Error updating pyth price feed", err);
  }
};
