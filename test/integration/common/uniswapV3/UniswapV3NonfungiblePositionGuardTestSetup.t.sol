// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {UniswapV3NonfungiblePositionGuard} from "contracts/guards/contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol";
import {UniswapV3AssetGuard} from "contracts/guards/assetGuards/UniswapV3AssetGuard.sol";
import {ERC20Asset} from "contracts/test/TestAssets.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {SingleFundTestSetup} from "test/integration/utils/foundry/SingleFundTestSetup.t.sol";

/// @notice UniswapV3NonfungiblePositionGuard flows: mint validation, increase/decrease/collect/burn,
/// multicall enforcement, the 3-position cap, nft-tracker bookkeeping, and rejecting NFT deposits.
/// Uses a live WETH/USDC pool; token0/token1 ordering is resolved from the pool at setUp.
abstract contract UniswapV3NonfungiblePositionGuardTestSetup is SingleFundTestSetup {
  uint256 private constant DEADLINE = type(uint256).max;

  address internal immutable nftManagerAddr;
  address internal immutable factoryAddr;
  uint24 internal immutable poolFee;

  INonfungiblePositionManager private nftManager;

  UniswapV3NonfungiblePositionGuard private positionGuard;

  // Pool token ordering (token0 < token1), resolved from the live pool.
  address internal token0;
  address internal token1;
  uint256 internal amount0; // in token0 units
  uint256 internal amount1; // in token1 units
  ERC20Asset internal unpricedSupportedAsset; // supported asset with no Uniswap pool
  ERC20Asset internal unsupportedToken; // never added to the fund's supported assets

  constructor(address _nftManager, address _factory, uint24 _poolFee) {
    nftManagerAddr = _nftManager;
    factoryAddr = _factory;
    poolFee = _poolFee;
  }

  function setUp() public virtual override {
    super.setUp();

    nftManager = INonfungiblePositionManager(nftManagerAddr);

    // Resolve pool token ordering so amount0/amount1 line up with token0/token1.
    address pool = IUniswapV3Factory(factoryAddr).getPool(wethData.asset, usdcData.asset, poolFee);
    require(pool != address(0), "weth/usdc pool missing on fork");
    token0 = IUniswapV3Pool(pool).token0();
    token1 = IUniswapV3Pool(pool).token1();
    (amount0, amount1) = token0 == wethData.asset
      ? (uint256(1e18), uint256(2_000e6))
      : (uint256(2_000e6), uint256(1e18));

    vm.startPrank(owner);
    positionGuard = new UniswapV3NonfungiblePositionGuard(3, address(nftTrackerStorageProxy));
    governance.setContractGuard({extContract: nftManagerAddr, guardAddress: address(positionGuard)});
    governance.setAssetGuard({
      assetType: uint16(AssetTypeIncomplete.UNISWAP_V3),
      guardAddress: address(new UniswapV3AssetGuard())
    });

    // A supported asset with a real Chainlink aggregator but no Uniswap pool, for the
    // "no liquidity pool" mint revert.
    unpricedSupportedAsset = new ERC20Asset("Test", "TST");
    unsupportedToken = new ERC20Asset("Unsupported", "UNS");
    IAssetHandler.Asset[] memory assetsToAdd = new IAssetHandler.Asset[](2);
    assetsToAdd[0] = IAssetHandler.Asset({
      asset: nftManagerAddr,
      assetType: uint16(AssetTypeIncomplete.UNISWAP_V3),
      aggregator: address(usdPriceAggregator)
    });
    assetsToAdd[1] = IAssetHandler.Asset({
      asset: address(unpricedSupportedAsset),
      assetType: uint16(AssetTypeIncomplete.CHAINLINK),
      aggregator: assetHandlerProxy.priceAggregators(usdcData.asset)
    });
    assetHandlerProxy.addAssets(assetsToAdd);
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: address(unpricedSupportedAsset), isDeposit: true});

    vm.prank(manager);
    fund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "UniswapV3NFTGuardTest",
        _fundSymbol: "U3G",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    // Generous funding so the 4th mint in the position-cap test can execute (and then be
    // rejected by the tracker) rather than running out of tokens first.
    _makeDeposit(fund, investor, wethData.asset, 10e18);
    _makeDeposit(fund, investor, usdcData.asset, 20_000e6);
  }

  /* ========== MINT VALIDATION ========== */

  function test_revert_mint_when_nft_position_not_enabled() public {
    (int24 lower, int24 upper) = _tickRange(1);
    vm.prank(manager);
    vm.expectRevert("uniswap asset not enabled");
    fund.execTransaction(nftManagerAddr, _mintCalldata(token0, token1, lower, upper, amount0, amount1));
  }

  function test_revert_mint_when_unsupported_assets() public {
    _enableNftPosition();
    (int24 lower, int24 upper) = _tickRange(1);

    // The guard rejects by name before touching any pool, so these stand-ins never have to be real
    // tokens - only to sort either side of USDC, so that each of the two branches is reached.
    // A deployed mock cannot do that: its address is wherever it lands.
    address sortsBelowUsdc = address(uint160(1));
    address sortsAboveUsdc = address(type(uint160).max);
    assertTrue(sortsBelowUsdc < usdcData.asset && usdcData.asset < sortsAboveUsdc, "stand-ins do not bracket USDC");

    vm.startPrank(manager);
    vm.expectRevert("unsupported asset: tokenA");
    fund.execTransaction(nftManagerAddr, _mintCalldata(sortsBelowUsdc, usdcData.asset, lower, upper, 1e18, 1e6));

    vm.expectRevert("unsupported asset: tokenB");
    fund.execTransaction(nftManagerAddr, _mintCalldata(usdcData.asset, sortsAboveUsdc, lower, upper, 1e6, 1e18));
    vm.stopPrank();
  }

  function test_revert_mint_when_invalid_receiver() public {
    _enableNftPosition();
    (int24 lower, int24 upper) = _tickRange(1);

    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
      token0: token0,
      token1: token1,
      fee: poolFee,
      tickLower: lower,
      tickUpper: upper,
      amount0Desired: amount0,
      amount1Desired: amount1,
      amount0Min: 0,
      amount1Min: 0,
      recipient: address(fundManagerLogic), // not the pool
      deadline: DEADLINE
    });

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    fund.execTransaction(nftManagerAddr, abi.encodeWithSelector(INonfungiblePositionManager.mint.selector, params));
  }

  function test_revert_mint_when_pool_has_no_liquidity() public {
    _enableNftPosition();

    // A supported token with no Uniswap pool against USDC.
    (address t0, address t1) = address(unpricedSupportedAsset) < usdcData.asset
      ? (address(unpricedSupportedAsset), usdcData.asset)
      : (usdcData.asset, address(unpricedSupportedAsset));

    vm.prank(manager);
    vm.expectRevert();
    fund.execTransaction(nftManagerAddr, _mintCalldata(t0, t1, int24(0), int24(60), 1e18, 1e6));
  }

  function test_revert_mint_when_position_count_exceeds_three() public {
    _enableNftPosition();

    // Three mints via the approve+mint batch (approvals set to max, so they persist for the 4th).
    for (uint256 i = 1; i <= 3; ++i) {
      _mintAsPool(i);
    }

    (int24 lower4, int24 upper4) = _tickRange(4);
    vm.prank(manager);
    vm.expectRevert("max position reached");
    fund.execTransaction(nftManagerAddr, _mintCalldata(token0, token1, lower4, upper4, amount0, amount1));
  }

  function test_mint_position_preserves_fund_value() public {
    _enableNftPosition();

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    _mintAsPool(1);

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.00001e18);
    assertEq(nftManager.balanceOf(address(fund)), 1);
  }

  /* ========== INCREASE / DECREASE / COLLECT / BURN ========== */

  function test_revert_increaseLiquidity_on_untracked_tokenId() public {
    _enableNftPosition();
    _mintAsPool(1);

    // Manager mints a personal position outside the fund.
    uint256 managerTokenId = _mintAsExternal(manager, 2);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    vm.prank(manager);
    vm.expectRevert("position is not in track");
    fund.execTransaction(nftManagerAddr, _increaseCalldata(managerTokenId));

    assertEq(fundManagerLogic.totalFundValue(), valueBefore);
  }

  function test_increaseLiquidity_on_tracked_position() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    (, , , , , , , uint128 liqBefore, , , , ) = nftManager.positions(tokenId);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    vm.prank(manager);
    fund.execTransaction(nftManagerAddr, _increaseCalldata(tokenId));

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.00001e18);
    (, , , , , , , uint128 liqAfter, , , , ) = nftManager.positions(tokenId);
    assertGt(uint256(liqAfter), uint256(liqBefore));
  }

  function test_decreaseLiquidity_to_zero_preserves_value_and_price() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 priceBefore = fund.tokenPrice();

    _decreaseAllLiquidity(tokenId);

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.00001e18);
    assertApproxEqRel(fund.tokenPrice(), priceBefore, 0.00001e18);
    (, , , , , , , uint128 liq, , , , ) = nftManager.positions(tokenId);
    assertEq(uint256(liq), 0);
  }

  function test_revert_collect_when_invalid_receiver() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    fund.execTransaction(nftManagerAddr, _collectCalldata(tokenId, address(fundManagerLogic)));
  }

  function test_collect_after_decrease() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _decreaseAllLiquidity(tokenId);

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 poolToken0Before = IERC20(token0).balanceOf(address(fund));
    uint256 poolToken1Before = IERC20(token1).balanceOf(address(fund));

    vm.prank(manager);
    fund.execTransaction(nftManagerAddr, _collectCalldata(tokenId, address(fund)));

    assertTrue(
      IERC20(token0).balanceOf(address(fund)) > poolToken0Before ||
        IERC20(token1).balanceOf(address(fund)) > poolToken1Before
    );
    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.00001e18);
  }

  function test_revert_collect_after_disabling_asset() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    // Zero the pool's loose token balances so removal is allowed, then disable token1.
    deal(token0, address(fund), 0);
    deal(token1, address(fund), 0);

    vm.startPrank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(token1));

    vm.expectRevert("unsupported asset: tokenB");
    fund.execTransaction(nftManagerAddr, _collectCalldata(tokenId, address(fund)));

    fundManagerLogic.changeAssets(_toSupportedAssets(token1, false), _toArray(token0));
    vm.expectRevert("unsupported asset: tokenA");
    fund.execTransaction(nftManagerAddr, _collectCalldata(tokenId, address(fund)));
    vm.stopPrank();
  }

  function test_burn_position() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _decreaseAllLiquidity(tokenId);

    vm.startPrank(manager);
    fund.execTransaction(nftManagerAddr, _collectCalldata(tokenId, address(fund)));

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    fund.execTransaction(nftManagerAddr, abi.encodeWithSelector(INonfungiblePositionManager.burn.selector, tokenId));
    vm.stopPrank();

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.00001e18);
    assertEq(nftManager.balanceOf(address(fund)), 0);
  }

  /* ========== WITHDRAWALS ========== */

  /// @dev Decreasing to zero without collecting leaves the tokens owed on the position rather than
  /// in the vault, so a withdrawal only pays out correctly if the asset guard collects them. The
  /// vault also holds loose token0/token1, so assert the position itself was drained rather than
  /// just that some tokens arrived.
  function test_withdraw_collects_owed_tokens_after_decreaseLiquidity_to_zero() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    _decreaseAllLiquidity(tokenId);

    (, , , , , , , uint128 liquidity, , , uint128 owed0, uint128 owed1) = nftManager.positions(tokenId);
    assertEq(uint256(liquidity), 0, "liquidity should be zero");
    assertTrue(owed0 > 0 && owed1 > 0, "position should owe both tokens");

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 token0Before = IERC20(token0).balanceOf(investor);
    uint256 token1Before = IERC20(token1).balanceOf(investor);

    skip(1 days + 1);
    uint256 shares = fund.balanceOf(investor);
    vm.prank(investor);
    fund.withdraw(shares);

    assertEq(fund.balanceOf(investor), 0);
    (, , , , , , , , , , uint128 owed0After, uint128 owed1After) = nftManager.positions(tokenId);
    assertEq(uint256(owed0After), 0, "owed token0 was not collected");
    assertEq(uint256(owed1After), 0, "owed token1 was not collected");
    assertApproxEqRel(_investorPayoutValue(token0Before, token1Before), valueBefore, 0.00001e18);
  }

  /// @dev With half the position decreased, its value sits partly in remaining liquidity and partly
  /// in owed tokens. A withdrawal has to unroll both, so pay out on a half withdrawal and then on
  /// the rest.
  function test_partial_then_full_withdraw_unrolls_liquidity_and_owed_tokens() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    (, , , , , , , uint128 liquidity, , , , ) = nftManager.positions(tokenId);
    bytes memory decreaseHalf = _decreaseCalldata(tokenId, liquidity / 2);
    vm.prank(manager);
    fund.execTransaction(nftManagerAddr, decreaseHalf);

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    (, , , , , , , uint128 liquidityLeft, , , uint128 owed0, uint128 owed1) = nftManager.positions(tokenId);
    assertGt(uint256(liquidityLeft), 0, "position should keep liquidity");
    assertTrue(owed0 > 0 && owed1 > 0, "position should also owe tokens");

    skip(1 days + 1);
    uint256 sharesBefore = fund.balanceOf(investor);
    uint256 token0Before = IERC20(token0).balanceOf(investor);
    uint256 token1Before = IERC20(token1).balanceOf(investor);

    vm.prank(investor);
    fund.withdraw(sharesBefore / 2);

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore / 2, 0.00001e18);
    assertApproxEqRel(_investorPayoutValue(token0Before, token1Before), valueBefore / 2, 0.00001e18);

    // Hoisted so the balance staticcall doesn't consume the prank.
    uint256 sharesLeft = fund.balanceOf(investor);
    vm.prank(investor);
    fund.withdraw(sharesLeft);

    assertEq(fund.balanceOf(investor), 0);
    assertApproxEqRel(_investorPayoutValue(token0Before, token1Before), valueBefore, 0.00001e18);
  }

  /* ========== MULTICALL ========== */

  function test_revert_multicall_with_disallowed_inner_call() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    bytes[] memory calls = new bytes[](3);
    calls[0] = _decreaseAllCalldataInner(tokenId);
    calls[1] = abi.encodeWithSelector(IERC20.approve.selector, nftManagerAddr, 1e6); // not a position-manager method
    calls[2] = abi.encodeWithSelector(INonfungiblePositionManager.burn.selector, tokenId);

    vm.prank(manager);
    vm.expectRevert("invalid transaction");
    fund.execTransaction(nftManagerAddr, abi.encodeWithSelector(IMulticall.multicall.selector, calls));
  }

  function test_multicall_decrease_collect_burn() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    bytes[] memory calls = new bytes[](3);
    calls[0] = _decreaseAllCalldataInner(tokenId);
    calls[1] = _collectCalldata(tokenId, address(fund));
    calls[2] = abi.encodeWithSelector(INonfungiblePositionManager.burn.selector, tokenId);

    uint256 valueBefore = fundManagerLogic.totalFundValue();

    vm.prank(manager);
    fund.execTransaction(nftManagerAddr, abi.encodeWithSelector(IMulticall.multicall.selector, calls));

    assertApproxEqRel(fundManagerLogic.totalFundValue(), valueBefore, 0.00001e18);
    assertEq(nftManager.balanceOf(address(fund)), 0);
  }

  function test_revert_multicall_mint_and_burn_in_one_tx() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);

    (int24 lower, int24 upper) = _tickRange(1);
    bytes[] memory calls = new bytes[](4);
    calls[0] = _mintCalldata(token0, token1, lower, upper, amount0, amount1);
    calls[1] = _decreaseAllCalldataInner(tokenId);
    calls[2] = _collectCalldata(tokenId, address(fund));
    calls[3] = abi.encodeWithSelector(INonfungiblePositionManager.burn.selector, tokenId);

    vm.prank(manager);
    vm.expectRevert("invalid multicall");
    fund.execTransaction(nftManagerAddr, abi.encodeWithSelector(IMulticall.multicall.selector, calls));
  }

  /* ========== NFT TRACKER ========== */

  function test_nft_tracker_updated_on_mint() public {
    _enableNftPosition();

    assertEq(_trackedTokenIds().length, 0);
    uint256 tokenId = _mintAsPool(1);

    uint256[] memory tracked = _trackedTokenIds();
    assertEq(tracked.length, 1);
    assertEq(tracked[0], tokenId);
  }

  function test_nft_tracker_updated_on_burn() public {
    _enableNftPosition();
    uint256 tokenId = _mintAsPool(1);
    assertEq(_trackedTokenIds().length, 1);

    bytes[] memory calls = new bytes[](3);
    calls[0] = _decreaseAllCalldataInner(tokenId);
    calls[1] = _collectCalldata(tokenId, address(fund));
    calls[2] = abi.encodeWithSelector(INonfungiblePositionManager.burn.selector, tokenId);

    vm.prank(manager);
    fund.execTransaction(nftManagerAddr, abi.encodeWithSelector(IMulticall.multicall.selector, calls));

    assertEq(_trackedTokenIds().length, 0);
  }

  /* ========== DEPOSIT REJECTION ========== */

  function test_revert_deposit_uniswapV3_position_nft() public {
    _enableNftPosition();

    // Manager holds a personal position and tries to deposit it as an NFT.
    uint256 managerTokenId = _mintAsExternal(manager, 1);

    vm.startPrank(manager);
    fundManagerLogic.changeAssets(_toSupportedAssets(nftManagerAddr, true), new address[](0));
    nftManager.approve(address(fund), managerTokenId);

    vm.expectRevert(bytes("dh9"));
    fund.deposit(nftManagerAddr, managerTokenId);
    vm.stopPrank();
  }

  /* ========== HELPERS ========== */

  function _enableNftPosition() internal {
    vm.prank(manager);
    fundManagerLogic.changeAssets(_toSupportedAssets(nftManagerAddr, false), new address[](0));
  }

  function _tickRange(uint256 _widthMultiple) internal view returns (int24 lower, int24 upper) {
    int24 spacing = int24(poolFee) / 50;
    int24 tick = _currentTick();
    int24 width = spacing * int24(_widthMultiple);
    lower = ((tick - width) / spacing) * spacing;
    upper = ((tick + width) / spacing) * spacing;
  }

  function _currentTick() internal view returns (int24 tick) {
    address pool = IUniswapV3Factory(factoryAddr).getPool(token0, token1, poolFee);
    (, tick, , , , , ) = IUniswapV3Pool(pool).slot0();
  }

  function _mintAsPool(uint256 _widthMultiple) internal returns (uint256 tokenId) {
    (int24 lower, int24 upper) = _tickRange(_widthMultiple);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](3);
    txs[0] = PoolLogic.TxToExecute({
      to: token0,
      data: abi.encodeWithSelector(IERC20.approve.selector, nftManagerAddr, type(uint256).max)
    });
    txs[1] = PoolLogic.TxToExecute({
      to: token1,
      data: abi.encodeWithSelector(IERC20.approve.selector, nftManagerAddr, type(uint256).max)
    });
    txs[2] = PoolLogic.TxToExecute({
      to: nftManagerAddr,
      data: _mintCalldata(token0, token1, lower, upper, amount0, amount1)
    });

    vm.prank(manager);
    fund.execTransactions(txs);
    tokenId = nftManager.tokenOfOwnerByIndex(address(fund), nftManager.balanceOf(address(fund)) - 1);
  }

  function _mintAsExternal(address _who, uint256 _widthMultiple) internal returns (uint256 tokenId) {
    (int24 lower, int24 upper) = _tickRange(_widthMultiple);
    deal(token0, _who, amount0);
    deal(token1, _who, amount1);

    vm.startPrank(_who);
    IERC20(token0).approve(nftManagerAddr, amount0);
    IERC20(token1).approve(nftManagerAddr, amount1);
    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
      token0: token0,
      token1: token1,
      fee: poolFee,
      tickLower: lower,
      tickUpper: upper,
      amount0Desired: amount0,
      amount1Desired: amount1,
      amount0Min: 0,
      amount1Min: 0,
      recipient: _who,
      deadline: DEADLINE
    });
    (tokenId, , , ) = nftManager.mint(params);
    vm.stopPrank();
  }

  function _mintCalldata(
    address _t0,
    address _t1,
    int24 _lower,
    int24 _upper,
    uint256 _a0,
    uint256 _a1
  ) internal view returns (bytes memory) {
    INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
      token0: _t0,
      token1: _t1,
      fee: poolFee,
      tickLower: _lower,
      tickUpper: _upper,
      amount0Desired: _a0,
      amount1Desired: _a1,
      amount0Min: 0,
      amount1Min: 0,
      recipient: address(fund),
      deadline: DEADLINE
    });
    return abi.encodeWithSelector(INonfungiblePositionManager.mint.selector, params);
  }

  function _increaseCalldata(uint256 _tokenId) internal view returns (bytes memory) {
    INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
      .IncreaseLiquidityParams({
        tokenId: _tokenId,
        amount0Desired: amount0,
        amount1Desired: amount1,
        amount0Min: 0,
        amount1Min: 0,
        deadline: DEADLINE
      });
    return abi.encodeWithSelector(INonfungiblePositionManager.increaseLiquidity.selector, params);
  }

  function _decreaseAllLiquidity(uint256 _tokenId) internal {
    // Built before the prank: _decreaseAllCalldataInner reads positions() and its staticcall
    // would otherwise consume the prank.
    bytes memory data = _decreaseAllCalldataInner(_tokenId);
    vm.prank(manager);
    fund.execTransaction(nftManagerAddr, data);
  }

  function _decreaseAllCalldataInner(uint256 _tokenId) internal view returns (bytes memory) {
    (, , , , , , , uint128 liquidity, , , , ) = nftManager.positions(_tokenId);
    return _decreaseCalldata(_tokenId, liquidity);
  }

  function _decreaseCalldata(uint256 _tokenId, uint128 _liquidity) internal pure returns (bytes memory) {
    INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
      .DecreaseLiquidityParams({
        tokenId: _tokenId,
        liquidity: _liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: DEADLINE
      });
    return abi.encodeWithSelector(INonfungiblePositionManager.decreaseLiquidity.selector, params);
  }

  /// @dev Value the withdrawer actually walked away with, priced by the vault's own oracles.
  function _investorPayoutValue(
    uint256 _token0Before,
    uint256 _token1Before
  ) internal view returns (uint256 payoutValue) {
    payoutValue =
      fundManagerLogic.assetValue(token0, IERC20(token0).balanceOf(investor) - _token0Before) +
      fundManagerLogic.assetValue(token1, IERC20(token1).balanceOf(investor) - _token1Before);
  }

  function _collectCalldata(uint256 _tokenId, address _recipient) internal pure returns (bytes memory) {
    INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
      tokenId: _tokenId,
      recipient: _recipient,
      amount0Max: type(uint128).max,
      amount1Max: type(uint128).max
    });
    return abi.encodeWithSelector(INonfungiblePositionManager.collect.selector, params);
  }

  function _trackedTokenIds() internal view returns (uint256[] memory) {
    return nftTrackerStorageProxy.getAllUintIds(keccak256("UNISWAP_NFT_TYPE"), address(fund));
  }
}
