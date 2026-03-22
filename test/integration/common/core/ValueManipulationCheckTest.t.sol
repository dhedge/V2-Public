// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IValueManipulationCheck} from "contracts/interfaces/IValueManipulationCheck.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ClosedContractGuard} from "contracts/guards/contractGuards/ClosedContractGuard.sol";

import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";

/// @title ValueManipulationCheckTestBase
/// @notice Base test contract for ValueManipulationCheck tests
/// @dev Abstract contract that defines all tests. Concrete implementations configure fees.
abstract contract ValueManipulationCheckTestBase is EthereumSetup {
  constructor() EthereumSetup(24440000) {} // Recent Ethereum block

  IValueManipulationCheck internal checker;
  PoolLogic internal testPool;
  PoolManagerLogic internal testPoolManagerLogic;
  address internal attacker = makeAddr("attacker");

  /// @notice Returns fee configuration for the test pool
  /// @return entryFee Entry fee numerator (10000 = 100%)
  /// @return exitFee Exit fee numerator (10000 = 100%)
  /// @return performanceFee Performance fee numerator (10000 = 100%)
  /// @return managementFee Management fee numerator (10000 = 100%)
  /// @return poolFeeShare Pool fee share numerator (0 = all to manager, feeDenominator = all to pool)
  function _getFeeConfig()
    internal
    pure
    virtual
    returns (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, uint256 poolFeeShare);

  function _getInitialDeposit() internal pure virtual returns (uint256 initialDeposit);

  function setUp() public override {
    super.setUp();

    // Mock USDC price to always be $1 for simplicity
    vm.mockCall(
      usdcData.aggregator,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(0, 1e8, 0, type(uint128).max, 0)
    );

    // Deploy ValueManipulationCheck using deployCode as a workaround for Solidity version incompatibility
    // ValueManipulationCheck requires Solidity 0.8.28 for transient storage (EIP-1153),
    // but this test file uses >=0.7.6 to import PoolLogic (0.7.6).
    // deployCode compiles the contract separately, avoiding the version conflict.
    checker = IValueManipulationCheck(deployCode("ValueManipulationCheck.sol"));

    // Get fee configuration from concrete implementation
    (
      uint256 entryFee,
      uint256 exitFee,
      uint256 performanceFee,
      uint256 managementFee,
      uint256 poolFeeShare
    ) = _getFeeConfig();

    // Create test pool with USDC as deposit asset
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
        _performanceFeeNumerator: performanceFee,
        _managerFeeNumerator: managementFee,
        _entryFeeNumerator: entryFee,
        _exitFeeNum: exitFee,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    // Set pool fee share if configured (percentage of fees that go back to the pool instead of manager)
    if (poolFeeShare > 0) {
      vm.prank(manager);
      testPoolManagerLogic.setPoolFeeShareNumerator(poolFeeShare);
    }

    // Disable exit cooldown for testing and set the checker on the factory
    vm.startPrank(owner);
    poolFactoryProxy.setExitCooldown(0);
    poolFactoryProxy.setValueManipulationCheck(address(checker));
    vm.stopPrank();

    // Fund accounts
    deal(usdcData.asset, investor, 2_000_000e6);
    deal(usdcData.asset, attacker, 2_000_000e6);

    // Make a small initial deposit so token price is not 0
    // This ensures the checker works properly in all tests
    // Odd number deposit to test rounding edge cases
    _makeDeposit(testPool, investor, usdcData.asset, _getInitialDeposit() + 1);

    // Advance time to allow withdrawal (dh3 check)
    vm.warp(block.timestamp + 1);
  }

  // ================== DEPLOYMENT TESTS ==================

  function test_deployment() public view {
    assertEq(address(checker), poolFactoryProxy.valueManipulationCheck(), "Checker should be set on factory");
  }

  // ================== SAME VALUE SCENARIOS (SHOULD WORK) ==================

  /// @notice Test that double deposit works when fund value changes as expected
  /// @dev Separate transactions, no value manipulation
  function test_double_deposit_same_value() public {
    uint256 depositAmount = 10_000e6;

    // First deposit
    uint256 fundValue1 = testPoolManagerLogic.totalFundValue();
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);
    uint256 fundValue2 = testPoolManagerLogic.totalFundValue();

    // Verify expected fund value stored in transient storage after first deposit
    // The stored value should be fundValue1 + depositAmount (the expected value after first deposit)
    uint256 storedFundValue = checker.getStoredFundValue(address(testPool));
    // storedFundValue should be approximately fundValue2 (fundValue1 + depositAmount)
    assertApproxEqAbs(storedFundValue, fundValue2, 1e15, "Stored fund value should match expected value");

    // Second deposit - should work because fund value matches expected
    _makeDeposit(testPool, investor, usdcData.asset, depositAmount);
    uint256 fundValue3 = testPoolManagerLogic.totalFundValue();

    // Fund values should increase by deposit amount each time
    assertApproxEqAbs(fundValue2 - fundValue1, depositAmount * 1e12, 1e15, "First deposit should increase fund value");
    assertApproxEqAbs(fundValue3 - fundValue2, depositAmount * 1e12, 1e15, "Second deposit should increase fund value");
  }

  /// @notice Test that withdraw works when fund value doesn't change unexpectedly
  function test_withdraw_same_value() public {
    uint256 balance = testPool.balanceOf(investor);
    uint256 fundValue1 = testPoolManagerLogic.totalFundValue();

    vm.prank(investor);
    testPool.withdraw(balance / 2);

    uint256 fundValue2 = testPoolManagerLogic.totalFundValue();

    // Verify expected fund value stored in transient storage after first withdrawal
    uint256 storedFundValue = checker.getStoredFundValue(address(testPool));
    assertApproxEqAbs(storedFundValue, fundValue2, 1e15, "Stored fund value should match expected value");

    // Second withdrawal - should work because fund value matches expected
    vm.prank(investor);
    testPool.withdraw(balance / 4);

    uint256 fundValue3 = testPoolManagerLogic.totalFundValue();

    // Fund values should decrease with each withdrawal
    assertTrue(fundValue2 < fundValue1, "First withdrawal should decrease fund value");
    assertTrue(fundValue3 < fundValue2, "Second withdrawal should decrease fund value");
  }

  // ================== VALUE MANIPULATION ATTACKS (SHOULD REVERT) ==================

  /// @notice Test that deposit → value inflation → deposit is blocked
  /// @dev Attacker tries to inflate fund value between deposits in same transaction
  function test_deposit_inflate_deposit_reverts() public {
    uint256 depositAmount = 10_000e6;
    uint256 inflationAmount = 10_000e6;
    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();

    // Deploy attacker contract
    TestValueInflationAttacker attackerContract = new TestValueInflationAttacker(address(testPool), usdcData.asset);

    // Fund attacker contract (needs 2x depositAmount + inflationAmount)
    deal(usdcData.asset, address(attackerContract), 2 * depositAmount + inflationAmount);

    // With fees, the exact prices are hard to predict, so just check for any revert
    (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, ) = _getFeeConfig();
    bool hasFees = entryFee > 0 || exitFee > 0 || performanceFee > 0 || managementFee > 0;

    if (hasFees) {
      vm.expectPartialRevert(bytes4(keccak256("ValueManipulationDetected(address,uint256,uint256)")));
    } else {
      vm.expectRevert(
        abi.encodeWithSignature(
          "ValueManipulationDetected(address,uint256,uint256)",
          address(testPool),
          totalFundValueBefore + (depositAmount * 1e12),
          totalFundValueBefore + ((depositAmount + inflationAmount) * 1e12)
        )
      );
    }

    attackerContract.attackViaInflation(depositAmount, inflationAmount);
  }

  /// @notice Test that withdraw → value inflation → withdraw is blocked
  /// @dev Attacker tries to inflate fund value between withdrawals in same transaction
  function test_withdraw_inflate_withdraw_reverts() public {
    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();

    // Deploy attacker contract
    TestValueInflationWithdrawAttacker attackerContract = new TestValueInflationWithdrawAttacker(
      address(testPool),
      usdcData.asset
    );

    // Transfer vault tokens to attacker contract
    uint256 investorBalance = testPool.balanceOf(investor);
    vm.prank(investor);
    testPool.transfer(address(attackerContract), investorBalance / 4);

    // Fund attacker with USDC to inflate value
    deal(usdcData.asset, address(attackerContract), 20_000e6);

    // With fees, the exact prices are hard to predict, so just check for any revert
    (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, ) = _getFeeConfig();
    bool hasFees = entryFee > 0 || exitFee > 0 || performanceFee > 0 || managementFee > 0;

    if (hasFees) {
      vm.expectPartialRevert(bytes4(keccak256("ValueManipulationDetected(address,uint256,uint256)")));
    } else {
      vm.expectRevert(
        abi.encodeWithSignature(
          "ValueManipulationDetected(address,uint256,uint256)",
          address(testPool),
          (totalFundValueBefore * 15) / 16,
          ((((totalFundValueBefore * 15) / 16) / 1e12) * 1e12) + 1_000e18 + 1e12 // USDC precision rounding
        )
      );
    }
    attackerContract.attackViaInflationWithdraw();
  }

  // ================== OPERATION TYPE MISMATCH TESTS ==================

  /// @notice Test that deposit → withdraw in same transaction is blocked
  /// @dev Tests that mixing deposit and withdraw operations reverts with OperationTypeMismatch
  function test_deposit_then_withdraw_reverts() public {
    uint256 depositAmount = 10_000e6;

    // Fund investor
    deal(usdcData.asset, investor, depositAmount);

    vm.startPrank(investor);
    // Approve pool
    IERC20(usdcData.asset).approve(address(testPool), depositAmount);

    // First operation: deposit
    testPool.deposit(usdcData.asset, depositAmount);

    // Advance time by 1 second to pass dh11 check
    vm.warp(block.timestamp + 1);

    // Second operation: withdraw (should revert with OperationTypeMismatch)
    uint256 balance = testPool.balanceOf(investor);
    vm.expectRevert(
      abi.encodeWithSignature(
        "OperationTypeMismatch(address,uint8,uint8)",
        address(testPool),
        uint8(IValueManipulationCheck.OperationType.Deposit),
        uint8(IValueManipulationCheck.OperationType.Withdraw)
      )
    );
    testPool.withdraw(balance / 2);
    vm.stopPrank();
  }

  /// @notice Test that withdraw → deposit in same transaction is blocked
  /// @dev Tests that mixing withdraw and deposit operations reverts with OperationTypeMismatch
  function test_withdraw_then_deposit_reverts() public {
    uint256 depositAmount = 10_000e6;

    // Fund investor
    deal(usdcData.asset, investor, depositAmount);

    vm.startPrank(investor);
    // Approve pool
    IERC20(usdcData.asset).approve(address(testPool), depositAmount);

    // First operation: withdraw
    uint256 balance = testPool.balanceOf(investor);
    testPool.withdraw(balance / 2);

    // Second operation: deposit (should revert with OperationTypeMismatch)
    vm.expectRevert(
      abi.encodeWithSignature(
        "OperationTypeMismatch(address,uint8,uint8)",
        address(testPool),
        uint8(IValueManipulationCheck.OperationType.Withdraw),
        uint8(IValueManipulationCheck.OperationType.Deposit)
      )
    );
    testPool.deposit(usdcData.asset, depositAmount);
    vm.stopPrank();
  }

  /// @notice Test that execTransaction → deposit in same transaction is blocked
  /// @dev Tests that mixing execTransaction and deposit operations reverts with OperationTypeMismatch
  function test_execTransaction_then_deposit_reverts() public {
    uint256 depositAmount = 10_000e6;

    // Fund investor
    deal(usdcData.asset, investor, depositAmount);

    // Deploy ClosedContractGuard and set it for a test contract
    ClosedContractGuard closedGuard = new ClosedContractGuard();
    address testContract = makeAddr("testContract");
    vm.prank(owner);
    governance.setContractGuard(testContract, address(closedGuard));

    vm.startPrank(manager);

    // First operation: execTransaction (approve USDC to test contract)
    bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, testContract, 1000e6);
    testPool.execTransaction(usdcData.asset, approveData);

    vm.stopPrank();

    // Second operation: deposit (should revert with OperationTypeMismatch)
    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), depositAmount);

    vm.expectRevert(
      abi.encodeWithSignature(
        "OperationTypeMismatch(address,uint8,uint8)",
        address(testPool),
        uint8(IValueManipulationCheck.OperationType.ExecTransaction),
        uint8(IValueManipulationCheck.OperationType.Deposit)
      )
    );
    testPool.deposit(usdcData.asset, depositAmount);
    vm.stopPrank();
  }

  /// @notice Test that execTransaction → withdraw in same transaction is blocked
  /// @dev Tests that mixing execTransaction and withdraw operations reverts with OperationTypeMismatch
  function test_execTransaction_then_withdraw_reverts() public {
    // Deploy ClosedContractGuard and set it for a test contract
    ClosedContractGuard closedGuard = new ClosedContractGuard();
    address testContract = makeAddr("testContract");
    vm.prank(owner);
    governance.setContractGuard(testContract, address(closedGuard));

    vm.startPrank(manager);

    // First operation: execTransaction (approve USDC to test contract)
    bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, testContract, 1000e6);
    testPool.execTransaction(usdcData.asset, approveData);

    vm.stopPrank();

    // Second operation: withdraw (should revert with OperationTypeMismatch)
    vm.startPrank(investor);
    uint256 balance = testPool.balanceOf(investor);

    vm.expectRevert(
      abi.encodeWithSignature(
        "OperationTypeMismatch(address,uint8,uint8)",
        address(testPool),
        uint8(IValueManipulationCheck.OperationType.ExecTransaction),
        uint8(IValueManipulationCheck.OperationType.Withdraw)
      )
    );
    testPool.withdraw(balance / 2);
    vm.stopPrank();
  }

  /// @notice Test that deposit → execTransaction in same transaction is blocked
  /// @dev Tests that mixing deposit and execTransaction operations reverts with OperationTypeMismatch
  function test_deposit_then_execTransaction_reverts() public {
    uint256 depositAmount = 10_000e6;

    // Deploy ClosedContractGuard and set it for a test contract
    ClosedContractGuard closedGuard = new ClosedContractGuard();
    address testContract = makeAddr("testContract");
    vm.prank(owner);
    governance.setContractGuard(testContract, address(closedGuard));

    // Fund investor
    deal(usdcData.asset, investor, depositAmount);

    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), depositAmount);

    // First operation: deposit
    testPool.deposit(usdcData.asset, depositAmount);

    vm.stopPrank();

    // Second operation: execTransaction (should revert with OperationTypeMismatch)
    vm.startPrank(manager);

    bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, testContract, 1000e6);

    vm.expectRevert(
      abi.encodeWithSignature(
        "OperationTypeMismatch(address,uint8,uint8)",
        address(testPool),
        uint8(IValueManipulationCheck.OperationType.Deposit),
        uint8(IValueManipulationCheck.OperationType.ExecTransaction)
      )
    );
    testPool.execTransaction(usdcData.asset, approveData);
    vm.stopPrank();
  }

  /// @notice Test that withdraw → execTransaction in same transaction is blocked
  /// @dev Tests that mixing withdraw and execTransaction operations reverts with OperationTypeMismatch
  function test_withdraw_then_execTransaction_reverts() public {
    // Deploy ClosedContractGuard and set it for a test contract
    ClosedContractGuard closedGuard = new ClosedContractGuard();
    address testContract = makeAddr("testContract");
    vm.prank(owner);
    governance.setContractGuard(testContract, address(closedGuard));

    vm.startPrank(investor);
    uint256 balance = testPool.balanceOf(investor);

    // First operation: withdraw
    testPool.withdraw(balance / 2);

    vm.stopPrank();

    // Second operation: execTransaction (should revert with OperationTypeMismatch)
    vm.startPrank(manager);

    bytes memory approveData = abi.encodeWithSelector(IERC20.approve.selector, testContract, 1000e6);

    vm.expectRevert(
      abi.encodeWithSignature(
        "OperationTypeMismatch(address,uint8,uint8)",
        address(testPool),
        uint8(IValueManipulationCheck.OperationType.Withdraw),
        uint8(IValueManipulationCheck.OperationType.ExecTransaction)
      )
    );
    testPool.execTransaction(usdcData.asset, approveData);
    vm.stopPrank();
  }

  // ================== ROUNDING ERROR TESTS ==================

  /// @notice Test that withdrawing half after odd deposit amounts doesn't cause rounding issues
  /// @dev Deposits odd amount, then withdraws exactly half to test division rounding
  function test_withdraw_half_after_odd_deposit() public {
    // the initial deposit is odd already

    // Get balance and withdraw exactly half
    uint256 balance = testPool.balanceOf(investor);
    uint256 fundValue1 = testPoolManagerLogic.totalFundValue();

    vm.prank(investor);
    testPool.withdraw(balance / 2);

    uint256 fundValue2 = testPoolManagerLogic.totalFundValue();

    // Withdraw half of the remaining balance (not all, to avoid emptying the pool)
    uint256 remainingBalance = testPool.balanceOf(investor);

    vm.prank(investor);
    testPool.withdraw(remainingBalance / 2);

    uint256 fundValue3 = testPoolManagerLogic.totalFundValue();

    // Fund values should decrease with each withdrawal
    assertTrue(fundValue2 < fundValue1, "Fund value should decrease after first withdrawal");
    assertTrue(fundValue3 < fundValue2, "Fund value should decrease after second withdrawal");
  }

  /// @notice Test that double withdraw works when second withdraw empties the pool
  /// @dev Tests edge case where final withdrawal results in totalSupply == 0
  function test_double_withdraw_emptying_pool() public {
    // Store original fee config
    (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, ) = _getFeeConfig();

    // Temporarily set fees to 0 to prevent fee minting
    vm.prank(manager);
    testPoolManagerLogic.setFeeNumerator(0, 0, 0, 0);

    // Withdraw any existing manager/DAO balances first (from setUp deposit)
    uint256 daoBalance = testPool.balanceOf(address(dao));
    if (daoBalance > 0) {
      vm.prank(address(dao));
      testPool.withdraw(daoBalance);
    }

    uint256 managerBalance = testPool.balanceOf(manager);
    if (managerBalance > 0) {
      vm.prank(manager);
      testPool.withdraw(managerBalance);
    }

    uint256 balance = testPool.balanceOf(investor);

    // First withdrawal: half the balance
    vm.prank(investor);
    testPool.withdraw(balance / 2);

    // Restore original fees before investor withdrawal and don't mint any fees to manager
    if (performanceFee > 0 || managementFee > 0 || entryFee > 0 || exitFee > 0) {
      vm.startPrank(manager);
      testPoolManagerLogic.announceFeeIncrease(performanceFee, managementFee, entryFee, exitFee);
      skip(15 days);
      testPoolManagerLogic.commitFeeIncrease();
      testPoolManagerLogic.setPoolFeeShareNumerator(poolFactoryProxy.feeDenominator());
      vm.stopPrank();
    }
    // Second withdrawal: remaining balance (empties the pool)
    uint256 remainingBalance = testPool.balanceOf(investor);

    vm.prank(investor);
    testPool.withdraw(remainingBalance);

    // Verify pool is now empty
    assertEq(testPool.totalSupply(), 0, "Pool should be empty after full withdrawal");
  }

  // ================== EMPTY POOL TESTS ==================

  /// @notice Test that double deposit works on a newly created empty pool
  /// @dev Empty pools have tokenPrice == 0 initially, testing that value check handles this correctly
  function test_double_deposit_on_empty_pool() public {
    // Get fee configuration
    (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, ) = _getFeeConfig();

    // Create a fresh empty pool (no initial deposit)
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.prank(manager);
    PoolLogic emptyPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Empty Vault",
        _fundSymbol: "EV",
        _performanceFeeNumerator: performanceFee,
        _managerFeeNumerator: managementFee,
        _entryFeeNumerator: entryFee,
        _exitFeeNum: exitFee,
        _supportedAssets: supportedAssets
      })
    );

    // Verify pool is empty
    assertEq(emptyPool.totalSupply(), 0, "Pool should be empty");

    // First deposit on empty pool
    _makeDeposit(emptyPool, investor, usdcData.asset, 10_000e6);

    // Second deposit in same transaction should work (fund value changed as expected)
    _makeDeposit(emptyPool, investor, usdcData.asset, 10_000e6);

    // Verify deposits succeeded
    assertTrue(emptyPool.balanceOf(investor) > 0, "Investor should have vault tokens");
  }

  // ================== CHECKER DISABLED TESTS ==================

  /// @notice Test that value manipulation check is skipped for pools with fund value under $1
  /// @dev When fundValue <= 1e18, the check is skipped to avoid issues with very small pools
  function test_skips_check_for_low_fund_value() public {
    // Get fee configuration
    (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, ) = _getFeeConfig();

    // Create a fresh empty pool (no initial deposit)
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.prank(manager);
    PoolLogic smallPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Small Vault",
        _fundSymbol: "SV",
        _performanceFeeNumerator: performanceFee,
        _managerFeeNumerator: managementFee,
        _entryFeeNumerator: entryFee,
        _exitFeeNum: exitFee,
        _supportedAssets: supportedAssets
      })
    );

    // Deploy attacker contract
    TestValueInflationAttacker attackerContract = new TestValueInflationAttacker(address(smallPool), usdcData.asset);

    // Make a tiny initial deposit (less than $1 = 1e6 USDC, which becomes < 1e18 in fund value)
    // Using 0.5 USDC = 0.5e6 = 500000, which gives fund value of 0.5e18
    uint256 tinyDeposit = 500000; // 0.5 USDC
    deal(usdcData.asset, address(attackerContract), tinyDeposit * 3);

    // Fund attacker contract and attempt attack
    // This should NOT revert because the fund value is under $1 (1e18)
    // and the check is skipped
    attackerContract.attackViaInflation(tinyDeposit, tinyDeposit);

    // Verify the attack succeeded (check was skipped due to low fund value)
    assertTrue(smallPool.balanceOf(address(attackerContract)) > 0, "Attack should succeed when fund value is under $1");

    // Verify the fund value is indeed under $1 after initial deposit
    PoolManagerLogic smallPoolManager = PoolManagerLogic(smallPool.poolManagerLogic());
    assertTrue(smallPoolManager.totalFundValue() < 2e18, "Fund value should be under $2 after tiny deposits");
  }

  /// @notice Test that value changes are allowed when checker is disabled
  function test_checker_disabled_allows_value_changes() public {
    // Disable checker (must be called by factory owner)
    vm.prank(owner);
    poolFactoryProxy.setValueManipulationCheck(address(0));

    uint256 depositAmount = 10_000e6;
    uint256 inflationAmount = 10_000e6;

    // Deploy attacker contract
    TestValueInflationAttacker attackerContract = new TestValueInflationAttacker(address(testPool), usdcData.asset);

    // Fund attacker contract (needs 2x depositAmount + inflationAmount)
    deal(usdcData.asset, address(attackerContract), 2 * depositAmount + inflationAmount);

    // Should work now (checker disabled)
    attackerContract.attackViaInflation(depositAmount, inflationAmount);

    // Verify attack succeeded
    assertTrue(testPool.balanceOf(address(attackerContract)) > 0, "Attacker should have vault tokens");
  }
}

