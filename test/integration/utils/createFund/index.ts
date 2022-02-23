import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { PoolFactory, PoolLogic__factory, PoolManagerLogic__factory } from "../../../../types";

export const createFund = async (
  poolFactory: PoolFactory,
  signer: SignerWithAddress,
  manager: SignerWithAddress,
  supportedAssets: { asset: string; isDeposit: boolean }[],
  performanceFee = 5000,
) => {
  const deployedFundsBefore = await poolFactory.getDeployedFunds();

  await poolFactory.createFund(
    false,
    manager.address,
    "Barren Wuffet",
    "Test Fund",
    "DHTF",
    ethers.BigNumber.from(performanceFee),
    supportedAssets,
  );

  const deployedFunds = await poolFactory.getDeployedFunds();
  expect(deployedFunds.length).to.be.equal(deployedFundsBefore.length + 1);

  const fundAddress = deployedFunds[deployedFunds.length - 1];
  expect(await poolFactory.isPool(fundAddress)).to.be.true;

  const poolLogicProxy = await PoolLogic__factory.connect(fundAddress, signer);
  const poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
  const poolManagerLogicProxy = await PoolManagerLogic__factory.connect(poolManagerLogicProxyAddress, signer);

  //default assets are supported
  expect((await poolManagerLogicProxy.getSupportedAssets()).length).to.eq(supportedAssets.length);
  for (const supportedAsset of supportedAssets) {
    expect(await poolManagerLogicProxy.isSupportedAsset(supportedAsset.asset)).to.be.true;
  }

  return {
    poolLogicProxy,
    poolManagerLogicProxy,
  };
};
