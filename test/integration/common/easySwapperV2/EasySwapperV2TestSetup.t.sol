// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {WithdrawalVault} from "contracts/swappers/easySwapperV2/WithdrawalVault.sol";
import {IEasySwapperV2} from "contracts/swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @notice User-facing EasySwapperV2 flows: deposits (plain, custom cooldown, native), withdrawal
/// vault lifecycle, initWithdrawal/completeWithdrawal/unrollAndClaim/partialWithdraw.
abstract contract EasySwapperV2TestSetup is BackboneSetup {
  uint256 internal constant USDC_DEPOSIT_AMOUNT = 1_000e6;
  uint256 internal constant WETH_DEPOSIT_AMOUNT = 1e18;
  uint256 internal constant DAI_DEPOSIT_AMOUNT = 1_000e18;

  PoolLogic internal testPool;
  PoolLogic internal usdcOnlyPool;

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory testPoolAssets = new IHasSupportedAsset.Asset[](3);
    testPoolAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    testPoolAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    testPoolAssets[2] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "EasySwapperV2Test",
        _fundSymbol: "EST",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: testPoolAssets
      })
    );

    IHasSupportedAsset.Asset[] memory usdcOnlyAssets = new IHasSupportedAsset.Asset[](1);
    usdcOnlyAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    usdcOnlyPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "UsdcOnlyPool",
        _fundSymbol: "UOP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: usdcOnlyAssets
      })
    );

    vm.stopPrank();

    EasySwapperV2.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2.WhitelistSetting[](2);
    whitelistSettings[0] = EasySwapperV2.WhitelistSetting({toWhitelist: address(testPool), whitelisted: true});
    whitelistSettings[1] = EasySwapperV2.WhitelistSetting({toWhitelist: address(usdcOnlyPool), whitelisted: true});

    vm.prank(owner);
    easySwapperV2Proxy.setCustomCooldownWhitelist(whitelistSettings);
  }

  /* ========== ADMIN ========== */

  function test_revert_setSwapper_when_not_owner() public {
    vm.prank(investor);
    vm.expectRevert("Ownable: caller is not the owner");
    easySwapperV2Proxy.setSwapper(ISwapper(investor));
  }

  function test_revert_setSwapper_zero_address() public {
    vm.prank(owner);
    vm.expectRevert("invalid address");
    easySwapperV2Proxy.setSwapper(ISwapper(address(0)));
  }

  function test_revert_setCustomCooldownWhitelist_when_not_a_vault() public {
    EasySwapperV2.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2.WhitelistSetting[](1);
    whitelistSettings[0] = EasySwapperV2.WhitelistSetting({toWhitelist: investor, whitelisted: true});

    vm.prank(owner);
    vm.expectRevert("not a vault");
    easySwapperV2Proxy.setCustomCooldownWhitelist(whitelistSettings);
  }

  /* ========== WITHDRAWALS ========== */

  function test_revert_initWithdrawal_when_tokens_locked() public {
    // Direct pool deposits have no lockup in the backbone (factory exit cooldown defaults to 0),
    // so deposit via EasySwapperV2 which applies its default 24-hour cooldown explicitly.
    uint256 expectedAmountReceived = _prepareErc20Deposit(investor, usdcData.asset, USDC_DEPOSIT_AMOUNT);

    vm.startPrank(investor);
    easySwapperV2Proxy.deposit(address(testPool), IERC20(usdcData.asset), USDC_DEPOSIT_AMOUNT, expectedAmountReceived);

    // One hour in, tokens are still locked.
    vm.warp(block.timestamp + 1 hours);

    uint256 poolTokens = testPool.balanceOf(investor);
    testPool.approve(address(easySwapperV2Proxy), poolTokens);
    // Hoisted so the helper's staticcall doesn't consume the expectRevert.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(testPool));
    vm.expectRevert(bytes("dh3"));
    easySwapperV2Proxy.initWithdrawal(address(testPool), poolTokens, complexAssetsData);
    vm.stopPrank();
  }

  function test_withdrawal_vault_lifecycle() public {
    assertEq(easySwapperV2Proxy.withdrawalContracts(investor), address(0));

    _depositAllThreeAssets(investor);
    _initWithdrawalAll(investor);

    address vaultAddress = easySwapperV2Proxy.withdrawalContracts(investor);
    assertTrue(vaultAddress != address(0));

    WithdrawalVault vault = WithdrawalVault(payable(vaultAddress));
    assertEq(vault.depositor(), investor);
    assertEq(vault.creator(), address(easySwapperV2Proxy));

    IWithdrawalVault.TrackedAsset[] memory trackedAssets = vault.getTrackedAssets();
    assertEq(trackedAssets.length, 3);

    for (uint256 i; i < trackedAssets.length; ++i) {
      uint256 vaultBalance = IERC20(trackedAssets[i].token).balanceOf(vaultAddress);
      assertGt(vaultBalance, 0);
      assertEq(vaultBalance, trackedAssets[i].balance);
    }
  }

  function test_revert_withdrawal_vault_functions_when_not_creator() public {
    _depositAllThreeAssets(investor);
    _initWithdrawalAll(investor);

    WithdrawalVault vault = WithdrawalVault(payable(easySwapperV2Proxy.withdrawalContracts(investor)));

    vm.startPrank(investor);

    vm.expectRevert("only creator");
    vault.unrollAssets(address(testPool), new IPoolLogic.ComplexAsset[](0));

    vm.expectRevert("only creator");
    vault.recoverAssets();

    vm.expectRevert("only creator");
    vault.recoverAssets(0, address(testPool));

    vm.expectRevert("only creator");
    vault.swapToSingleAsset(_emptyMultiInSingleOutData(), 0);

    vm.stopPrank();
  }

  function test_revert_completeWithdrawal_single_token_when_vault_not_exists() public {
    vm.prank(investor);
    vm.expectRevert("not exists");
    easySwapperV2Proxy.completeWithdrawal(_emptyMultiInSingleOutData(), 0);
  }

  function test_revert_completeWithdrawal_multiple_tokens_when_vault_not_exists() public {
    vm.prank(investor);
    vm.expectRevert("not exists");
    easySwapperV2Proxy.completeWithdrawal();
  }

  function test_revert_partialWithdraw_when_invalid_portion() public {
    _depositAllThreeAssets(investor);
    _initWithdrawalAll(investor);

    vm.startPrank(investor);

    vm.expectRevert("invalid portion");
    easySwapperV2Proxy.partialWithdraw(0, investor, IEasySwapperV2.WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL);

    vm.expectRevert("invalid portion");
    easySwapperV2Proxy.partialWithdraw(1e18 + 1, investor, IEasySwapperV2.WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL);

    vm.stopPrank();
  }

  function test_partialWithdraw_claims_portion_of_tracked_assets() public {
    _depositAllThreeAssets(investor);
    _initWithdrawalAll(investor);

    address recipient = makeAddr("partialWithdrawRecipient");
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = easySwapperV2Proxy.getTrackedAssets(investor);

    vm.prank(investor);
    easySwapperV2Proxy.partialWithdraw(0.5e18, recipient, IEasySwapperV2.WithdrawalVaultType.SINGLE_ASSET_WITHDRAWAL);

    for (uint256 i; i < trackedAssets.length; ++i) {
      assertApproxEqAbs(IERC20(trackedAssets[i].token).balanceOf(recipient), trackedAssets[i].balance / 2, 1);
    }
  }

  function test_completeWithdrawal_to_multiple_tokens() public {
    _depositAllThreeAssets(investor);
    _initWithdrawalAll(investor);

    address vaultAddress = easySwapperV2Proxy.withdrawalContracts(investor);
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = easySwapperV2Proxy.getTrackedAssets(investor);
    assertEq(trackedAssets.length, 3);

    uint256[] memory investorBalancesBefore = new uint256[](trackedAssets.length);
    for (uint256 i; i < trackedAssets.length; ++i) {
      investorBalancesBefore[i] = IERC20(trackedAssets[i].token).balanceOf(investor);
    }

    vm.prank(investor);
    easySwapperV2Proxy.completeWithdrawal();

    assertEq(easySwapperV2Proxy.getTrackedAssets(investor).length, 0);

    for (uint256 i; i < trackedAssets.length; ++i) {
      assertEq(IERC20(trackedAssets[i].token).balanceOf(vaultAddress), 0);
      assertEq(
        IERC20(trackedAssets[i].token).balanceOf(investor),
        investorBalancesBefore[i] + trackedAssets[i].balance
      );
    }
  }

  function test_completeWithdrawal_to_single_token_without_swaps() public {
    // Pool holds only USDC, so the withdrawal vault tracks a single asset and no swaps are
    // required to complete the withdrawal into USDC.
    _makeDeposit(testPool, investor, usdcData.asset, USDC_DEPOSIT_AMOUNT);
    vm.warp(block.timestamp + 1 days + 1);
    _initWithdrawalAll(investor);

    IWithdrawalVault.TrackedAsset[] memory trackedAssets = easySwapperV2Proxy.getTrackedAssets(investor);
    assertEq(trackedAssets.length, 1);
    assertEq(trackedAssets[0].token, usdcData.asset);

    uint256 investorUsdcBalanceBefore = IERC20(usdcData.asset).balanceOf(investor);

    // minDestAmount refers to swap output only; with no swaps it must be 0, while the outer
    // expected amount still asserts the total the depositor receives.
    IWithdrawalVault.MultiInSingleOutData memory swapData = IWithdrawalVault.MultiInSingleOutData({
      srcData: new ISwapper.SrcTokenSwapDetails[](0),
      destData: ISwapper.DestData({destToken: IERC20(usdcData.asset), minDestAmount: 0})
    });

    vm.prank(investor);
    easySwapperV2Proxy.completeWithdrawal(swapData, trackedAssets[0].balance);

    assertEq(easySwapperV2Proxy.getTrackedAssets(investor).length, 0);
    assertEq(IERC20(usdcData.asset).balanceOf(investor), investorUsdcBalanceBefore + trackedAssets[0].balance);
    assertEq(IERC20(usdcData.asset).balanceOf(easySwapperV2Proxy.withdrawalContracts(investor)), 0);
  }

  function test_unrollAndClaim_to_multiple_tokens() public {
    _depositAllThreeAssets(investor);
    vm.warp(block.timestamp + 1 days + 1);

    uint256 poolTokens = testPool.balanceOf(investor);

    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);
    uint256 investorWethBefore = IERC20(wethData.asset).balanceOf(investor);
    uint256 investorDaiBefore = IERC20(daiData.asset).balanceOf(investor);

    vm.startPrank(investor);
    testPool.approve(address(easySwapperV2Proxy), poolTokens);
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = easySwapperV2Proxy.unrollAndClaim(
      address(testPool),
      poolTokens,
      _getEmptyPoolComplexAssetsData(address(testPool))
    );
    vm.stopPrank();

    assertEq(easySwapperV2Proxy.getTrackedAssets(investor).length, 0);
    assertEq(trackedAssets.length, 3);

    for (uint256 i; i < trackedAssets.length; ++i) {
      uint256 balanceBefore;
      if (trackedAssets[i].token == usdcData.asset) balanceBefore = investorUsdcBefore;
      else if (trackedAssets[i].token == wethData.asset) balanceBefore = investorWethBefore;
      else balanceBefore = investorDaiBefore;

      uint256 balanceAfter = IERC20(trackedAssets[i].token).balanceOf(investor);
      assertApproxEqRel(balanceAfter, balanceBefore + trackedAssets[i].balance, 0.00001e18); // 0.001%
      assertEq(IERC20(trackedAssets[i].token).balanceOf(easySwapperV2Proxy.withdrawalContracts(investor)), 0);
    }
  }

  /* ========== DEPOSITS ========== */

  function test_deposit_applies_default_cooldown() public {
    uint256 expectedAmountReceived = _prepareErc20Deposit(investor, usdcData.asset, USDC_DEPOSIT_AMOUNT);

    vm.prank(investor);
    easySwapperV2Proxy.deposit(address(testPool), IERC20(usdcData.asset), USDC_DEPOSIT_AMOUNT, expectedAmountReceived);

    assertEq(testPool.getExitRemainingCooldown(investor), 1 days);
    assertGe(testPool.balanceOf(investor), expectedAmountReceived);
  }

  function test_depositWithCustomCooldown_applies_custom_cooldown() public {
    uint256 expectedAmountReceived = _prepareErc20Deposit(investor, usdcData.asset, USDC_DEPOSIT_AMOUNT);

    vm.prank(investor);
    easySwapperV2Proxy.depositWithCustomCooldown(
      address(testPool),
      IERC20(usdcData.asset),
      USDC_DEPOSIT_AMOUNT,
      expectedAmountReceived
    );

    assertEq(testPool.getExitRemainingCooldown(investor), 1 hours);
    assertGe(testPool.balanceOf(investor), expectedAmountReceived);
  }

  function test_nativeDeposit_applies_default_cooldown() public {
    uint256 expectedAmountReceived = easySwapperV2Proxy.depositQuote(
      address(testPool),
      wethData.asset,
      WETH_DEPOSIT_AMOUNT
    );

    vm.deal(investor, WETH_DEPOSIT_AMOUNT);
    vm.prank(investor);
    easySwapperV2Proxy.nativeDeposit{value: WETH_DEPOSIT_AMOUNT}(address(testPool), expectedAmountReceived);

    assertEq(testPool.getExitRemainingCooldown(investor), 1 days);
    assertGe(testPool.balanceOf(investor), expectedAmountReceived);
  }

  function test_nativeDepositWithCustomCooldown_applies_custom_cooldown() public {
    uint256 expectedAmountReceived = easySwapperV2Proxy.depositQuote(
      address(testPool),
      wethData.asset,
      WETH_DEPOSIT_AMOUNT
    );

    vm.deal(investor, WETH_DEPOSIT_AMOUNT);
    vm.prank(investor);
    easySwapperV2Proxy.nativeDepositWithCustomCooldown{value: WETH_DEPOSIT_AMOUNT}(
      address(testPool),
      expectedAmountReceived
    );

    assertEq(testPool.getExitRemainingCooldown(investor), 1 hours);
    assertGe(testPool.balanceOf(investor), expectedAmountReceived);
  }

  function test_revert_custom_cooldown_deposits_when_pool_not_whitelisted() public {
    EasySwapperV2.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2.WhitelistSetting[](1);
    whitelistSettings[0] = EasySwapperV2.WhitelistSetting({toWhitelist: address(testPool), whitelisted: false});
    vm.prank(owner);
    easySwapperV2Proxy.setCustomCooldownWhitelist(whitelistSettings);

    EasySwapperV2.SingleInSingleOutData memory stubSwapData = _stubSingleInSingleOutData(
      wethData.asset,
      WETH_DEPOSIT_AMOUNT
    );

    vm.deal(investor, WETH_DEPOSIT_AMOUNT * 2);
    vm.startPrank(investor);

    vm.expectRevert("not whitelisted");
    easySwapperV2Proxy.depositWithCustomCooldown(address(testPool), IERC20(usdcData.asset), USDC_DEPOSIT_AMOUNT, 0);

    vm.expectRevert("not whitelisted");
    easySwapperV2Proxy.nativeDepositWithCustomCooldown{value: WETH_DEPOSIT_AMOUNT}(address(testPool), 0);

    vm.expectRevert("not whitelisted");
    easySwapperV2Proxy.zapDepositWithCustomCooldown(address(testPool), stubSwapData, 0);

    vm.expectRevert("not whitelisted");
    easySwapperV2Proxy.zapNativeDepositWithCustomCooldown{value: WETH_DEPOSIT_AMOUNT}(
      address(testPool),
      stubSwapData,
      0
    );

    vm.stopPrank();
  }

  function test_revert_zap_native_deposits_when_invalid_src_token() public {
    // Src token in swap data must be the wrapped native token.
    EasySwapperV2.SingleInSingleOutData memory stubSwapData = _stubSingleInSingleOutData(
      usdcData.asset,
      WETH_DEPOSIT_AMOUNT
    );

    vm.deal(investor, WETH_DEPOSIT_AMOUNT * 2);
    vm.startPrank(investor);

    vm.expectRevert("invalid src token");
    easySwapperV2Proxy.zapNativeDeposit{value: WETH_DEPOSIT_AMOUNT}(address(testPool), stubSwapData, 0);

    vm.expectRevert("invalid src token");
    easySwapperV2Proxy.zapNativeDepositWithCustomCooldown{value: WETH_DEPOSIT_AMOUNT}(
      address(testPool),
      stubSwapData,
      0
    );

    vm.stopPrank();
  }

  function test_revert_zap_native_deposits_when_src_amount_mismatches_msg_value() public {
    EasySwapperV2.SingleInSingleOutData memory stubSwapData = _stubSingleInSingleOutData(
      wethData.asset,
      WETH_DEPOSIT_AMOUNT - 1
    );

    vm.deal(investor, WETH_DEPOSIT_AMOUNT * 2);
    vm.startPrank(investor);

    vm.expectRevert("invalid src amount");
    easySwapperV2Proxy.zapNativeDeposit{value: WETH_DEPOSIT_AMOUNT}(address(testPool), stubSwapData, 0);

    vm.expectRevert("invalid src amount");
    easySwapperV2Proxy.zapNativeDepositWithCustomCooldown{value: WETH_DEPOSIT_AMOUNT}(
      address(testPool),
      stubSwapData,
      0
    );

    vm.stopPrank();
  }

  function test_revert_native_deposits_when_wrapped_native_not_deposit_asset() public {
    vm.deal(investor, WETH_DEPOSIT_AMOUNT * 2);
    vm.startPrank(investor);

    vm.expectRevert(bytes("dh8"));
    easySwapperV2Proxy.nativeDeposit{value: WETH_DEPOSIT_AMOUNT}(address(usdcOnlyPool), 0);

    vm.expectRevert(bytes("dh8"));
    easySwapperV2Proxy.nativeDepositWithCustomCooldown{value: WETH_DEPOSIT_AMOUNT}(address(usdcOnlyPool), 0);

    vm.stopPrank();
  }

  /* ========== HELPERS ========== */

  function _depositAllThreeAssets(address _depositor) internal {
    _makeDeposit(testPool, _depositor, usdcData.asset, USDC_DEPOSIT_AMOUNT);
    _makeDeposit(testPool, _depositor, wethData.asset, WETH_DEPOSIT_AMOUNT);
    _makeDeposit(testPool, _depositor, daiData.asset, DAI_DEPOSIT_AMOUNT);
    vm.warp(block.timestamp + 1 days + 1);
  }

  function _initWithdrawalAll(address _depositor) internal {
    uint256 poolTokens = testPool.balanceOf(_depositor);

    vm.startPrank(_depositor);
    testPool.approve(address(easySwapperV2Proxy), poolTokens);
    easySwapperV2Proxy.initWithdrawal(address(testPool), poolTokens, _getEmptyPoolComplexAssetsData(address(testPool)));
    vm.stopPrank();
  }

  function _prepareErc20Deposit(
    address _depositor,
    address _token,
    uint256 _amount
  ) internal returns (uint256 expectedAmountReceived) {
    deal(_token, _depositor, _amount);
    vm.prank(_depositor);
    IERC20(_token).approve(address(easySwapperV2Proxy), _amount);
    expectedAmountReceived = easySwapperV2Proxy.depositQuote(address(testPool), _token, _amount);
  }

  function _stubSingleInSingleOutData(
    address _srcToken,
    uint256 _srcAmount
  ) internal view returns (EasySwapperV2.SingleInSingleOutData memory swapData) {
    swapData = EasySwapperV2.SingleInSingleOutData({
      srcData: ISwapper.SrcTokenSwapDetails({
        token: IERC20(_srcToken),
        amount: _srcAmount,
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32(0), swapData: ""})
      }),
      destData: ISwapper.DestData({destToken: IERC20(usdcData.asset), minDestAmount: 0})
    });
  }

  function _emptyMultiInSingleOutData() internal pure returns (IWithdrawalVault.MultiInSingleOutData memory swapData) {
    swapData = IWithdrawalVault.MultiInSingleOutData({
      srcData: new ISwapper.SrcTokenSwapDetails[](0),
      destData: ISwapper.DestData({destToken: IERC20(address(0)), minDestAmount: 0})
    });
  }
}
