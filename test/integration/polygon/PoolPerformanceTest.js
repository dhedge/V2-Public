const { ethers, upgrades } = require("hardhat");
const { expect, use } = require("chai");
const chaiAlmost = require("chai-almost");
const { checkAlmostSame, getAmountOut } = require("../../TestHelpers");

use(chaiAlmost());

const units = (value) => ethers.utils.parseUnits(value.toString());

describe("PoolPerformance", function () {
  describe("Only Standard ERC20", () => {
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    it("tokenPriceAdjustForPerformance", () => {});

    // Create Fund, with 20% management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustedForPerformanceAndManagerFee() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustedForPerformanceAndManagerFee == $2 - .04 / 2 = $0.8; (i.e directDepositFactor 0.5)
    it("tokenPriceAdjustedForPerformanceAndManagerFee", () => {});

    // In this test we make sure users can withdraw without disrupting the directDeposit detection
    // Create Fund, no management fee, enable usdc
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way (store as newTokensIssued)
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Withdraw newTokensIssued (should not affect tokenPriceAdjustedForPerformance)
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    it("withdrawal + tokenPriceAdjustForPerformance", () => {});
  });

  describe("Aave aERC20", () => {
    // Create Fund, no management fee, enable usdc, aaveLending Pool
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance() should be $1
    // Check hasDirectDeposit() == FALSE
    // Deposit aUSDC $1 directly
    // Check hasDirectDeposit() == TRUE
    // Check TokenPrice() should be $2
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Call recordDirectDepositValue
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    // Deposit $1 conventional way
    // Check tokenPriceAdjustForPerformance == $1; (i.e directDepositFactor 0.5)
    it("tokenPriceAdjustForPerformance", () => {});
  });
});