// ================== CONCRETE TEST IMPLEMENTATIONS ==================

/// @title ValueManipulationCheckTestNoFees
/// @notice Tests ValueManipulationCheck with a pool that has no fees
contract ValueManipulationCheckTestNoFees is ValueManipulationCheckTestBase {
  function _getFeeConfig()
    internal
    pure
    override
    returns (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, uint256 poolFeeShare)
  {
    return (0, 0, 0, 0, 0);
  }

  function _getInitialDeposit() internal pure override returns (uint256 initialDeposit) {
    return 1_000e6;
  }
}

/// @title ValueManipulationCheckTestWithFees
/// @notice Tests ValueManipulationCheck with a pool that has fees configured
/// @dev Entry: 0.2%, Exit: 0.2%, Performance: 10%, Management: 2%
contract ValueManipulationCheckTestWithFees is ValueManipulationCheckTestBase {
  function _getFeeConfig()
    internal
    pure
    override
    returns (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, uint256 poolFeeShare)
  {
    // Entry: 0.2%, Exit: 0.2%, Performance: 10%, Management: 2%
    return (20, 20, 1000, 200, 0);
  }

  function _getInitialDeposit() internal pure override returns (uint256 initialDeposit) {
    return 1_000e6;
  }
}

/// @title ValueManipulationCheckTestWithFeesToPool
/// @notice Tests ValueManipulationCheck with a pool that has fees configured and 100% pool fee share
/// @dev Entry: 1%, Exit: 1%, Performance: 10%, Management: 2%, Pool Fee Share: 100%
contract ValueManipulationCheckTestWithFeesToPool is ValueManipulationCheckTestBase {
  function _getFeeConfig()
    internal
    pure
    override
    returns (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, uint256 poolFeeShare)
  {
    // Entry: 1%, Exit: 1%, Performance: 10%, Management: 2%, Pool Fee Share: 100%
    return (100, 100, 1000, 200, 10000);
  }

  function _getInitialDeposit() internal pure override returns (uint256 initialDeposit) {
    return 1_000e6;
  }
}

