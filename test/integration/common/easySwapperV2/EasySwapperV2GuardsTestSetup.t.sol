// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {EasySwapperV2ContractGuard} from "contracts/guards/contractGuards/EasySwapperV2ContractGuard.sol";
import {EasySwapperV2UnrolledAssetsGuard} from "contracts/guards/assetGuards/EasySwapperV2UnrolledAssetsGuard.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {ISwapDataConsumingGuard} from "contracts/interfaces/guards/ISwapDataConsumingGuard.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @notice Manager-facing EasySwapperV2ContractGuard flows: vault-in-vault deposits into a nested
/// dHEDGE (Toros-style) pool, initWithdrawal/completeWithdrawal validation, and the
/// EasySwapperV2UnrolledAssetsGuard withdrawProcessing paths for depositors.
/// Swap-dependent zap happy paths need real aggregator swap data and live in the FFI suite.
abstract contract EasySwapperV2GuardsTestSetup is BackboneSetup {
  uint16 internal constant GUARD_MAX_SLIPPAGE_TOLERANCE = 200; // 2%
  uint256 internal constant TOROS_SEED_AMOUNT = 500e6;
  uint256 internal constant TEST_DEPOSIT_AMOUNT = 500e6;

  address internal torosDepositor = makeAddr("torosDepositor");

  PoolLogic internal torosPool;
  PoolLogic internal testFund;
  PoolManagerLogic internal testFundManagerLogic;

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    // Manager-side guard for EasySwapperV2 with 2% max swap slippage tolerance.
    EasySwapperV2ContractGuard easySwapperV2ContractGuard = new EasySwapperV2ContractGuard(
      address(slippageAccumulator),
      GUARD_MAX_SLIPPAGE_TOLERANCE
    );
    governance.setContractGuard({
      extContract: address(easySwapperV2Proxy),
      guardAddress: address(easySwapperV2ContractGuard)
    });

    // EasySwapperV2UnrolledAssetsGuard requires the PoolLimitOrderManager.
    address poolLimitOrderManager = deployCode("PoolLimitOrderManager.sol:PoolLimitOrderManager");
    address poolLimitOrderManagerProxy = address(
      new TransparentUpgradeableProxy(poolLimitOrderManager, proxyAdmin, "")
    );
    (bool success, ) = poolLimitOrderManagerProxy.call(
      abi.encodeWithSignature(
        "initialize(address,address,address,uint16,address)",
        owner,
        address(poolFactoryProxy),
        address(easySwapperV2Proxy),
        uint16(100), // 1% default slippage tolerance
        usdcData.asset
      )
    );
    require(success, "PoolLimitOrderManager init failed");

    governance.setAssetGuard(
      uint16(AssetTypeIncomplete.EASYSWAPPER_V2_UNROLLED),
      address(new EasySwapperV2UnrolledAssetsGuard(poolLimitOrderManagerProxy))
    );

    vm.stopPrank();

    // Nested dHEDGE pool (Toros-style) the test fund is going to trade, with a 0.1% entry fee.
    IHasSupportedAsset.Asset[] memory torosPoolAssets = _toSupportedAssets(usdcData.asset, true);

    vm.startPrank(manager);
    torosPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "TorosPool",
        _fundSymbol: "TRP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 10, // 0.1%
        _exitFeeNum: 0,
        _supportedAssets: torosPoolAssets
      })
    );

    vm.stopPrank();

    // The nested pool must be a valid asset before any fund can list it as supported.
    address torosPoolAggregator = deployCode("DHedgePoolAggregator.sol:DHedgePoolAggregator", abi.encode(torosPool));

    IAssetHandler.Asset[] memory assetsToAdd = new IAssetHandler.Asset[](2);
    assetsToAdd[0] = IAssetHandler.Asset({
      asset: address(torosPool),
      assetType: uint16(AssetTypeIncomplete.CHAINLINK),
      aggregator: torosPoolAggregator
    });
    assetsToAdd[1] = IAssetHandler.Asset({
      asset: address(easySwapperV2Proxy),
      assetType: uint16(AssetTypeIncomplete.EASYSWAPPER_V2_UNROLLED),
      aggregator: address(usdPriceAggregator)
    });

    vm.startPrank(owner);
    assetHandlerProxy.addAssets(assetsToAdd);

    EasySwapperV2.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2.WhitelistSetting[](1);
    whitelistSettings[0] = EasySwapperV2.WhitelistSetting({toWhitelist: address(torosPool), whitelisted: true});
    easySwapperV2Proxy.setCustomCooldownWhitelist(whitelistSettings);
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory testFundAssets = new IHasSupportedAsset.Asset[](3);
    testFundAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    testFundAssets[1] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});
    testFundAssets[2] = IHasSupportedAsset.Asset({asset: address(torosPool), isDeposit: true});

    vm.prank(manager);
    testFund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "TestFund",
        _fundSymbol: "TFD",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: testFundAssets
      })
    );

    testFundManagerLogic = PoolManagerLogic(testFund.poolManagerLogic());

    // Seed the nested pool so it has non-zero supply and a sane token price.
    _makeDeposit(torosPool, torosDepositor, usdcData.asset, TOROS_SEED_AMOUNT);
  }

  /* ========== GENERIC GUARD ========== */

  function test_revert_when_manager_calls_disallowed_function() public {
    _enableEasySwapperV2Asset();

    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(EasySwapperV2.partialWithdraw.selector, 1e18, manager, uint8(0))
    );
  }

  /* ========== DEPOSITS ========== */

  function test_manager_can_depositWithCustomCooldown() public {
    _makeDeposit(testFund, investor, usdcData.asset, TEST_DEPOSIT_AMOUNT);

    assertApproxEqRel(testFund.tokenPrice(), 1e18, 0.001e18); // 0.1%
    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();

    uint256 expectedAmountReceived = _managerDepositIntoToros(TEST_DEPOSIT_AMOUNT);

    assertGe(testFundManagerLogic.assetBalance(address(torosPool)), expectedAmountReceived);
    assertApproxEqRel(testFundManagerLogic.totalFundValue(), totalFundValueBefore, 0.002e18); // 0.2% (0.1% entry fee)
    assertApproxEqRel(testFund.tokenPrice(), 1e18, 0.002e18);
  }

  function test_revert_deposits_when_destination_asset_not_supported() public {
    _makeDeposit(testFund, investor, usdcData.asset, TEST_DEPOSIT_AMOUNT);

    vm.startPrank(manager);
    testFundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(address(torosPool)));

    vm.expectRevert("unsupported destination asset");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSignature(
        "depositWithCustomCooldown(address,address,uint256,uint256)",
        address(torosPool),
        usdcData.asset,
        TEST_DEPOSIT_AMOUNT,
        0
      )
    );

    EasySwapperV2.SingleInSingleOutData memory stubSwapData = EasySwapperV2.SingleInSingleOutData({
      srcData: ISwapper.SrcTokenSwapDetails({
        token: IERC20(daiData.asset),
        amount: 0,
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32(0), swapData: ""})
      }),
      destData: ISwapper.DestData({destToken: IERC20(usdcData.asset), minDestAmount: 0})
    });

    vm.expectRevert("unsupported destination asset");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodePacked(
        bytes4(
          keccak256(
            "zapDepositWithCustomCooldown(address,((address,uint256,(bytes32,bytes)),(address,uint256)),uint256)"
          )
        ),
        abi.encode(address(torosPool), stubSwapData, uint256(0))
      )
    );

    vm.stopPrank();
  }

  /* ========== WITHDRAWALS: initWithdrawal VALIDATION ========== */

  function test_revert_initWithdrawal_when_easySwapperV2_asset_not_enabled() public {
    _depositAndEnterToros();

    // EasySwapperV2 tracking asset deliberately not enabled.
    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(EasySwapperV2.initWithdrawal.selector, address(torosPool), 0, _torosComplexAssetsData(100))
    );
  }

  function test_revert_initWithdrawal_when_slippage_beyond_allowed() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    vm.prank(manager);
    vm.expectRevert("beyond allowed slippage");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(
        EasySwapperV2.initWithdrawal.selector,
        address(torosPool),
        0,
        _torosComplexAssetsData(2000)
      )
    );
  }

  function test_revert_initWithdrawal_when_zero_slippage() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    vm.prank(manager);
    vm.expectRevert("0 slippage not allowed");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(EasySwapperV2.initWithdrawal.selector, address(torosPool), 0, _torosComplexAssetsData(0))
    );
  }

  function test_revert_initWithdrawal_when_slippage_tolerance_mismatch() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _torosComplexAssetsData(200);
    complexAssetsData[0].withdrawData = _encodeComplexAssetSwapData(usdcData.asset, 100);

    vm.prank(manager);
    vm.expectRevert("slippage tolerance mismatch");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(EasySwapperV2.initWithdrawal.selector, address(torosPool), 0, complexAssetsData)
    );
  }

  function test_revert_initWithdrawal_when_invalid_dst_asset() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _torosComplexAssetsData(200);
    // testFund itself is not a valid asset in the AssetHandler.
    complexAssetsData[0].withdrawData = _encodeComplexAssetSwapData(address(testFund), 200);

    vm.prank(manager);
    vm.expectRevert("invalid dst asset");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(EasySwapperV2.initWithdrawal.selector, address(torosPool), 0, complexAssetsData)
    );
  }

  function test_revert_initWithdrawal_when_invalid_src_asset() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](1);
    srcData[0] = ISwapper.SrcTokenSwapDetails({
      token: IERC20(manager), // not a valid asset
      amount: 0,
      aggregatorData: ISwapper.AggregatorData({routerKey: bytes32(0), swapData: ""})
    });

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _torosComplexAssetsData(200);
    complexAssetsData[0].withdrawData = abi.encode(
      ISwapDataConsumingGuard.ComplexAssetSwapData({
        srcData: abi.encode(srcData),
        destData: ISwapper.DestData({destToken: IERC20(usdcData.asset), minDestAmount: 0}),
        slippageTolerance: 200
      })
    );

    vm.prank(manager);
    vm.expectRevert("invalid src asset");
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(EasySwapperV2.initWithdrawal.selector, address(torosPool), 0, complexAssetsData)
    );
  }

  function test_revert_initWithdrawal_when_complexAsset_mismatches_supported_asset() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    uint256 torosAmountToWithdraw = testFundManagerLogic.assetBalance(address(torosPool)) / 2;

    // Entries with withdrawData must align pairwise with the nested pool's supported assets;
    // naming DAI instead of its USDC breaks the match.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _torosComplexAssetsData(100);
    complexAssetsData[0].supportedAsset = daiData.asset;
    complexAssetsData[0].withdrawData = _encodeComplexAssetSwapData(usdcData.asset, 100);

    vm.startPrank(manager);
    testFund.execTransaction(
      address(torosPool),
      abi.encodeWithSelector(IERC20.approve.selector, address(easySwapperV2Proxy), torosAmountToWithdraw)
    );

    vm.expectRevert(bytes("dh19"));
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(
        EasySwapperV2.initWithdrawal.selector,
        address(torosPool),
        torosAmountToWithdraw,
        complexAssetsData
      )
    );
    vm.stopPrank();
  }

  function test_revert_initWithdrawal_when_withdrawData_supplied_for_simple_asset() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    uint256 torosAmountToWithdraw = testFundManagerLogic.assetBalance(address(torosPool)) / 2;

    // USDC inside the nested pool is a simple asset; supplying withdrawData for it reverts
    // (without a reason string) since no swap-data consuming guard exists for it.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _torosComplexAssetsData(100);
    complexAssetsData[0].withdrawData = _encodeComplexAssetSwapData(usdcData.asset, 100);

    vm.startPrank(manager);
    testFund.execTransaction(
      address(torosPool),
      abi.encodeWithSelector(IERC20.approve.selector, address(easySwapperV2Proxy), torosAmountToWithdraw)
    );

    vm.expectRevert();
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(
        EasySwapperV2.initWithdrawal.selector,
        address(torosPool),
        torosAmountToWithdraw,
        complexAssetsData
      )
    );
    vm.stopPrank();
  }

  function test_manager_initWithdrawal_preserves_total_fund_value() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();

    _managerInitWithdrawalHalf();

    assertEq(testFundManagerLogic.totalFundValue(), totalFundValueBefore);
  }

  /* ========== WITHDRAWALS: completeWithdrawal ========== */

  function test_manager_can_completeWithdrawal_to_single_asset_without_swaps() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();
    _managerInitWithdrawalHalf();

    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();

    IWithdrawalVault.TrackedAsset[] memory trackedAssets = easySwapperV2Proxy.getTrackedAssets(address(testFund));
    assertEq(trackedAssets.length, 1);
    assertEq(trackedAssets[0].token, usdcData.asset);

    vm.prank(manager);
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      _encodeCompleteWithdrawalSingle(usdcData.asset, trackedAssets[0].balance)
    );

    assertEq(easySwapperV2Proxy.getTrackedAssets(address(testFund)).length, 0);
    assertGe(IERC20(usdcData.asset).balanceOf(address(testFund)), trackedAssets[0].balance);
    assertApproxEqRel(testFundManagerLogic.totalFundValue(), totalFundValueBefore, 0.001e18);
  }

  function test_revert_completeWithdrawal_single_when_dest_asset_not_enabled() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    vm.prank(manager);
    testFundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(daiData.asset));

    _managerInitWithdrawalHalf();

    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testFund.execTransaction(address(easySwapperV2Proxy), _encodeCompleteWithdrawalSingle(daiData.asset, 0));
  }

  function test_revert_completeWithdrawal_single_when_swap_slippage_too_high() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();
    _managerInitWithdrawalHalf();

    // Vault tracks ~250 USDC; asking for only ~200 DAI out implies >2% slippage on the swap.
    vm.prank(manager);
    vm.expectRevert("swap slippage too high");
    testFund.execTransaction(address(easySwapperV2Proxy), _encodeCompleteWithdrawalSingle(daiData.asset, 200e18));
  }

  function test_manager_can_completeWithdrawal_to_multiple_assets() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();
    _managerInitWithdrawalHalf();

    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = easySwapperV2Proxy.getTrackedAssets(address(testFund));
    assertEq(trackedAssets.length, 1);

    vm.prank(manager);
    testFund.execTransaction(address(easySwapperV2Proxy), abi.encodeWithSignature("completeWithdrawal()"));

    assertEq(easySwapperV2Proxy.getTrackedAssets(address(testFund)).length, 0);
    assertGe(IERC20(usdcData.asset).balanceOf(address(testFund)), trackedAssets[0].balance);
    assertApproxEqRel(testFundManagerLogic.totalFundValue(), totalFundValueBefore, 0.0001e18);
  }

  function test_revert_completeWithdrawal_multiple_when_tracked_asset_not_enabled() public {
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();
    _managerInitWithdrawalHalf();

    // All USDC has been deposited into the nested pool, so USDC can be removed from the fund.
    vm.startPrank(manager);
    testFundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(usdcData.asset));

    vm.expectRevert("unsupported destination asset");
    testFund.execTransaction(address(easySwapperV2Proxy), abi.encodeWithSignature("completeWithdrawal()"));
    vm.stopPrank();
  }

  /* ========== WITHDRAWALS: DEPOSITOR PATHS ========== */

  function test_depositor_can_withdraw_after_initWithdrawal() public {
    // Exercises EasySwapperV2UnrolledAssetsGuard withdrawProcessing with a NON-ZERO vault balance.
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);
    uint256 investorTorosBefore = torosPool.balanceOf(investor);
    uint256 balanceToWithdraw = testFund.balanceOf(investor) / 2;

    _managerInitWithdrawalHalf();

    vm.prank(investor);
    testFund.withdraw(balanceToWithdraw);

    // The fund's nested position is ~499.5 after the 0.1% entry fee; investor gets a quarter of it
    // as USDC (from the withdrawal vault) and a quarter as nested pool tokens.
    assertApproxEqRel(testFundManagerLogic.totalFundValue(), totalFundValueBefore / 2, 0.0001e18);
    assertApproxEqRel(IERC20(usdcData.asset).balanceOf(investor), investorUsdcBefore + 124.875e6, 0.001e18);
    assertApproxEqRel(torosPool.balanceOf(investor), investorTorosBefore + 124.875e18, 0.001e18);
  }

  function test_depositor_can_withdraw_before_initWithdrawal_with_easySwapperV2_asset_enabled() public {
    // Exercises EasySwapperV2UnrolledAssetsGuard withdrawProcessing with a ZERO vault balance.
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);
    uint256 investorTorosBefore = torosPool.balanceOf(investor);
    uint256 balanceToWithdraw = testFund.balanceOf(investor) / 2;

    vm.prank(investor);
    testFund.withdraw(balanceToWithdraw);

    assertApproxEqRel(testFundManagerLogic.totalFundValue(), totalFundValueBefore / 2, 0.0001e18);
    assertEq(IERC20(usdcData.asset).balanceOf(investor), investorUsdcBefore);
    assertApproxEqRel(torosPool.balanceOf(investor), investorTorosBefore + 249.75e18, 0.001e18);
  }

  function test_depositor_can_single_asset_withdraw_after_initWithdrawal() public {
    // Exercises EasySwapperV2 _unrollAssets when the EasySwapperV2 asset has a NON-ZERO balance.
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);
    uint256 investorTorosBefore = torosPool.balanceOf(investor);
    uint256 balanceToWithdraw = testFund.balanceOf(investor) / 2;

    _managerInitWithdrawalHalf();

    _depositorSingleAssetWithdrawal(balanceToWithdraw);

    assertApproxEqRel(testFundManagerLogic.totalFundValue(), totalFundValueBefore / 2, 0.0001e18);
    assertApproxEqRel(IERC20(usdcData.asset).balanceOf(investor), investorUsdcBefore + 249.75e6, 0.001e18);
    assertEq(torosPool.balanceOf(investor), investorTorosBefore);
  }

  function test_depositor_can_single_asset_withdraw_before_initWithdrawal() public {
    // Exercises EasySwapperV2 _unrollAssets when the EasySwapperV2 asset has a ZERO balance.
    _depositAndEnterToros();
    _enableEasySwapperV2Asset();

    uint256 totalFundValueBefore = testFundManagerLogic.totalFundValue();
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);
    uint256 investorTorosBefore = torosPool.balanceOf(investor);
    uint256 balanceToWithdraw = testFund.balanceOf(investor) / 2;

    _depositorSingleAssetWithdrawal(balanceToWithdraw);

    assertApproxEqRel(testFundManagerLogic.totalFundValue(), totalFundValueBefore / 2, 0.0001e18);
    assertApproxEqRel(IERC20(usdcData.asset).balanceOf(investor), investorUsdcBefore + 249.75e6, 0.001e18);
    assertEq(torosPool.balanceOf(investor), investorTorosBefore);
  }

  /* ========== HELPERS ========== */

  /// @dev Investor funds the test fund with USDC, manager deposits it all into the nested pool,
  /// then time passes beyond both the custom cooldown and the investor's lockup.
  function _depositAndEnterToros() internal {
    _makeDeposit(testFund, investor, usdcData.asset, TEST_DEPOSIT_AMOUNT);
    _managerDepositIntoToros(TEST_DEPOSIT_AMOUNT);
    vm.warp(block.timestamp + 1 days + 1);
  }

  function _managerDepositIntoToros(uint256 _usdcAmount) internal returns (uint256 expectedAmountReceived) {
    expectedAmountReceived = easySwapperV2Proxy.depositQuote(address(torosPool), usdcData.asset, _usdcAmount);

    vm.startPrank(manager);
    testFund.execTransaction(
      usdcData.asset,
      abi.encodeWithSelector(IERC20.approve.selector, address(easySwapperV2Proxy), _usdcAmount)
    );
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSignature(
        "depositWithCustomCooldown(address,address,uint256,uint256)",
        address(torosPool),
        usdcData.asset,
        _usdcAmount,
        expectedAmountReceived
      )
    );
    vm.stopPrank();
  }

  function _enableEasySwapperV2Asset() internal {
    vm.prank(manager);
    testFundManagerLogic.changeAssets(_toSupportedAssets(address(easySwapperV2Proxy), false), new address[](0));
  }

  function _managerInitWithdrawalHalf() internal {
    uint256 torosAmountToWithdraw = testFundManagerLogic.assetBalance(address(torosPool)) / 2;

    vm.startPrank(manager);
    testFund.execTransaction(
      address(torosPool),
      abi.encodeWithSelector(IERC20.approve.selector, address(easySwapperV2Proxy), torosAmountToWithdraw)
    );
    testFund.execTransaction(
      address(easySwapperV2Proxy),
      abi.encodeWithSelector(
        EasySwapperV2.initWithdrawal.selector,
        address(torosPool),
        torosAmountToWithdraw,
        _torosComplexAssetsData(100)
      )
    );
    vm.stopPrank();
  }

  function _depositorSingleAssetWithdrawal(uint256 _poolTokenAmount) internal {
    vm.startPrank(investor);
    testFund.approve(address(easySwapperV2Proxy), _poolTokenAmount);
    easySwapperV2Proxy.initWithdrawal(
      address(testFund),
      _poolTokenAmount,
      _getEmptyPoolComplexAssetsData(address(testFund))
    );
    easySwapperV2Proxy.completeWithdrawal();
    vm.stopPrank();
  }

  function _torosComplexAssetsData(
    uint256 _slippageTolerance
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    complexAssetsData = new IPoolLogic.ComplexAsset[](1);
    complexAssetsData[0] = IPoolLogic.ComplexAsset({
      supportedAsset: usdcData.asset,
      withdrawData: "",
      slippageTolerance: _slippageTolerance
    });
  }

  function _encodeComplexAssetSwapData(
    address _destToken,
    uint256 _slippageTolerance
  ) internal pure returns (bytes memory withdrawData) {
    withdrawData = abi.encode(
      ISwapDataConsumingGuard.ComplexAssetSwapData({
        srcData: abi.encode(new ISwapper.SrcTokenSwapDetails[](0)),
        destData: ISwapper.DestData({destToken: IERC20(_destToken), minDestAmount: 0}),
        slippageTolerance: _slippageTolerance
      })
    );
  }

  function _encodeCompleteWithdrawalSingle(
    address _destToken,
    uint256 _expectedDestTokenAmount
  ) internal pure returns (bytes memory txData) {
    // minDestAmount refers to swap output only; these tests never swap, so it stays 0 while the
    // outer expected amount drives both the guard's slippage check and the vault's final check.
    IWithdrawalVault.MultiInSingleOutData memory swapData = IWithdrawalVault.MultiInSingleOutData({
      srcData: new ISwapper.SrcTokenSwapDetails[](0),
      destData: ISwapper.DestData({destToken: IERC20(_destToken), minDestAmount: 0})
    });

    txData = abi.encodePacked(
      bytes4(keccak256("completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)")),
      abi.encode(swapData, _expectedDestTokenAmount)
    );
  }
}
