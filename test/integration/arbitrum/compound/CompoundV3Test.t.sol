// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CompoundV3CometAssetGuard} from "contracts/guards/assetGuards/CompoundV3CometAssetGuard.sol";
import {CompoundV3CometContractGuard} from "contracts/guards/contractGuards/compound/CompoundV3CometContractGuard.sol";
// solhint-disable-next-line max-line-length
import {CompoundV3CometRewardsContractGuard} from "contracts/guards/contractGuards/compound/CompoundV3CometRewardsContractGuard.sol";
import {ICompoundV3CometRewards} from "contracts/interfaces/compound/ICompoundV3CometRewards.sol";
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

  /// @dev Comet's rewards distributor on Arbitrum, per config/arbitrum governance guards.
  ICompoundV3CometRewards internal constant cometRewards =
    ICompoundV3CometRewards(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae);

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
    governance.setContractGuard({
      extContract: address(cometRewards),
      guardAddress: address(new CompoundV3CometRewardsContractGuard())
    });

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
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );

    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    _dealTokens();

    // Provide the fund with enough USDC to supply to Compound V3.
    deal(USDCAddy, address(fund), 1_000_000e6);

    vm.stopPrank();
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

  /* ========== REWARDS ========== */

  /// @notice Claiming Comet rewards is guarded on three counts: the rewards must land in the vault,
  /// the vault must actually hold the Comet position, and it must be able to price what it is paid.
  function test_revert_claim_rewards_to_a_receiver_other_than_the_vault() public {
    _supplyToComet();

    vm.prank(manager);
    vm.expectRevert("invalid receiver");
    fund.execTransaction(address(cometRewards), _claimCalldata(address(cUSDC), manager));
  }

  function test_revert_claim_rewards_for_a_comet_the_vault_does_not_hold() public {
    _supplyToComet();

    // A Comet the vault does not support: nothing is owed to it and nothing should be claimable.
    vm.prank(manager);
    vm.expectRevert("Compound asset not enabled");
    fund.execTransaction(address(cometRewards), _claimCalldata(makeAddr("someOtherComet"), address(fund)));
  }

  function test_revert_claim_rewards_when_the_reward_asset_is_not_enabled() public {
    address rewardAsset = cometRewards.rewardConfig(address(cUSDC)).token;
    _registerRewardAsset(rewardAsset);
    _supplyToComet();

    // Registered protocol-wide but not enabled on this vault, so it cannot be valued if received.
    vm.prank(manager);
    vm.expectRevert("reward asset not enabled");
    fund.execTransaction(address(cometRewards), _claimCalldata(address(cUSDC), address(fund)));
  }

  function test_manager_can_claim_rewards_into_the_vault() public {
    address rewardAsset = cometRewards.rewardConfig(address(cUSDC)).token;
    _registerRewardAsset(rewardAsset);
    _enableRewardAssetOnFund(rewardAsset);
    _supplyToComet();

    uint256 rewardBalanceBefore = IERC20(rewardAsset).balanceOf(address(fund));

    vm.prank(manager);
    fund.execTransaction(address(cometRewards), _claimCalldata(address(cUSDC), address(fund)));

    // Rewards accrue to the vault, never to the manager. Assert the balance strictly grew: a claim
    // that paid nothing, or paid somewhere else, must not pass as success.
    assertGt(IERC20(rewardAsset).balanceOf(address(fund)), rewardBalanceBefore, "no rewards claimed");
    assertEq(IERC20(rewardAsset).balanceOf(manager), 0);
  }

  function _supplyToComet() internal {
    vm.prank(manager);
    fund.execTransaction(USDCAddy, abi.encodeWithSelector(IERC20.approve.selector, address(cUSDC), 1_000_000e6));

    vm.prank(manager);
    fund.execTransaction(
      address(cUSDC),
      abi.encodeWithSelector(ICompoundV3Comet.supply.selector, USDCAddy, 1_000_000e6)
    );

    skip(1 days);
  }

  function _registerRewardAsset(address _rewardAsset) internal {
    vm.prank(owner);
    assetHandlerProxy.addAsset({
      asset: _rewardAsset,
      assetType: uint16(AssetTypeIncomplete.CHAINLINK),
      aggregator: usdcData.aggregator // any working feed; these tests never assert its value
    });
  }

  function _enableRewardAssetOnFund(address _rewardAsset) internal {
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: _rewardAsset, isDeposit: false});

    vm.prank(manager);
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
  }

  function _claimCalldata(address _comet, address _receiver) internal pure returns (bytes memory data) {
    data = abi.encodeWithSelector(ICompoundV3CometRewards.claim.selector, _comet, _receiver, true);
  }

  /* ========== GUARD VALIDATION ========== */

  /// @notice The Comet guard only lets a vault move Comet's own base token, and only in and out of
  /// a Comet position the vault actually supports.
  function test_revert_supply_an_asset_that_is_not_the_comet_base_token() public {
    vm.prank(manager);
    vm.expectRevert("invalid Compound asset");
    fund.execTransaction(
      address(cUSDC),
      abi.encodeWithSelector(ICompoundV3Comet.supply.selector, address(cUSDC), 1_000e6)
    );
  }

  function test_revert_supply_when_the_comet_position_is_not_enabled() public {
    // Drop the Comet position from the vault, keeping only the base token.
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = address(cUSDC);

    vm.prank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    vm.prank(manager);
    vm.expectRevert("Compound not enabled");
    fund.execTransaction(address(cUSDC), abi.encodeWithSelector(ICompoundV3Comet.supply.selector, USDCAddy, 1_000e6));
  }

  function test_revert_withdraw_an_asset_the_vault_does_not_support() public {
    _supplyToComet();

    // The Comet share token is not a withdrawal asset - only the base token is.
    vm.prank(manager);
    vm.expectRevert("unsupported withdrawal asset");
    fund.execTransaction(
      address(cUSDC),
      abi.encodeWithSelector(ICompoundV3Comet.withdraw.selector, makeAddr("notAVaultAsset"), 1_000e6)
    );
  }
}