/// @title ValueManipulationCheckTestNoFeesLargeDeposit
contract ValueManipulationCheckTestNoFeesLargeDeposit is ValueManipulationCheckTestBase {
  function _getFeeConfig()
    internal
    pure
    override
    returns (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, uint256 poolFeeShare)
  {
    return (0, 0, 0, 0, 0);
  }

  function _getInitialDeposit() internal pure override returns (uint256 initialDeposit) {
    return 1_000_000e6;
  }
}

/// @title ValueManipulationCheckTestWithFeesLargeDeposit
contract ValueManipulationCheckTestWithFeesLargeDeposit is ValueManipulationCheckTestBase {
  function _getFeeConfig()
    internal
    pure
    override
    returns (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, uint256 poolFeeShare)
  {
    // Entry: 1%, Exit: 1%, Performance: 10%, Management: 2%, Pool Fee Share: 0%
    return (100, 100, 1000, 200, 0);
  }

  function _getInitialDeposit() internal pure override returns (uint256 initialDeposit) {
    return 1_000_000e6;
  }
}

/// @title ValueManipulationCheckTestWithFeesToPoolLargeDeposit
contract ValueManipulationCheckTestWithFeesToPoolLargeDeposit is ValueManipulationCheckTestBase {
  function _getFeeConfig()
    internal
    pure
    override
    returns (uint256 entryFee, uint256 exitFee, uint256 performanceFee, uint256 managementFee, uint256 poolFeeShare)
  {
    // Entry: 1%, Exit: 1%, Performance: 10%, Management: 2%, Pool Fee Share: 100%
    return (100, 100, 1000, 200, 10000);
  }

  function _getInitialDeposit() internal pure override returns (uint256 initialDeposit) {
    return 1_000_000e6;
  }
}

