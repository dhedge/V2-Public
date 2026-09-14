// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {IVelodromeNonfungiblePositionManager} from "contracts/interfaces/velodrome/IVelodromeNonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {VelodromeCLTestSetup} from "test/integration/common/velodromeCL/VelodromeCLTestSetup.t.sol";

/// @notice `VelodromeNonfungiblePositionGuard` decides which concentrated liquidity positions a
/// vault may open and how it may manage them: only between assets the vault supports, only into
/// the vault itself, and only up to the tracked position limit.
abstract contract VelodromeCLPositionGuardTestSetup is VelodromeCLTestSetup {
  /* ========== MINT VALIDATION ========== */

  function test_revert_mint_when_the_position_asset_is_not_enabled() public {
    (int24 lower, int24 upper) = _tickRange(1);

    vm.prank(manager);
    vm.expectRevert("velodrome cl asset not enabled");
    fund.execTransaction(
      cl.nonfungiblePositionManager,
      _mintCalldata(cl.token0, cl.token1, lower, upper, address(fund))
    );
  }

  function test_revert_mint_with_an_unsupported_token() public {
    _enableNftPosition();
    (int24 lower, int24 upper) = _tickRange(1);

    // The guard rejects by name before touching any pool, so these stand-ins never have to be real
    // tokens - only to sort either side of token1, so that each of the two branches is reached.
    // A deployed mock cannot do that: its address is wherever it lands.
    address sortsBelow = address(uint160(1));
    address sortsAbove = address(type(uint160).max);
    assertTrue(sortsBelow < cl.token1 && cl.token1 < sortsAbove, "stand-ins do not bracket token1");

    vm.startPrank(manager);
    vm.expectRevert("unsupported asset: tokenA");
    fund.execTransaction(
      cl.nonfungiblePositionManager,
      _mintCalldata(sortsBelow, cl.token1, lower, upper, address(fund))
    );

    vm.expectRevert("unsupported asset: tokenB");
    fund.execTransaction(
      cl.nonfungiblePositionManager,
      _mintCalldata(cl.token1, sortsAbove, lower, upper, address(fund))
    );
    vm.stopPrank();
  }

  function test_revert_mint_to_a_recipient_other_than_the_vault() public {
    _enableNftPosition();
    (int24 lower, int24 upper) = _tickRange(1);

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    fund.execTransaction(cl.nonfungiblePositionManager, _mintCalldata(cl.token0, cl.token1, lower, upper, manager));
  }

  function test_revert_mint_beyond_the_position_limit() public {
    _enableNftPosition();

    for (uint256 i = 1; i <= MAX_POSITIONS; ++i) {
      _mintAsPool(i);
    }

    (int24 lower, int24 upper) = _tickRange(MAX_POSITIONS + 1);
    vm.prank(manager);
    vm.expectRevert("max position reached");
    fund.execTransaction(
      cl.nonfungiblePositionManager,
      _mintCalldata(cl.token0, cl.token1, lower, upper, address(fund))
    );
  }

  function test_minting_a_position_preserves_vault_value() public {
    _enableNftPosition();
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _mintAsPool(1);

    assertEq(nftManager.balanceOf(address(fund)), 1);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  /* ========== POSITION MANAGEMENT ========== */

  function test_revert_increasing_liquidity_on_an_untracked_position() public {
    _enableNftPosition();
    _mintAsPool(1);

    uint256 foreignTokenId = _mintAsOutsider();
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    vm.prank(manager);
    vm.expectRevert("position is not in track");
    fund.execTransaction(cl.nonfungiblePositionManager, _increaseCalldata(foreignTokenId));

    assertEq(fundManagerLogic.totalFundValue(), valueBefore);
  }

  function test_manager_can_increase_liquidity() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    (, , , , , , , uint128 liquidityBefore, , , , ) = nftManager.positions(tokenId);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    _managerExec(cl.nonfungiblePositionManager, _increaseCalldata(tokenId));

    (, , , , , , , uint128 liquidityAfter, , , , ) = nftManager.positions(tokenId);
    assertGt(uint256(liquidityAfter), uint256(liquidityBefore));
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
  }

  function test_decreasing_liquidity_to_zero_preserves_value_and_price() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 priceBefore = fund.tokenPrice();

    _decreaseAllLiquidity(tokenId);

    (, , , , , , , uint128 liquidity, , , , ) = nftManager.positions(tokenId);
    assertEq(uint256(liquidity), 0);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.01e18);
    assertApproxEqRel(fund.tokenPrice(), priceBefore, 0.01e18);
  }

  /// @dev The guard reads the position's own tokens on collect, so dropping either underlying has
  /// to stop the collect rather than let fees land in an asset the vault can no longer price.
  function test_revert_collect_after_disabling_an_underlying() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    // An asset can only be dropped once the vault holds none of it loose.
    deal(cl.token0, address(fund), 0);
    deal(cl.token1, address(fund), 0);

    vm.startPrank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(cl.token1));

    vm.expectRevert("unsupported asset: tokenB");
    fund.execTransaction(cl.nonfungiblePositionManager, _collectCalldata(tokenId, address(fund)));

    // Put token1 back and drop token0 instead, to reach the other branch. token1 goes back as a
    // deposit asset because a vault must keep at least one.
    fundManagerLogic.changeAssets(_toSupportedAssets(cl.token1, true), _toArray(cl.token0));

    vm.expectRevert("unsupported asset: tokenA");
    fund.execTransaction(cl.nonfungiblePositionManager, _collectCalldata(tokenId, address(fund)));
    vm.stopPrank();
  }

  function test_revert_collecting_to_a_recipient_other_than_the_vault() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    fund.execTransaction(cl.nonfungiblePositionManager, _collectCalldata(tokenId, manager));
  }

  function test_manager_can_collect_after_decreasing() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _decreaseAllLiquidity(tokenId);

    uint256 token0Before = IERC20(cl.token0).balanceOf(address(fund));
    uint256 token1Before = IERC20(cl.token1).balanceOf(address(fund));

    _managerExec(cl.nonfungiblePositionManager, _collectCalldata(tokenId, address(fund)));

    assertTrue(
      IERC20(cl.token0).balanceOf(address(fund)) > token0Before ||
        IERC20(cl.token1).balanceOf(address(fund)) > token1Before
    );
  }

  function test_manager_can_burn_an_emptied_position() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _decreaseAllLiquidity(tokenId);
    _managerExec(cl.nonfungiblePositionManager, _collectCalldata(tokenId, address(fund)));

    _managerExec(
      cl.nonfungiblePositionManager,
      abi.encodeWithSelector(IVelodromeNonfungiblePositionManager.burn.selector, tokenId)
    );

    assertEq(nftManager.balanceOf(address(fund)), 0);
  }

  /* ========== MULTICALL ========== */

  function test_manager_can_unwind_a_position_in_one_multicall() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    bytes[] memory calls = new bytes[](3);
    calls[0] = _decreaseAllCalldata(tokenId);
    calls[1] = _collectCalldata(tokenId, address(fund));
    calls[2] = abi.encodeWithSelector(IVelodromeNonfungiblePositionManager.burn.selector, tokenId);

    _managerExec(cl.nonfungiblePositionManager, abi.encodeWithSelector(IMulticall.multicall.selector, calls));

    assertEq(nftManager.balanceOf(address(fund)), 0);
    assertEq(_trackedTokenIds().length, 0);
  }

  function test_revert_multicall_containing_a_disallowed_call() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    bytes[] memory calls = new bytes[](2);
    calls[0] = _decreaseAllCalldata(tokenId);
    calls[1] = abi.encodeWithSelector(IERC20.approve.selector, manager, 1);

    vm.prank(manager);
    vm.expectRevert("invalid transaction");
    fund.execTransaction(cl.nonfungiblePositionManager, abi.encodeWithSelector(IMulticall.multicall.selector, calls));
  }

  /// @dev The tracker identifies a freshly minted position by the manager's `totalSupply`, so it can
  /// only account for one position appearing or disappearing per batch.
  function test_revert_multicall_that_mints_twice() public {
    _enableNftPosition();
    _mintAsPool(1); // also leaves the manager approved to pull both tokens

    (int24 lowerA, int24 upperA) = _tickRange(2);
    (int24 lowerB, int24 upperB) = _tickRange(3);

    bytes[] memory calls = new bytes[](2);
    calls[0] = _mintCalldata(cl.token0, cl.token1, lowerA, upperA, address(fund));
    calls[1] = _mintCalldata(cl.token0, cl.token1, lowerB, upperB, address(fund));

    vm.prank(manager);
    vm.expectRevert("invalid multicall");
    fund.execTransaction(cl.nonfungiblePositionManager, abi.encodeWithSelector(IMulticall.multicall.selector, calls));
  }

  /* ========== NFT TRACKER ========== */

  function test_nft_tracker_follows_mint_and_burn() public {
    _enableNftPosition();
    assertEq(_trackedTokenIds().length, 0);

    uint256 tokenId = _mintAsPool(1);
    uint256[] memory tracked = _trackedTokenIds();
    assertEq(tracked.length, 1);
    assertEq(tracked[0], tokenId);

    bytes[] memory calls = new bytes[](3);
    calls[0] = _decreaseAllCalldata(tokenId);
    calls[1] = _collectCalldata(tokenId, address(fund));
    calls[2] = abi.encodeWithSelector(IVelodromeNonfungiblePositionManager.burn.selector, tokenId);
    _managerExec(cl.nonfungiblePositionManager, abi.encodeWithSelector(IMulticall.multicall.selector, calls));

    assertEq(_trackedTokenIds().length, 0);
  }

  /* ========== DEPOSIT REJECTION ========== */

  function test_revert_depositing_a_position_nft_into_the_vault() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsOutsider();

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: cl.nonfungiblePositionManager, isDeposit: true});

    vm.startPrank(manager);
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
    nftManager.approve(address(fund), tokenId);

    vm.expectRevert(bytes("dh9"));
    fund.deposit(cl.nonfungiblePositionManager, tokenId);
    vm.stopPrank();
  }

  /* ========== HELPERS ========== */

  /// @dev A position held outside the vault, used for the untracked and deposit cases.
  function _mintAsOutsider() internal returns (uint256 tokenId) {
    (int24 lower, int24 upper) = _tickRange(2);

    deal(cl.token0, manager, cl.amount0);
    deal(cl.token1, manager, cl.amount1);

    vm.startPrank(manager);
    IERC20(cl.token0).approve(cl.nonfungiblePositionManager, cl.amount0);
    IERC20(cl.token1).approve(cl.nonfungiblePositionManager, cl.amount1);
    (tokenId, , , ) = nftManager.mint(
      IVelodromeNonfungiblePositionManager.MintParams({
        token0: cl.token0,
        token1: cl.token1,
        tickSpacing: cl.tickSpacing,
        tickLower: lower,
        tickUpper: upper,
        amount0Desired: cl.amount0,
        amount1Desired: cl.amount1,
        amount0Min: 0,
        amount1Min: 0,
        recipient: manager,
        deadline: DEADLINE,
        sqrtPriceX96: 0
      })
    );
    vm.stopPrank();
  }

  function _increaseCalldata(uint256 _tokenId) internal view returns (bytes memory data) {
    data = abi.encodeWithSelector(
      IVelodromeNonfungiblePositionManager.increaseLiquidity.selector,
      IVelodromeNonfungiblePositionManager.IncreaseLiquidityParams({
        tokenId: _tokenId,
        amount0Desired: cl.amount0,
        amount1Desired: cl.amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: DEADLINE
      })
    );
  }

  function _decreaseAllCalldata(uint256 _tokenId) internal view returns (bytes memory data) {
    (, , , , , , , uint128 liquidity, , , , ) = nftManager.positions(_tokenId);
    data = abi.encodeWithSelector(
      IVelodromeNonfungiblePositionManager.decreaseLiquidity.selector,
      IVelodromeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: _tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: DEADLINE
      })
    );
  }

  function _decreaseAllLiquidity(uint256 _tokenId) internal {
    bytes memory data = _decreaseAllCalldata(_tokenId);
    _managerExec(cl.nonfungiblePositionManager, data);
  }

  function _collectCalldata(uint256 _tokenId, address _recipient) internal pure returns (bytes memory data) {
    data = abi.encodeWithSelector(
      IVelodromeNonfungiblePositionManager.collect.selector,
      IVelodromeNonfungiblePositionManager.CollectParams({
        tokenId: _tokenId,
        recipient: _recipient,
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
  }
}
