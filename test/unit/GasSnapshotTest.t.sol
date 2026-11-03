// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/v3/contracts/proxy/TransparentUpgradeableProxy.sol";

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {WithdrawalVault} from "contracts/swappers/easySwapperV2/WithdrawalVault.sol";
import {WETH9} from "contracts/test/WETH9.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice Gas of the user-paid paths (EasySwapperV2 as the frontends use it, plus the PoolLogic
/// entry points underneath), recorded to `snapshots/GasSnapshotTest.json`, and bytecode size of the
/// core contracts, recorded to `snapshots/ContractSizes.json`. Every `forge test` run rewrites both,
/// so a gas or size change shows up as a diff, and CI fails when the committed files no longer match.
/// @dev Runs isolated so each measured call is its own transaction with cold storage, as it is paid
/// for on-chain. Without isolation the slots warmed by `setUp` make the numbers understate real cost.
/// forge-config: default.isolate = true
contract GasSnapshotTest is PoolUnitTestSetup {
  string internal constant GROUP = "GasSnapshotTest";
  string internal constant SIZES_GROUP = "ContractSizes";
  uint256 internal constant DEPOSIT_AMOUNT = 1_000e6;
  uint256 internal constant NATIVE_DEPOSIT_AMOUNT = 1 ether;
  uint256 internal constant CUSTOM_COOLDOWN = 60 minutes;

  address internal spender = makeAddr("spender");
  address internal spenderGuard = makeAddr("spenderGuard");

  WETH9 internal weth9;
  EasySwapperV2 internal easySwapper;
  /// @dev Reached through EasySwapperV2: takes USDC and wrapped native, whitelisted for the custom cooldown.
  PoolLogic internal swapperVault;

  function setUp() public override {
    super.setUp();

    weth9 = new WETH9();
    vm.prank(owner);
    assetHandlerProxy.addAsset({asset: address(weth9), assetType: 0, aggregator: wethPriceFeed});

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: address(weth9), isDeposit: true});
    swapperVault = _createFund(supportedAssets);

    vm.startPrank(owner);
    easySwapper = EasySwapperV2(address(new TransparentUpgradeableProxy(address(new EasySwapperV2()), proxyAdmin, "")));
    easySwapper.initialize(
      address(new WithdrawalVault()),
      address(0),
      IWETH(address(weth9)),
      ISwapper(makeAddr("swapper")),
      CUSTOM_COOLDOWN
    );
    easySwapper.setdHedgePoolFactory(address(poolFactoryProxy));
    poolFactoryProxy.addCustomCooldownWhitelist(address(easySwapper));
    EasySwapperV2.WhitelistSetting[] memory whitelist = new EasySwapperV2.WhitelistSetting[](1);
    whitelist[0] = EasySwapperV2.WhitelistSetting({toWhitelist: address(swapperVault), whitelisted: true});
    easySwapper.setCustomCooldownWhitelist(whitelist);
    vm.stopPrank();

    vm.deal(investor, 10 ether);
    vm.prank(investor);
    usdc.approve(address(easySwapper), type(uint256).max);
  }

  /* ========== EASYSWAPPERV2, THE FRONTEND PATH ========== */

  function test_gas_easy_swapper_deposit() public {
    vm.prank(investor);
    easySwapper.deposit(address(swapperVault), IERC20(address(usdc)), DEPOSIT_AMOUNT, 0);
    vm.snapshotGasLastCall(GROUP, "EasySwapperV2_deposit");
  }

  function test_gas_easy_swapper_depositWithCustomCooldown() public {
    vm.prank(investor);
    easySwapper.depositWithCustomCooldown(address(swapperVault), IERC20(address(usdc)), DEPOSIT_AMOUNT, 0);
    vm.snapshotGasLastCall(GROUP, "EasySwapperV2_depositWithCustomCooldown");
  }

  function test_gas_easy_swapper_nativeDepositWithCustomCooldown() public {
    vm.prank(investor);
    easySwapper.nativeDepositWithCustomCooldown{value: NATIVE_DEPOSIT_AMOUNT}(address(swapperVault), 0);
    vm.snapshotGasLastCall(GROUP, "EasySwapperV2_nativeDepositWithCustomCooldown");
  }

  /// @dev One flow, two snapshots: `completeWithdrawal` only exists after `initWithdrawal`.
  function test_gas_easy_swapper_withdrawal_flow() public {
    uint256 shares = _depositThroughSwapperAndWaitOutCooldown();

    vm.startPrank(investor);
    swapperVault.approve(address(easySwapper), shares);
    easySwapper.initWithdrawal(address(swapperVault), shares, _getEmptyPoolComplexAssetsData(address(swapperVault)));
    vm.snapshotGasLastCall(GROUP, "EasySwapperV2_initWithdrawal");

    easySwapper.completeWithdrawal();
    vm.snapshotGasLastCall(GROUP, "EasySwapperV2_completeWithdrawal");
    vm.stopPrank();
  }

  /* ========== POOLLOGIC DEPOSITS ========== */

  function test_gas_deposit_first() public {
    vm.prank(investor);
    fund.deposit(address(usdc), DEPOSIT_AMOUNT);
    vm.snapshotGasLastCall(GROUP, "deposit_first");
  }

  function test_gas_deposit_subsequent() public {
    _deposit(investor, address(usdc), DEPOSIT_AMOUNT);

    vm.prank(otherInvestor);
    fund.deposit(address(usdc), DEPOSIT_AMOUNT);
    vm.snapshotGasLastCall(GROUP, "deposit_subsequent");
  }

  /* ========== POOLLOGIC WITHDRAWALS ========== */

  function test_gas_withdrawSafe_partial() public {
    uint256 shares = _depositAndWaitOutCooldown();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(fund));

    vm.prank(investor);
    fund.withdrawSafe(shares / 2, complexAssetsData);
    vm.snapshotGasLastCall(GROUP, "withdrawSafe_partial");
  }

  function test_gas_withdrawSafe_full() public {
    uint256 shares = _depositAndWaitOutCooldown();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(fund));

    vm.prank(investor);
    fund.withdrawSafe(shares, complexAssetsData);
    vm.snapshotGasLastCall(GROUP, "withdrawSafe_full");
  }

  function test_gas_withdrawToSafe() public {
    uint256 shares = _depositAndWaitOutCooldown();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(fund));

    vm.prank(investor);
    fund.withdrawToSafe(otherInvestor, shares / 2, complexAssetsData);
    vm.snapshotGasLastCall(GROUP, "withdrawToSafe");
  }

  /* ========== MANAGER AND PUBLIC ACTIONS ========== */

  function test_gas_execTransaction_approve() public {
    vm.prank(owner);
    governance.setContractGuard({extContract: spender, guardAddress: spenderGuard});

    vm.prank(manager);
    fund.execTransaction(address(usdc), abi.encodeWithSelector(IERC20.approve.selector, spender, 1e6));
    vm.snapshotGasLastCall(GROUP, "execTransaction_approve");
  }

  function test_gas_mintManagerFee() public {
    PoolLogic feeFund = _createFund(manager, _toSupportedAssets(address(usdc), true), 5_000, 200, 0, 0);
    _makeDeposit(feeFund, investor, address(usdc), DEPOSIT_AMOUNT);
    // 10% profit and half a year of streaming fee, so both fee legs mint.
    deal(address(usdc), address(feeFund), (usdc.balanceOf(address(feeFund)) * 110) / 100);
    vm.warp(block.timestamp + 180 days);

    feeFund.mintManagerFee();
    vm.snapshotGasLastCall(GROUP, "mintManagerFee");
  }

  function test_gas_createFund() public {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: address(weth), isDeposit: true});

    _createFund(supportedAssets);
    vm.snapshotGasLastCall(GROUP, "createFund");
  }

  /* ========== VALUATION ========== */

  function test_gas_totalFundValue_two_assets() public {
    _deposit(investor, address(usdc), DEPOSIT_AMOUNT);
    _deposit(investor, address(weth), 1e18);

    fundManagerLogic.totalFundValue();
    vm.snapshotGasLastCall(GROUP, "totalFundValue_two_assets");
  }

  /* ========== BYTECODE SIZE ========== */

  /// @dev Runtime size of the core contracts and the library PoolLogic links, in their own file
  /// (`snapshots/ContractSizes.json`) so gas and bytes never share one.
  function test_size_core_contracts() public {
    vm.snapshotValue(SIZES_GROUP, "PoolLogic", vm.getDeployedCode("PoolLogic.sol:PoolLogic").length);
    vm.snapshotValue(SIZES_GROUP, "PoolLogicLib", vm.getDeployedCode("PoolLogicLib.sol:PoolLogicLib").length);
    vm.snapshotValue(
      SIZES_GROUP,
      "PoolManagerLogic",
      vm.getDeployedCode("PoolManagerLogic.sol:PoolManagerLogic").length
    );
    vm.snapshotValue(SIZES_GROUP, "PoolFactory", vm.getDeployedCode("PoolFactory.sol:PoolFactory").length);
    vm.snapshotValue(SIZES_GROUP, "EasySwapperV2", vm.getDeployedCode("EasySwapperV2.sol:EasySwapperV2").length);
  }

  /* ========== HELPERS ========== */

  function _depositAndWaitOutCooldown() internal returns (uint256 shares) {
    shares = _deposit(investor, address(usdc), DEPOSIT_AMOUNT);
    vm.warp(block.timestamp + EXIT_COOLDOWN);
  }

  /// @dev USDC plus native, so the withdrawal tracks two assets like a typical vault would.
  function _depositThroughSwapperAndWaitOutCooldown() internal returns (uint256 shares) {
    vm.startPrank(investor);
    easySwapper.depositWithCustomCooldown(address(swapperVault), IERC20(address(usdc)), DEPOSIT_AMOUNT, 0);
    easySwapper.nativeDepositWithCustomCooldown{value: NATIVE_DEPOSIT_AMOUNT}(address(swapperVault), 0);
    vm.stopPrank();
    shares = swapperVault.balanceOf(investor);
    vm.warp(block.timestamp + CUSTOM_COOLDOWN);
  }
}
