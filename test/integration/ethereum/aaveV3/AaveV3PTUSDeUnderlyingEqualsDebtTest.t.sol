// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IAaveV3Pool} from "contracts/interfaces/aave/v3/IAaveV3Pool.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasAssetInfo} from "contracts/interfaces/IHasAssetInfo.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
// Aliased so the mock can use SafeERC20 (USDT-safe) without clashing with the repo IERC20 used by the ISwapper structs.
import {IERC20 as IERC20OZ} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/// @dev Minimal admin surface of the flatMoney Swapper (not exposed by the repo's ISwapper interface).
interface ISwapperRouterAdmin {
  function owner() external view returns (address);

  function addRouter(bytes32 routerKey, address router) external;
}

/// @dev Test-only swap router used by the off-chain scenario below to mock the single USDT->USDe swap (real Odos
///      routes USDe through a pool that cannot execute in a Foundry fork). Pulls the exact src amount from the caller
///      and pays out the pre-funded dst amount (funded by _buildMockSwap); SafeERC20 supports non-standard tokens
///      like USDT. Registered under a dedicated routerKey so ONLY the swap opting into that key is mocked.
contract OracleEstimatedSwapMock {
  using SafeERC20 for IERC20OZ;

  function swap(address src, address dst, uint256 srcAmount, uint256 destAmount) external {
    IERC20OZ(src).safeTransferFrom(msg.sender, address(this), srcAmount);
    IERC20OZ(dst).safeTransfer(msg.sender, destAmount);
  }
}

