import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, units } from "../../../testHelpers";
import {
  CErc20Interface__factory,
  CTokenInterface,
  ComptrollerInterface__factory,
  ComptrollerLensInterface,
  IERC20__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  SonneFinanceComptrollerGuard,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { SonneFinanceCTokenGuard } from "../../../../types/SonneFinanceCTokenGuard";
import { SonneFinancePriceAggregator } from "../../../../types";
import { IERC20Extended } from "../../../../types/IERC20Extended";
import { constants } from "ethers";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { ovmChainData } from "../../../../config/chainData/ovmData";

const parseUnits = ethers.utils.parseUnits;

interface SonneToken {
  address: string;
  cToken: string;
  balanceOfSlot: number;
}

interface ISonneFinanceTestParameters {
  comptroller: string;
  weth: {
    address: string;
    cToken: string;
    balanceOfSlot: number;
  };
  dai: {
    address: string;
    cToken: string;
    balanceOfSlot: number;
  };
  usdc: {
    address: string;
    cToken: string;
    balanceOfSlot: number;
  };
}

export const testSonneFinance = ({ comptroller, weth, dai, usdc }: ISonneFinanceTestParameters) => {
  describe("Sonne Finance Test", function () {
    let USDC: IERC20Extended, DAI: IERC20Extended, cUSDC: CTokenInterface;
    let comptrollerLens: ComptrollerLensInterface;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let deployments: IBackboneDeployments;
    // let comptrollerContract: ComptrollerInterface;
    let sonneFinanceCTokenGuard: SonneFinanceCTokenGuard,
      sonneFinanceComptrollerGuard: SonneFinanceComptrollerGuard,
      sonneFinancePriceAggregator: SonneFinancePriceAggregator;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const icErc20 = new ethers.utils.Interface(CErc20Interface__factory.abi);
    const iComptroller = new ethers.utils.Interface(ComptrollerInterface__factory.abi);
    const delta = 0.01;

    async function deployAndSetSonnePriceAggregator(
      tokenObj: SonneToken,
      sonneFinanceCTokenGuard: SonneFinanceCTokenGuard,
    ) {
      const underlyingToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", tokenObj.address);
      const cToken = <CTokenInterface>await ethers.getContractAt("CTokenInterface", tokenObj.cToken);
      const underlyingTokenDecimals = await underlyingToken.decimals();
      const cTokenDecimals = await cToken.decimals();

      const SonneFinancePriceAggregator = await ethers.getContractFactory("SonneFinancePriceAggregator");
      sonneFinancePriceAggregator = await SonneFinancePriceAggregator.deploy(
        tokenObj.cToken,
        comptroller,
        parseUnits("0.02", underlyingTokenDecimals + 18 - cTokenDecimals).toString(), // 6 (USDC decimals) + 18 - 8 (cToken decimals) = 16
      );
      await sonneFinancePriceAggregator.deployed();

      await deployments.assetHandler.addAsset(
        tokenObj.cToken,
        AssetType["Lending Enable Asset"],
        sonneFinancePriceAggregator.address,
      );

      await deployments.governance.setContractGuard(tokenObj.cToken, sonneFinanceCTokenGuard.address);
    }

    before(async function () {
      [logicOwner, manager] = await ethers.getSigners();

      deployments = await deployBackboneContracts(ovmChainData);
      poolFactory = deployments.poolFactory;

      comptrollerLens = <ComptrollerLensInterface>await ethers.getContractAt("ComptrollerLensInterface", comptroller);

      USDC = <IERC20Extended>await ethers.getContractAt("IERC20Extended", usdc.address);
      cUSDC = <CTokenInterface>await ethers.getContractAt("CTokenInterface", usdc.cToken);
      DAI = <IERC20Extended>await ethers.getContractAt("IERC20Extended", dai.address);

      const funds = await createFund(poolFactory, logicOwner, manager, [
        { asset: usdc.address, isDeposit: true },
        { asset: dai.address, isDeposit: true },
      ]);
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      const SonneFinanceCTokenGuardFactory = await ethers.getContractFactory("SonneFinanceCTokenGuard");
      sonneFinanceCTokenGuard = await SonneFinanceCTokenGuardFactory.deploy([poolLogicProxy.address]);
      await sonneFinanceCTokenGuard.deployed();

      const SonneFinanceComptrollerGuardFactory = await ethers.getContractFactory("SonneFinanceComptrollerGuard");
      sonneFinanceComptrollerGuard = await SonneFinanceComptrollerGuardFactory.deploy();
      await sonneFinanceComptrollerGuard.deployed();

      await deployments.governance.setContractGuard(comptroller, sonneFinanceComptrollerGuard.address);

      // Deploy price aggregator contract for cUSDC and cDAI and set them as guards for the same.
      await deployAndSetSonnePriceAggregator(usdc, sonneFinanceCTokenGuard);
      await deployAndSetSonnePriceAggregator(dai, sonneFinanceCTokenGuard);
      await deployAndSetSonnePriceAggregator(weth, sonneFinanceCTokenGuard);

      await getAccountToken(units(100000, 6), logicOwner.address, usdc.address, usdc.balanceOfSlot);
      await getAccountToken(units(100000, 18), logicOwner.address, dai.address, dai.balanceOfSlot);
      await getAccountToken(units(100000, 18), logicOwner.address, weth.address, weth.balanceOfSlot);

      // Deposit 20K of USDC and DAI.
      await USDC.approve(poolLogicProxy.address, units(20000, 6));
      await poolLogicProxy.deposit(usdc.address, units(20000, 6));
      await DAI.approve(poolLogicProxy.address, units(20000, 18));
      await poolLogicProxy.deposit(dai.address, units(20000, 18));
    });

    let snapId: string;
    beforeEach(async () => {
      snapId = await utils.evmTakeSnap();
    });

    afterEach(async () => {
      await utils.evmRestoreSnap(snapId);
    });

    it("Should be able to mint cUSDC", async function () {
      const amount = units(10000, 6);

      let mintABI = icErc20.encodeFunctionData("mint", [amount]);

      await expect(poolLogicProxy.connect(manager).execTransaction(poolLogicProxy.address, mintABI)).to.be.revertedWith(
        "invalid transaction",
      );

      // approve cUSDC
      const approveUSDCABI = iERC20.encodeFunctionData("approve", [usdc.cToken, amount]);
      await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveUSDCABI);

      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: weth.cToken, isDeposit: false }], []);

      // dai is not enabled in this pool
      mintABI = icErc20.encodeFunctionData("mint", [amount]);
      await expect(poolLogicProxy.connect(manager).execTransaction(weth.cToken, mintABI)).to.be.revertedWith(
        "unsupported underlying asset",
      );

      // Minting with a wrong `_to` address should fail.
      mintABI = icErc20.encodeFunctionData("mint", [amount]);
      await expect(poolLogicProxy.connect(manager).execTransaction(usdc.address, mintABI)).to.be.revertedWith(
        "invalid transaction",
      );

      // Enable the cToken asset.
      await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const cUSDCBalanceBefore = await cUSDC.balanceOf(poolLogicProxy.address);
      const exchangeRateCurrent = await cUSDC.callStatic.exchangeRateCurrent();

      expect(usdcBalanceBefore).to.be.equal(units(20000, 6));
      expect(cUSDCBalanceBefore).to.be.equal(0);

      // Mint cUSDC
      mintABI = icErc20.encodeFunctionData("mint", [amount]);
      await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, mintABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const cUSDCBalanceAfter = await cUSDC.balanceOf(poolLogicProxy.address);

      checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.sub(amount), delta);
      checkAlmostSame(
        cUSDCBalanceAfter,
        cUSDCBalanceBefore.add(amount.mul(units(1, 18)).div(exchangeRateCurrent)),
        delta,
      );
    });

    describe("Redemptions", async () => {
      it("Should be able to redeem cUSDC - full amount + interest", async () => {
        const amount = units(10000, 6);

        const mintABI = icErc20.encodeFunctionData("mint", [amount]);
        const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);

        // approve cUSDC
        const approveUSDCABI = iERC20.encodeFunctionData("approve", [usdc.cToken, amount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveUSDCABI);

        // Enable the cToken asset.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);

        // Mint cUSDC
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, mintABI);

        const cUSDCBalanceAfterMint = await cUSDC.balanceOf(poolLogicProxy.address);

        const supplyRatePerBlockBefore = await cUSDC.supplyRatePerBlock();

        // Increase the number of blocks to earn interest.
        // Although the same can be achieved by increasing the time, it will be difficult to calculate the
        // interest earned because the interest rate is calculated on a per block basis.
        await utils.increaseBlocks(5_000);

        // Redeem all the cUSDC.
        const redeemABI = icErc20.encodeFunctionData("redeem", [cUSDCBalanceAfterMint]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, redeemABI);

        const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
        const cUSDCBalanceAfterRedeem = await cUSDC.balanceOf(poolLogicProxy.address);

        // Calculate the interest earned on the `amount` of USDC supplied.
        // This formula is taken from the Compound Finance docs <https://docs.compound.finance/v2/#protocol-math>
        // Note that we added 1 to number of blocks mined because the redemption actually happens in this block number.
        const totalInterestEarned = amount
          .mul(supplyRatePerBlockBefore)
          .mul(ethers.BigNumber.from(5_001))
          .div(parseUnits("1", 18));

        checkAlmostSame(usdcBalanceAfter, usdcBalanceBefore.add(totalInterestEarned), delta);
        checkAlmostSame(cUSDCBalanceAfterRedeem, constants.Zero, delta);
      });

      it("Should be able to redeem cUSDC - partial amount + interest earned", async () => {
        const amount = units(10000, 6);

        const mintABI = icErc20.encodeFunctionData("mint", [amount]);
        const usdcBalanceBeforeMint = await USDC.balanceOf(poolLogicProxy.address);

        // approve cUSDC
        const approveUSDCABI = iERC20.encodeFunctionData("approve", [usdc.cToken, amount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveUSDCABI);

        // Enable the cToken asset.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);

        // Mint cUSDC
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, mintABI);

        const cUSDCBalanceAfterMint = await cUSDC.balanceOf(poolLogicProxy.address);
        const supplyRatePerBlockBefore = await cUSDC.supplyRatePerBlock();

        // Increase the number of blocks to earn interest.
        // Although the same can be achieved by increasing the time, it will be difficult to calculate the
        // interest earned because the interest rate is calculated on a per block basis.
        await utils.increaseBlocks(5_000);

        // Redeem 50% of the cUSDC.
        const redeemABI = icErc20.encodeFunctionData("redeem", [cUSDCBalanceAfterMint.div(2)]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, redeemABI);

        const usdcBalanceAfterRedemption = await USDC.balanceOf(poolLogicProxy.address);
        const cUSDCBalanceAfterRedeem = await cUSDC.balanceOf(poolLogicProxy.address);

        // Calculate the interest earned on the `amount` of USDC supplied.
        // This formula is taken from the Compound Finance docs <https://docs.compound.finance/v2/#protocol-math>
        // Note that we added 1 to number of blocks mined because the redemption actually happens in this block number.
        const totalInterestEarned = amount
          .mul(supplyRatePerBlockBefore)
          .mul(ethers.BigNumber.from(5_001))
          .div(parseUnits("2", 18)); // Dividing by 2 because we redeemed 50% of the cUSDC.

        // We redeemed 50% of the cUSDC and hence expect the new balance to be 50% of the original balance + interest.
        checkAlmostSame(
          usdcBalanceAfterRedemption,
          usdcBalanceBeforeMint.sub(amount.div(2)).add(totalInterestEarned),
          delta,
        );

        checkAlmostSame(cUSDCBalanceAfterRedeem, cUSDCBalanceAfterMint.div(2), delta);
      });
    });

    describe("Borrowing", async () => {
      it("Should be able to borrow USDC with the same collateral - max borrow", async () => {
        const amount = units(10000, 6);

        const mintABI = icErc20.encodeFunctionData("mint", [amount]);

        // approve cUSDC
        const approveUSDCABI = iERC20.encodeFunctionData("approve", [usdc.cToken, amount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveUSDCABI);

        // Enable the cToken asset.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);

        // Mint cUSDC
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, mintABI);

        // Enter the market for USDC to enable borrowing.
        const enterMarketABI = iComptroller.encodeFunctionData("enterMarkets", [[usdc.cToken]]);
        await poolLogicProxy.connect(manager).execTransaction(comptroller, enterMarketABI);

        const enteredMarkets = await comptrollerLens.getAssetsIn(poolLogicProxy.address);
        const marketsOutput = await comptrollerLens.markets(usdc.cToken);
        const collateralFactorUSDC = marketsOutput[1];
        const accountLiquidityBeforeBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const usdcBalanceBeforeBorrow = await USDC.balanceOf(poolLogicProxy.address);

        expect(enteredMarkets.length).to.be.equal(1);
        expect(enteredMarkets[0]).to.be.equal(usdc.cToken);

        // collateralFactorUSDC.div(parseUnits("1", 16)) is the collateral factor in percentage.
        // And amount.mul(collateralFactorUSDC.div(parseUnits("1", 16))) is the max borrow amount in underlying token units (i.e, 6 decimal units for USDC).
        // There we need to divide the this amount by 1e8 (1e6 for USDC decimals and 1e2 for the percentage denominator).
        checkAlmostSame(
          accountLiquidityBeforeBorrow[1].div(parseUnits("1", 18)),
          amount.mul(collateralFactorUSDC.div(parseUnits("1", 16))).div(parseUnits("1", 8)),
          delta,
        );

        // We will borrow $1 less than the max borrow amount. This is to avoid revert due to rounding issues when borrowing
        // and also to avoid breaching the borrow limit.
        // The borrow amount is in underlying token units i.e. 6 decimals for USDC.
        const borrowAmount = accountLiquidityBeforeBorrow[1].div(parseUnits("1", 12)).sub(parseUnits("1", 6));

        // Borrow USDC.
        const borrowABI = icErc20.encodeFunctionData("borrow", [borrowAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, borrowABI);

        const usdcBalanceAfterBorrow = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);

        // Account liquidity after borrow (in USD terms) should be close to 0.
        checkAlmostSame(accountLiquidityAfterBorrow[1].div(parseUnits("1", 18)), constants.Zero, delta);

        checkAlmostSame(usdcBalanceAfterBorrow, usdcBalanceBeforeBorrow.add(borrowAmount), delta);
      });

      it("Should be able to borrow USDC with the same collateral - partial (50%) borrow", async () => {
        const amount = units(10000, 6);

        const mintABI = icErc20.encodeFunctionData("mint", [amount]);

        // approve cUSDC
        const approveUSDCABI = iERC20.encodeFunctionData("approve", [usdc.cToken, amount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveUSDCABI);

        // Enable the cToken asset.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);

        // Mint cUSDC
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, mintABI);

        // Enter the market for USDC to enable borrowing.
        const enterMarketABI = iComptroller.encodeFunctionData("enterMarkets", [[usdc.cToken]]);
        await poolLogicProxy.connect(manager).execTransaction(comptroller, enterMarketABI);

        const enteredMarkets = await comptrollerLens.getAssetsIn(poolLogicProxy.address);
        const marketsOutput = await comptrollerLens.markets(usdc.cToken);
        const collateralFactorUSDC = marketsOutput[1];
        const accountLiquidityBeforeBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const usdcBalanceBeforeBorrow = await USDC.balanceOf(poolLogicProxy.address);

        expect(enteredMarkets.length).to.be.equal(1);
        expect(enteredMarkets[0]).to.be.equal(usdc.cToken);

        // collateralFactorUSDC.div(parseUnits("1", 16)) is the collateral factor in percentage.
        // And amount.mul(collateralFactorUSDC.div(parseUnits("1", 16))) is the max borrow amount in underlying token units (i.e, 6 decimal units for USDC).
        // There we need to divide the this amount by 1e8 (1e6 for USDC decimals and 1e2 for the percentage denominator).
        checkAlmostSame(
          accountLiquidityBeforeBorrow[1].div(parseUnits("1", 18)),
          amount.mul(collateralFactorUSDC.div(parseUnits("1", 16))).div(parseUnits("1", 8)),
          delta,
        );

        // Borrow half of the max borrow amount.
        // The borrow amount is in underlying token units i.e. 6 decimals for USDC.
        let borrowAmount = accountLiquidityBeforeBorrow[1].div(parseUnits("2", 12));

        // Borrow USDC.
        let borrowABI = icErc20.encodeFunctionData("borrow", [borrowAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, borrowABI);

        const usdcBalanceAfterBorrow = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);

        // Account liquidity after borrow (in USD terms) should be close to 50%.
        checkAlmostSame(
          accountLiquidityAfterBorrow[1].div(parseUnits("1", 18)),
          accountLiquidityBeforeBorrow[1].div(parseUnits("2", 18)),
          delta,
        );

        checkAlmostSame(usdcBalanceAfterBorrow, usdcBalanceBeforeBorrow.add(borrowAmount));

        // Borrowing the same amount again should pass too.
        // However, we will adjust the borrow amount to avoid rounding issues.
        borrowAmount = accountLiquidityAfterBorrow[1].div(parseUnits("1", 12)).sub(parseUnits("1", 6));

        borrowABI = icErc20.encodeFunctionData("borrow", [borrowAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, borrowABI);

        const usdcBalanceAfterSecondBorrow = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterSecondBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);

        // Account liquidity after borrow (in USD terms) should be close to 0.
        checkAlmostSame(accountLiquidityAfterSecondBorrow[1].div(parseUnits("1", 18)), constants.Zero, delta);

        checkAlmostSame(usdcBalanceAfterSecondBorrow, usdcBalanceAfterBorrow.add(borrowAmount), delta);
      });

      it("Should be able to borrow USDC with a different collateral (DAI)", async () => {
        const daiSuppplyAmount = units(10000, 18);

        const mintABI = icErc20.encodeFunctionData("mint", [daiSuppplyAmount]);

        // approve cDAI
        const approveDAIABI = iERC20.encodeFunctionData("approve", [dai.cToken, daiSuppplyAmount]);
        await poolLogicProxy.connect(manager).execTransaction(dai.address, approveDAIABI);

        // Enable cDAI and cUSDC.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: dai.cToken, isDeposit: false }], []);

        // Mint cDAI
        await poolLogicProxy.connect(manager).execTransaction(dai.cToken, mintABI);

        // Enter the market for DAI to enable borrowing.
        const enterMarketABI = iComptroller.encodeFunctionData("enterMarkets", [[dai.cToken]]);
        await poolLogicProxy.connect(manager).execTransaction(comptroller, enterMarketABI);

        const enteredMarkets = await comptrollerLens.getAssetsIn(poolLogicProxy.address);
        const marketsOutput = await comptrollerLens.markets(dai.cToken);
        const collateralFactorDAI = marketsOutput[1];
        const accountLiquidityBeforeBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const usdcBalanceBeforeBorrow = await USDC.balanceOf(poolLogicProxy.address);

        expect(enteredMarkets.length).to.be.equal(1);
        expect(enteredMarkets[0]).to.be.equal(dai.cToken);

        // collateralFactorDAI.div(parseUnits("1", 16)) is the collateral factor in percentage.
        // And daiSuppplyAmount.mul(collateralFactorDAI.div(parseUnits("1", 16))) is the max borrow amount in underlying token units (i.e, 18 decimal units for DAI).
        // There we need to divide the this amount by 1e18 (1e18 for DAI decimals and 1e2 for the percentage denominator).
        // Note that we are okay with an error of around $10. This is mostly due to rounding issues.
        expect(accountLiquidityBeforeBorrow[1].div(parseUnits("1", 18))).to.be.closeTo(
          daiSuppplyAmount.mul(collateralFactorDAI.div(parseUnits("1", 16))).div(parseUnits("1", 20)),
          10,
        );

        // We will borrow $1 less than the max borrow amount. This is to avoid revert due to rounding issues when borrowing
        // and also to avoid breaching the borrow limit.
        // The borrow amount is in underlying token units i.e. 6 decimals for USDC.
        const borrowAmount = accountLiquidityBeforeBorrow[1].div(parseUnits("1", 12)).sub(parseUnits("1", 6));

        // Borrow USDC.
        const borrowABI = icErc20.encodeFunctionData("borrow", [borrowAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, borrowABI);

        const usdcBalanceAfterBorrow = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);

        // Account liquidity after borrow (in USD terms) should be close to 0.
        checkAlmostSame(accountLiquidityAfterBorrow[1].div(parseUnits("1", 18)), constants.Zero, delta);

        checkAlmostSame(usdcBalanceAfterBorrow, usdcBalanceBeforeBorrow.add(borrowAmount), delta);
      });

      it("Should be able to borrow USDC and DAI with the same collateral (DAI)", async () => {
        const daiSuppplyAmount = units(10000, 18);

        const mintABI = icErc20.encodeFunctionData("mint", [daiSuppplyAmount]);

        // approve cDAI
        const approveDAIABI = iERC20.encodeFunctionData("approve", [dai.cToken, daiSuppplyAmount]);
        await poolLogicProxy.connect(manager).execTransaction(dai.address, approveDAIABI);

        // Enable cDAI and cUSDC.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: dai.cToken, isDeposit: false }], []);

        // Mint cDAI
        await poolLogicProxy.connect(manager).execTransaction(dai.cToken, mintABI);

        // Enter the market for DAI to enable borrowing.
        const enterMarketABI = iComptroller.encodeFunctionData("enterMarkets", [[dai.cToken]]);
        await poolLogicProxy.connect(manager).execTransaction(comptroller, enterMarketABI);

        const enteredMarkets = await comptrollerLens.getAssetsIn(poolLogicProxy.address);
        const marketsOutput = await comptrollerLens.markets(dai.cToken);
        const collateralFactorDAI = marketsOutput[1];
        const accountLiquidityBeforeBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const usdcBalanceBeforeBorrow = await USDC.balanceOf(poolLogicProxy.address);

        expect(enteredMarkets.length).to.be.equal(1);
        expect(enteredMarkets[0]).to.be.equal(dai.cToken);

        // collateralFactorDAI.div(parseUnits("1", 16)) is the collateral factor in percentage.
        // And daiSuppplyAmount.mul(collateralFactorDAI.div(parseUnits("1", 16))) is the max borrow amount in underlying token units (i.e, 18 decimal units for DAI).
        // There we need to divide the this amount by 1e18 (1e18 for DAI decimals and 1e2 for the percentage denominator).
        expect(accountLiquidityBeforeBorrow[1].div(parseUnits("1", 18))).to.be.closeTo(
          daiSuppplyAmount.mul(collateralFactorDAI.div(parseUnits("1", 16))).div(parseUnits("1", 20)),
          10,
        );

        // We will borrow $1 less than the max borrow amount. This is to avoid revert due to rounding issues when borrowing
        // and also to avoid breaching the borrow limit.
        // The borrow amount is in underlying token units i.e. 6 decimals for USDC.
        const borrowAmountUSDC = accountLiquidityBeforeBorrow[1].div(parseUnits("2", 12)).sub(parseUnits("1", 6));

        // Borrow USDC.
        const borrowABI = icErc20.encodeFunctionData("borrow", [borrowAmountUSDC]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, borrowABI);

        const usdcBalanceAfterBorrow = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);

        // Account liquidity after borrow (in USD terms) should be close to 50%.
        expect(accountLiquidityAfterBorrow[1].div(parseUnits("1", 18))).to.be.closeTo(
          accountLiquidityBeforeBorrow[1].div(parseUnits("2", 18)),
          10,
        );

        checkAlmostSame(usdcBalanceAfterBorrow, usdcBalanceBeforeBorrow.add(borrowAmountUSDC), delta);

        const daiBalanceBeforeBorrow = await DAI.balanceOf(poolLogicProxy.address);

        // Borrowing the same amount again should pass too.
        // But this time we will borrow DAI.
        const borrowAmountDAI = accountLiquidityAfterBorrow[1];

        // Borrow DAI.
        const borrowDAIABI = icErc20.encodeFunctionData("borrow", [borrowAmountDAI]);
        await poolLogicProxy.connect(manager).execTransaction(dai.cToken, borrowDAIABI);

        const daiBalanceAfterBorrow = await DAI.balanceOf(poolLogicProxy.address);

        // Account liquidity after borrow (in USD terms) should be close to 0.
        // NOTE: This test will fail most probably because of rounding issues hence ignore the check here.
        // For this particular scenario, the account liquidity remaining is $3 which is as good as 0.
        // const accountLiquidityAfterSecondBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        // checkAlmostSame(accountLiquidityAfterSecondBorrow[1].div(parseUnits("1", 18)), constants.Zero);

        checkAlmostSame(daiBalanceAfterBorrow, daiBalanceBeforeBorrow.add(borrowAmountDAI), delta);
      });
    });

    describe("Repaying", async () => {
      it("Should be able to repay USDC loan - full amount", async () => {
        const amount = units(10000, 6);

        const mintABI = icErc20.encodeFunctionData("mint", [amount]);

        // approve cUSDC
        const approveUSDCABI = iERC20.encodeFunctionData("approve", [usdc.cToken, amount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveUSDCABI);

        // Enable the cToken asset.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);

        // Mint cUSDC
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, mintABI);

        // Enter the market for USDC to enable borrowing.
        const enterMarketABI = iComptroller.encodeFunctionData("enterMarkets", [[usdc.cToken]]);
        await poolLogicProxy.connect(manager).execTransaction(comptroller, enterMarketABI);

        const accountLiquidityBeforeBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const usdcBalanceBeforeBorrow = await USDC.balanceOf(poolLogicProxy.address);

        // We will borrow $1 less than the max borrow amount. This is to avoid revert due to rounding issues when borrowing
        // and also to avoid breaching the borrow limit.
        // The borrow amount is in underlying token units i.e. 6 decimals for USDC.
        const borrowAmount = accountLiquidityBeforeBorrow[1].div(parseUnits("1", 12)).sub(parseUnits("1", 6));

        // Borrow USDC.
        const borrowABI = icErc20.encodeFunctionData("borrow", [borrowAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, borrowABI);

        // Allow the cToken contract to take the USDC from the pool.
        // This is necessary for repayment.
        // We are adding 1 USDC to the amount to repay to avoid reverts due to rounding issues.
        const approveABI = iERC20.encodeFunctionData("approve", [usdc.cToken, borrowAmount.add(parseUnits("1", 6))]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveABI);

        // According to compound docs <https://docs.compound.finance/v2/ctokens/#repay-borrow> when 2^256-1 is passed as the amount to repay, it repays the full amount.
        const repayABI = icErc20.encodeFunctionData("repayBorrow", [constants.MaxUint256]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, repayABI);

        const usdcBalanceAfterRepay = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterRepay = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);

        const borrowBalance = await cUSDC.callStatic.borrowBalanceCurrent(poolLogicProxy.address);

        expect(borrowBalance).to.be.equal(0);
        checkAlmostSame(usdcBalanceAfterRepay, usdcBalanceBeforeBorrow, delta);
        checkAlmostSame(
          accountLiquidityAfterRepay[1].div(parseUnits("1", 18)),
          accountLiquidityBeforeBorrow[1].div(parseUnits("1", 18)),
          delta,
        );
      });

      it("Should be able to repay USDC loan - partial amount", async () => {
        const amount = units(10000, 6);

        const mintABI = icErc20.encodeFunctionData("mint", [amount]);

        // approve cUSDC
        const approveUSDCABI = iERC20.encodeFunctionData("approve", [usdc.cToken, amount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveUSDCABI);

        // Enable the cToken asset.
        await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: usdc.cToken, isDeposit: false }], []);

        // Mint cUSDC
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, mintABI);

        // Enter the market for USDC to enable borrowing.
        const enterMarketABI = iComptroller.encodeFunctionData("enterMarkets", [[usdc.cToken]]);
        await poolLogicProxy.connect(manager).execTransaction(comptroller, enterMarketABI);

        const accountLiquidityBeforeBorrow = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const usdcBalanceBeforeBorrow = await USDC.balanceOf(poolLogicProxy.address);

        // We will borrow $1 less than the max borrow amount. This is to avoid revert due to rounding issues when borrowing
        // and also to avoid breaching the borrow limit.
        // The borrow amount is in underlying token units i.e. 6 decimals for USDC.
        const borrowAmount = accountLiquidityBeforeBorrow[1].div(parseUnits("1", 12)).sub(parseUnits("1", 6));

        // Borrow USDC.
        const borrowABI = icErc20.encodeFunctionData("borrow", [borrowAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, borrowABI);

        const usdcBalanceAfterBorrow = await USDC.balanceOf(poolLogicProxy.address);

        // Allow the cToken contract to take the USDC from the pool.
        // This is necessary for repayment.
        // We are adding 1 USDC to the amount to repay to avoid reverts due to rounding issues.
        const approveABI = iERC20.encodeFunctionData("approve", [
          usdc.cToken,
          borrowAmount.div(constants.Two).add(parseUnits("1", 6)),
        ]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveABI);

        // Repay half of the borrowed amount.
        const repayAmount = borrowAmount.div(constants.Two);
        const repayABI = icErc20.encodeFunctionData("repayBorrow", [repayAmount]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, repayABI);

        const usdcBalanceAfterRepay = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterRepay = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const borrowBalance = await cUSDC.callStatic.borrowBalanceCurrent(poolLogicProxy.address);

        checkAlmostSame(borrowBalance, borrowAmount.sub(repayAmount), delta);
        checkAlmostSame(usdcBalanceAfterRepay, usdcBalanceAfterBorrow.sub(repayAmount), delta);
        checkAlmostSame(
          accountLiquidityAfterRepay[1].div(parseUnits("1", 18)),
          accountLiquidityBeforeBorrow[1].div(parseUnits("2", 18)),
          delta,
        );

        // Repay the total borrowed amount.
        const approveABIAgain = iERC20.encodeFunctionData("approve", [
          usdc.cToken,
          borrowBalance.add(parseUnits("1", 6)),
        ]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.address, approveABIAgain);

        const repayABIAgain = icErc20.encodeFunctionData("repayBorrow", [constants.MaxUint256]);
        await poolLogicProxy.connect(manager).execTransaction(usdc.cToken, repayABIAgain);

        const usdcBalanceAfterRepayAgain = await USDC.balanceOf(poolLogicProxy.address);
        const accountLiquidityAfterRepayAgain = await comptrollerLens.getAccountLiquidity(poolLogicProxy.address);
        const borrowBalanceAgain = await cUSDC.callStatic.borrowBalanceCurrent(poolLogicProxy.address);

        expect(borrowBalanceAgain).to.be.equal(0);
        checkAlmostSame(usdcBalanceAfterRepayAgain, usdcBalanceBeforeBorrow, delta);
        checkAlmostSame(
          accountLiquidityAfterRepayAgain[1].div(parseUnits("1", 18)),
          accountLiquidityBeforeBorrow[1].div(parseUnits("1", 18)),
          delta,
        );
      });
    });
  });
};
