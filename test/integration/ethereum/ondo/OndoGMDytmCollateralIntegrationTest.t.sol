// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {DytmWithdrawLib} from "contracts/swappers/easySwapperV2/libraries/dytm/DytmWithdrawLib.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmPeriphery} from "contracts/interfaces/dytm/IDytmPeriphery.sol";
import {IOndoGMSwap} from "contracts/interfaces/ondo/IOndoGMSwap.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {OndoDytmCollateralIntegrationTestSetup} from "test/integration/common/dytm/OndoDytmCollateralIntegrationTestSetup.t.sol";

/// @notice Real ethereum DYTM addresses for the SPYon-collateral integration test (market 1).
/// @dev `DYTM_MARKET_CONFIG` + `MARKET_CREATOR` are only needed for the borrow (debt) scenarios —
///      supply is permissionless. The debt scenarios skip themselves if either is `address(0)`.
library OndoDytmEthereumSharedData {
  uint256 internal constant FORK_BLOCK_NUMBER = 25452351;

  address internal constant DYTM_OFFICE = 0x0ff1ceB93DbADfB13722058D60c4B8cD122b06ea;
  address internal constant DYTM_PERIPHERY = 0xfA03F9Ce907006133a0E77796a31c40AC22151d5;
  address internal constant DYTM_ACCOUNT_SPLITTER_AND_MERGER = 0x2439089A93eedc9f7fFfbc8CD32b85143D0E591C;
  address internal constant SPYON = 0xFeDC5f4a6c38211c1338aa411018DFAf26612c08;
  uint88 internal constant DYTM_MARKET_ID = 1;

  // Borrow is gated on a hook whitelist (supply is permissionless). marketConfig.hooks() is the
  // whitelist hook; MARKET_CREATOR (the marketConfig owner) is authorized to call setAddressWhitelist.
  address internal constant DYTM_MARKET_CONFIG = 0xce2f5Efe4608d1933cD14A7511d1D718C9E36637;
  address internal constant MARKET_CREATOR = 0x5a76f841bFe5182f04bf511fC0Ecf88C27189FCB;
}

