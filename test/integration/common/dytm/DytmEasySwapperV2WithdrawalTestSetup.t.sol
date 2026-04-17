// SPDX-License-Identifier: MIT
// solhint-disable no-unused-vars

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DytmDelegationCallTestSetup} from "./DytmDelegationCallTestSetup.t.sol";
import {DytmWithdrawProcessor} from "contracts/swappers/easySwapperV2/libraries/dytm/DytmWithdrawProcessor.sol";
import {DytmOfficeAssetGuard} from "contracts/guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmPeriphery} from "contracts/interfaces/dytm/IDytmPeriphery.sol";
import {IDytmDelegatee} from "contracts/interfaces/dytm/IDytmDelegatee.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {ISwapDataConsumingGuard} from "contracts/interfaces/guards/ISwapDataConsumingGuard.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {Governance} from "contracts/Governance.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {PendlePTAssetGuard} from "contracts/guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {MockPendlePTChainlinkOracle} from "./MockPendlePTChainlinkOracle.sol";
import {OdosAPIHelper} from "../odos/OdosAPIHelper.sol";
import {IPActionMarketCoreStatic} from "contracts/interfaces/pendle/IPActionMarketCoreStatic.sol";
import {IDytmWeights} from "./dytmInterface/IDytmWeights.sol";
import {IMarketConfig} from "./dytmInterface/IDytmMarketConfig.sol";

