// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {IVelodromeV2Gauge} from "contracts/interfaces/velodrome/IVelodromeV2Gauge.sol";
import {IVelodromeV2Router} from "contracts/interfaces/velodrome/IVelodromeV2Router.sol";
import {IVelodromeV2Pair} from "contracts/interfaces/velodrome/IVelodromeV2Pair.sol";

/// @notice Investigates and reproduces (in a fork test) the owner-triggered unwind of the FondAS vault's
/// Velodrome V2 sUSD/USDC stable LP position on Optimism.
///
/// Context: at block 154134242, FondAS's staked LP position is valued (via `VelodromeV2LPAssetGuard` +
/// `UniV2LPAggregator`) at ~$389 out of a total fund value of ~$475 - it dominates the vault's NAV.
/// That valuation is based on `IVelodromeV2Pair.getReserves()`, which is stale: the sUSD side of the
/// pair (`reserve1`) still reports ~3.24M sUSD, but sUSD (`SUSD`) has since been fully deprecated on
/// Optimism (`IERC20(SUSD).totalSupply() == 0`), so the pair's *actual* sUSD balance is 0. The LP
/// position therefore massively overstates the fund's real NAV.
///
/// Since the manager EOA has no special privileges here, the fix must be executed by the *protocol
/// owner* (the dHEDGE protocol DAO Safe on Optimism), which `PoolLogicLib.execTransaction` already
/// allows to call `execTransaction`/`execTransactions` on any vault. However, at this fork block,
/// Optimism's deployed `PoolLogic`/`PoolManagerLogic` beacon implementations are still on the old
/// `v2.12.0` release, which predates that owner-bypass. So this test first "rolls" the pending core
/// contracts upgrade (deploy latest `PoolLogic` + `PoolManagerLogic` and swap them in via
/// `PoolFactory.setLogic`, exactly like `deployment/upgrade/jobs/poolLogicAndManagerLogicJob.ts` does in
/// production) before exercising the unwind.
///
/// IMPORTANT FINDING: a full "unstake -> claim -> removeLiquidity" unwind (turning the LP back into
/// USDC + sUSD) is NOT achievable on-chain. Velodrome V2's `Pair.burn()` requires both `amount0 > 0 &&
/// amount1 > 0` ("InsufficientLiquidityBurned" otherwise). Because sUSD's total supply is permanently 0,
/// `amount1` is always 0 for *any* liquidity amount burned - by anyone, not just this vault. The pair is
/// therefore permanently un-burnable. The only assets that can realistically be recovered are the
/// staked LP tokens themselves (moved from the gauge back to the vault, still unburnable) and the
/// accrued VELO gauge rewards. See test_revert_removeLiquidity_always_reverts_susd_is_deprecated below.
contract UnwindFondASVeloV2PositionTest is Test {
  uint256 public constant FORK_BLOCK = 154134242;

  // FondAS vault ("FAD") being unwound.
  address public constant VAULT = 0xCc65077153fCC0DD2B12da8D387f66258b53a80F;
  address public constant VAULT_MANAGER_LOGIC = 0xC9f0944Edf5b9BcE794b104E66D7e9DD4397F400;

  address public constant POOL_FACTORY = 0x5e61a079A178f0E5784107a4963baAe0c5a680c6;
  // PoolFactory.owner() - the dHEDGE protocol DAO Safe (3-of-5) on Optimism.
  address public constant PROTOCOL_DAO_SAFE = 0x90b1a66957914EbbE7a8df254c0c1E455972379C;

  // Velodrome V2 sUSD/USDC stable LP position to unwind.
  address public constant VELO_V2_LP = 0xbC26519f936A90E78fe2C9aA2A03CC208f041234;
  address public constant VELO_V2_GAUGE = 0x0E4c56B4a766968b12c286f67aE341b11eDD8b8d;
  address public constant VELO_V2_ROUTER = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;

  address public constant USDC_NATIVE = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // LP token0
  address public constant SUSD = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9; // LP token1, deprecated
  address public constant VELO = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db; // gauge reward token

  function setUp() public {
    vm.createSelectFork("optimism", FORK_BLOCK);
  }

  /// @dev Deploys the latest `PoolLogic`/`PoolManagerLogic` implementations (forge auto-links the
  /// external `PoolLogicLib`) and swaps them into the beacon-style `ProxyFactory.setLogic`, pranked as
  /// the protocol owner. This is the "upgrade to roll first" step required before the owner can call
  /// `execTransaction` on any vault.
  function _upgradeCoreLogicContracts() internal {
    address newPoolLogic = address(new PoolLogic());
    address newPoolManagerLogic = address(new PoolManagerLogic());

    assertEq(PoolFactory(POOL_FACTORY).owner(), PROTOCOL_DAO_SAFE, "unexpected PoolFactory owner");

    vm.prank(PROTOCOL_DAO_SAFE);
    PoolFactory(POOL_FACTORY).setLogic(newPoolLogic, newPoolManagerLogic);
  }

  function test_sanity_susd_is_fully_deprecated() public view {
    // Confirms the root cause: sUSD's entire supply has been burned/redeemed network-wide, so the
    // pair's actual sUSD balance can never become non-zero again.
    assertEq(IERC20(SUSD).totalSupply(), 0, "expected sUSD total supply to be fully deprecated");
    assertEq(IERC20(SUSD).balanceOf(VELO_V2_LP), 0, "expected pair to hold no real sUSD");

    (uint112 reserve0, uint112 reserve1, ) = IVelodromeV2Pair(VELO_V2_LP).getReserves();
    assertGt(uint256(reserve0), 0, "sanity: reserve0 (USDC) cache is non-zero");
    assertGt(uint256(reserve1), 0, "sanity: stale reserve1 (sUSD) cache is still non-zero, driving the overvaluation");
  }

  function test_revert_owner_execTransaction_before_upgrade() public {
    uint256 stakedLp = IVelodromeV2Gauge(VELO_V2_GAUGE).balanceOf(VAULT);

    bytes memory data = abi.encodeWithSelector(IVelodromeV2Gauge.withdraw.selector, stakedLp);

    // At this block, Optimism's deployed PoolLogic doesn't yet allow the protocol owner to bypass
    // manager/trader in `execTransaction` - confirms the upgrade is a prerequisite for the real unwind.
    vm.prank(PROTOCOL_DAO_SAFE);
    vm.expectRevert(bytes("dh24"));
    PoolLogic(VAULT).execTransaction(VELO_V2_GAUGE, data);
  }

  /// @dev Documents the key blocker: even after the upgrade, unstaking, and claiming rewards, burning
  /// the LP position via the router is permanently impossible because the pair can never hold sUSD again.
  function test_revert_removeLiquidity_always_reverts_susd_is_deprecated() public {
    uint256 stakedLp = IVelodromeV2Gauge(VELO_V2_GAUGE).balanceOf(VAULT);
    assertGt(stakedLp, 0, "expected an existing staked Velodrome V2 LP position");

    _upgradeCoreLogicContracts();

    PoolLogic.TxToExecute[] memory unstakeTxs = new PoolLogic.TxToExecute[](2);
    unstakeTxs[0] = PoolLogic.TxToExecute({
      to: VELO_V2_GAUGE,
      data: abi.encodeWithSelector(IVelodromeV2Gauge.withdraw.selector, stakedLp)
    });
    unstakeTxs[1] = PoolLogic.TxToExecute({
      to: VELO_V2_LP,
      data: abi.encodeWithSelector(IERC20.approve.selector, VELO_V2_ROUTER, stakedLp)
    });

    vm.prank(PROTOCOL_DAO_SAFE);
    PoolLogic(VAULT).execTransactions(unstakeTxs);

    bytes memory removeLiquidityData = abi.encodeWithSelector(
      IVelodromeV2Router.removeLiquidity.selector,
      USDC_NATIVE,
      SUSD,
      true, // stable pool
      stakedLp,
      0,
      0,
      VAULT,
      block.timestamp
    );

    // Reverts with Velodrome's "InsufficientLiquidityBurned" custom error: `Pair.burn()` requires both
    // amount0 > 0 and amount1 > 0, and amount1 (sUSD) is always floor(liquidity * 0 / totalSupply) = 0.
    vm.prank(PROTOCOL_DAO_SAFE);
    vm.expectRevert();
    PoolLogic(VAULT).execTransaction(VELO_V2_ROUTER, removeLiquidityData);
  }

  /// @dev The realistically achievable unwind: recover control of the LP from the gauge and claim the
  /// real, meaningful accrued VELO rewards. The LP tokens themselves remain in the vault (unburnable),
  /// so they still appear in the fund composition - correcting their valuation requires a separate,
  /// deliberate governance action (re-pointing the asset's price aggregator), not a vault-level
  /// execTransaction, since the position cannot be reduced to a zero balance.
  function test_unwind_gauge_position_and_claim_velo_rewards_after_upgrade() public {
    uint256 stakedLpBefore = IVelodromeV2Gauge(VELO_V2_GAUGE).balanceOf(VAULT);
    assertGt(stakedLpBefore, 0, "expected an existing staked Velodrome V2 LP position");
    assertEq(IERC20(VELO_V2_LP).balanceOf(VAULT), 0, "expected LP to be fully staked in the gauge");

    uint256 veloBefore = IERC20(VELO).balanceOf(VAULT);

    _upgradeCoreLogicContracts();

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({
      to: VELO_V2_GAUGE,
      data: abi.encodeWithSelector(IVelodromeV2Gauge.withdraw.selector, stakedLpBefore)
    });
    txs[1] = PoolLogic.TxToExecute({
      to: VELO_V2_GAUGE,
      data: abi.encodeWithSelector(IVelodromeV2Gauge.getReward.selector, VAULT)
    });

    vm.prank(PROTOCOL_DAO_SAFE);
    PoolLogic(VAULT).execTransactions(txs);

    // Nothing left staked - the whole position moved back to a raw LP balance held by the vault.
    assertEq(IVelodromeV2Gauge(VELO_V2_GAUGE).balanceOf(VAULT), 0, "gauge position should be fully unstaked");
    assertEq(IERC20(VELO_V2_LP).balanceOf(VAULT), stakedLpBefore, "LP tokens should now be held raw by the vault");

    // Real, meaningful value recovered: accrued VELO rewards.
    assertGt(IERC20(VELO).balanceOf(VAULT), veloBefore, "VELO rewards should have been claimed");
  }
}
