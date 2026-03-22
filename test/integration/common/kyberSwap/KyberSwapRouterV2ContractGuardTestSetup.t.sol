// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {KyberSwapRouterV2ContractGuard} from "contracts/guards/contractGuards/kyberSwap/KyberSwapRouterV2ContractGuard.sol";
import {IMetaAggregationRouterV2} from "contracts/interfaces/kyberSwap/IMetaAggregationRouterV2.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {KyberSwapAPIHelper} from "./KyberSwapAPIHelper.sol";

abstract contract KyberSwapRouterV2ContractGuardTestSetup is BackboneSetup, KyberSwapAPIHelper {
  address private immutable kyberSwapRouterV2;
  uint256 private immutable chainId;

  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;
  KyberSwapRouterV2ContractGuard private kyberSwapRouterV2ContractGuard;

  constructor(address _kyberSwapRouterV2, uint256 _chainId) {
    kyberSwapRouterV2 = _kyberSwapRouterV2;
    chainId = _chainId;
  }

  function setUp() public virtual override {
    super.setUp();
    __KyberSwapAPIHelper_init(true);

    kyberSwapRouterV2ContractGuard = new KyberSwapRouterV2ContractGuard(address(slippageAccumulator));

    vm.prank(owner);
    governance.setContractGuard({
      extContract: kyberSwapRouterV2,
      guardAddress: address(kyberSwapRouterV2ContractGuard)
    });

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "KyberSwap Test Vault",
        _fundSymbol: "KTV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    _makeDeposit(testPool, investor, usdcData.asset, 10000e6);

    bytes memory approveCallData = abi.encodeWithSelector(
      IERC20.approve.selector,
      kyberSwapRouterV2,
      type(uint256).max
    );

    vm.startPrank(manager);
    testPool.execTransaction(usdcData.asset, approveCallData);
    testPool.execTransaction(daiData.asset, approveCallData);
    vm.stopPrank();
  }

  // Helper function to create test swap data
  function _createSwapExecutionParams(
    address srcToken,
    address dstToken,
    address dstReceiver,
    uint256 amount,
    uint256 minReturnAmount
  ) internal pure returns (IMetaAggregationRouterV2.SwapExecutionParams memory) {
    return
      IMetaAggregationRouterV2.SwapExecutionParams({
        callTarget: address(0),
        approveTarget: address(0),
        targetData: "",
        desc: _createSwapDescriptionV2(srcToken, dstToken, dstReceiver, amount, minReturnAmount),
        clientData: ""
      });
  }

  function _createSwapDescriptionV2(
    address srcToken,
    address dstToken,
    address dstReceiver,
    uint256 amount,
    uint256 minReturnAmount
  ) internal pure returns (IMetaAggregationRouterV2.SwapDescriptionV2 memory) {
    return
      IMetaAggregationRouterV2.SwapDescriptionV2({
        srcToken: srcToken,
        dstToken: dstToken,
        srcReceivers: new address[](0),
        srcAmounts: new uint256[](0),
        feeReceivers: new address[](0),
        feeAmounts: new uint256[](0),
        dstReceiver: dstReceiver,
        amount: amount,
        minReturnAmount: minReturnAmount,
        flags: 0,
        permit: ""
      });
  }

  // Test: constructor revert - invalid address
  function test_revert_constructor_invalid_slippage_accumulator() public {
    vm.expectRevert("invalid address");
    new KyberSwapRouterV2ContractGuard(address(0));
  }

  // Test: _accessControl revert - caller not pool logic for txGuard
  function test_revert_txguard_caller_is_not_pool_logic() public {
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    vm.expectRevert("not pool logic");
    kyberSwapRouterV2ContractGuard.txGuard(address(testPoolManagerLogic), kyberSwapRouterV2, callData);
  }

  // Test: _accessControl revert - caller not pool logic for afterTxGuard
  function test_revert_aftertxguard_caller_is_not_pool_logic() public {
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    vm.expectRevert("not pool logic");
    kyberSwapRouterV2ContractGuard.afterTxGuard(address(testPoolManagerLogic), kyberSwapRouterV2, callData);
  }

  // Test: recipient is not pool - swap method
  function test_revert_swap_recipient_is_not_pool() public {
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      manager, // Wrong recipient
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: recipient is not pool - swapSimpleMode method
  function test_revert_swap_simple_mode_recipient_is_not_pool() public {
    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = _createSwapDescriptionV2(
      usdcData.asset,
      daiData.asset,
      manager, // Wrong recipient
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(
      IMetaAggregationRouterV2.swapSimpleMode.selector,
      address(0),
      desc,
      "",
      ""
    );

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: unsupported destination asset - swap method
  function test_revert_swap_unsupported_destination_asset() public {
    // Create a random token address that's not supported
    address unsupportedToken = address(0x1234567890123456789012345678901234567890);

    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      unsupportedToken,
      address(testPool),
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: unsupported destination asset - swapSimpleMode method
  function test_revert_swap_simple_mode_unsupported_destination_asset() public {
    // Create a random token address that's not supported
    address unsupportedToken = address(0x1234567890123456789012345678901234567890);

    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = _createSwapDescriptionV2(
      usdcData.asset,
      unsupportedToken,
      address(testPool),
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(
      IMetaAggregationRouterV2.swapSimpleMode.selector,
      address(0),
      desc,
      "",
      ""
    );

    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: fees not supported - swap method
  function test_revert_swap_fees_not_supported() public {
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );

    // Add fee receivers to trigger the revert
    execution.desc.feeReceivers = new address[](1);
    execution.desc.feeReceivers[0] = address(0x1111);
    execution.desc.feeAmounts = new uint256[](1);
    execution.desc.feeAmounts[0] = 100;

    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    vm.prank(manager);
    vm.expectRevert("fees not supported");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: fees not supported - swapSimpleMode method
  function test_revert_swap_simple_mode_fees_not_supported() public {
    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = _createSwapDescriptionV2(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );

    // Add fee receivers to trigger the revert
    desc.feeReceivers = new address[](1);
    desc.feeReceivers[0] = address(0x1111);
    desc.feeAmounts = new uint256[](1);
    desc.feeAmounts[0] = 100;

    bytes memory callData = abi.encodeWithSelector(
      IMetaAggregationRouterV2.swapSimpleMode.selector,
      address(0),
      desc,
      "",
      ""
    );

    vm.prank(manager);
    vm.expectRevert("fees not supported");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: permit not supported - swap method
  function test_revert_swap_permit_not_supported() public {
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );

    // Add permit data to trigger the revert
    execution.desc.permit = "0x1234";

    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    vm.prank(manager);
    vm.expectRevert("permit not supported");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: permit not supported - swapSimpleMode method
  function test_revert_swap_simple_mode_permit_not_supported() public {
    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = _createSwapDescriptionV2(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );

    // Add permit data to trigger the revert
    desc.permit = "0x1234";

    bytes memory callData = abi.encodeWithSelector(
      IMetaAggregationRouterV2.swapSimpleMode.selector,
      address(0),
      desc,
      "",
      ""
    );

    vm.prank(manager);
    vm.expectRevert("permit not supported");
    testPool.execTransaction(kyberSwapRouterV2, callData);
  }

  // Test: unsupported destination asset in afterTxGuard - swap method
  function test_revert_aftertxguard_swap_unsupported_destination_asset() public {
    // Create valid swap execution params
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );

    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    // First remove WETH as supported asset to trigger the afterTxGuard check
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory assets;
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = daiData.asset;
    testPoolManagerLogic.changeAssets(assets, removeAssets);
    vm.stopPrank();

    // Now calling afterTxGuard should fail with unsupported destination asset
    vm.expectRevert("unsupported destination asset");
    vm.prank(address(testPool));
    kyberSwapRouterV2ContractGuard.afterTxGuard(address(testPoolManagerLogic), kyberSwapRouterV2, callData);
  }

  // Test: unsupported destination asset in afterTxGuard - swapSimpleMode method
  function test_revert_aftertxguard_swap_simple_mode_unsupported_destination_asset() public {
    // Create valid swap description
    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = _createSwapDescriptionV2(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );

    bytes memory callData = abi.encodeWithSelector(
      IMetaAggregationRouterV2.swapSimpleMode.selector,
      address(0),
      desc,
      "",
      ""
    );

    // First remove WETH as supported asset to trigger the afterTxGuard check
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory assets;
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = daiData.asset;
    testPoolManagerLogic.changeAssets(assets, removeAssets);
    vm.stopPrank();

    // Now calling afterTxGuard should fail with unsupported destination asset
    vm.expectRevert("unsupported destination asset");
    vm.prank(address(testPool));
    kyberSwapRouterV2ContractGuard.afterTxGuard(address(testPoolManagerLogic), kyberSwapRouterV2, callData);
  }

  // Test: unsupported source asset in afterTxGuard
  function test_revert_aftertxguard_unsupported_source_asset() public {
    // Create a test pool with just WETH as supported asset
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});

    PoolLogic testPool2 = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Test Pool 2",
        _fundSymbol: "TP2",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    PoolManagerLogic testPool2ManagerLogic = PoolManagerLogic(testPool2.poolManagerLogic());

    // Add USDC as supported asset temporarily
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    testPool2ManagerLogic.changeAssets(assetsToAdd, new address[](0));
    vm.stopPrank();

    // Create swap data that uses USDC as source asset
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      address(testPool2),
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    // Call txGuard to set up the source asset check (this will set the flag for USDC)
    vm.prank(address(testPool2));
    kyberSwapRouterV2ContractGuard.txGuard(address(testPool2ManagerLogic), kyberSwapRouterV2, callData);

    // Now remove USDC as supported asset
    vm.startPrank(manager);
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = usdcData.asset;
    testPool2ManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);
    vm.stopPrank();

    // Now calling afterTxGuard should fail with unsupported source asset
    vm.expectRevert("unsupported source asset");
    vm.prank(address(testPool2));
    kyberSwapRouterV2ContractGuard.afterTxGuard(address(testPool2ManagerLogic), kyberSwapRouterV2, callData);
  }

  // Test: unsupported method selector
  function test_txguard_unsupported_method_returns_zero() public {
    // Create call data with unsupported method selector
    bytes memory callData = abi.encodeWithSelector(bytes4(0x12345678), "test");

    vm.prank(address(testPool));
    (uint16 txType, bool isPublic) = kyberSwapRouterV2ContractGuard.txGuard(
      address(testPoolManagerLogic),
      kyberSwapRouterV2,
      callData
    );

    assertEq(uint256(txType), 0);
    assertEq(isPublic, false);
  }

  // Test: successful txGuard for swap method
  function test_txguard_swap_success() public {
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = _createSwapExecutionParams(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);

    vm.prank(address(testPool));
    (uint16 txType, bool isPublic) = kyberSwapRouterV2ContractGuard.txGuard(
      address(testPoolManagerLogic),
      kyberSwapRouterV2,
      callData
    );

    assertEq(uint256(txType), 2); // TransactionType.Exchange = 2
    assertEq(isPublic, false);
  }

  // Test: successful txGuard for swapSimpleMode method
  function test_txguard_swap_simple_mode_success() public {
    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = _createSwapDescriptionV2(
      usdcData.asset,
      daiData.asset,
      address(testPool),
      1000e6,
      1e17
    );
    bytes memory callData = abi.encodeWithSelector(
      IMetaAggregationRouterV2.swapSimpleMode.selector,
      address(0),
      desc,
      "",
      ""
    );

    vm.prank(address(testPool));
    (uint16 txType, bool isPublic) = kyberSwapRouterV2ContractGuard.txGuard(
      address(testPoolManagerLogic),
      kyberSwapRouterV2,
      callData
    );

    assertEq(uint256(txType), 2); // TransactionType.Exchange = 2
    assertEq(isPublic, false);
  }

  function test_should_be_able_to_swap() public {
    KyberSwapAPIHelper.KyberSwapData memory params = KyberSwapAPIHelper.KyberSwapData({
      srcAmount: 10000e6,
      srcToken: usdcData.asset,
      destToken: daiData.asset,
      user: address(testPool),
      slippageBPS: 10 // 0.1%
    });
    (, bytes memory txData) = getDataFromKyberSwap(params, chainId);

    uint256 valueBefore = testPoolManagerLogic.totalFundValue();

    vm.prank(manager);
    testPool.execTransaction(kyberSwapRouterV2, txData);
    uint256 valueAfter = testPoolManagerLogic.totalFundValue();

    assertApproxEqRel(valueBefore, valueAfter, 0.001e18); // 0.1% tolerance
    assertEq(IERC20(usdcData.asset).balanceOf(address(testPool)), 0);
    assertGt(IERC20(daiData.asset).balanceOf(address(testPool)), 0);
  }

  function test_revert_when_swap_to_native_token() public {
    KyberSwapAPIHelper.KyberSwapData memory params = KyberSwapAPIHelper.KyberSwapData({
      srcAmount: 10000e6,
      srcToken: usdcData.asset,
      destToken: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // Address representing native token
      user: address(testPool),
      slippageBPS: 10 // 0.1%
    });
    (, bytes memory txData) = getDataFromKyberSwap(params, chainId);

    vm.expectRevert("unsupported destination asset");
    vm.prank(manager);
    testPool.execTransaction(kyberSwapRouterV2, txData);
  }

  function test_revert_when_swap_from_native_token() public {
    KyberSwapAPIHelper.KyberSwapData memory params = KyberSwapAPIHelper.KyberSwapData({
      srcAmount: 10000e6,
      srcToken: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // Address representing native token
      destToken: daiData.asset,
      user: address(testPool),
      slippageBPS: 10 // 0.1%
    });
    (, bytes memory txData) = getDataFromKyberSwap(params, chainId);

    vm.expectRevert();
    vm.prank(manager);
    testPool.execTransaction(kyberSwapRouterV2, txData);
  }
}
