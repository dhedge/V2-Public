// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {IVelodromeNonfungiblePositionManager} from "contracts/interfaces/velodrome/IVelodromeNonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {VelodromeCLTestSetup} from "test/integration/common/velodromeCL/VelodromeCLTestSetup.t.sol";

/// @notice `VelodromeCLAssetGuard` is what lets a vault hold CL positions: it values every tracked
/// position and unwinds the withdrawer's share of each on exit. Both feed the total fund value that deposits and withdrawals price off.
abstract contract VelodromeCLAssetGuardTestSetup is VelodromeCLTestSetup {
  /// @dev Live pool ratios drift against the Chainlink feeds, so equality here is approximate.
  uint256 internal constant VALUATION_TOLERANCE = 0.04e18; // 4%

  /* ========== VALUATION ========== */

  function test_the_position_asset_reports_eighteen_decimals() public view {
    assertEq(clAssetGuard.getDecimals(cl.nonfungiblePositionManager), 18);
  }

  function test_a_vault_with_no_positions_values_them_at_zero() public {
    _enableNftPosition();

    assertEq(clAssetGuard.getBalance(address(fund), cl.nonfungiblePositionManager), 0);
  }

  function test_position_value_replaces_the_underlyings_it_consumed() public {
    _enableNftPosition();
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _mintAsPool(1);

    assertGt(clAssetGuard.getBalance(address(fund), cl.nonfungiblePositionManager), 0);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  function test_the_position_asset_values_every_tracked_position() public {
    _enableNftPosition();

    _mintAsPool(1);
    uint256 oneValue = clAssetGuard.getBalance(address(fund), cl.nonfungiblePositionManager);

    _mintAsPool(2);
    uint256 twoValue = clAssetGuard.getBalance(address(fund), cl.nonfungiblePositionManager);

    assertEq(_trackedTokenIds().length, 2);
    assertGt(twoValue, oneValue);
  }

  /* ========== POSITION LIFECYCLE ========== */

  /// @dev Burning frees a tracker slot, so a vault at the limit can rotate positions rather than
  /// being stuck with them.
  function test_a_position_can_be_minted_again_after_burning_at_the_limit() public {
    _enableNftPosition();

    uint256 firstTokenId = _mintAsPool(1);
    for (uint256 i = 2; i <= MAX_POSITIONS; ++i) {
      _mintAsPool(i);
    }
    assertEq(_trackedTokenIds().length, MAX_POSITIONS);

    _burn(firstTokenId);
    assertEq(_trackedTokenIds().length, MAX_POSITIONS - 1);

    uint256 replacementTokenId = _mintAsPool(MAX_POSITIONS + 1);

    assertEq(_trackedTokenIds().length, MAX_POSITIONS);
    assertEq(nftManager.ownerOf(replacementTokenId), address(fund));
  }

  /* ========== WITHDRAW PROCESSING ========== */

  function test_withdrawing_half_unwinds_half_of_a_position() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    (, , , , , , , uint128 liquidityBefore, , , , ) = nftManager.positions(tokenId);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _withdrawHalf();

    (, , , , , , , uint128 liquidityAfter, , , , ) = nftManager.positions(tokenId);
    assertApproxEqRel(uint256(liquidityAfter), uint256(liquidityBefore) / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore / 2, VALUATION_TOLERANCE);
  }

  function test_the_withdrawer_receives_the_underlyings_of_their_share() public {
    _enableNftPosition();
    _mintAsPool(1);

    uint256 token0Before = IERC20(cl.token0).balanceOf(investor);
    uint256 token1Before = IERC20(cl.token1).balanceOf(investor);

    _withdrawHalf();

    assertGt(IERC20(cl.token0).balanceOf(investor), token0Before);
    assertGt(IERC20(cl.token1).balanceOf(investor), token1Before);
  }

  function test_withdrawing_unwinds_every_position_together() public {
    _enableNftPosition();
    uint256 firstTokenId = _mintAsPool(1);
    uint256 secondTokenId = _mintAsPool(2);

    (, , , , , , , uint128 firstBefore, , , , ) = nftManager.positions(firstTokenId);
    (, , , , , , , uint128 secondBefore, , , , ) = nftManager.positions(secondTokenId);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _withdrawHalf();

    (, , , , , , , uint128 firstAfter, , , , ) = nftManager.positions(firstTokenId);
    (, , , , , , , uint128 secondAfter, , , , ) = nftManager.positions(secondTokenId);
    assertApproxEqRel(uint256(firstAfter), uint256(firstBefore) / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(uint256(secondAfter), uint256(secondBefore) / 2, VALUATION_TOLERANCE);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore / 2, VALUATION_TOLERANCE);
  }

  /// @dev The last holder out takes everything, so nothing is left stranded in the position.
  function test_a_full_exit_empties_every_position() public {
    _enableNftPosition();
    uint256 firstTokenId = _mintAsPool(1);
    uint256 secondTokenId = _mintAsPool(2);

    uint256 shares = fund.balanceOf(investor);

    vm.prank(investor);
    fund.withdraw(shares);

    (, , , , , , , uint128 firstAfter, , , , ) = nftManager.positions(firstTokenId);
    (, , , , , , , uint128 secondAfter, , , , ) = nftManager.positions(secondTokenId);
    assertEq(uint256(firstAfter), 0);
    assertEq(uint256(secondAfter), 0);
    assertApproxEqAbs(fundManagerLogic.totalFundValue(), 0, 1e15);
  }

  /* ========== HELPERS ========== */

  function _burn(uint256 _tokenId) internal {
    (, , , , , , , uint128 liquidity, , , , ) = nftManager.positions(_tokenId);

    bytes[] memory calls = new bytes[](3);
    calls[0] = abi.encodeWithSelector(
      IVelodromeNonfungiblePositionManager.decreaseLiquidity.selector,
      IVelodromeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: _tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: DEADLINE
      })
    );
    calls[1] = abi.encodeWithSelector(
      IVelodromeNonfungiblePositionManager.collect.selector,
      IVelodromeNonfungiblePositionManager.CollectParams({
        tokenId: _tokenId,
        recipient: address(fund),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    calls[2] = abi.encodeWithSelector(IVelodromeNonfungiblePositionManager.burn.selector, _tokenId);

    _managerExec(cl.nonfungiblePositionManager, abi.encodeWithSelector(IMulticall.multicall.selector, calls));
  }
}