// ================== HELPER CONTRACTS ==================

/// @notice Test contract that simulates value inflation attack via deposits
contract TestValueInflationAttacker {
  IPoolLogic public pool;
  address public asset;

  constructor(address _pool, address _asset) {
    pool = IPoolLogic(_pool);
    asset = _asset;
  }

  /// @notice Attempts to exploit via value inflation between deposits
  function attackViaInflation(uint256 firstDepositAmount, uint256 inflationAmount) external {
    // Approve pool to spend
    IERC20(asset).approve(address(pool), firstDepositAmount + inflationAmount);

    // Step 1: Make first deposit
    pool.deposit(asset, firstDepositAmount);

    // Step 2: Inflate pool value by sending assets directly to pool
    // This increases pool value without minting new tokens, thus increasing token price
    IERC20(asset).transfer(address(pool), inflationAmount);

    // Step 3: Try to make second deposit at inflated price
    // This should REVERT due to ValueManipulationCheck detecting unexpected value change
    pool.deposit(asset, firstDepositAmount);
  }
}

/// @notice Test contract that simulates value inflation attack via withdrawals
contract TestValueInflationWithdrawAttacker {
  IPoolLogic public pool;
  address public asset;

  constructor(address _pool, address _asset) {
    pool = IPoolLogic(_pool);
    asset = _asset;
  }

  /// @notice Attempts to exploit via value inflation between withdrawals
  function attackViaInflationWithdraw() external {
    uint256 balance = pool.balanceOf(address(this));
    require(balance > 0, "No vault tokens");

    // Step 1: Make first withdrawal (25% of balance)
    pool.withdraw(balance / 4);

    // Step 2: Inflate pool value by sending assets directly to pool
    // This increases fund value unexpectedly
    IERC20(asset).transfer(address(pool), 1_000e6); // Send 1k USDC

    // Step 3: Try to make second withdrawal
    // This should REVERT due to ValueManipulationCheck detecting unexpected value change
    pool.withdraw(balance / 4);
  }
}
