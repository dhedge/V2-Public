// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract EntryExitFeesTestSetup is BackboneSetup {
  uint256 private daoFeeNumerator;
  uint256 private daoFeeDenominator;
  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;

  function setUp() public virtual override {
    super.setUp();

    // Let USDC be always equal $1 for simplicity in tests
    vm.mockCall(
      usdcData.aggregator,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, 1e8, 0, type(uint128).max, 0)
    );

    (daoFeeNumerator, daoFeeDenominator) = poolFactoryProxy.getDaoFee();

    // Create a test dHEDGE pool with USDC enabled as deposit asset.
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Test Vault",
        _fundSymbol: "TV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());
  }

  // ================== ENTRY FEE TESTS ==================

  function test_entry_fee_not_set_first_deposit() public {
    uint256 depositAmount = 1000e6;

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    assertEq(balanceBefore, 0, "Investor balance should be zero before deposit");
    assertEq(daoBalanceBefore, 0, "DAO balance should be zero before deposit");
    assertEq(managerBalanceBefore, 0, "Manager balance should be zero before deposit");

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);

    assertEq(balanceAfter, liquidityMinted, "Investor should receive exact liquidity minted");
    assertEq(
      balanceAfter,
      depositAmount * 1e12,
      "Investor should receive liquidity equal to deposit amount in 18 decimals"
    );
    assertEq(managerBalanceAfter, managerBalanceBefore, "Manager should not receive entry fees when fee is 0");
    assertEq(daoBalanceAfter, daoBalanceBefore, "DAO should not receive entry fees when fee is 0");
  }

  function test_entry_fee_with_zero_pool_share_first_deposit() public {
    _setEntryFee();

    uint256 depositAmount = 1000e6;

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    assertEq(balanceBefore, 0, "Investor balance should be zero before deposit");
    assertEq(daoBalanceBefore, 0, "DAO balance should be zero before deposit");
    assertEq(managerBalanceBefore, 0, "Manager balance should be zero before deposit");

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();

    uint256 entryFee = (depositAmount * 1e12 * 10) / 10000;

    assertEq(balanceAfter, liquidityMinted, "Investor should receive exact liquidity minted");
    assertEq(balanceAfter, depositAmount * 1e12 - entryFee, "Investor should receive liquidity minus entry fee");
    assertEq(
      managerBalanceAfter,
      (entryFee * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator,
      "Manager should receive entry fee tokens"
    );
    assertEq(daoBalanceAfter, (entryFee * daoFeeNumerator) / daoFeeDenominator, "DAO should receive entry fee tokens");
    assertEq(tokenPriceAfter, 1e18, "Token price should not change after first deposit with entry fee");
  }

  function test_entry_fee_with_zero_pool_share_non_first_deposit() public {
    uint256 depositAmount = 1000e6;

    _makeDeposit(testPool, manager, usdcData.asset, depositAmount);

    _setEntryFee();

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();

    assertEq(balanceBefore, 0, "Investor balance should be zero before deposit");
    assertEq(daoBalanceBefore, 0, "DAO balance should be zero before deposit");
    assertEq(
      managerBalanceBefore,
      testPool.totalSupply(),
      "Manager balance should be equal to total supply before deposit"
    );
    assertEq(tokenPriceBefore, 1e18, "Token price should be 1 after first deposit");

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();

    uint256 entryFee = (depositAmount * 1e12 * 10) / 10000;

    assertEq(balanceAfter, liquidityMinted, "Investor should receive exact liquidity minted");
    assertEq(balanceAfter, depositAmount * 1e12 - entryFee, "Investor should receive liquidity minus entry fee");
    assertEq(
      managerBalanceAfter,
      managerBalanceBefore + (entryFee * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator,
      "Manager should receive entry fee tokens"
    );
    assertEq(daoBalanceAfter, (entryFee * daoFeeNumerator) / daoFeeDenominator, "DAO should receive entry fee tokens");
    assertEq(tokenPriceBefore, tokenPriceAfter, "Token price should not change after deposit with entry fee");
  }

  function test_entry_fee_with_full_pool_share_first_deposit() public {
    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(10000); // 100% to pool

    _setEntryFee();

    uint256 depositAmount = 1000e6;

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    assertEq(balanceBefore, 0, "Investor balance should be zero before deposit");
    assertEq(daoBalanceBefore, 0, "DAO balance should be zero before deposit");
    assertEq(managerBalanceBefore, 0, "Manager balance should be zero before deposit");

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();

    uint256 entryFee = (depositAmount * 1e12 * 10) / 10000;

    assertEq(balanceAfter, liquidityMinted, "Investor should receive exact liquidity minted");
    assertEq(balanceAfter, depositAmount * 1e12 - entryFee, "Investor should receive liquidity minus entry fee");
    assertEq(managerBalanceAfter, managerBalanceBefore, "No fees should go to manager when poolShare is 100%");
    assertEq(daoBalanceAfter, daoBalanceBefore, "No fees should go to DAO when poolShare is 100%");
    assertGt(tokenPriceAfter, 1e18, "Token price should increase after deposit with 100% pool share");
  }

  function test_entry_fee_with_full_pool_share_non_first_deposit() public {
    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(10000); // 100% to pool

    uint256 depositAmount = 1000e6;

    _makeDeposit(testPool, manager, usdcData.asset, depositAmount);

    _setEntryFee();

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();

    assertEq(balanceBefore, 0, "Investor balance should be zero before deposit");
    assertEq(daoBalanceBefore, 0, "DAO balance should be zero before deposit");
    assertEq(
      managerBalanceBefore,
      testPool.totalSupply(),
      "Manager balance should be equal to total supply before deposit"
    );
    assertEq(tokenPriceBefore, 1e18, "Token price should be 1 after first deposit");

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();

    uint256 entryFee = (depositAmount * 1e12 * 10) / 10000;

    assertEq(balanceAfter, liquidityMinted, "Investor should receive exact liquidity minted");
    assertEq(balanceAfter, depositAmount * 1e12 - entryFee, "Investor should receive liquidity minus entry fee");
    assertEq(managerBalanceAfter, managerBalanceBefore, "No fees should go to manager when poolShare is 100%");
    assertEq(daoBalanceAfter, daoBalanceBefore, "No fees should go to DAO when poolShare is 100%");
    assertGt(tokenPriceAfter, tokenPriceBefore, "Token price should increase after deposit with 100% pool share");
  }

  function test_entry_fee_with_partial_pool_share_first_deposit() public {
    uint256 poolShare = 5000; // 50% to pool

    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(poolShare);

    _setEntryFee();

    uint256 depositAmount = 1000e6;

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    assertEq(balanceBefore, 0, "Investor balance should be zero before deposit");
    assertEq(daoBalanceBefore, 0, "DAO balance should be zero before deposit");
    assertEq(managerBalanceBefore, 0, "Manager balance should be zero before deposit");

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();

    uint256 entryFee = (depositAmount * 1e12 * 10) / 10000;
    uint256 entryFeeToTransfer = (entryFee * (10000 - poolShare)) / 10000;
    uint256 expectedManagerFee = (entryFeeToTransfer * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator;
    uint256 expectedDaoFee = (entryFeeToTransfer * daoFeeNumerator) / daoFeeDenominator;

    assertEq(balanceAfter, liquidityMinted, "Investor should receive exact liquidity minted");
    assertEq(balanceAfter, depositAmount * 1e12 - entryFee, "Investor should receive liquidity minus entry fee");
    assertEq(
      managerBalanceAfter,
      managerBalanceBefore + expectedManagerFee,
      "Manager should receive expected entry fee tokens"
    );
    assertEq(daoBalanceAfter, daoBalanceBefore + expectedDaoFee, "DAO should receive expected entry fee tokens");
    assertGt(tokenPriceAfter, 1e18, "Token price should increase after deposit with 50% pool share");
  }

  function test_entry_fee_with_partial_pool_share_non_first_deposit() public {
    uint256 poolShare = 5000; // 50% to pool

    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(poolShare);

    uint256 depositAmount = 1000e6;

    _makeDeposit(testPool, manager, usdcData.asset, depositAmount);

    _setEntryFee();

    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();

    assertEq(testPool.balanceOf(investor), 0, "Investor balance should be zero before deposit");
    assertEq(daoBalanceBefore, 0, "DAO balance should be zero before deposit");
    assertEq(
      managerBalanceBefore,
      testPool.totalSupply(),
      "Manager balance should be equal to total supply before deposit"
    );
    assertEq(tokenPriceBefore, 1e18, "Token price should be 1 after first deposit");

    uint256 liquidityMinted = _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();

    uint256 entryFee = (depositAmount * 1e12 * 10) / 10000;
    uint256 entryFeeToTransfer = (entryFee * (10000 - poolShare)) / 10000;
    uint256 expectedManagerFee = (entryFeeToTransfer * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator;
    uint256 expectedDaoFee = (entryFeeToTransfer * daoFeeNumerator) / daoFeeDenominator;

    assertEq(balanceAfter, liquidityMinted, "Investor should receive exact liquidity minted");
    assertEq(balanceAfter, depositAmount * 1e12 - entryFee, "Investor should receive liquidity minus entry fee");
    assertEq(
      managerBalanceAfter,
      managerBalanceBefore + expectedManagerFee,
      "Manager should receive expected entry fee tokens"
    );
    assertEq(daoBalanceAfter, daoBalanceBefore + expectedDaoFee, "DAO should receive expected entry fee tokens");
    assertGt(tokenPriceAfter, tokenPriceBefore, "Token price should increase after deposit with 50% pool share");
  }

  // ================== EXIT FEE TESTS ==================

  function test_exit_fee_not_set_full_withdrawal() public {
    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    vm.startPrank(investor);
    testPool.withdrawSafe(balanceBefore, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    assertEq(balanceAfter, 0, "Investor balance should be zero after withdrawal");
    assertEq(managerBalanceAfter, managerBalanceBefore, "Manager should not receive exit fees when fee is 0");
    assertEq(daoBalanceAfter, daoBalanceBefore, "DAO should not receive exit fees when fee is 0");
    assertEq(tokenPriceAfter, 0, "Token price should reset to 0 after full withdrawal");
    assertEq(totalValueAfter, 0, "Total fund value should be zero after full withdrawal");
    assertEq(totalSupplyAfter, 0, "Total supply should be zero after full withdrawal");
  }

  function test_exit_fee_not_set_not_full_withdrawal() public {
    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyBefore = testPool.totalSupply();

    vm.startPrank(investor);
    uint256 withdrawAmount = (balanceBefore * 3) / 4; // Withdraw 75%
    testPool.withdrawSafe(withdrawAmount, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    assertEq(balanceAfter, balanceBefore - withdrawAmount, "Investor balance should be reduced by withdrawal amount");
    assertEq(managerBalanceAfter, managerBalanceBefore, "Manager should not receive exit fees when fee is 0");
    assertEq(daoBalanceAfter, daoBalanceBefore, "DAO should not receive exit fees when fee is 0");
    assertEq(
      tokenPriceAfter,
      tokenPriceBefore,
      "Token price should not change after partial withdrawal with no exit fee"
    );
    assertEq(totalValueAfter, totalValueBefore / 4, "Total fund value should match value withdrawn");
    assertEq(totalSupplyAfter, totalSupplyBefore - withdrawAmount, "Total supply should match tokens withdrawn");
  }

  function test_exit_fee_with_zero_pool_share_full_withdrawal() public {
    _setExitFee();

    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 tokenPriceBefore = testPool.tokenPrice();

    vm.startPrank(investor);
    testPool.withdrawSafe(balanceBefore, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    uint256 exitFee = (balanceBefore * 10) / 10000; // 0.1%

    assertEq(balanceAfter, 0, "Investor balance should be zero after withdrawal");
    assertEq(
      managerBalanceAfter,
      (exitFee * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator,
      "Manager should receive exit fee tokens"
    );
    assertEq(daoBalanceAfter, (exitFee * daoFeeNumerator) / daoFeeDenominator, "DAO should receive exit fee tokens");
    assertEq(tokenPriceAfter, tokenPriceBefore, "Token price should not change after full withdrawal with exit fee");
    assertEq(totalValueAfter, exitFee, "Total fund value should be equal to exit fee after full withdrawal");
    assertEq(totalSupplyAfter, exitFee, "Total supply should be equal to exit fee after full withdrawal");
  }

  function test_exit_fee_with_zero_pool_share_not_full_withdrawal() public {
    _setExitFee();

    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyBefore = testPool.totalSupply();

    vm.startPrank(investor);
    uint256 withdrawAmount = (balanceBefore * 3) / 4; // Withdraw 75%
    testPool.withdrawSafe(withdrawAmount, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    uint256 exitFee = (withdrawAmount * 10) / 10000; // 0.1%

    assertEq(
      testPool.balanceOf(investor),
      balanceBefore - withdrawAmount,
      "Investor balance should be reduced by withdrawal amount"
    );
    assertEq(
      managerBalanceAfter,
      managerBalanceBefore + (exitFee * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator,
      "Manager should receive exit fee tokens"
    );
    assertEq(
      daoBalanceAfter,
      daoBalanceBefore + (exitFee * daoFeeNumerator) / daoFeeDenominator,
      "DAO should receive exit fee tokens"
    );
    assertEq(tokenPriceAfter, tokenPriceBefore, "Token price should not change after partial withdrawal with exit fee");
    assertEq(totalValueAfter, totalValueBefore / 4 + exitFee, "Total fund value should match value withdrawn");
    assertEq(
      totalSupplyAfter,
      totalSupplyBefore - withdrawAmount + exitFee,
      "Total supply should match after partial withdrawal"
    );
  }

  function test_exit_fee_with_full_pool_share_full_withdrawal() public {
    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(10000); // 100% to pool

    _setExitFee();

    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    vm.startPrank(investor);
    testPool.withdrawSafe(balanceBefore, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    assertEq(balanceAfter, 0, "Investor balance should be zero after withdrawal");
    assertEq(managerBalanceAfter, managerBalanceBefore, "No fees should go to manager when poolShare is 100%");
    assertEq(daoBalanceAfter, daoBalanceBefore, "No fees should go to DAO when poolShare is 100%");
    assertEq(tokenPriceAfter, 0, "Token price should reset to 0 after full withdrawal with 100% pool share");
    // This is a known edge case when vault holds some value against 0 minted shares.
    assertGt(
      totalValueAfter,
      0,
      "Total fund value should be greater than zero after full withdrawal with 100% pool share"
    );
    assertEq(totalSupplyAfter, 0, "Total supply should be zero after full withdrawal with 100% pool share");
  }

  function test_exit_fee_with_full_pool_share_not_full_withdrawal() public {
    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(10000); // 100% to pool

    _setExitFee();

    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyBefore = testPool.totalSupply();

    vm.startPrank(investor);
    uint256 withdrawAmount = (balanceBefore * 3) / 4; // Withdraw 75%
    testPool.withdrawSafe(withdrawAmount, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    uint256 exitFee = (withdrawAmount * 10) / 10000; // 0.1%

    assertEq(
      testPool.balanceOf(investor),
      balanceBefore - withdrawAmount,
      "Investor balance should be reduced by withdrawal amount"
    );
    assertEq(managerBalanceAfter, managerBalanceBefore, "No fees should go to manager when poolShare is 100%");
    assertEq(daoBalanceAfter, daoBalanceBefore, "No fees should go to DAO when poolShare is 100%");
    assertGt(
      tokenPriceAfter,
      tokenPriceBefore,
      "Token price should increase after partial withdrawal with 100% pool share"
    );
    assertEq(totalValueAfter, totalValueBefore / 4 + exitFee, "Total value should match value withdrawn");
    assertEq(
      totalSupplyAfter,
      totalSupplyBefore - withdrawAmount,
      "Total supply should match after partial withdrawal"
    );
  }

  function test_exit_fee_with_partial_pool_share_full_withdrawal() public {
    uint256 poolShare = 5000; // 50% to pool

    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(poolShare);

    _setExitFee();

    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();

    vm.startPrank(investor);
    testPool.withdrawSafe(balanceBefore, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 balanceAfter = testPool.balanceOf(investor);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);
    uint256 tokenPriceAfter = testPool.tokenPrice();
    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    uint256 exitFee = (balanceBefore * 10) / 10000; // 0.1%
    uint256 exitFeeToTransfer = (exitFee * (10000 - poolShare)) / 10000;
    uint256 expectedManagerFee = (exitFeeToTransfer * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator;
    uint256 expectedDaoFee = (exitFeeToTransfer * daoFeeNumerator) / daoFeeDenominator;

    assertEq(balanceAfter, 0, "Investor balance should be zero after withdrawal");
    assertEq(
      managerBalanceAfter,
      managerBalanceBefore + expectedManagerFee,
      "Manager should receive expected exit fee tokens"
    );
    assertEq(daoBalanceAfter, daoBalanceBefore + expectedDaoFee, "DAO should receive expected exit fee tokens");
    assertGt(
      tokenPriceAfter,
      tokenPriceBefore,
      "Token price should increase after full withdrawal with partial pool share"
    );
    assertEq(totalValueAfter, exitFee, "Total value should match exit fees");
    assertEq(totalSupplyAfter, exitFeeToTransfer, "Total supply should match exit fees transferred");
  }

  function test_exit_fee_with_partial_pool_share_not_full_withdrawal() public {
    uint256 poolShare = 5000; // 50% to pool

    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(poolShare);

    _setExitFee();

    uint256 depositAmount = 1000e6;
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);

    skip(1 days);

    uint256 balanceBefore = testPool.balanceOf(investor);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 tokenPriceBefore = testPool.tokenPrice();
    uint256 totalValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyBefore = testPool.totalSupply();

    vm.startPrank(investor);
    uint256 withdrawAmount = (balanceBefore * 3) / 4; // Withdraw 75%
    testPool.withdrawSafe(withdrawAmount, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 totalValueAfter = testPoolManagerLogic.totalFundValue();
    uint256 totalSupplyAfter = testPool.totalSupply();

    uint256 exitFee = (withdrawAmount * 10) / 10000; // 0.1%
    uint256 exitFeeToTransfer = (exitFee * (10000 - poolShare)) / 10000;
    uint256 expectedManagerFee = (exitFeeToTransfer * (daoFeeDenominator - daoFeeNumerator)) / daoFeeDenominator;
    uint256 expectedDaoFee = (exitFeeToTransfer * daoFeeNumerator) / daoFeeDenominator;

    assertEq(
      testPool.balanceOf(investor),
      balanceBefore - withdrawAmount,
      "Investor balance should be reduced by withdrawal amount"
    );
    assertEq(
      testPool.balanceOf(manager),
      managerBalanceBefore + expectedManagerFee,
      "Manager should receive expected exit fee tokens"
    );
    assertEq(testPool.balanceOf(dao), daoBalanceBefore + expectedDaoFee, "DAO should receive expected exit fee tokens");
    assertGt(
      testPool.tokenPrice(),
      tokenPriceBefore,
      "Token price should increase after partial withdrawal with partial pool share"
    );
    assertEq(totalValueAfter, totalValueBefore / 4 + exitFee, "Total value should match value left after withdrawal");
    assertEq(
      totalSupplyAfter,
      totalSupplyBefore - withdrawAmount + exitFeeToTransfer,
      "Total supply should match after partial withdrawal"
    );
  }

  function _setEntryFee() internal {
    vm.startPrank(manager);

    testPoolManagerLogic.announceFeeIncrease(0, 0, 10, 0); // 0.1%
    skip(15 days);
    testPoolManagerLogic.commitFeeIncrease();

    vm.stopPrank();
  }

  function _setExitFee() internal {
    vm.startPrank(manager);
    testPoolManagerLogic.announceFeeIncrease(0, 0, 0, 10); // 0.1%

    skip(15 days);

    testPoolManagerLogic.commitFeeIncrease();
    vm.stopPrank();
  }
}