abstract contract DytmEasySwapperV2WithdrawalTestSetup is DytmDelegationCallTestSetup {
  DytmWithdrawProcessor public dytmProcessor;
  address public investorVault;

  function setUp() public virtual override {
    super.setUp();

    // Deploy DytmWithdrawProcessor
    dytmProcessor = new DytmWithdrawProcessor(dytmOffice, address(dhedgePoolFactory), address(easySwapperV2Instance));

    // Redeploy DytmOfficeAssetGuard with processor address set
    _redeployAssetGuardWithProcessor(address(dytmProcessor));

    // Predict investor's withdrawal vault address
    _computeInvestorWithdrawalVault();
  }

  // ========== Setup Helpers ==========

  function _redeployAssetGuardWithProcessor(address _processor) internal {
    Governance governance = Governance(dhedgePoolFactory.governanceAddress());

    vm.startPrank(dhedgePoolFactory.owner());

    dytmOfficeAssetGuard = new DytmOfficeAssetGuard(
      5,
      pendleStaticRouter,
      dytmOffice,
      address(dhedgePoolFactory),
      dytmPeriphery,
      accountSplitterAndMerger,
      _processor
    );
    governance.setAssetGuard(uint16(106), address(dytmOfficeAssetGuard));

    vm.stopPrank();
  }

  function _computeInvestorWithdrawalVault() internal {
    address existingVault = easySwapperV2Instance.withdrawalContracts(investor);
    if (existingVault != address(0)) {
      investorVault = existingVault;
    } else {
      uint64 nonce = vm.getNonce(address(easySwapperV2Instance));
      investorVault = vm.computeCreateAddress(address(easySwapperV2Instance), nonce);
    }
  }

  // ========== Tests: DytmWithdrawProcessor Constructor ==========

  function test_dytm_processor_constructor_sets_immutables() public view {
    assertEq(dytmProcessor.dytmOffice(), dytmOffice, "dytmOffice should match");
    assertEq(dytmProcessor.easySwapperV2(), address(easySwapperV2Instance), "easySwapperV2 should match");
    assertEq(dytmProcessor.dHedgePoolFactory(), address(dhedgePoolFactory), "dHedgePoolFactory should match");
  }

  // ========== Tests: DytmWithdrawProcessor Access Control ==========

  function test_dytm_processor_rejects_non_office_caller() public {
    vm.expectRevert("invalid caller");
    dytmProcessor.onDelegationCallback(bytes(""));
  }

  // ========== Tests: Withdrawal with DYTM Position - No Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_no_debt() public {
    // Supply collateral to DYTM (no borrowing)
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify pool has DYTM position
    uint256 collateralValueBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Pool should have collateral in DYTM");
      assertEq(pos.debt.debtAssets, 0, "Pool should have no debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
    }

    // Get investor's pool token balance and compute withdrawal amount
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    assertGt(investorPoolTokensBefore, 0, "Investor should have pool tokens");
    uint256 withdrawAmount = investorPoolTokensBefore / 2;

    // Build complexAssetsData for no-debt withdrawal
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmNoSwapComplexAssetsData();

    // Capture token price before withdrawal (burning tokens can change it)
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    // Investor approves and initiates withdrawal
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault was created correctly
    assertEq(vault, investorVault, "Vault address should match prediction");

    // Verify tracked assets have balances
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify withdrawn value matches pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal (recover assets without swapping)
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor has fewer pool tokens
    assertLt(dytmTestPool.balanceOf(investor), investorPoolTokensBefore, "Investor should have fewer pool tokens");

    // Verify pool's DYTM position was reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
    }

    // Verify total value is preserved within tolerance
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.01e18, // 1% tolerance for fees and slippage
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Withdrawal with swapToAsset Collateral - No Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_swapToAsset_no_debt() public {
    // Supply swapToAsset (WETH) as escrow collateral, no borrowing
    uint256 wethAmount = 1e16; // 0.01 WETH
    deal(swapToAsset, address(dytmTestPool), wethAmount);

    // Supply WETH to DYTM via delegationCall (1 tx, no borrow)
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](1);
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(swapToAsset),
          assets: wethAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position: collateral > 0, no debt
    uint256 collateralValueBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Pool should have collateral in DYTM");
      assertEq(pos.debt.debtAssets, 0, "Pool should have no debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
    }

    // Investor withdraws 50%
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmNoSwapComplexAssetsData();

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match prediction");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor received withdrawn assets
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool collateral reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
    }

    // Verify remaining pool value is approximately half
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.01e18, // 1% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Withdrawal with DYTM Position - With Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_with_debt() public {
    // Step 1: Create a DYTM position with WETH collateral and USDC debt
    uint256 wethAmount = 1e16; // 0.01 WETH
    deal(swapToAsset, address(dytmTestPool), wethAmount);

    // Supply WETH as escrow collateral and borrow USDC via delegationCall
    uint256 borrowAmount = 5 * (10 ** IERC20Extended(borrowAsset).decimals()); // 5 USDC

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);

    // Supply WETH to DYTM
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(swapToAsset),
          assets: wethAmount,
          extraData: ""
        })
      )
    });

    // Borrow USDC
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Step 2: Investor withdraws half
    uint256 withdrawAmount = dytmTestPool.balanceOf(investor) / 2;

    // Build complexAssetsData with swap data for WETH -> USDC (to repay debt)
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmWithDebtComplexAssetsData(withdrawAmount);

    // Investor approves and initiates withdrawal
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault
    assertEq(vault, investorVault, "Vault address should match");
    assertGt(trackedAssets.length, 0, "Should have tracked assets");

    // Complete withdrawal
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify total value is approximately halved
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.05e18, // 5% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Withdrawal with collateralAsset Collateral + Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_collateral_with_debt() public {
    // Supply collateralAsset as escrow + borrow borrowAsset via delegationCall
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);

    // Supply collateralAsset to DYTM as escrow
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: initialCollateral,
          extraData: ""
        })
      )
    });

    // Borrow borrowAsset
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Investor withdraws 50%
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmWithDebtComplexAssetsData(withdrawAmount);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor received withdrawn assets
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify remaining pool value is approximately half
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.01e18, // 1% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Edge Cases ==========

  function test_withdrawal_reverts_if_processor_not_set() public {
    // Redeploy guard with processor=address(0)
    _redeployAssetGuardWithProcessor(address(0));

    // Supply collateral (no debt)
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    uint256 withdrawAmount = dytmTestPool.balanceOf(investor) / 2;

    // Build complexAssetsData
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmNoSwapComplexAssetsData();

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    vm.expectRevert("dytm processor not set");
    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();
  }

  function test_withdrawal_without_dytm_position_skips_processing() public {
    // Don't supply anything to DYTM - pool has no DYTM position
    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokens / 2;

    // Build complexAssetsData without withdraw data for DYTM office
    IHasSupportedAsset.Asset[] memory supportedAssets = dytmTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](supportedAssets.length);

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      complexAssetsData[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supportedAssets[i].asset,
        withdrawData: new bytes(0),
        slippageTolerance: 100
      });
    }

    // Should not revert - DYTM processing is skipped when no positions exist
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();

    // Complete withdrawal to verify assets flow correctly
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();
  }

  // ========== Tests: Full Leverage Up + Withdrawal ==========

  function test_easyswapper_v2_withdrawal_after_leverage_up() public {
    // Leverage up (creates DYTM position with pool token collateral + USDC debt)
    _leverage_up();

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Investor withdraws a quarter (to reduce impact)
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 4;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    // Build complexAssetsData with swap data for debt repayment
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmWithDebtComplexAssetsData(withdrawAmount);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify remaining pool value is approximately 3/4 of original
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      (totalValueBefore * 3) / 4,
      0.01e18, // 1% tolerance
      "Remaining pool value should be approximately 3/4"
    );
  }

  // ========== Tests: Withdrawal with PT-Holding Collateral Vault - No Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_collateral_pt_no_debt() public {
    _setupPTInCollateralVault();

    // Supply collateral to DYTM (no borrowing)
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify pool has DYTM position
    uint256 collateralValueBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Pool should have collateral in DYTM");
      assertEq(pos.debt.debtAssets, 0, "Pool should have no debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
    }

    // Get investor's pool token balance and compute withdrawal amount
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    assertGt(investorPoolTokensBefore, 0, "Investor should have pool tokens");
    uint256 withdrawAmount = investorPoolTokensBefore / 2;

    // Build complexAssetsData for no-debt withdrawal
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmNoSwapComplexAssetsData();

    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    // Investor approves and initiates withdrawal
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault was created correctly
    assertEq(vault, investorVault, "Vault address should match prediction");

    // Verify tracked assets have balances
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify withdrawn value matches pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.02e18, // 2% tolerance (PT unrolling may incur minor slippage)
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor has fewer pool tokens
    assertLt(dytmTestPool.balanceOf(investor), investorPoolTokensBefore, "Investor should have fewer pool tokens");

    // Verify pool's DYTM position was reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
    }

    // Verify total value is preserved within tolerance
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.02e18, // 2% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Withdrawal with PT-Holding Collateral Vault - With Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_collateral_pt_with_debt() public {
    _setupPTInCollateralVault();

    // Supply collateralAsset as escrow + borrow borrowAsset via delegationCall
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);

    // Supply collateralAsset to DYTM as escrow
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: initialCollateral,
          extraData: ""
        })
      )
    });

    // Borrow borrowAsset
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Investor withdraws 50%
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmWithDebtComplexAssetsData(withdrawAmount);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.02e18, // 2% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor received withdrawn assets
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify remaining pool value is approximately half
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.05e18, // 5% tolerance for swap slippage
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Helpers ==========

  function _setupPTInCollateralVault() internal {
    require(pendlePT != address(0), "PT config not set");
    require(isCollateralDhedgePoolToken, "Collateral must be a dHedge pool token");

    Governance governance = Governance(dhedgePoolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(dhedgePoolFactory.getAssetHandler());

    vm.startPrank(dhedgePoolFactory.owner());

    // 1. Deploy PendlePTAssetGuard with the Pendle market
    address[] memory knownPendleMarkets = new address[](1);
    knownPendleMarkets[0] = pendleMarket;
    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(knownPendleMarkets);
    governance.setAssetGuard(37, address(pendlePTAssetGuard)); // Asset type 37 = PENDLE_PRINCIPAL_TOKEN

    // 2. Deploy mock PT/SY oracle using actual market rate (slightly discounted for slippage buffer)
    (uint256 netSyOut, , , ) = IPActionMarketCoreStatic(pendleStaticRouter).swapExactPtForSyStatic(
      pendleMarket,
      1e18 // 1 PT
    );
    // Use 99% of actual rate to ensure slippage check passes after market swap
    int256 ptRate = int256((netSyOut * 99) / 100);
    MockPendlePTChainlinkOracle mockPtOracle = new MockPendlePTChainlinkOracle(ptRate);
    address pendlePTPriceAggregator = deployCode(
      "PendlePTPriceAggregator.sol",
      abi.encode(pendlePTUnderlying, address(mockPtOracle), address(assetHandler))
    );

    // 3. Register PT in asset handler as type 37
    assetHandler.addAsset(
      pendlePT,
      37, // PENDLE_PRINCIPAL_TOKEN
      pendlePTPriceAggregator
    );

    vm.stopPrank();

    // 4. Add PT as supported asset in the collateral vault
    address collateralPoolManager = PoolLogic(collateralAsset).poolManagerLogic();
    vm.prank(PoolManagerLogic(collateralPoolManager).manager());
    PoolManagerLogic(collateralPoolManager).changeAssets(_singleSupportedAsset(pendlePT, false), new address[](0));

    // 5. Deal PT tokens into the collateral vault
    uint256 ptAmount = 1e18; // 1 PT token
    deal(pendlePT, collateralAsset, ptAmount);
  }

  function _singleSupportedAsset(
    address _asset,
    bool _isDeposit
  ) internal pure returns (IHasSupportedAsset.Asset[] memory assets) {
    assets = new IHasSupportedAsset.Asset[](1);
    assets[0] = IHasSupportedAsset.Asset({asset: _asset, isDeposit: _isDeposit});
  }

  function _buildDytmNoSwapComplexAssetsData()
    internal
    view
    returns (IPoolLogic.ComplexAsset[] memory complexAssetsData)
  {
    IHasSupportedAsset.Asset[] memory supportedAssets = dytmTestPoolManagerLogic.getSupportedAssets();
    complexAssetsData = new IPoolLogic.ComplexAsset[](supportedAssets.length);

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      complexAssetsData[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supportedAssets[i].asset,
        withdrawData: new bytes(0),
        slippageTolerance: 100 // 1%
      });
    }
  }

  function _buildDytmWithDebtComplexAssetsData(
    uint256 _withdrawAmount
  ) internal returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    // Calculate swap data parameters via the asset guard's calculateSwapDataParams
    // Prank both msg.sender and tx.origin to address(0) to pass cannotExecute modifier
    vm.prank(address(0), address(0));
    ISwapDataConsumingGuard.SwapDataParams memory swapDataParams = dytmOfficeAssetGuard.calculateSwapDataParams(
      address(dytmTestPool),
      _withdrawAmount,
      100 // 1% slippage tolerance
    );

    // Build swap data if there are source assets to swap
    bytes memory withdrawData;
    if (swapDataParams.dstData.asset != address(0) && swapDataParams.srcData.length > 0) {
      // Get Odos swap data for each source asset -> debt asset
      ISwapper.SrcTokenSwapDetails[] memory srcTokenSwapDetails = new ISwapper.SrcTokenSwapDetails[](
        swapDataParams.srcData.length
      );

      address swapperAddress = address(easySwapperV2Instance.swapper());

      for (uint256 i = 0; i < swapDataParams.srcData.length; i++) {
        if (swapDataParams.srcData[i].amount == 0) continue;

        (, bytes memory odosSwapData) = _getSwapDataForSwapper(
          swapDataParams.srcData[i].asset,
          swapDataParams.dstData.asset,
          swapDataParams.srcData[i].amount,
          swapperAddress
        );

        srcTokenSwapDetails[i] = ISwapper.SrcTokenSwapDetails({
          token: IERC20(swapDataParams.srcData[i].asset),
          amount: swapDataParams.srcData[i].amount,
          aggregatorData: ISwapper.AggregatorData({routerKey: bytes32("ODOS_V3"), swapData: odosSwapData})
        });
      }

      ISwapDataConsumingGuard.ComplexAssetSwapData memory complexAssetSwapData = ISwapDataConsumingGuard
        .ComplexAssetSwapData({
          srcData: abi.encode(srcTokenSwapDetails),
          destData: ISwapper.DestData({
            destToken: IERC20(swapDataParams.dstData.asset),
            minDestAmount: swapDataParams.dstData.amount
          }),
          slippageTolerance: 100 // 1%
        });

      withdrawData = abi.encode(complexAssetSwapData);
    }

    // Build complexAssetsData
    IHasSupportedAsset.Asset[] memory supportedAssets = dytmTestPoolManagerLogic.getSupportedAssets();
    complexAssetsData = new IPoolLogic.ComplexAsset[](supportedAssets.length);

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      bytes memory assetWithdrawData;
      if (supportedAssets[i].asset == dytmOffice) {
        assetWithdrawData = withdrawData;
      }
      complexAssetsData[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supportedAssets[i].asset,
        withdrawData: assetWithdrawData,
        slippageTolerance: 100 // 1%
      });
    }
  }

  function _assertHasNonZeroTrackedAsset(IWithdrawalVault.TrackedAsset[] memory trackedAssets) internal pure {
    assertGt(trackedAssets.length, 0, "Should have tracked assets");
    bool hasNonZeroBalance;
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        hasNonZeroBalance = true;
        break;
      }
    }
    assertTrue(hasNonZeroBalance, "At least one tracked asset should have balance");
  }

  function _getSwapDataForSwapper(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    address _swapper
  ) internal returns (uint256 destAmount, bytes memory swapData) {
    OdosAPIHelper.OdosFunctionStruct memory params = OdosAPIHelper.OdosFunctionStruct({
      srcAmount: srcAmount,
      srcToken: srcToken,
      destToken: destToken,
      user: _swapper,
      slippage: 5 // Higher slippage for fork block price differences
    });
    (destAmount, swapData) = getDataFromOdos(params, chainId, true, "v3");
  }

  // ========== Tests: Debt with no swap needed ==========

  function test_easyswapper_withdraw_dytm_with_debt_no_swap_needed() public {
    // Setup: supply borrowAsset (USDC) as both collateral and debt on market 1
    // After filterSrcDataAndCalculateMinDst, srcData will be empty (collateral == debt asset)

    // 1. Configure USDC-ESCROW / USDC-debt weight
    IDytmWeights weights = IDytmWeights(IMarketConfig(dytmMarketConfig).weights());
    vm.prank(marketCreator);
    weights.setWeight(_getTokenIdForMarket(borrowAsset, marketId, 1), _getReserveKey(borrowAsset), uint64(0.85e18));

    // 2. Deal USDC to the pool and supply as ESCROW collateral (ONLY USDC, no other collateral)
    uint256 usdcSupplyAmount = borrowAmountNormalized * 10 * (10 ** IERC20Extended(borrowAsset).decimals());
    deal(borrowAsset, address(dytmTestPool), usdcSupplyAmount);

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForMarket(borrowAsset, marketId, 1), // ESCROW
          assets: usdcSupplyAmount,
          extraData: ""
        })
      )
    );

    // 3. Borrow USDC (same asset as collateral)
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    );

    // Verify position: has ONLY USDC collateral and USDC debt
    DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );
    assertGt(position.totalCollateralValueUSD, 0, "Should have collateral");
    assertGt(position.debt.debtAssets, 0, "Should have debt");
    assertEq(position.debt.debtAsset, borrowAsset, "Debt asset should be borrowAsset");

    // 4. Withdrawal via EasySwapperV2.initWithdrawal (goes through DytmWithdrawProcessor)
    // filterSrcDataAndCalculateMinDst filters out USDC (== debt asset) → srcData is empty.
    // Processor handles this via _processDebtNoSwapCase (repay without swapping).
    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokens / 2;
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildComplexAssetsData();

    vm.warp(block.timestamp + 86401);
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);
    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();
  }
}
