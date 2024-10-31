// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CompoundV3CometAssetGuard} from "contracts/guards/assetGuards/CompoundV3CometAssetGuard.sol";
import {CompoundV3CometContractGuard} from "contracts/guards/contractGuards/compound/CompoundV3CometContractGuard.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {Governance} from "contracts/Governance.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {ICompoundV3Comet} from "contracts/interfaces/compound/ICompoundV3Comet.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

import {Test} from "forge-std/Test.sol";

contract CompoundV3Test is Test {
  uint256 internal FORK_BLOCK_NUMBER = 251583884;

  // dHEDGE contracts and addresses
  address internal owner = 0x13471A221D6A346556723842A1526C603Dc4d36B;
  PoolFactory internal constant factory = PoolFactory(0xffFb5fB14606EB3a548C113026355020dDF27535);
  PoolLogic internal constant poolLogicImplementation = PoolLogic(0x126ECA2B9C092DfA1f7CB15fA6D9c42D60649222);
  PoolManagerLogic internal constant poolManagerLogicImplementation =
    PoolManagerLogic(0x96142e2D9CD98F8B9dF8f1d2569956F0bd4f418a);
  Governance internal constant governance = Governance(0x0b844847558A5814CD0d5Ca539AdF62A5486c826);
  AssetHandler internal constant assetHandler = AssetHandler(0x1BaF125D53F65a708bCb5559c9a9fdD9D088eDe3);

  // Compound V3 and related contracts
  address internal constant USDCAddy = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
  ICompoundV3Comet internal constant cUSDC = ICompoundV3Comet(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);
  IERC20 internal constant USDC = IERC20(USDCAddy);
  IERC20 internal constant cUSDCToken = IERC20(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);

  // Test contracts and addresses
  address internal manager = makeAddr("manager");
  address internal investor = makeAddr("investor");
  address[] internal accounts = [manager, investor];

  PoolLogic internal fund;
  PoolManagerLogic internal fundManagerLogic;
  CompoundV3CometContractGuard internal compContractGuard;
  CompoundV3CometAssetGuard internal compAssetGuard;

  function setUp() public {
    vm.createSelectFork("arbitrum", FORK_BLOCK_NUMBER);

    // Change the runtime code of the integration contracts.
    // This allows us to add console logs in the contracts.
    vm.etch(address(poolLogicImplementation), vm.getDeployedCode("PoolLogic.sol:PoolLogic"));
    vm.etch(address(poolManagerLogicImplementation), vm.getDeployedCode("PoolManagerLogic.sol:PoolManagerLogic"));

    vm.startPrank(owner);

    // Deploy the Compound V3 contract and asset guards.
    compContractGuard = new CompoundV3CometContractGuard();
    compAssetGuard = new CompoundV3CometAssetGuard();

    // Set the Compound V3 asset guard in the governance contract.
    governance.setAssetGuard({
      assetType: 28, // Compound V3 Comet Asset
      guardAddress: address(compAssetGuard)
    });

    // Set the Compound V3 contract guard in the governance contract.
    governance.setContractGuard({extContract: address(cUSDC), guardAddress: address(compContractGuard)});

    // Create a test dHEDGE fund with USDC enabled as deposit asset.
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: USDCAddy, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: address(cUSDC), isDeposit: false});

    // Add cUSDC asset to the asset handler.
    assetHandler.addAsset({
      asset: address(cUSDC),
      assetType: 28,
      aggregator: 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3
    });

    // Disable chainlink expiry timeout.
    assetHandler.setChainlinkTimeout(86400 * 365); // 1 year

    vm.startPrank(manager);

    fund = PoolLogic(
      factory.createFund({
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

    fund.withdrawSafe(fundTokenBalanceOfInvestorBefore, 10_000);

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
