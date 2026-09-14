// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IVelodromeCLGauge} from "contracts/interfaces/velodrome/IVelodromeCLGauge.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {VelodromeCLTestSetup} from "test/integration/common/velodromeCL/VelodromeCLTestSetup.t.sol";

/// @notice `VelodromeCLGaugeContractGuard` lets a vault stake its own tracked CL positions for
/// emissions. It only accepts positions the NFT tracker knows the vault owns, and only while the
/// vault supports the reward token and both position underlyings.
abstract contract VelodromeCLGaugeGuardTestSetup is VelodromeCLTestSetup {
  /// @dev A tokenId the vault has never owned.
  uint256 internal constant FOREIGN_TOKEN_ID = 1234;
  /// @dev The gauge also has a `getReward(address)`, so this one cannot be taken off the interface.
  bytes4 internal constant GET_REWARD_SELECTOR = bytes4(keccak256("getReward(uint256)"));

  /* ========== STAKING ========== */

  function test_revert_stake_an_untracked_position() public {
    _enableNftPosition();

    vm.prank(manager);
    vm.expectRevert("position is not tracked");
    fund.execTransaction(cl.gauge, _gaugeCalldata(IVelodromeCLGauge.deposit.selector, FOREIGN_TOKEN_ID));
  }

  /// @dev Emissions would land in the vault unpriced, so the guard refuses before looking at the
  /// position at all.
  function test_revert_stake_when_the_reward_token_is_not_supported() public {
    _removeSupportedAsset(cl.protocolToken);

    vm.prank(manager);
    vm.expectRevert("unsupported asset: rewardToken");
    fund.execTransaction(cl.gauge, _gaugeCalldata(IVelodromeCLGauge.deposit.selector, FOREIGN_TOKEN_ID));
  }

  function test_revert_stake_when_a_position_underlying_is_not_supported() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    _removeSupportedAsset(cl.token1);

    vm.prank(manager);
    vm.expectRevert("unsupported asset: tokenB");
    fund.execTransaction(cl.gauge, _gaugeCalldata(IVelodromeCLGauge.deposit.selector, tokenId));
  }

  function test_manager_can_stake_a_position() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _stake(tokenId);

    assertEq(nftManager.ownerOf(tokenId), cl.gauge);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  /* ========== UNSTAKING ========== */

  function test_revert_unstake_an_untracked_position() public {
    _enableNftPosition();

    vm.prank(manager);
    vm.expectRevert("position is not tracked");
    fund.execTransaction(cl.gauge, _gaugeCalldata(IVelodromeCLGauge.withdraw.selector, FOREIGN_TOKEN_ID));
  }

  function test_manager_can_unstake_a_position() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _stake(tokenId);

    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _managerExec(cl.gauge, _gaugeCalldata(IVelodromeCLGauge.withdraw.selector, tokenId));

    assertEq(nftManager.ownerOf(tokenId), address(fund));
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  /* ========== REWARDS ========== */

  function test_revert_claiming_rewards_for_an_untracked_position() public {
    _enableNftPosition();

    vm.prank(manager);
    vm.expectRevert("position is not tracked");
    fund.execTransaction(cl.gauge, _gaugeCalldata(GET_REWARD_SELECTOR, FOREIGN_TOKEN_ID));
  }

  function test_claiming_rewards_pays_the_vault_in_the_protocol_token() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _stake(tokenId);
    skip(7 days);

    assertGt(IVelodromeCLGauge(cl.gauge).earned(address(fund), tokenId), 0, "position earned nothing");
    uint256 rewardBefore = IERC20(cl.protocolToken).balanceOf(address(fund));

    _managerExec(cl.gauge, _gaugeCalldata(GET_REWARD_SELECTOR, tokenId));

    assertGt(IERC20(cl.protocolToken).balanceOf(address(fund)), rewardBefore);
    assertEq(IVelodromeCLGauge(cl.gauge).earned(address(fund), tokenId), 0);
  }

  /// @dev Unclaimed emissions belong to the vault, so they must be priced before anyone claims
  /// them - otherwise a withdrawal right before a claim would short-change the withdrawer.
  function test_unclaimed_emissions_are_counted_in_vault_value() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _stake(tokenId);

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    skip(7 days);

    assertGt(IVelodromeCLGauge(cl.gauge).earned(address(fund), tokenId), 0, "position earned nothing");
    assertGt(fundManagerLogic.totalFundValue(), valueBefore);
  }

  /* ========== UNSUPPORTED GAUGE METHODS ========== */

  function test_revert_increaseStakedLiquidity() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _stake(tokenId);

    (, , , , , , , uint128 liquidityBefore, , , , ) = nftManager.positions(tokenId);

    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    fund.execTransaction(
      cl.gauge,
      abi.encodeWithSelector(
        IVelodromeCLGauge.increaseStakedLiquidity.selector,
        tokenId,
        cl.amount0,
        cl.amount1,
        0,
        0,
        DEADLINE
      )
    );

    (, , , , , , , uint128 liquidityAfter, , , , ) = nftManager.positions(tokenId);
    assertEq(uint256(liquidityAfter), uint256(liquidityBefore));
  }

  function test_revert_decreaseStakedLiquidity() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _stake(tokenId);

    (, , , , , , , uint128 liquidityBefore, , , , ) = nftManager.positions(tokenId);

    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    fund.execTransaction(
      cl.gauge,
      abi.encodeWithSelector(
        IVelodromeCLGauge.decreaseStakedLiquidity.selector,
        tokenId,
        liquidityBefore,
        0,
        0,
        DEADLINE
      )
    );

    (, , , , , , , uint128 liquidityAfter, , , , ) = nftManager.positions(tokenId);
    assertEq(uint256(liquidityAfter), uint256(liquidityBefore));
  }

  /* ========== REWARD ASSET LINKAGE ========== */

  /// @dev Dropping the reward token while a position can still earn it would strand the emissions.
  function test_revert_removing_the_reward_asset_while_positions_are_supported() public {
    _enableNftPosition();

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = cl.protocolToken;

    vm.prank(manager);
    vm.expectRevert("remove linked asset first");
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);
  }

  /* ========== HELPERS ========== */

  function _gaugeCalldata(bytes4 _selector, uint256 _tokenId) internal pure returns (bytes memory data) {
    data = abi.encodeWithSelector(_selector, _tokenId);
  }

  /// @dev The gauge collects fees as itself while taking custody, so it needs the position approved
  /// first. The position guard does not handle `approve`, so it falls through to the ERC20 approve
  /// path on the CL asset guard, which only permits spenders that have a contract guard.
}
