import { Contract, ContractFactory } from "ethers";
import { checkAlmostSame, units } from "../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { aave, assets, assetsBalanceOfSlot } from "../../../config/chainData/polygon-data";
import { artifacts, ethers } from "hardhat";
import { expect } from "chai";
import { Interface } from "@ethersproject/abi";
import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts } from "../utils/deployContracts";

const { BigNumber } = ethers;

const oneDollar = units(1);
const twoDollar = units(2);
const threeDollar = units(3);

// https://kndrck.co/posts/local_erc20_bal_mani_w_hh/
const setStorageAt = async (address: string, index: string, value: string) => {
  console.log("Debug:SetStorage:", address, index, value);
  await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
};

describe("PoolPerformance", function () {
  let USDC: Contract, WETH: Contract;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let PoolLogic: ContractFactory;
  let poolFactory: Contract, poolPerformance: Contract;
  let AMUSDC: Contract, AMWETH: Contract, iERC20: Interface;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();

    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    poolPerformance = deployments.poolPerformance;

    WETH = deployments.assets.WETH;
    USDC = deployments.assets.USDC;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    AMUSDC = deployments.assets.AMUSDC!;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    AMWETH = deployments.assets.AMWETH!;

    await getAccountToken(units(6000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    PoolLogic = await ethers.getContractFactory("PoolLogic");

    const IERC20 = await artifacts.readArtifact("IERC20");
    iERC20 = new ethers.utils.Interface(IERC20.abi);
  });

  describe("Existing pools before PoolPerformance deployed", () => {
    // This tests checks that pools that existed with funds before PoolPerformance is deployed
    // That they are not penalized
    it("existing pool unintitialized with deposit + tokenPriceAdjustedForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      console.log(">>>>>>>> poolAddress", poolLogicProxy.address);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      // When pools are created they are set to initialized in PoolPerformance
      // But in this integration test we want to test as though this pool existed
      // Before PoolPerformance was deployed.
      // So we hack the storage of PoolPerformance to mark the Pool as not initialised
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(true);
      const poolIndex = ethers.utils.solidityKeccak256(
        ["uint256", "uint256"],
        // mapping(address => bool) public poolInitialized; in PoolPerformance.sol
        // is storage slot 101 because of extending contracts with gaps[50]
        // I found this storage slot by looping through every index between 0 and 300 looking for true value
        [poolLogicProxy.address, 101], // key, slot
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //true
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000001");

      console.log(">>>>>>>> poolIndex", poolIndex);
      console.log(">>>>>>>> poolPerformance.address", poolPerformance.address);

      await setStorageAt(
        poolPerformance.address,
        poolIndex,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //false
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000000");
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(false);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      // Add some value into the pool directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Check tokenPriceAdjustForPerformance() should be $2
      // Because this pool is not initialised in PoolPerformance we ignore direct deposits
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );

      // Deposit $1 conventional way
      // This will initialize the pool in PoolPerformance and record it's balances
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      // Check tokenPriceAdjustForPerformance() should be $2 still
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );

      // Add some value into the pool directly, this should be detected now the pool is initialized in PoolPerformance
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Check the $1 direct transferered is allocated to token holders
      // TokenPrice should now be more than $2
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        "2666666666666666666",
      );
      // Check tokenPriceAdjustForPerformance should still be $2; (i.e directDepositFactor $1)
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        twoDollar,
        2,
      );
    });
    // This tests checks that pools that existed but with not funds before PoolPerformance is deployed
    // That they are not penalized
    it("existing pool unitialized without deposit + tokenPriceAdjustedForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);

      // When pools are created they are set to initialized in PoolPerformance
      // But in this integration test we want to test as though this pool existed
      // Before PoolPerformance was deployed.
      // So we hack the storage of PoolPerformance to mark the Pool as not initialised
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(true);
      const poolIndex = ethers.utils.solidityKeccak256(
        ["uint256", "uint256"],
        // mapping(address => bool) public poolInitialized; in PoolPerformance.sol
        // is storage slot 101 because of extending contracts with gaps[50]
        // I found this storage slot by looping through every index between 0 and 300 looking for true value
        [poolLogicProxy.address, 101], // key, slot
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //true
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000001");

      await setStorageAt(
        poolPerformance.address,
        poolIndex,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      );

      expect(
        await ethers.provider.getStorageAt(poolPerformance.address, poolIndex),
        //false
      ).to.equal("0x0000000000000000000000000000000000000000000000000000000000000000");
      expect(await poolPerformance.poolInitialized(poolLogicProxy.address)).to.equal(false);

      // Add some value into the pool directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );

      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // Check TokenPrice() should be $3
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        threeDollar.toString(),
      );
      // Check tokenPriceAdjustForPerformance == $2; (i.e directDepositFactor $1)
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        twoDollar,
        2,
      );
    });
  });

  describe("Only Standard ERC20 supportedAssets", () => {
    // Tests that tokenPriceAdjustedForPerformance adjusts for direct deposits
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasExternalBalances() == FALSE
    // Deposit $1 directly
    // Check hasExternalBalances() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Call recordExternalValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
    it("tokenPriceAdjustedForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // Check TokenPrice() should be $2
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Call recordExternalValue
      await poolPerformance.recordExternalValue(poolLogicProxy.address);
      // Check TokenPrice() should be $2
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check TokenPrice() should be $2
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
    });

    // In this test we make sure users can withdraw without disrupting the directDeposit detection
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasExternalBalances() == FALSE
    // Deposit $1 directly
    // Deposit $1 conventional way
    // Check Price
    // Deposit $1 conventional way
    // Check Price
    // Withdraw
    // Check Price
    it("withdrawal + tokenPriceAdjustForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());

      // Deposit $1 conventional way
      // This will record the direct deposit factor
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      // Check token price is $2
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      await poolFactory.setExitCooldown(0);
      const withdrawQuarterAmount = (await poolLogicProxy.totalSupply()) / 4;
      await poolLogicProxy.withdraw(withdrawQuarterAmount.toString());

      // Check token price is still $2
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      // Check tokenPriceAdjustForPerformance is still == $1; (i.e directDepositFactor $1)
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
    });

    // Early pool exit was backed out leaving here for now.

    // Checks to make sure PoolPerformance is updated on early withdraws
    // we make a conventional deposit and immediately withdraw 10% of the issued tokens
    // we then check to make sure pool performance is adjusted down to compensate for the fee kept by the pool
    it.skip("early 10% withdrawal with 0.5% fee adjustInternalValueFactor + tokenPriceAdjustForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      const tokenPriceBefore = await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address);
      // Check token price is $1
      expect(tokenPriceBefore.toString()).to.equal(oneDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1;
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      await poolFactory.setExitCooldown(6000000);
      await poolFactory.setExitFee(5, 1000); // 0.5%
      const totalSupply = await poolLogicProxy.totalSupply();
      const totalValue = totalSupply.mul(await poolLogicProxy.tokenPrice());
      // 10% withdrawal
      const withdrawalAmount = totalSupply.div(10);
      // early exit fee is 0.5% of the withdrawn amount
      const totalEarlyExitFee = totalValue.div(10).div(200);
      const tokensLeft = totalSupply.sub(withdrawalAmount);
      const extraValuePerToken = totalEarlyExitFee.div(tokensLeft);

      await poolLogicProxy.withdraw(withdrawalAmount.toString());

      // $100 TotalValue
      // 100 Tokens TotalSupply

      // withdrawing 10% sans 0.5% fee
      // $10 * 0.005 = $0.05 fee
      // Left in pool $90 + 0.05 = 90.05
      // 90 Tokens TotalSupply left after withdraw
      // $90.05 / 90 = $1.000555556

      const tokenPriceAfter = await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address);
      expect(tokenPriceBefore).not.to.equal(tokenPriceAfter);
      // Check token price has increased by the fee kept by the pool
      expect(tokenPriceAfter.toString()).to.equal(oneDollar.add(extraValuePerToken));
      // Make sure the performance of the token hasn't changed
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        1,
      );
    });

    // Checks to make sure PoolPerformance is updated on early withdraws
    // we make a conventional deposit and immediately withdraw 50% of the issued tokens
    // we then check to make sure pool performance is adjusted down to compensate for the fee kept by the pool
    it.skip("early 50% withdrawal with 10% fee adjustInternalValueFactor + tokenPriceAdjustForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      const tokenPriceBefore = await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address);
      // Check token price is $1
      expect(tokenPriceBefore.toString()).to.equal(oneDollar.toString());
      // Check tokenPriceAdjustForPerformance == $1;
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      await poolFactory.setExitCooldown(6000000);
      await poolFactory.setExitFee(10, 100); // 10%
      const totalSupply = await poolLogicProxy.totalSupply();
      const tokenPrice = await poolLogicProxy.tokenPrice();
      // 50% withdrawal - div(2) is the same as * 0.5
      const withdrawalAmount = totalSupply.div(2);
      const totalEarlyExitFee = tokenPrice.mul(withdrawalAmount).div(10);
      const tokensLeft = totalSupply.sub(withdrawalAmount);
      const extraValuePerToken = totalEarlyExitFee.div(tokensLeft);

      await poolLogicProxy.withdraw(withdrawalAmount.toString());

      // $100 TotalValue
      // 100 Tokens TotalSupply

      // withdrawing half sans 10% fee
      // 50 * 0.1 = $5 fee
      // Left in pool $55
      // 50 Tokens TotalSupply left after withdraw
      // 55/50 = 1.1
      // 1 -> 1.05

      const tokenPriceAfter = await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address);
      expect(tokenPriceBefore).not.to.equal(tokenPriceAfter);
      // Check token price has increased by the fee kept by the pool
      expect(tokenPriceAfter.toString()).to.equal(oneDollar.add(extraValuePerToken));
      // Make sure the performance of the token hasn't changed
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        1,
      );
    });

    // Checks to make sure early exit PoolPerformance update is skipped if investor is withdrawing 100% of the pool.
    // we make a conventional deposit and immediately withdraw 50% of the issued tokens
    // we then check to make sure pool performance is adjusted down to compensate for the fee kept by the pool
    it.skip("early 100% withdrawal should skip adjustInternalValueFactor + tokenPriceAdjustForPerformance", async () => {
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);

      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());

      // Check token price is $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Check tokenPriceAdjustForPerformance == $1;
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      await poolFactory.setExitCooldown(6000000);
      await poolFactory.setExitFee(10, 100); // 10%

      // 100% withdrawal
      const withdrawalAmount = await poolLogicProxy.totalSupply();

      expect(await poolPerformance.realtimeInternalValueFactor(poolLogicProxy.address)).to.equal((1e18).toString());

      await poolLogicProxy.withdraw(withdrawalAmount.toString());

      // Check token price has increased by the fee kept by the pool
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal("0");
      // // Make sure the performance of the token hasn't changed
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal("0");
    });

    // In this test we test that the realtime fee + performance is calculated correctly
    it("tokenPriceAdjustedForPerformance", async () => {
      const managerFee = BigNumber.from("5000"); // 50%;
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const fund = funds[funds.length - 1];
      const poolLogicProxy = await PoolLogic.attach(fund);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);
      // DollarSixty
      // You might be thinking you expect this to be $1.50 not $1.60 because
      // There is $1 of performance and 50% performance fee and so manager fee should be worth 50c but
      // we mint the manager fee in a novel way, that's not exactly performance fee.
      // The mints manager fee mints 0.25 tokens (a value of 50% of the current performance value)
      // Which means before the mint there is 1 token and after mint there is 1.25 tokens and $2 value
      // i.e the tokenValue is $1.6 now because there is more tokens in circulation
      // Check TokenPrice() should be $1.60
      const expectedTokenPriceAdjustedForManagerFee = 16e17;
      const checkTokenValue = async () => {
        expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(
          expectedTokenPriceAdjustedForManagerFee.toString(),
        );
        expect(
          (await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString(),
          // sixty cents
        ).to.equal((expectedTokenPriceAdjustedForManagerFee / 2).toString());
      };
      // Deposit $1 directly
      await USDC.transfer(poolLogicProxy.address, (100e6).toString());
      // The direct deposit should be detected.
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        twoDollar.toString(),
      );
      await checkTokenValue();
      // Call recordExternalValue
      await poolPerformance.recordExternalValue(poolLogicProxy.address);
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
      // We mint the manager fee
      await poolLogicProxy.mintManagerFee();
      // The base tokenPrice should now be the same as the tokenPriceAdjustedForManagerFees now fees are minted
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformance.tokenPrice(poolLogicProxy.address)).toString(),
      );
      // The tokenPriceAdjustedForPerformance should now be the same as adjustedForPerformanceAndManagerFee now fees are minted
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString(),
      );
      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, (100e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (100e6).toString());
      // This should have no affect on tokenPricesAdjustedForFee
      checkTokenValue();
    });

    it("tokenPriceAdjustedForPerformance with small manager fee, small deposit", async () => {
      const oneDollarTwentyCents = 12e17;
      const managerFee = BigNumber.from("1000"); // 10%;
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const fund = funds[funds.length - 1];
      const poolLogicProxy = await PoolLogic.attach(fund);
      // Deposit $10 conventional way
      await USDC.approve(poolLogicProxy.address, (1000e6).toString());
      await poolLogicProxy.deposit(assets.usdc, (1000e6).toString());
      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPrice(poolLogicProxy.address)).toString()).to.equal(oneDollar.toString());
      // Check hasExternalBalances() == FALSE
      expect(await poolPerformance.hasExternalBalances(poolLogicProxy.address)).to.equal(false);

      // Deposit $2 directly
      // This means the fee should be around
      await USDC.transfer(poolLogicProxy.address, (200e6).toString());

      // We have $10 in the pool
      // Direct deposit $2
      // now every token is worth $1.2
      // The manager gets ~10% of the 0.2 - around 2 cents
      // The direct deposit factor is 20c (per token)
      // tokenPriceWithFee 118
      // tokenPriceWithFeeAndPerformance 118-20c == 98c;
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollarTwentyCents.toString(),
      );

      // We have 10 in the pool
      // Direct deposit $2
      const checkTokenValue = async () => {
        expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.equal(
          // dollar18Cents
          "1180327868852459016",
        );

        expect(
          (await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString(),
          // dollar18Cents subtract 20c
          // nintetyEight cents
        ).to.equal("983606557377049179");
      };

      await checkTokenValue();

      // We mint the manager fee
      await poolLogicProxy.mintManagerFee();

      // The base tokenPrice should now be the same as the tokenPriceAdjustedForManagerFees now fees are minted
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        (await poolPerformance.tokenPrice(poolLogicProxy.address)).toString(),
      );

      // This should have no affect on tokenPricesAdjustedForFee
      await checkTokenValue();
    });
  });

  describe("Aave aERC20", () => {
    // In this test we simply check that depositing into aave doesn't affect our PoolPerf figures
    // Create the fund we're going to use for testing
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve usdc transfer to AAVE
    // Check before balances of usdc and amusdc
    // Deposit usdc to aave
    // Check after balances of usdc and amusdc
    // Check PoolPerformance Figures remain the same
    it("tokenPriceAdjustForPerformance no direct deposit", async () => {
      const usdcAmount = (100e6).toString();
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
        [aave.lendingPool, false],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, usdcAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcAmount);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, usdcAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      expect(usdcBalanceBefore).to.be.equal(usdcAmount);
      expect(amusdcBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      // deposit
      const depositABI = iLendingPool.encodeFunctionData("deposit", [
        assets.usdc,
        usdcAmount,
        poolLogicProxy.address,
        0,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((0).toString());
      checkAlmostSame(amusdcBalanceAfter, 100e6);

      // We check that depositing into AAVE doesn't affect any of our poolPerformance figures
      expect(await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
    });

    // In this test we simply check that depositing into aave doesn't affect our PoolPerf figures
    // Create the fund we're going to use for testing
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve usdc transfer to AAVE
    // Check before balances of usdc and amusdc
    // Deposit usdc to aave
    // Check after balances of usdc and amusdc
    // Check PoolPerformance Figures remain the same
    // call PoolPerformance.recordExternalValue
    // Check PoolPerformance Figures remain the same
    it("tokenPriceAdjustForPerformance only deposit half into aave, recordExternalValue after deposit", async () => {
      const usdcAmount = (100e6).toString();
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
        [aave.lendingPool, false],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, usdcAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcAmount);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, usdcAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      expect(usdcBalanceBefore).to.be.equal(usdcAmount);
      expect(amusdcBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      // deposit
      const depositABI = iLendingPool.encodeFunctionData("deposit", [
        assets.usdc,
        100e6 / 2,
        poolLogicProxy.address,
        0,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((50e6).toString());
      checkAlmostSame(amusdcBalanceAfter, 50e6);

      // We check that depositing into AAVE doesn't affect any of our poolPerformance figures
      expect(await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );

      // This test makes sure that aToken balances are being included in the externalBalances
      await poolPerformance.recordExternalValue(poolLogicProxy.address);

      // We check that recording external value after depositing doesn't affect price
      expect(await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
    });

    // In this test we simply check that depositing into aave doesn't affect our PoolPerf figures
    // Create the fund we're going to use for testing
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve usdc transfer to AAVE
    // Check before balances of usdc and amusdc
    // Deposit usdc to aave
    // Check after balances of usdc and amusdc
    // Check PoolPerformance Figures remain the same
    // Borrow from AAVE
    // Check PoolPerformance Figures remain the same
    it("borrow + tokenPriceAdjustForPerformance no direct deposit", async () => {
      const usdcAmount = (100e6).toString();
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
        [aave.lendingPool, false],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, usdcAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcAmount);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, usdcAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      expect(usdcBalanceBefore).to.be.equal(usdcAmount);
      expect(amusdcBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      // deposit
      const depositABI = iLendingPool.encodeFunctionData("deposit", [
        assets.usdc,
        usdcAmount,
        poolLogicProxy.address,
        0,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceAfter = await AMUSDC.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter).to.be.equal((0).toString());
      checkAlmostSame(amusdcBalanceAfter, 100e6);

      // We check that depositing into AAVE doesn't affect any of our poolPerformance figures
      expect(await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interestes on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interestes on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interestes on our debt each block
        1e11,
      );

      const borrowABI = iLendingPool.encodeFunctionData("borrow", [
        assets.usdc,
        100e6 / 2,
        2,
        0,
        poolLogicProxy.address,
      ]);

      // borrow
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, borrowABI);

      // We check that depositing into AAVE doesn't affect any of our poolPerformance figures
      expect(await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(
        oneDollar,
        // aave allocates us interest and we incur interest on our debt each block
        1e11,
      );
    });
    // In this test we make sure directDeposits of aTokens are accounted for by PoolPerformance
    // Create the fund we're going to use for testing
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve usdc transfer to AAVE
    // Check before balances of usdc and amusdc
    // Deposit usdc to aave
    // Check after balances of usdc and amusdc
    // Direct deposit amUSDC to Pool
    // check that the directDeposit of amUSDC is accounted for by PoolPerformance
    it("tokenPriceAdjustForPerformance with direct deposit", async () => {
      const usdcAmount = (100e6).toString();
      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.usdc, true],
        [aave.lendingPool, false],
      ]);
      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, usdcAmount);
      await poolLogicProxy.deposit(assets.usdc, usdcAmount);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, usdcAmount]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const amusdcBalanceBefore = await AMUSDC.balanceOf(poolLogicProxy.address);

      expect(usdcBalanceBefore).to.be.equal(usdcAmount);
      expect(amusdcBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      // deposit
      const depositABI = iLendingPool.encodeFunctionData("deposit", [
        assets.usdc,
        usdcAmount,
        poolLogicProxy.address,
        0,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal((0).toString());
      checkAlmostSame(await AMUSDC.balanceOf(poolLogicProxy.address), 100e6);

      // Here we are taking some of the logicOwners usdc and depositing it directly into the aave Pool as amUSDC
      await USDC.approve(aave.lendingPool, usdcAmount);
      const AaveLendingPool = await ethers.getContractAt(ILendingPool.abi, aave.lendingPool);
      await AaveLendingPool.deposit(assets.usdc, usdcAmount, poolLogicProxy.address, 0);

      checkAlmostSame(await AMUSDC.balanceOf(poolLogicProxy.address), 200e6);

      // We check that the directDeposit of amUSDC is accounted for by PoolPerformance
      // We use closeTo here because every block we are getting crumbs as interest on our aAsset which
      // increases the price slightly
      expect(await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).to.be.closeTo(
        BigNumber.from(twoDollar),
        1e11,
      );
      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(BigNumber.from(twoDollar), 1e11);

      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        BigNumber.from(twoDollar.div(2)),
        1e11,
      );
    });

    // In this test we make sure directDeposits of aTokens are accounted for by PoolPerformance using WETH
    // Create the fund we're going to use for testing
    // Deposit x Weth conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Approve weth transfer to AAVE
    // Check before balances of weth and amweth
    // Deposit weth to aave
    // Check after balances of weth and amweth
    // Direct deposit amweth to Pool
    // check that the directDeposit of amWeth is accounted for by PoolPerformance
    it("tokenPriceAdjustForPerformance with direct deposit (WETH)", async () => {
      await getAccountToken(units(1), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);

      const managerFee = BigNumber.from("0"); // 0%;
      // Create the fund we're going to use for testing
      await poolFactory.createFund(false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", managerFee, [
        [assets.weth, true],
        [aave.lendingPool, false],
      ]);

      const balanceOfWeth = await WETH.balanceOf(logicOwner.address);
      const halfBalanceOfWeth = balanceOfWeth.div(2);

      const funds = await poolFactory.getDeployedFunds();
      const poolLogicProxy = await PoolLogic.attach(funds[funds.length - 1]);
      // Deposit $1 conventional way
      await WETH.approve(poolLogicProxy.address, halfBalanceOfWeth);
      await poolLogicProxy.deposit(assets.weth, halfBalanceOfWeth);

      // Check tokenPriceAdjustForPerformance() should be $1
      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );
      expect((await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      const ILendingPool = await artifacts.readArtifact("ILendingPool");
      const iLendingPool = new ethers.utils.Interface(ILendingPool.abi);

      // approve usdc
      const approveABI = iERC20.encodeFunctionData("approve", [aave.lendingPool, halfBalanceOfWeth]);
      await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      const amWethBalanceBefore = await AMWETH.balanceOf(poolLogicProxy.address);

      expect(wethBalanceBefore).to.be.equal(halfBalanceOfWeth);
      expect(amWethBalanceBefore).to.be.equal(0);

      expect((await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).toString()).to.equal(
        oneDollar.toString(),
      );

      // deposit
      const depositABI = iLendingPool.encodeFunctionData("deposit", [
        assets.weth,
        halfBalanceOfWeth,
        poolLogicProxy.address,
        0,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(aave.lendingPool, depositABI);

      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      const amWethBalanceAfter = await AMWETH.balanceOf(poolLogicProxy.address);

      expect(wethBalanceAfter).to.be.equal(0);
      checkAlmostSame(amWethBalanceAfter, halfBalanceOfWeth);

      // Here we are taking some of the logicOwners weth and depositing it directly into the aave Pool as amWETH
      await WETH.approve(aave.lendingPool, halfBalanceOfWeth);
      const AaveLendingPool = await ethers.getContractAt(ILendingPool.abi, aave.lendingPool);
      await AaveLendingPool.deposit(assets.weth, halfBalanceOfWeth, poolLogicProxy.address, 0);

      // All the logicOwners weth is now aWETH half deposited normally, half direct deposited
      checkAlmostSame(await AMWETH.balanceOf(poolLogicProxy.address), balanceOfWeth);

      // We check that the directDeposit of amWeth is accounted for by PoolPerformance
      // We've double the amount of underlying assets so the price should be nearly double
      // We use closeTo here because every block we are getting crumbs as interest on our aAsset which
      // increases the price slightly
      expect(await poolPerformance.tokenPriceWithoutManagerFee(poolLogicProxy.address)).to.be.closeTo(
        BigNumber.from(twoDollar),
        1e11,
      );

      expect(await poolPerformance.tokenPrice(poolLogicProxy.address)).to.be.closeTo(BigNumber.from(twoDollar), 1e11);

      expect(await poolPerformance.tokenPriceAdjustedForPerformance(poolLogicProxy.address)).to.be.closeTo(
        BigNumber.from(twoDollar.div(2)),
        1e11,
      );
    });
  });
});