/// @dev Bug fixture: a Pendle PT collateral whose UNDERLYING equals the Aave DEBT asset.
///      - collateral PT-USDe-JUL-2025 (underlying = USDe), borrow USDe (== underlying).
///      - token1 = USDT is a DIFFERENT swappable collateral, used by the off-chain scenario.
///      Triggers the harness collision guard (token0ToLendUnderlying == tokenToBorrow).
contract AaveV3PTUSDeUnderlyingEqualsDebtTest is AaveV3TestSetup, EthereumSetup {
  uint256 private testForkBlockNumber = 22732376; // PT-USDe-JUL not expired; eMode 12 (USDe borrowable)

  OracleEstimatedSwapMock private mockSwapRouter;

  constructor() AaveV3TestSetup(_createAaveV3TestConfig()) EthereumSetup(testForkBlockNumber) {}

  function _createAaveV3TestConfig() internal pure returns (AaveV3TestSetup.AaveV3TestConfig memory config) {
    config.swapper = EthereumConfig.SWAPPER;
    config.aaveV3Pool = EthereumConfig.AAVE_V3_LENDING_POOL;
    config.uniV3Factory = EthereumConfig.UNISWAP_V3_FACTORY;
    config.uniV3Router = EthereumConfig.UNISWAP_V3_ROUTER;
    config.uniV2LikeRouters = new address[](0);
    config.token0ToLend = EthereumConfig.PT_USDe_JUL_2025;
    config.token1ToLend = EthereumConfig.USDT;
    config.tokenToBorrow = EthereumConfig.USDe; // == PT underlying (the bug condition)
    config.token0AmountNormalized = 10000;
    config.token1AmountNormalized = 1000;
    config.tokenToBorrowAmountNormalized = 6000;
    config.token0Oracle = EthereumConfig.PT_USDe_JUL_2025_PRICE_AGGREGATOR;
    config.token1Oracle = EthereumConfig.USDT_CHAINLINK_ORACLE;
    config.tokenToBorrowOracle = EthereumConfig.USDe_CHAINLINK_ORACLE;
    config.pendleYieldContractFactory = EthereumConfig.PENDLE_YIELD_CONTRACT_FACTORY;
    config.pendleStaticRouter = EthereumConfig.PENDLE_STATIC_ROUTER;
    config.token0ToLendPendleMarket = EthereumConfig.PENDLE_MARKET_USDe_JUL_2025;
    config.token0ToLendUnderlying = EthereumConfig.USDe; // == tokenToBorrow -> triggers harness collision guard
    config.token0ToLendUnderlyingOracle = EthereumConfig.USDe_CHAINLINK_ORACLE;
    config.useEMode = 12; // PT-USDe / USDe eMode — the category that allows borrowing USDe against PT-USDe
  }

  function setUp() public virtual override(AaveV3TestSetup, EthereumSetup) {
    super.setUp();

    // Register a mock swap router under a dedicated key, used only by the off-chain scenario below. Real Odos routes
    // USDT->USDe through a pool that cannot be executed in a Foundry fork, so that single swap is mocked (nothing else).
    mockSwapRouter = new OracleEstimatedSwapMock();
    vm.prank(ISwapperRouterAdmin(swapper).owner());
    ISwapperRouterAdmin(swapper).addRouter(bytes32("MOCK"), address(mockSwapRouter));
  }

  // ----- helpers shared by the scenarios below -----

  function _setEMode() internal {
    vm.prank(manager);
    aaveTestPool.execTransaction(aaveV3Pool, abi.encodeWithSelector(IAaveV3Pool.setUserEMode.selector, useEMode));
  }

  function _supplyExtra(address _asset, uint256 _amount) internal {
    deal(_asset, address(aaveTestPool), _amount);
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, _asset, _amount, address(aaveTestPool), 0)
    );
  }

  function _borrowDebt() internal {
    uint256 borrowAmount = tokenToBorrowAmountNormalized * (10 ** IERC20Extended(tokenToBorrow).decimals());
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.borrow.selector, tokenToBorrow, borrowAmount, 2, 0, address(aaveTestPool))
    );
  }

  // ===== Test cases (a Pendle PT whose underlying == the Aave debt asset) =====
  // - calculateSwapDataParams excludes the matching PT from srcData:
  //   - PT only       -> srcData empty
  //   - PT + USDT     -> srcData == [USDT]
  //   - PT + raw USDe -> srcData empty (both excluded; exercises value accumulation)
  // - on-chain withdraw (empty swap data): PT unrolled to USDe repays directly (PT only; and PT + raw USDe)
  // - off-chain withdraw: PT unrolled (no swap) + USDT swapped to USDe (swap mocked, see _buildMockSwap)
  // - on-chain withdraw reverts "pt requires offchain data" when a PT's underlying != the repay asset
  // - inherited offchain swap-data validation tests are skipped below (srcData is empty; covered by other fixtures)

  // Skipped: not applicable here — srcData is empty, so there is nothing to tamper (see test-cases note above).
  function test_revert_withdraw_with_swap_data_length_mismatch() public override {
    vm.skip(true);
  }

  function test_revert_withdraw_with_src_token_mismatch() public override {
    vm.skip(true);
  }

  function test_revert_withdraw_with_src_amount_too_high() public override {
    vm.skip(true);
  }

  function test_revert_withdraw_with_src_amount_mismatch() public override {
    vm.skip(true);
  }

  function test_revert_withdraw_with_dst_amount_mismatch() public override {
    vm.skip(true);
  }

  function test_withdrawSafe_builds_collateral_txs_when_debt_asset_collateral_is_after_last_src_asset()
    public
    override
  {
    vm.skip(true);
  }

  function _calcParams(uint256 _amountToWithdraw) internal returns (AaveLendingPoolAssetGuard.SwapDataParams memory) {
    vm.prank(address(this), address(0)); // tx.origin == 0 to satisfy `cannotExecute`
    return aaveLendingPoolAssetGuard.calculateSwapDataParams(address(aaveTestPool), _amountToWithdraw, 100);
  }

  /// @dev Builds swapData for the mock router: estimates the dst out from oracle prices (−0.1% slippage) and pre-funds
  ///      the mock with that amount so it can pay it out on swap.
  function _buildMockSwap(address _src, address _dst, uint256 _srcAmount) internal returns (bytes memory) {
    address factory = IPoolLogic(address(aaveTestPool)).factory();
    uint256 usdValueD18 = aaveTestPoolManagerLogic.assetValue(_src, _srcAmount);
    uint256 destAmount = (usdValueD18 * (10 ** IERC20Extended(_dst).decimals())) /
      IHasAssetInfo(factory).getAssetPrice(_dst);
    destAmount = (destAmount * (10_000 - 10)) / 10_000; // −0.1% slippage
    deal(_dst, address(mockSwapRouter), destAmount);
    return abi.encodeWithSelector(OracleEstimatedSwapMock.swap.selector, _src, _dst, _srcAmount, destAmount);
  }

  // (a) calculateSwapDataParams excludes the PT whose underlying == debt (PT-only -> empty srcData)
  function test_calculateSwapDataParams_excludes_pt_when_underlying_equals_debt_PT_only() public {
    _supplyAndBorrow(); // PT-USDe only (the inherited default position) -> srcData must be empty

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    AaveLendingPoolAssetGuard.SwapDataParams memory p = _calcParams(amountToWithdraw);

    assertEq(p.srcData.length, 0, "PT whose underlying == debt must be excluded from srcData");
    assertEq(p.dstData.asset, tokenToBorrow, "dstData asset must be the debt asset");
  }

  // (a) calculateSwapDataParams keeps only the non-matching collateral (PT + USDT -> [USDT])
  function test_calculateSwapDataParams_keeps_only_usdt_when_pt_plus_usdt() public {
    _supply(); // PT-USDe
    _setEMode();
    _supplyExtra(token1ToLend, token1AmountNormalized * (10 ** IERC20Extended(token1ToLend).decimals())); // USDT
    _borrowDebt(); // USDe

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    AaveLendingPoolAssetGuard.SwapDataParams memory p = _calcParams(amountToWithdraw);

    assertEq(p.srcData.length, 1, "only USDT should remain in srcData");
    assertEq(p.srcData[0].asset, token1ToLend, "remaining src must be USDT");
  }

  // (f) two collaterals match the debt (PT-USDe + raw USDe) -> both excluded; exercises the accumulation path
  function test_calculateSwapDataParams_excludes_pt_and_raw_debt_collateral() public {
    _supply(); // PT-USDe
    _setEMode();
    _supplyExtra(tokenToBorrow, 2000 * (10 ** IERC20Extended(tokenToBorrow).decimals())); // raw USDe collateral
    _borrowDebt(); // USDe

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    AaveLendingPoolAssetGuard.SwapDataParams memory p = _calcParams(amountToWithdraw);

    assertEq(p.srcData.length, 0, "PT-underlying and raw debt collateral both excluded");
    assertEq(p.dstData.amount, 0, "no swap value -> zero minDstAmount");
  }

  // (b) on-chain path (empty withdrawData): PT unrolled to USDe which repays the flashloan directly, no swap
  function test_withdrawSafe_onchain_unrolls_pt_when_underlying_equals_debt() public {
    skip(1 days); // avoid the same-block deposit/withdraw lock (dh11)
    _supplyAndBorrow(); // PT-USDe only (the inherited default position) -> srcData empty -> on-chain path

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    // USD value of the pool tokens being withdrawn = what the investor should receive back (minus minor slippage).
    uint256 valueToWithdraw = (aaveTestPool.tokenPrice() * amountToWithdraw) / 1e18;
    uint256 totalBefore = aaveTestPoolManagerLogic.totalFundValue();

    assertEq(IERC20Extended(tokenToBorrow).balanceOf(investor), 0, "investor has no USDe before withdraw");

    // Build the array before pranking: _getEmptyPoolComplexAssetsData makes an external staticcall that would
    // otherwise consume the prank, leaving withdrawSafe with the wrong msg.sender.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(aaveTestPool));
    vm.prank(investor);
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);

    assertApproxEqRel(aaveTestPoolManagerLogic.totalFundValue(), totalBefore / 2, 0.02e18, "value should ~halve");

    // The investor receives USDe whose value ~= the withdrawn pool-token value (no value lost in the PT unroll).
    uint256 valueReceived = aaveTestPoolManagerLogic.assetValue(
      tokenToBorrow,
      IERC20Extended(tokenToBorrow).balanceOf(investor)
    );
    assertApproxEqRel(valueReceived, valueToWithdraw, 0.01e18, "received USDe value ~= withdrawn value");
  }

  // (c) on-chain path: PT (underlying==debt) + raw USDe collateral; both repay directly, no swap
  function test_withdrawSafe_onchain_pt_plus_raw_debt_collateral() public {
    skip(1 days); // avoid the same-block deposit/withdraw lock (dh11)
    _supply(); // PT-USDe
    _setEMode();
    _supplyExtra(tokenToBorrow, 2000 * (10 ** IERC20Extended(tokenToBorrow).decimals())); // raw USDe collateral
    _borrowDebt(); // USDe

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    uint256 valueToWithdraw = (aaveTestPool.tokenPrice() * amountToWithdraw) / 1e18;
    uint256 totalBefore = aaveTestPoolManagerLogic.totalFundValue();

    assertEq(IERC20Extended(tokenToBorrow).balanceOf(investor), 0, "investor has no USDe before withdraw");

    // Build the array before pranking: _getEmptyPoolComplexAssetsData makes an external staticcall that would
    // otherwise consume the prank, leaving withdrawSafe with the wrong msg.sender.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(aaveTestPool));
    vm.prank(investor);
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);

    assertApproxEqRel(aaveTestPoolManagerLogic.totalFundValue(), totalBefore / 2, 0.02e18, "value should ~halve");

    // The investor receives USDe whose value ~= the withdrawn pool-token value (PT unroll + raw USDe, no swap).
    uint256 valueReceived = aaveTestPoolManagerLogic.assetValue(
      tokenToBorrow,
      IERC20Extended(tokenToBorrow).balanceOf(investor)
    );
    assertApproxEqRel(valueReceived, valueToWithdraw, 0.01e18, "received USDe value ~= withdrawn value");
  }

  // (d) off-chain path: PT (underlying==debt) + USDT collateral. The PT is unrolled (no swap, repays directly) and
  //     only USDT is swapped to USDe. That single USDT->USDe swap is mocked via the MOCK routerKey (real Odos routes
  //     USDe through a pool that cannot execute in a Foundry fork); nothing else is mocked.
  function test_withdrawSafe_offchain_pt_unrolled_and_usdt_swapped() public {
    skip(1 days); // clear the deposit lock (dh11) and exit cooldown (dh3)
    _supply(); // PT-USDe
    _setEMode();
    _supplyExtra(token1ToLend, token1AmountNormalized * (10 ** IERC20Extended(token1ToLend).decimals())); // USDT
    _borrowDebt(); // USDe

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    uint256 valueToWithdraw = (aaveTestPool.tokenPrice() * amountToWithdraw) / 1e18;
    uint256 totalBefore = aaveTestPoolManagerLogic.totalFundValue();

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 170; // 1.7%

    vm.prank(address(this), address(0)); // tx.origin == 0 to satisfy `cannotExecute`
    AaveLendingPoolAssetGuard.SwapDataParams memory p = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    // PT excluded (its underlying == debt) -> only USDT is swapped, and no degenerate src==dst entry exists.
    assertEq(p.srcData.length, 1, "only USDT should be swapped");
    assertTrue(p.srcData[0].asset != p.dstData.asset, "no degenerate src==dst entry");

    withdrawData.destData.destToken = IERC20(p.dstData.asset);
    withdrawData.destData.minDestAmount = p.dstData.amount;

    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](p.srcData.length);
    for (uint256 i = 0; i < srcData.length; i++) {
      srcData[i].token = IERC20(p.srcData[i].asset);
      srcData[i].amount = p.srcData[i].amount;
      srcData[i].aggregatorData.routerKey = bytes32("MOCK");
      srcData[i].aggregatorData.swapData = _buildMockSwap(p.srcData[i].asset, p.dstData.asset, p.srcData[i].amount);
    }
    withdrawData.srcData = abi.encode(srcData);

    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);
    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;
      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    vm.prank(investor);
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);

    assertApproxEqRel(aaveTestPoolManagerLogic.totalFundValue(), totalBefore / 2, 0.02e18, "value should ~halve");
    uint256 valueReceived = aaveTestPoolManagerLogic.assetValue(
      tokenToBorrow,
      IERC20Extended(tokenToBorrow).balanceOf(investor)
    );
    assertApproxEqRel(valueReceived, valueToWithdraw, 0.02e18, "received USDe value ~= withdrawn value");
  }

  // (e) on-chain path reverts when a PT's underlying != the repay asset. Here we borrow USDT (eMode 10 allows
  //     stablecoin borrow against PT-USDe), so the PT's underlying (USDe) != repay (USDT): unrolling it leaves USDe
  //     that still needs swapping, which the on-chain path does not support -> revert, requiring offchain swap data.
  function test_withdrawSafe_onchain_reverts_when_pt_underlying_not_repay_asset() public {
    skip(1 days); // clear the deposit lock (dh11) and exit cooldown (dh3)
    _supply(); // PT-USDe

    vm.prank(manager);
    aaveTestPool.execTransaction(aaveV3Pool, abi.encodeWithSelector(IAaveV3Pool.setUserEMode.selector, uint8(10)));
    uint256 borrowAmount = 1000 * (10 ** IERC20Extended(token1ToLend).decimals()); // USDT
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.borrow.selector, token1ToLend, borrowAmount, 2, 0, address(aaveTestPool))
    );

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    // Empty complex data -> empty withdrawData -> on-chain path. PT-USDe's underlying (USDe) != repay asset (USDT).
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(aaveTestPool));
    vm.prank(investor);
    vm.expectRevert("pt requires offchain data");
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }
}