/// @title OndoGMDytmCollateralIntegrationTest
/// @notice End-to-end DYTM dispatcher → Ondo unwind through real `EasySwapperV2.initWithdrawal`,
///         against REAL mainnet DYTM (market 1, SPYon collateral) + a REAL Ondo redemption.
/// @dev    Scenario 1 (no-debt) is fully exercised. The with-debt scenario + the retargeted
///         USDC-debt `removeAssetCheck` need the pool's DYTM account whitelisted for borrowing
///         (`DYTM_MARKET_CONFIG` + `MARKET_CREATOR`); they self-skip until those are provided.
contract OndoGMDytmCollateralIntegrationTest is OndoDytmCollateralIntegrationTestSetup, EthereumSetup {
  uint256 internal constant SLIPPAGE_BPS = 100; // 1%
  uint256 internal constant USDC_DEBT_AMOUNT = 1_000e6;

  constructor()
    EthereumSetup(OndoDytmEthereumSharedData.FORK_BLOCK_NUMBER)
    OndoDytmCollateralIntegrationTestSetup(_createConfig())
  {}

  function _createConfig() internal pure returns (OndoDytmConfig memory config) {
    config.dytmOffice = OndoDytmEthereumSharedData.DYTM_OFFICE;
    config.dytmPeriphery = OndoDytmEthereumSharedData.DYTM_PERIPHERY;
    config.accountSplitterAndMerger = OndoDytmEthereumSharedData.DYTM_ACCOUNT_SPLITTER_AND_MERGER;
    config.dytmMarketConfig = OndoDytmEthereumSharedData.DYTM_MARKET_CONFIG;
    config.marketCreator = OndoDytmEthereumSharedData.MARKET_CREATOR;
    config.marketId = OndoDytmEthereumSharedData.DYTM_MARKET_ID;
    config.collateralGmToken = OndoDytmEthereumSharedData.SPYON;
  }

  function setUp() public override(OndoDytmCollateralIntegrationTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    OndoDytmCollateralIntegrationTestSetup.setUp();
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Scenario 1 — no-debt withdraw (real DYTM split → Ondo redeem → USDC)
  // ═══════════════════════════════════════════════════════════════════════════════

  function test_dytmOndo_easySwapperV2_noDebt_redeemsGMtoUSDC() public {
    _seedNoDebtPosition(SP_REDEEM_AMOUNT_IN);

    // Pool holds a real SPYon escrow position in DYTM, nothing in the pool wallet.
    DytmParamStructs.AccountPosition memory posBefore = _poolPosition();
    assertGt(posBefore.totalCollateralValueUSD, 0, "pool must hold DYTM collateral");
    assertEq(posBefore.debt.debtAssets, 0, "pool must have no debt");

    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    assertGt(investorPoolTokens, 0, "investor must hold pool tokens");
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildComplexAssetsData(
      _encodeNoDebtWithdrawData(investorPoolTokens),
      SLIPPAGE_BPS
    );

    vm.startPrank(investor);
    IERC20(address(dytmTestPool)).approve(address(easySwapperV2Proxy), investorPoolTokens);
    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Proxy.initWithdrawal(
      address(dytmTestPool),
      investorPoolTokens,
      complexAssetsData
    );
    vm.stopPrank();

    assertEq(vault, investorVault, "vault address mismatch");

    bool foundUsdc;
    for (uint256 i; i < trackedAssets.length; ++i) {
      assertTrue(trackedAssets[i].token != collateralGmToken, "vault must not track SPYon");
      if (trackedAssets[i].token == usdcData.asset) {
        foundUsdc = true;
        assertGt(trackedAssets[i].balance, 0, "vault USDC balance must be > 0");
      }
    }
    assertTrue(foundUsdc, "vault must track USDC");

    vm.prank(investor);
    easySwapperV2Proxy.completeWithdrawal();

    // Pool's DYTM collateral fully unwound (sole depositor → 100% withdrawal).
    assertEq(_poolPosition().totalCollateralValueUSD, 0, "pool DYTM collateral should be drained");
    // Processor holds no leftover SPYon / USDC.
    assertEq(IERC20(collateralGmToken).balanceOf(investorVault), 0, "processor must hold no SPYon");
    assertEq(IERC20(usdcData.asset).balanceOf(investorVault), 0, "processor must hold no USDC");

    // Investor receives USDC ≥ the signed attestation's floor.
    uint256 investorUsdcGained = IERC20(usdcData.asset).balanceOf(investor) - investorUsdcBefore;
    assertGe(investorUsdcGained, SP_REDEEM_MIN_RECEIVE, "investor USDC below SP_REDEEM_MIN_RECEIVE");
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Scenario 2 — with-debt USDC (redeem SPYon → USDC, repay USDC debt, settle remainder)
  // ═══════════════════════════════════════════════════════════════════════════════

  function test_dytmOndo_easySwapperV2_debtUsdcNoSwap_redeemsRepaysAndSettles() public {
    _skipIfBorrowUnconfigured();

    _seedDebtPosition(SP_REDEEM_AMOUNT_IN, usdcData.asset, USDC_DEBT_AMOUNT);

    DytmParamStructs.AccountPosition memory posBefore = _poolPosition();
    assertGt(posBefore.debt.debtAssets, 0, "pool must have USDC debt");

    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 investorUsdcBefore = IERC20(usdcData.asset).balanceOf(investor);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildComplexAssetsData(
      _encodeWithDebtUsdcWithdrawData(investorPoolTokens),
      SLIPPAGE_BPS
    );

    vm.startPrank(investor);
    IERC20(address(dytmTestPool)).approve(address(easySwapperV2Proxy), investorPoolTokens);
    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Proxy.initWithdrawal(
      address(dytmTestPool),
      investorPoolTokens,
      complexAssetsData
    );
    vm.stopPrank();

    assertEq(vault, investorVault, "vault address mismatch");

    bool foundUsdc;
    for (uint256 i; i < trackedAssets.length; ++i) {
      assertTrue(trackedAssets[i].token != collateralGmToken, "vault must not track SPYon");
      if (trackedAssets[i].token == usdcData.asset) {
        foundUsdc = true;
        assertGt(trackedAssets[i].balance, 0, "vault USDC balance must be > 0");
      }
    }
    assertTrue(foundUsdc, "vault must track USDC");

    vm.prank(investor);
    easySwapperV2Proxy.completeWithdrawal();

    // Position fully unwound — collateral and debt cleared.
    DytmParamStructs.AccountPosition memory posAfter = _poolPosition();
    assertEq(posAfter.totalCollateralValueUSD, 0, "pool DYTM collateral should be drained");
    assertApproxEqAbs(posAfter.debt.debtAssets, 0, 1e6, "pool DYTM debt should be cleared");

    assertEq(IERC20(usdcData.asset).balanceOf(investorVault), 0, "processor must hold no USDC");
    assertEq(IERC20(collateralGmToken).balanceOf(investorVault), 0, "processor must hold no SPYon");

    // Investor receives the post-repay remainder ≈ redeemed USDC − debt.
    uint256 investorUsdcGained = IERC20(usdcData.asset).balanceOf(investor) - investorUsdcBefore;
    assertGe(investorUsdcGained, SP_REDEEM_MIN_RECEIVE - USDC_DEBT_AMOUNT, "investor USDC gain below floor");
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Scenario 3 — removeAssetCheck blocks GM removal while held inside DYTM
  // ═══════════════════════════════════════════════════════════════════════════════

  function test_removeAssetCheck_blocksRemovalWhenGMIsCollateralInDytm() public {
    _seedNoDebtPosition(SP_REDEEM_AMOUNT_IN);

    address[] memory toRemove = new address[](1);
    toRemove[0] = collateralGmToken;
    vm.expectRevert("asset held as DYTM collateral");
    vm.prank(manager);
    dytmTestPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), toRemove);
  }

  // NOTE: the "asset held as DYTM debt" branch of ERC20Guard._checkDytmAssetPositions is not
  // unit-tested here. The only borrowable reserve on market 1 is USDC, which is also the pool's
  // deposit/base asset — so the pool always holds a non-zero USDC balance and removeAssetCheck
  // reverts on the earlier "cannot remove non-empty asset" guard before reaching the DYTM-debt
  // check. The symmetric collateral branch is covered by the collateral test above.

  function test_removeAssetCheck_allowsRemovalWhenDytmHoldsNoGM() public {
    // No DYTM position: the pool holds no SPYon (wallet or DYTM). Removal is allowed.
    address[] memory toRemove = new address[](1);
    toRemove[0] = collateralGmToken;
    vm.prank(manager);
    dytmTestPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), toRemove);

    assertFalse(dytmTestPoolManagerLogic.isSupportedAsset(collateralGmToken), "SPYon should be removed");
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════════

  function _poolPosition() internal view returns (DytmParamStructs.AccountPosition memory) {
    return IDytmPeriphery(dytmPeriphery).getAccountPosition(_toUserAccount(address(dytmTestPool)), marketId);
  }

  function _skipIfBorrowUnconfigured() internal {
    if (dytmMarketConfig == address(0) || marketCreator == address(0)) {
      vm.skip(true); // borrow scenarios need DYTM_MARKET_CONFIG + MARKET_CREATOR (hook whitelist)
    }
  }

  /// @dev No-debt unwind: split the position (real DYTM), withdraw the SPYon collateral from the
  ///      split account to the processor, then redeem it to USDC via the signed Ondo attestation.
  ///      `previewWithdrawal` (callStatic) yields the dynamically-allocated split account/tokenId.
  function _encodeNoDebtWithdrawData(uint256 _withdrawAmount) internal returns (bytes memory) {
    DytmParamStructs.AssetData memory col = _previewSingleCollateral(_withdrawAmount);
    address processor = dytmOfficeAssetGuard.dytmWithdrawProcessor();

    DytmWithdrawLib.Action[] memory actions = new DytmWithdrawLib.Action[](3);
    actions[0] = DytmWithdrawLib.Action({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: col.accountId,
          tokenId: col.tokenId,
          receiver: processor,
          assets: SP_REDEEM_AMOUNT_IN,
          shares: 0,
          extraData: ""
        })
      )
    });
    actions[1] = DytmWithdrawLib.Action({
      to: collateralGmToken,
      data: abi.encodeWithSelector(IERC20.approve.selector, ondoGMSwap, SP_REDEEM_AMOUNT_IN)
    });
    actions[2] = DytmWithdrawLib.Action({
      to: ondoGMSwap,
      data: abi.encodeWithSelector(
        IOndoGMSwap.swapExactInWithAttestation.selector,
        collateralGmToken,
        SP_REDEEM_AMOUNT_IN,
        usdcData.asset,
        SP_REDEEM_MIN_RECEIVE,
        SP_REDEEM_ATTESTATION_SIGNATURE,
        _spRedeemQuote()
      )
    });

    return
      abi.encode(
        DytmWithdrawLib.UnwindPlan({
          actions: actions,
          outputAsset: usdcData.asset,
          minOutputAmount: SP_REDEEM_MIN_RECEIVE
        })
      );
  }

  /// @dev With-debt-USDC unwind: same redeem as the no-debt path, plus approve + repay to clear the
  ///      USDC debt on the split account before the residual settles to the investor.
  function _encodeWithDebtUsdcWithdrawData(uint256 _withdrawAmount) internal returns (bytes memory) {
    (DytmParamStructs.AssetData memory col, DytmParamStructs.AssetData memory debt) = _previewCollateralAndDebt(
      _withdrawAmount
    );
    address processor = dytmOfficeAssetGuard.dytmWithdrawProcessor();

    DytmWithdrawLib.Action[] memory actions = new DytmWithdrawLib.Action[](5);
    actions[0] = DytmWithdrawLib.Action({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: col.accountId,
          tokenId: col.tokenId,
          receiver: processor,
          assets: SP_REDEEM_AMOUNT_IN,
          shares: 0,
          extraData: ""
        })
      )
    });
    actions[1] = DytmWithdrawLib.Action({
      to: collateralGmToken,
      data: abi.encodeWithSelector(IERC20.approve.selector, ondoGMSwap, SP_REDEEM_AMOUNT_IN)
    });
    actions[2] = DytmWithdrawLib.Action({
      to: ondoGMSwap,
      data: abi.encodeWithSelector(
        IOndoGMSwap.swapExactInWithAttestation.selector,
        collateralGmToken,
        SP_REDEEM_AMOUNT_IN,
        usdcData.asset,
        SP_REDEEM_MIN_RECEIVE,
        SP_REDEEM_ATTESTATION_SIGNATURE,
        _spRedeemQuote()
      )
    });
    actions[3] = DytmWithdrawLib.Action({
      to: usdcData.asset,
      data: abi.encodeWithSelector(IERC20.approve.selector, dytmOffice, type(uint256).max)
    });
    actions[4] = DytmWithdrawLib.Action({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.repay.selector,
        DytmParamStructs.RepayParams({
          account: col.accountId,
          key: debt.debtKey,
          withCollateralType: DytmParamStructs.TokenType.NONE,
          assets: type(uint256).max,
          shares: 0,
          extraData: ""
        })
      )
    });

    return
      abi.encode(
        DytmWithdrawLib.UnwindPlan({
          actions: actions,
          outputAsset: usdcData.asset,
          minOutputAmount: SP_REDEEM_MIN_RECEIVE - USDC_DEBT_AMOUNT
        })
      );
  }

  function _previewSingleCollateral(uint256 _withdrawAmount) internal returns (DytmParamStructs.AssetData memory col) {
    vm.prank(address(0), address(0));
    DytmParamStructs.AssetData[] memory assetData = dytmOfficeAssetGuard.previewWithdrawal(
      address(dytmTestPool),
      _withdrawAmount
    );
    require(assetData.length == 1 && !assetData[0].isDebt, "expected single collateral, no debt");
    col = assetData[0];
  }

  function _previewCollateralAndDebt(
    uint256 _withdrawAmount
  ) internal returns (DytmParamStructs.AssetData memory col, DytmParamStructs.AssetData memory debt) {
    vm.prank(address(0), address(0));
    DytmParamStructs.AssetData[] memory assetData = dytmOfficeAssetGuard.previewWithdrawal(
      address(dytmTestPool),
      _withdrawAmount
    );
    bool foundCol;
    bool foundDebt;
    for (uint256 i; i < assetData.length; ++i) {
      if (assetData[i].isDebt) {
        debt = assetData[i];
        foundDebt = true;
      } else {
        col = assetData[i];
        foundCol = true;
      }
    }
    require(foundCol && foundDebt, "expected one collateral + one debt");
  }
}
