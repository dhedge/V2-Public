import { ethers, network } from "hardhat";
import { expect } from "chai";
import { CTokenInterface, IERC20Extended, SonneFinancePriceAggregatorMock__factory } from "../../types";
import { parseUnits } from "@ethersproject/units";

interface ISonnePriceAggregatorSimulationTestParams {
  token: {
    address: string;
    cToken: string;
  };
  startBlock: number;
  numberOfBlocks: number;
}

export const runSonnePriceAggregatorSimulationTest = async (testParams: ISonnePriceAggregatorSimulationTestParams) => {
  const underlyingTokenContract = <IERC20Extended>(
    await ethers.getContractAt("IERC20Extended", testParams.token.address)
  );
  const cTokenContract = <CTokenInterface>await ethers.getContractAt("CTokenInterface", testParams.token.cToken);
  const cTokenDecimals = await cTokenContract.decimals();
  const underlyingTokenDecimals = await underlyingTokenContract.decimals();

  const sonneFinancePriceAggregatorMockFactory = <SonneFinancePriceAggregatorMock__factory>(
    await ethers.getContractFactory("SonneFinancePriceAggregatorMock")
  );

  // Obtain the bytecode needed to deploy the contract.
  const { data } = sonneFinancePriceAggregatorMockFactory.getDeployTransaction(
    testParams.token.cToken,
    parseUnits("0.02", underlyingTokenDecimals + 18 - cTokenDecimals),
  );

  for (let i = testParams.startBlock; i < testParams.startBlock + testParams.numberOfBlocks; i++) {
    // `blockTag` requires a hex string, so we need to convert the block number to hex.
    // However, we can't use the BigNumber.toHexString() method because it will return a hex string with leading 0s.
    // This is the alternative.
    const cleanedBlockNumber = "0x" + i.toString(16);

    // Perform a eth_call. The constructor will return data encoded using abi.encode.
    const retDataEncoded = await network.provider.send("eth_call", [
      {
        from: "0x55DCad916750C19C4Ec69D65Ff0317767B36cE90",
        data: data,
      },
      cleanedBlockNumber,
    ]);

    // Decode the data returned by the constructor.
    const retData = ethers.utils.defaultAbiCoder.decode(["uint256"], retDataEncoded);

    const cTokenRetData = await cTokenContract.callStatic.exchangeRateCurrent({ blockTag: cleanedBlockNumber });

    expect(retData[0].toString()).to.be.equal(cTokenRetData);
  }

  console.info("No exchangeRate exceptions found!");
};
