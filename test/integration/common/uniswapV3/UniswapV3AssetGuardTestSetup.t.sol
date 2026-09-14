// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {UniswapV3NonfungiblePositionGuard} from "contracts/guards/contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol";
import {UniswapV3AssetGuard} from "contracts/guards/assetGuards/UniswapV3AssetGuard.sol";
import {UniswapV3PriceLibraryTest} from "contracts/test/UniswapV3PriceLibraryTest.sol";
import {IV3SwapRouter} from "contracts/interfaces/uniswapV3/IV3SwapRouter.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {SingleFundTestSetup} from "test/integration/utils/foundry/SingleFundTestSetup.t.sol";

/// @notice UniswapV3AssetGuard valuation behaviour: oracle-vs-pool price manipulation resistance,
/// that only the pool's own (tracked) positions are counted, and that positions whose underlying
/// tokens are not priceable never break `tokenPrice`/withdrawals.
abstract contract UniswapV3AssetGuardTestSetup is SingleFundTestSetup {
  uint256 private constant DEADLINE = type(uint256).max;
  /// @dev Multiple of a pool's reserves to dump on one side to force the pool price off the oracle.
  uint256 internal constant MANIPULATION_MULTIPLIER = 10;

  struct TestParams {
    address nftManager;
    address uniswapV3Factory;
    address swapRouter;
    uint24 supportedPairFee; // WETH/USDC pool the fund LPs into
    address unsupportedTokenA; // not registered in the backbone AssetHandler (e.g. WBTC)
    address unsupportedTokenAOracle; // its real Chainlink feed, for the de-registration test
    address unsupportedTokenB; // not registered in the backbone AssetHandler (e.g. LINK)
    uint24 bothUnsupportedFee; // unsupportedTokenA/unsupportedTokenB pool
    uint24 oneUnsupportedFee; // unsupportedTokenA/WETH pool
  }

  TestParams internal params;

  INonfungiblePositionManager private nftManager;
  UniswapV3NonfungiblePositionGuard private positionGuard;
  UniswapV3AssetGuard internal assetGuard;

  address internal lpUser = makeAddr("lpUser");

  constructor(TestParams memory _params) {
    params = _params;
  }

  function setUp() public virtual override {
    super.setUp();

    nftManager = INonfungiblePositionManager(params.nftManager);

    vm.startPrank(owner);
    positionGuard = new UniswapV3NonfungiblePositionGuard(3, address(nftTrackerStorageProxy));
    assetGuard = new UniswapV3AssetGuard();
    governance.setContractGuard({extContract: params.nftManager, guardAddress: address(positionGuard)});
    governance.setAssetGuard({assetType: uint16(AssetTypeIncomplete.UNISWAP_V3), guardAddress: address(assetGuard)});

    assetHandlerProxy.addAsset({
      asset: params.nftManager,
      assetType: uint16(AssetTypeIncomplete.UNISWAP_V3),
      aggregator: address(usdPriceAggregator)
    });
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: params.nftManager, isDeposit: false});

    vm.prank(manager);
    fund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "UniswapV3AssetGuardTest",
        _fundSymbol: "U3A",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    _makeDeposit(fund, investor, wethData.asset, 20e18);
    _makeDeposit(fund, investor, usdcData.asset, 40_000e6);
  }

  /* ========== PRICE MANIPULATION RESISTANCE ========== */

  function test_revert_tokenPrice_when_pool_price_manipulated_away_from_oracle() public {
    _mintAsPool(false);

    // Sanity: valuation works and the vault is worth roughly its deposits before manipulation.
    uint256 tokenPriceBefore = fund.tokenPrice();
    assertApproxEqRel(tokenPriceBefore, 1e18, 0.01e18);
    assertGt(assetGuard.getBalance(address(fund), params.nftManager), 0);

    address pool = _supportedPool();
    uint256 reservesBefore = IERC20(wethData.asset).balanceOf(pool);

    _dumpOnPool(wethData.asset, usdcData.asset, params.supportedPairFee, reservesBefore * MANIPULATION_MULTIPLIER);

    // The pool price no longer agrees with the Chainlink oracles, so the guard refuses to value
    // the position rather than reporting a manipulated number.
    assertGt(IERC20(wethData.asset).balanceOf(pool), reservesBefore);
    vm.expectRevert("Uni v3 LP price mismatch");
    fund.tokenPrice();
  }

  function test_revert_getBalance_when_pool_price_manipulated_away_from_oracle() public {
    _mintAsPool(false);

    address pool = _supportedPool();
    _dumpOnPool(
      usdcData.asset,
      wethData.asset,
      params.supportedPairFee,
      IERC20(usdcData.asset).balanceOf(pool) * MANIPULATION_MULTIPLIER
    );

    // Manipulating the other direction is rejected just the same.
    vm.expectRevert("Uni v3 LP price mismatch");
    assetGuard.getBalance(address(fund), params.nftManager);
  }

  /* ========== ONLY THE POOL'S OWN POSITIONS ARE COUNTED ========== */

  function test_balance_ignores_transferred_in_position_when_user_minted_first() public {
    _runTransferredInPositionScenario({_userMintsFirst: true, _outOfRange: false});
  }

  function test_balance_ignores_transferred_in_position_when_user_minted_first_out_of_range() public {
    _runTransferredInPositionScenario({_userMintsFirst: true, _outOfRange: true});
  }

  function test_balance_ignores_transferred_in_position_when_manager_minted_first() public {
    _runTransferredInPositionScenario({_userMintsFirst: false, _outOfRange: false});
  }

  function test_balance_ignores_transferred_in_position_when_manager_minted_first_out_of_range() public {
    _runTransferredInPositionScenario({_userMintsFirst: false, _outOfRange: true});
  }

  /// @dev The pool mints its maximum of three positions and a fourth is transferred in from
  /// outside. Only the three tracked ones may be valued, whatever order they were created in.
  function _runTransferredInPositionScenario(bool _userMintsFirst, bool _outOfRange) internal {
    uint256 userTokenId;

    if (_userMintsFirst) {
      userTokenId = _mintAsUser(_outOfRange);
    }
    for (uint256 i; i < 3; ++i) {
      _mintAsPool(_outOfRange);
    }
    if (!_userMintsFirst) {
      userTokenId = _mintAsUser(_outOfRange);
    }

    uint256 tokenPriceBefore = fund.tokenPrice();
    uint256 balanceBefore = assetGuard.getBalance(address(fund), params.nftManager);
    assertGt(balanceBefore, 0);

    vm.prank(lpUser);
    nftManager.transferFrom(lpUser, address(fund), userTokenId);

    assertEq(assetGuard.getBalance(address(fund), params.nftManager), balanceBefore);
    assertEq(fund.tokenPrice(), tokenPriceBefore);
    assertEq(nftManager.balanceOf(lpUser), 0);
    assertEq(nftManager.balanceOf(address(fund)), 4);
  }

  /* ========== POSITIONS WITH UNPRICEABLE UNDERLYINGS ========== */

  function test_tokenPrice_and_withdraw_survive_transferred_in_position_with_both_assets_unsupported() public {
    _runUnsupportedUnderlyingScenario(params.unsupportedTokenA, params.unsupportedTokenB, params.bothUnsupportedFee);
  }

  function test_tokenPrice_and_withdraw_survive_transferred_in_position_with_one_asset_unsupported() public {
    _runUnsupportedUnderlyingScenario(params.unsupportedTokenA, wethData.asset, params.oneUnsupportedFee);
  }

  /// @dev Anyone can push an arbitrary position NFT into a vault. One holding tokens the
  /// AssetHandler cannot price must not brick valuation or withdrawals.
  function _runUnsupportedUnderlyingScenario(address _tokenA, address _tokenB, uint24 _fee) internal {
    uint256 tokenId = _mintExternalPosition(lpUser, _tokenA, _tokenB, _fee, false);

    uint256 tokenPriceBefore = fund.tokenPrice();

    vm.prank(lpUser);
    nftManager.transferFrom(lpUser, address(fund), tokenId);

    assertEq(fund.tokenPrice(), tokenPriceBefore);
    assertEq(nftManager.balanceOf(lpUser), 0);
    assertEq(nftManager.balanceOf(address(fund)), 1);
    assertGt(fundManagerLogic.totalFundValue(), 0);

    // The whole vault can still be withdrawn.
    vm.warp(block.timestamp + 1 days + 1);
    // Hoisted so the balance staticcall doesn't consume the prank.
    uint256 investorBalance = fund.balanceOf(investor);
    vm.prank(investor);
    fund.withdraw(investorBalance);

    assertEq(fund.balanceOf(investor), 0);
    assertEq(fundManagerLogic.totalFundValue(), 0);
  }

  /// @dev A position the vault minted itself stops being valued once one of its tokens is
  /// de-registered from the AssetHandler: the guard skips it instead of reverting.
  function test_balance_skips_tracked_position_after_underlying_asset_removed() public {
    address unpriceableToken = params.unsupportedTokenA;

    // Register the token (with its real feed, so the pool price agrees with the oracle) to let
    // the vault mint a position with it.
    vm.prank(owner);
    assetHandlerProxy.addAsset({
      asset: unpriceableToken,
      assetType: uint16(AssetTypeIncomplete.CHAINLINK),
      aggregator: params.unsupportedTokenAOracle
    });

    vm.prank(manager);
    fundManagerLogic.changeAssets(_toSupportedAssets(unpriceableToken, false), new address[](0));

    deal(unpriceableToken, address(fund), 1e8);
    _mintPoolPosition(unpriceableToken, wethData.asset, params.oneUnsupportedFee, false);
    assertGt(assetGuard.getBalance(address(fund), params.nftManager), 0);

    // Drop the token from the vault and then from the AssetHandler.
    deal(unpriceableToken, address(fund), 0);
    vm.prank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(unpriceableToken));
    vm.prank(owner);
    assetHandlerProxy.removeAsset(unpriceableToken);

    assertEq(assetGuard.getBalance(address(fund), params.nftManager), 0);
    assertGt(fund.tokenPrice(), 0);
  }

  /* ========== PRICE LIBRARY ========== */

  function test_price_library_accepts_fair_pool_prices() public {
    UniswapV3PriceLibraryTest priceLibrary = new UniswapV3PriceLibraryTest();
    (address t0, address t1) = _sortTokens(wethData.asset, usdcData.asset);

    // Reverts if the pool price has drifted from the oracles; unmanipulated pools must pass.
    priceLibrary.assertFairPrice(address(poolFactoryProxy), params.uniswapV3Factory, t0, t1, params.supportedPairFee);
  }

  function test_revert_price_library_on_manipulated_pool() public {
    UniswapV3PriceLibraryTest priceLibrary = new UniswapV3PriceLibraryTest();
    (address t0, address t1) = _sortTokens(wethData.asset, usdcData.asset);

    _dumpOnPool(
      wethData.asset,
      usdcData.asset,
      params.supportedPairFee,
      IERC20(wethData.asset).balanceOf(_supportedPool()) * MANIPULATION_MULTIPLIER
    );

    vm.expectRevert("Uni v3 LP price mismatch");
    priceLibrary.assertFairPrice(address(poolFactoryProxy), params.uniswapV3Factory, t0, t1, params.supportedPairFee);
  }

  /* ========== HELPERS ========== */

  function _supportedPool() internal view returns (address pool) {
    pool = IUniswapV3Factory(params.uniswapV3Factory).getPool(wethData.asset, usdcData.asset, params.supportedPairFee);
  }

  /// @dev Swaps `_amountIn` through the pool with no price limit, dragging its price far from the oracle.
  function _dumpOnPool(address _tokenIn, address _tokenOut, uint24 _fee, uint256 _amountIn) internal {
    address whale = makeAddr("whale");
    deal(_tokenIn, whale, _amountIn);

    vm.startPrank(whale);
    IERC20(_tokenIn).approve(params.swapRouter, _amountIn);
    IV3SwapRouter(params.swapRouter).exactInputSingle(
      IV3SwapRouter.ExactInputSingleParams({
        tokenIn: _tokenIn,
        tokenOut: _tokenOut,
        fee: _fee,
        recipient: whale,
        amountIn: _amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      })
    );
    vm.stopPrank();
  }

  function _mintAsPool(bool _outOfRange) internal returns (uint256 tokenId) {
    tokenId = _mintPoolPosition(wethData.asset, usdcData.asset, params.supportedPairFee, _outOfRange);
  }

  function _mintPoolPosition(
    address _tokenA,
    address _tokenB,
    uint24 _fee,
    bool _outOfRange
  ) internal returns (uint256 tokenId) {
    (address t0, address t1) = _sortTokens(_tokenA, _tokenB);
    (int24 lower, int24 upper) = _tickRange(t0, t1, _fee, _outOfRange);
    (uint256 a0, uint256 a1) = _mintAmounts(t0, t1);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](3);
    txs[0] = PoolLogic.TxToExecute({
      to: t0,
      data: abi.encodeWithSelector(IERC20.approve.selector, params.nftManager, type(uint256).max)
    });
    txs[1] = PoolLogic.TxToExecute({
      to: t1,
      data: abi.encodeWithSelector(IERC20.approve.selector, params.nftManager, type(uint256).max)
    });
    txs[2] = PoolLogic.TxToExecute({
      to: params.nftManager,
      data: abi.encodeWithSelector(
        INonfungiblePositionManager.mint.selector,
        INonfungiblePositionManager.MintParams({
          token0: t0,
          token1: t1,
          fee: _fee,
          tickLower: lower,
          tickUpper: upper,
          amount0Desired: a0,
          amount1Desired: a1,
          amount0Min: 0,
          amount1Min: 0,
          recipient: address(fund),
          deadline: DEADLINE
        })
      )
    });

    vm.prank(manager);
    fund.execTransactions(txs);
    tokenId = nftManager.tokenOfOwnerByIndex(address(fund), nftManager.balanceOf(address(fund)) - 1);
  }

  function _mintAsUser(bool _outOfRange) internal returns (uint256 tokenId) {
    tokenId = _mintExternalPosition(lpUser, wethData.asset, usdcData.asset, params.supportedPairFee, _outOfRange);
  }

  function _mintExternalPosition(
    address _who,
    address _tokenA,
    address _tokenB,
    uint24 _fee,
    bool _outOfRange
  ) internal returns (uint256 tokenId) {
    (address t0, address t1) = _sortTokens(_tokenA, _tokenB);
    (int24 lower, int24 upper) = _tickRange(t0, t1, _fee, _outOfRange);
    (uint256 a0, uint256 a1) = _mintAmounts(t0, t1);

    deal(t0, _who, a0);
    deal(t1, _who, a1);

    vm.startPrank(_who);
    IERC20(t0).approve(params.nftManager, a0);
    IERC20(t1).approve(params.nftManager, a1);
    (tokenId, , , ) = nftManager.mint(
      INonfungiblePositionManager.MintParams({
        token0: t0,
        token1: t1,
        fee: _fee,
        tickLower: lower,
        tickUpper: upper,
        amount0Desired: a0,
        amount1Desired: a1,
        amount0Min: 0,
        amount1Min: 0,
        recipient: _who,
        deadline: DEADLINE
      })
    );
    vm.stopPrank();
  }

  /// @dev In-range spans the current tick; out-of-range sits entirely below it, so the position
  /// holds a single token.
  function _tickRange(
    address _token0,
    address _token1,
    uint24 _fee,
    bool _outOfRange
  ) internal view returns (int24 lower, int24 upper) {
    IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(params.uniswapV3Factory).getPool(_token0, _token1, _fee));
    require(address(pool) != address(0), "uniV3 pool missing on fork");

    (, int24 tick, , , , , ) = pool.slot0();
    int24 spacing = pool.tickSpacing();
    int24 aligned = (tick / spacing) * spacing;

    if (_outOfRange) {
      (lower, upper) = (aligned - spacing * 3, aligned - spacing * 2);
    } else {
      (lower, upper) = (aligned - spacing * 2, aligned + spacing * 2);
    }
  }

  /// @dev Modest, decimal-aware amounts: enough for a valuable position, small enough that three
  /// of them fit inside the vault's deposits.
  function _mintAmounts(address _token0, address _token1) internal view returns (uint256 amount0, uint256 amount1) {
    amount0 = _mintAmount(_token0);
    amount1 = _mintAmount(_token1);
  }

  function _mintAmount(address _token) internal view returns (uint256 amount) {
    if (_token == wethData.asset) return 1e18;
    if (_token == usdcData.asset) return 2_000e6;
    // Unsupported side: a small notional is enough, these positions are never valued.
    return _token == params.unsupportedTokenA ? 1e6 : 50e18;
  }

  function _sortTokens(address _tokenA, address _tokenB) internal pure returns (address token0, address token1) {
    (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
  }
}
