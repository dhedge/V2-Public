// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {OneInchV6Guard} from "contracts/guards/contractGuards/OneInchV6Guard.sol";
import {IAggregationRouterV6} from "contracts/interfaces/oneInch/IAggregationRouterV6.sol";
import {IUniswapV2Factory} from "contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "contracts/interfaces/uniswapV2/IUniswapV2Pair.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {MockSwapExecutor} from "test/integration/common/oneInch/MockSwapExecutor.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @notice OneInchV6Guard decode/validation paths: generic `swap` plus the compressed
/// `unoswap`/`unoswap2`/`unoswap3` routes, executed against the real router and real
/// Uniswap V3 pools with locally-crafted calldata (no aggregator API involved).
abstract contract OneInchV6GuardTestSetup is BackboneSetup {
  // Bit layout of 1inch AggregationRouterV6 dex words (see ProtocolLib/AddressLib).
  uint256 internal constant PROTOCOL_OFFSET = 253;
  uint256 internal constant PROTOCOL_UNISWAP_V2 = 0;
  uint256 internal constant PROTOCOL_UNISWAP_V3 = 1;
  uint256 internal constant PROTOCOL_CURVE = 2;
  uint256 internal constant DIRECTION_FLAG = 1 << 247; // zeroForOne
  uint256 internal constant WETH_UNWRAP_FLAG = 1 << 252;
  uint256 internal constant USE_PERMIT2_FLAG = 1 << 250;
  /// @dev Uniswap V2 dex words carry the pair's fee as a numerator over 1e9 in bits 160-191.
  uint256 internal constant UNISWAP_V2_FEE_NUMERATOR = 997_000_000 << 160;

  uint256 internal constant SINGLE_HOP_WETH_AMOUNT = 0.1e18;
  uint256 internal constant MULTI_HOP_WETH_AMOUNT = 0.05e18;

  IAggregationRouterV6 internal router = IAggregationRouterV6(EthereumConfig.ONE_INCH_V6_ROUTER);

  IUniswapV2Factory internal immutable uniswapV2Factory;
  IUniswapV3Factory internal immutable uniswapV3Factory;
  address internal immutable quickswapV2Factory;

  OneInchV6Guard internal oneInchV6Guard;
  PoolLogic internal testPool;
  PoolManagerLogic internal testPoolManagerLogic;

  address internal swapCounterparty = makeAddr("swapCounterparty");

  address internal poolWethUsdc500;
  address internal poolWethUsdc3000;
  address internal poolDaiWeth3000;

  constructor(IUniswapV2Factory _uniswapV2Factory, IUniswapV3Factory _uniswapV3Factory, address _quickswapV2Factory) {
    uniswapV2Factory = _uniswapV2Factory;
    uniswapV3Factory = _uniswapV3Factory;
    quickswapV2Factory = _quickswapV2Factory;
  }

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);
    oneInchV6Guard = new OneInchV6Guard(
      address(slippageAccumulator),
      uniswapV2Factory,
      uniswapV3Factory,
      quickswapV2Factory
    );
    governance.setContractGuard({extContract: address(router), guardAddress: address(oneInchV6Guard)});
    vm.stopPrank();

    poolWethUsdc500 = uniswapV3Factory.getPool(wethData.asset, usdcData.asset, 500);
    poolWethUsdc3000 = uniswapV3Factory.getPool(wethData.asset, usdcData.asset, 3000);
    poolDaiWeth3000 = uniswapV3Factory.getPool(daiData.asset, wethData.asset, 3000);
    require(
      poolWethUsdc500 != address(0) && poolWethUsdc3000 != address(0) && poolDaiWeth3000 != address(0),
      "uniV3 pool missing on fork"
    );

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "OneInchV6GuardTest",
        _fundSymbol: "OIG",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    _makeDeposit(testPool, investor, wethData.asset, 1e18);
  }

  /* ========== txGuard ACCESS CONTROL ========== */

  function test_revert_txGuard_when_caller_not_pool() public {
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      0,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_UNISWAP_V3)
    );

    vm.prank(investor);
    vm.expectRevert("not pool logic");
    oneInchV6Guard.txGuard(address(testPoolManagerLogic), address(router), unoswapData);
  }

  /* ========== swap ========== */

  function test_revert_swap_when_recipient_not_pool() public {
    bytes memory swapData = _encodeSwap({
      _executor: investor,
      _srcToken: wethData.asset,
      _dstToken: usdcData.asset,
      _dstReceiver: manager,
      _amount: SINGLE_HOP_WETH_AMOUNT,
      _minReturn: 1
    });

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(address(router), swapData);
  }

  function test_revert_swap_when_dst_asset_not_enabled() public {
    vm.startPrank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(daiData.asset));

    bytes memory swapData = _encodeSwap({
      _executor: investor,
      _srcToken: wethData.asset,
      _dstToken: daiData.asset,
      _dstReceiver: address(testPool),
      _amount: SINGLE_HOP_WETH_AMOUNT,
      _minReturn: 1
    });

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(address(router), swapData);
    vm.stopPrank();
  }

  function test_swap_happy_path_with_executor() public {
    uint256 usdcEquivalent = _usdcEquivalent(SINGLE_HOP_WETH_AMOUNT);
    MockSwapExecutor executor = new MockSwapExecutor(wethData.asset, usdcData.asset, swapCounterparty, usdcEquivalent);
    deal(usdcData.asset, address(executor), usdcEquivalent);

    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();
    uint256 poolUsdcBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    _approveForRouter(wethData.asset, SINGLE_HOP_WETH_AMOUNT);

    bytes memory swapData = _encodeSwap({
      _executor: address(executor),
      _srcToken: wethData.asset,
      _dstToken: usdcData.asset,
      _dstReceiver: address(testPool),
      _amount: SINGLE_HOP_WETH_AMOUNT,
      _minReturn: (usdcEquivalent * 99) / 100
    });

    vm.prank(manager);
    testPool.execTransaction(address(router), swapData);

    assertEq(IERC20(usdcData.asset).balanceOf(address(testPool)), poolUsdcBefore + usdcEquivalent);
    assertApproxEqRel(testPoolManagerLogic.totalFundValue(), totalFundValueBefore, 0.001e18);
  }

  /* ========== unoswap HAPPY PATHS ========== */

  function test_unoswap_single_hop() public {
    uint256 minReturn = (_usdcEquivalent(SINGLE_HOP_WETH_AMOUNT) * 98) / 100;
    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();

    _approveForRouter(wethData.asset, SINGLE_HOP_WETH_AMOUNT);

    // Built ahead of the prank: _dexWord makes staticcalls which would consume it.
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      minReturn,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_UNISWAP_V3)
    );

    vm.prank(manager);
    testPool.execTransaction(address(router), unoswapData);

    assertGe(IERC20(usdcData.asset).balanceOf(address(testPool)), minReturn);
    assertApproxEqRel(testPoolManagerLogic.totalFundValue(), totalFundValueBefore, 0.005e18);
  }

  function test_unoswap_through_uniV2_pair() public {
    _assertUnoswapThroughV2Pair(uniswapV2Factory.getPair(wethData.asset, usdcData.asset));
  }

  function test_unoswap2_two_hops() public {
    // USDC -> WETH (0.05%) -> DAI (0.3%) through two distinct real pools.
    uint256 usdcAmountIn = 100e6;
    _makeDeposit(testPool, investor, usdcData.asset, usdcAmountIn);

    uint256 minReturn = (testPoolManagerLogic.assetValue(usdcData.asset, usdcAmountIn) * 90) / 100;
    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();

    _approveForRouter(usdcData.asset, usdcAmountIn);

    // Built ahead of the prank: _dexWord makes staticcalls which would consume it.
    bytes memory unoswap2Data = abi.encodeWithSelector(
      IAggregationRouterV6.unoswap2.selector,
      uint256(uint160(usdcData.asset)),
      usdcAmountIn,
      minReturn,
      _dexWord(poolWethUsdc500, usdcData.asset, PROTOCOL_UNISWAP_V3),
      _dexWord(poolDaiWeth3000, wethData.asset, PROTOCOL_UNISWAP_V3)
    );

    vm.prank(manager);
    testPool.execTransaction(address(router), unoswap2Data);

    assertGe(IERC20(daiData.asset).balanceOf(address(testPool)), minReturn);
    assertApproxEqRel(testPoolManagerLogic.totalFundValue(), totalFundValueBefore, 0.01e18);
  }

  function test_unoswap3_three_hops() public {
    // WETH -> USDC (0.05%) -> WETH (0.3%) -> DAI (0.3%) across three distinct real pools.
    uint256 minReturn = (_daiEquivalent(MULTI_HOP_WETH_AMOUNT) * 90) / 100;
    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();

    _approveForRouter(wethData.asset, MULTI_HOP_WETH_AMOUNT);

    // Built ahead of the prank: _dexWord makes staticcalls which would consume it.
    bytes memory unoswap3Data = abi.encodeWithSelector(
      IAggregationRouterV6.unoswap3.selector,
      uint256(uint160(wethData.asset)),
      MULTI_HOP_WETH_AMOUNT,
      minReturn,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_UNISWAP_V3),
      _dexWord(poolWethUsdc3000, usdcData.asset, PROTOCOL_UNISWAP_V3),
      _dexWord(poolDaiWeth3000, wethData.asset, PROTOCOL_UNISWAP_V3)
    );

    vm.prank(manager);
    testPool.execTransaction(address(router), unoswap3Data);

    assertGe(IERC20(daiData.asset).balanceOf(address(testPool)), minReturn);
    assertApproxEqRel(testPoolManagerLogic.totalFundValue(), totalFundValueBefore, 0.01e18);
  }

  /* ========== unoswap VALIDATION ========== */

  function test_revert_unoswap_when_dst_asset_not_enabled() public {
    vm.startPrank(manager);
    testPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(daiData.asset));

    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      1,
      _dexWord(poolDaiWeth3000, wethData.asset, PROTOCOL_UNISWAP_V3)
    );

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(address(router), unoswapData);
    vm.stopPrank();
  }

  function test_revert_unoswap_when_weth_unwrap_flag_set() public {
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      1,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_UNISWAP_V3) | WETH_UNWRAP_FLAG
    );

    vm.prank(manager);
    vm.expectRevert("WETH unwrap not supported");
    testPool.execTransaction(address(router), unoswapData);
  }

  function test_revert_unoswap_when_permit2_flag_set() public {
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      1,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_UNISWAP_V3) | USE_PERMIT2_FLAG
    );

    vm.prank(manager);
    vm.expectRevert("permit2 not supported");
    testPool.execTransaction(address(router), unoswapData);
  }

  function test_revert_unoswap_when_direction_mismatch() public {
    // Correct word for a WETH source, with the zeroForOne bit flipped.
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      1,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_UNISWAP_V3) ^ DIRECTION_FLAG
    );

    vm.prank(manager);
    vm.expectRevert("direction mismatch");
    testPool.execTransaction(address(router), unoswapData);
  }

  function test_revert_unoswap_when_src_not_in_pool() public {
    // USDC is not a token of the DAI/WETH pool.
    bytes memory unoswapData = _encodeUnoswap(
      usdcData.asset,
      1e6,
      1,
      _dexWord(poolDaiWeth3000, daiData.asset, PROTOCOL_UNISWAP_V3)
    );

    vm.prank(manager);
    vm.expectRevert("invalid path");
    testPool.execTransaction(address(router), unoswapData);
  }

  function test_revert_unoswap_when_protocol_not_supported() public {
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      1,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_CURVE)
    );

    vm.prank(manager);
    vm.expectRevert("exchange pool not supported");
    testPool.execTransaction(address(router), unoswapData);
  }

  function test_revert_unoswap_when_uniV2_pool_invalid() public {
    // A Uniswap V3 pool address marked as the UniswapV2 protocol fails the factory check.
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      SINGLE_HOP_WETH_AMOUNT,
      1,
      _dexWord(poolWethUsdc500, wethData.asset, PROTOCOL_UNISWAP_V2)
    );

    vm.prank(manager);
    vm.expectRevert("uniV2 pool invalid");
    testPool.execTransaction(address(router), unoswapData);
  }

  /* ========== HELPERS ========== */

  function _dexWord(address _pool, address _srcToken, uint256 _protocol) internal view returns (uint256 dex) {
    dex = uint256(uint160(_pool)) | (_protocol << PROTOCOL_OFFSET);

    if (IUniswapV3Pool(_pool).token0() == _srcToken) {
      dex |= DIRECTION_FLAG; // zeroForOne
    }
  }

  /// @dev Swaps a sliver of the pair's WETH reserve so price impact stays negligible whatever the
  /// pair's depth, then checks the pair really was the venue by matching its constant-product quote.
  function _assertUnoswapThroughV2Pair(address _pair) internal {
    require(_pair != address(0), "uniV2 pair missing on fork");

    (uint256 wethReserve, uint256 usdcReserve) = _v2Reserves(_pair, wethData.asset);
    uint256 wethAmount = wethReserve / 1000;
    uint256 expectedUsdc = (wethAmount * 997 * usdcReserve) / (wethReserve * 1000 + wethAmount * 997);
    uint256 usdcBefore = IERC20(usdcData.asset).balanceOf(address(testPool));
    uint256 totalFundValueBefore = testPoolManagerLogic.totalFundValue();

    _approveForRouter(wethData.asset, wethAmount);

    // Built ahead of the prank: _dexWord makes staticcalls which would consume it.
    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      wethAmount,
      (expectedUsdc * 99) / 100,
      _dexWord(_pair, wethData.asset, PROTOCOL_UNISWAP_V2) | UNISWAP_V2_FEE_NUMERATOR
    );

    vm.prank(manager);
    testPool.execTransaction(address(router), unoswapData);

    assertApproxEqRel(IERC20(usdcData.asset).balanceOf(address(testPool)) - usdcBefore, expectedUsdc, 0.001e18);
    assertApproxEqRel(testPoolManagerLogic.totalFundValue(), totalFundValueBefore, 0.005e18);
  }

  function _v2Reserves(address _pair, address _tokenIn) internal view returns (uint256 reserveIn, uint256 reserveOut) {
    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(_pair).getReserves();
    (reserveIn, reserveOut) = IUniswapV2Pair(_pair).token0() == _tokenIn
      ? (uint256(reserve0), uint256(reserve1))
      : (uint256(reserve1), uint256(reserve0));
  }

  function _encodeUnoswap(
    address _srcToken,
    uint256 _amount,
    uint256 _minReturn,
    uint256 _dex
  ) internal pure returns (bytes memory data) {
    data = abi.encodeWithSelector(
      IAggregationRouterV6.unoswap.selector,
      uint256(uint160(_srcToken)),
      _amount,
      _minReturn,
      _dex
    );
  }

  function _encodeSwap(
    address _executor,
    address _srcToken,
    address _dstToken,
    address _dstReceiver,
    uint256 _amount,
    uint256 _minReturn
  ) internal pure returns (bytes memory data) {
    IAggregationRouterV6.SwapDescription memory description = IAggregationRouterV6.SwapDescription({
      srcToken: _srcToken,
      dstToken: _dstToken,
      srcReceiver: payable(_executor),
      dstReceiver: payable(_dstReceiver),
      amount: _amount,
      minReturnAmount: _minReturn,
      flags: 0
    });

    data = abi.encodeWithSelector(IAggregationRouterV6.swap.selector, _executor, description, bytes(""));
  }

  function _approveForRouter(address _token, uint256 _amount) internal {
    vm.prank(manager);
    testPool.execTransaction(_token, abi.encodeWithSelector(IERC20.approve.selector, address(router), _amount));
  }

  function _usdcEquivalent(uint256 _wethAmount) internal view returns (uint256 usdcAmount) {
    // USD value is 18 decimals; USDC has 6.
    usdcAmount = testPoolManagerLogic.assetValue(wethData.asset, _wethAmount) / 1e12;
  }

  function _daiEquivalent(uint256 _wethAmount) internal view returns (uint256 daiAmount) {
    daiAmount = testPoolManagerLogic.assetValue(wethData.asset, _wethAmount);
  }
}
