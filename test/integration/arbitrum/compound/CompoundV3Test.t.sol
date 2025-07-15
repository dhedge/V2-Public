// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CompoundV3CometAssetGuard} from "contracts/guards/assetGuards/CompoundV3CometAssetGuard.sol";
import {CompoundV3CometContractGuard} from "contracts/guards/contractGuards/compound/CompoundV3CometContractGuard.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {ICompoundV3Comet} from "contracts/interfaces/compound/ICompoundV3Comet.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract CompoundV3Test is ArbitrumSetup {
  uint256 internal FORK_BLOCK_NUMBER = 251583884;

  // Compound V3 and related contracts
  address internal immutable USDCAddy;
  ICompoundV3Comet internal constant cUSDC = ICompoundV3Comet(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);
  IERC20 internal immutable USDC;
  IERC20 internal constant cUSDCToken = IERC20(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);

  // Test contracts and addresses
  address[] internal accounts = [manager, investor];

  PoolLogic internal fund;
  PoolManagerLogic internal fundManagerLogic;
  CompoundV3CometContractGuard internal compContractGuard;
  CompoundV3CometAssetGuard internal compAssetGuard;

  constructor() ArbitrumSetup(FORK_BLOCK_NUMBER) {
    USDCAddy = usdcData.asset;
    USDC = IERC20(usdcData.asset);
  }

  function setUp() public override {
    super.setUp();

    vm.startPrank(owner);

    // Deploy the Compound V3 contract and asset guards.
    compContractGuard = new CompoundV3CometContractGuard();
    compAssetGuard = new CompoundV3CometAssetGuard();

    // Set the Compound V3 asset guard in the governance contract.
    governance.setAssetGuard({
      assetType: uint16(AssetTypeIncomplete.COMPOUND_V3_COMET),
      guardAddress: address(compAssetGuard)
    });

    // Set the Compound V3 contract guard in the governance contract.
    governance.setContractGuard({extContract: address(cUSDC), guardAddress: address(compContractGuard)});

    // Create a test dHEDGE fund with USDC enabled as deposit asset.
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: USDCAddy, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: address(cUSDC), isDeposit: false});

    // Add cUSDC asset to the asset handler.
    assetHandlerProxy.addAsset({
      asset: address(cUSDC),
      assetType: uint16(AssetTypeIncomplete.COMPOUND_V3_COMET),
      aggregator: usdcData.aggregator // USDC Chainlink oracle
    });

    vm.startPrank(manager);

    fund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "manager",
        _fundName: "CompoundV3",
        _fundSymbol: "dHC3",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );

    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    _dealTokens();

    // Provide the fund with enough USDC to supply to Compound V3.
    deal(USDCAddy, address(fund), 1_000_000e6);
  }

  function test_comet_supply() public {
    uint256 USDCBalanceOfPoolBefore = USDC.balanceOf(address(fund));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, address(cUSDC), type(uint256).max);
    bytes memory supplyCallData = abi.encodeWithSelector(ICompoundV3Comet.supply.selector, USDCAddy, 1_000e6);

    vm.startPrank(manager);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: USDCAddy, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: address(cUSDC), data: supplyCallData});

    fund.execTransactions(txs);

    assertEq(USDC.balanceOf(address(fund)), USDCBalanceOfPoolBefore - 1_000e6, "USDC balance of pool is incorrect");
    assertApproxEqAbs(cUSDCToken.balanceOf(address(fund)), 1_000e6, 10, "cUSDC balance of pool is incorrect");
  }

  function test_deposit_into_compound_supported_fund() public {
    uint256 USDCBalanceOfInvestorBefore = USDC.balanceOf(investor);

    // Reset the fund's USDC balance to 0.
    deal(USDCAddy, address(fund), 0);

    // Make a deposit into the fund.
    vm.startPrank(manager);

    USDC.approve(address(fund), type(uint256).max);
    fund.deposit(USDCAddy, 10_000e6);

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, address(cUSDC), type(uint256).max);
    bytes memory supplyCallData = abi.encodeWithSelector(ICompoundV3Comet.supply.selector, USDCAddy, 1_000e6);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: USDCAddy, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: address(cUSDC), data: supplyCallData});

    fund.execTransactions(txs);

    vm.startPrank(investor);

    uint256 tokenPrice = fund.tokenPrice();

    USDC.approve(address(fund), 1_000e6);
    fund.deposit(USDCAddy, 1_000e6);

    assertEq(USDC.balanceOf(investor), USDCBalanceOfInvestorBefore - 1_000e6, "Investor USDC balance incorrect");
    assertGe(
      fund.balanceOf(investor),
      fundManagerLogic.assetValue(USDCAddy, 1_000e6) / tokenPrice,
      "Investor should have received some funds tokens"
    );
  }

  function test_comet_withdraw_full() public {
    uint256 USDCBalanceOfPoolBefore = USDC.balanceOf(address(fund));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, address(cUSDC), type(uint256).max);
    bytes memory supplyCallData = abi.encodeWithSelector(ICompoundV3Comet.supply.selector, USDCAddy, 1_000e6);

    vm.startPrank(manager);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: USDCAddy, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: address(cUSDC), data: supplyCallData});

    fund.execTransactions(txs);

    skip(1 days);

    bytes memory withdrawCallData = abi.encodeWithSelector(
      ICompoundV3Comet.withdraw.selector,
      USDCAddy,
      type(uint256).max // Max withdraw
    );

    fund.execTransaction(address(cUSDC), withdrawCallData);

    // Since a day has passed and the interest has accrued, the USDC balance of the pool should be higher than before.
    assertGt(USDC.balanceOf(address(fund)), USDCBalanceOfPoolBefore, "USDC balance of pool is incorrect");
    assertEq(cUSDCToken.balanceOf(address(fund)), 0, "cUSDC balance of pool is incorrect");
  }

  function test_comet_withdraw_partial() public {
    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, address(cUSDC), type(uint256).max);
    bytes memory supplyCallData = abi.encodeWithSelector(ICompoundV3Comet.supply.selector, USDCAddy, 1_000e6);

    vm.startPrank(manager);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: USDCAddy, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: address(cUSDC), data: supplyCallData});

    fund.execTransactions(txs);

    skip(1 days);

    uint256 cUSDCBalance = cUSDCToken.balanceOf(address(fund));
    uint256 USDCBalanceOfPoolBeforeWithdrawal = USDC.balanceOf(address(fund));

    bytes memory withdrawCallData = abi.encodeWithSelector(
      ICompoundV3Comet.withdraw.selector,
      USDCAddy,
      cUSDCBalance / 2
    );

    fund.execTransaction(address(cUSDC), withdrawCallData);

    assertEq(
      USDC.balanceOf(address(fund)),
      USDCBalanceOfPoolBeforeWithdrawal + cUSDCBalance / 2,
      "USDC balance of pool is incorrect"
    );
    assertApproxEqAbs(cUSDCToken.balanceOf(address(fund)), cUSDCBalance / 2, 10, "cUSDC balance of pool is incorrect");
  }

  function test_withdraw_from_compounds_supported_fund() public {
    uint256 USDCInvestorBalanceBefore = USDC.balanceOf(investor);

    // Reset the fund's USDC balance to 0.
    deal(USDCAddy, address(fund), 0);

    // Make a deposit into the fund.
    vm.startPrank(manager);

    USDC.approve(address(fund), type(uint256).max);
    fund.deposit(USDCAddy, 10_000e6);

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, address(cUSDC), type(uint256).max);
    bytes memory supplyCallData = abi.encodeWithSelector(ICompoundV3Comet.supply.selector, USDCAddy, 1_000e6);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: USDCAddy, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: address(cUSDC), data: supplyCallData});

    fund.execTransactions(txs);

    vm.startPrank(investor);

    USDC.approve(address(fund), 1_000e6);
    fund.deposit(USDCAddy, 1_000e6);

    uint256 fundTokenBalanceOfInvestorBefore = fund.balanceOf(investor);

    skip(1 days);

    fund.withdraw(fundTokenBalanceOfInvestorBefore);

    assertEq(cUSDCToken.balanceOf(investor), 0, "Investor shouldn't receive cUSDC");
    assertGe(USDC.balanceOf(investor), USDCInvestorBalanceBefore, "Investor's USDC balance incorrect after withdrawal");
    assertEq(fund.balanceOf(investor), 0, "Investor's fund token balance incorrect after withdrawal");
  }

  function _dealTokens() internal {
    for (uint256 i; i < accounts.length; ++i) {
      deal(accounts[i], 100e18);
      deal(USDCAddy, accounts[i], 1_000_000e6);
    }
  }
}
