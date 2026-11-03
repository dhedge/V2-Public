// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasAssetInfo} from "contracts/interfaces/IHasAssetInfo.sol";
import {IHasGuardInfo} from "contracts/interfaces/IHasGuardInfo.sol";
import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmWithdrawalCalculator} from "contracts/interfaces/guards/IDytmWithdrawalCalculator.sol";
import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {IOndoGMSwap} from "contracts/interfaces/ondo/IOndoGMSwap.sol";
import {IOndoSanityCheckOracle} from "contracts/interfaces/ondo/IOndoSanityCheckOracle.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {DytmOfficeAssetGuard} from "contracts/guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";
import {DytmWithdrawProcessor} from "contracts/swappers/easySwapperV2/DytmWithdrawProcessor.sol";
import {DytmWithdrawLib} from "contracts/swappers/easySwapperV2/libraries/dytm/DytmWithdrawLib.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/// @notice Live Ethereum addresses this suite runs against. Everything is production state except
///         the attestation signing key (granted on the fork) and the patched processor runtime.
library DytmLiveVaultData {
  // Pinned past the last production DYTM unwind (block 25990081) so the processor's real leftover
  // balances are present and the suite can prove the fix leaves them alone.
  uint256 internal constant FORK_BLOCK_NUMBER = 25995000;

  address internal constant ONDO_GM_SWAP = 0xde41399145F23936b03dD1474eC16c1519c0DC2a;
  address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
  address internal constant STRCON = 0xECABE1Ff8a9e1dC55899cf58dac8497ecE5Ae84c;
  // Every token the deployed processor is still holding at the fork block, left there by past
  // unwinds. `setUp` rescues all of them, so the suite runs against an empty processor.
  address internal constant SPCXON = 0xc9eef266834730340A55B6CC24621B31BAF55581;
  address internal constant IRENON = 0x0b59fDb1A233A7477ea14061004b9DD776e73CB3;
  address internal constant NVDAON = 0x2D1F7226Bd1F780AF6B9A49DCC0aE00E8Df4bDEE;

  // The two live STRC leverage vaults and their largest holders at the fork block.
  address internal constant STRCBULL3X = 0xF5509ab5e02cE875fA8ceCA1b5c07e73841282E1;
  address internal constant STRCBULL3X_TOP_HOLDER = 0x7AaC49c2DC11c3DE13bc1bD72bF53E4320F1376F;
  address internal constant STRCBULL2X = 0xE25Fb378b2d98e6320CAc3b32DcFF2B2AE710879;
  address internal constant STRCBULL2X_TOP_HOLDER = 0x43d271C17612f8F431c7533b7827993E203E9e83;

  // `userId` Ondo has registered for `OndoGMSwap`, read off the production redeem calldata of
  // tx 0x67a4e126f86cb47a91b669d64964b582f024a593a23c27733bc722c386be9045.
  bytes32 internal constant ONDO_USER_ID = 0x474d000000000000b50d13795402932300000000000000000000000000000000;

  uint16 internal constant ONDO_GM_ASSET_TYPE = 41;
}

/// @title DytmLiveVaultWithdrawalTestEthereum
/// @notice Runs the production frontend's DYTM unwind plan for the largest holder of each live STRC
///         vault against the patched `DytmWithdrawProcessor`, and proves the patch blocks a plan
///         from spending the leftovers earlier withdrawals left in the shared processor.
/// @dev    Production state throughout — the deployed EasySwapperV2, WithdrawalVault, asset guard,
///         DYTM Office, OndoGMSwap and GMTokenManager, the real vaults and their real holders. Two
///         things are fork-local: the patched processor runtime is etched over the deployed address
///         (so the asset guard's immutable still resolves to it), and a test key is granted Ondo's
///         `ATTESTATION_SIGNER_ROLE` so quotes can be minted for amounts Ondo never signed. Quote
///         prices come from Ondo's own sanity oracle, so every other Ondo check runs for real.
contract DytmLiveVaultWithdrawalTestEthereum is Test {
  // `AutomationBase.cannotExecute` accepts this as a simulated-call tx.origin.
  address internal constant SIMULATION_ORIGIN = 0x1111111111111111111111111111111111111111;

  uint256 internal constant ATTESTATION_SIGNER_KEY = 0xA11CE;
  bytes32 internal constant QUOTE_TYPEHASH =
    keccak256(
      "Quote(uint256 chainId,uint256 attestationId,bytes32 userId,address asset,uint256 price,uint256 quantity,uint256 expiration,uint8 side,bytes32 additionalData)"
    );

  // Frontend constants (`packages/trading-widget/src/core-kit`).
  uint256 internal constant BPS_DENOMINATOR = 10_000;
  uint256 internal constant DYTM_SLIPPAGE_TOLERANCE_BPS = 200; // pinned to the contract max
  uint256 internal constant OUTPUT_ASSET_FLOOR_BPS = 5;
  uint256 internal constant MAX_DISCOUNT_BPS = 100;
  uint256 internal constant MIN_GM_UNWIND_VALUE_USD = 1e18;
  uint256 internal constant USDC_SCALE = 1e6;
  // `useAppliedWithdrawSlippage` default for these vaults, in percent units.
  uint256 internal constant SLIPPAGE_PERCENT_BPS = 50; // 0.5%

  address internal easySwapperV2;
  address internal dytmOfficeAssetGuard;
  address internal withdrawProcessor;
  bytes internal deployedProcessorCode;
  address internal processorOwner;
  address internal signerAddress;
  bytes32 internal domainSeparator;
  uint256 internal nextAttestationId = 1;

  function setUp() public {
    vm.createSelectFork("ethereum", DytmLiveVaultData.FORK_BLOCK_NUMBER);

    // Patched processor runtime over the deployed address. The constructor args match the live
    // immutables, and etching leaves storage (the owner) untouched.
    dytmOfficeAssetGuard = IHasGuardInfo(EthereumConfig.POOL_FACTORY_PROD).getAssetGuard(EthereumConfig.DYTM_OFFICE);
    withdrawProcessor = DytmOfficeAssetGuard(dytmOfficeAssetGuard).dytmWithdrawProcessor();
    easySwapperV2 = address(DytmWithdrawProcessor(withdrawProcessor).easySwapperV2());

    deployedProcessorCode = _runtimeCode(withdrawProcessor);
    processorOwner = DytmWithdrawProcessor(withdrawProcessor).owner();
    DytmWithdrawProcessor patched = new DytmWithdrawProcessor(
      easySwapperV2,
      EthereumConfig.POOL_FACTORY_PROD,
      EthereumConfig.USDC
    );
    vm.etch(withdrawProcessor, _runtimeCode(address(patched)));

    signerAddress = vm.addr(ATTESTATION_SIGNER_KEY);
    domainSeparator = IGMTokenManager(EthereumConfig.ONDO_GM_TOKEN_MANAGER).getDomainSeparator();
    bytes32 signerRole = IGMTokenManager(EthereumConfig.ONDO_GM_TOKEN_MANAGER).ATTESTATION_SIGNER_ROLE();
    vm.prank(_gmTokenManagerAdmin());
    (bool granted, ) = EthereumConfig.ONDO_GM_TOKEN_MANAGER.call(
      abi.encodeWithSignature("grantRole(bytes32,address)", signerRole, signerAddress)
    );
    require(granted, "grantRole failed");

    // Clear the leftovers past unwinds left behind, the way the owner is expected to before this
    // fix ships. Everything below then runs against an empty processor.
    address[] memory leftovers = _knownLeftoverTokens();
    vm.startPrank(processorOwner);
    for (uint256 i; i < leftovers.length; ++i) {
      uint256 balance = IERC20(leftovers[i]).balanceOf(withdrawProcessor);
      if (balance > 0) {
        DytmWithdrawProcessor(withdrawProcessor).rescueToken(leftovers[i], balance, processorOwner);
      }
    }
    vm.stopPrank();
  }

  /// @dev First holder of `DEFAULT_ADMIN_ROLE` (`bytes32(0)`) on Ondo's GMTokenManager.
  function _gmTokenManagerAdmin() internal view returns (address admin) {
    (bool ok, bytes memory ret) = EthereumConfig.ONDO_GM_TOKEN_MANAGER.staticcall(
      abi.encodeWithSignature("getRoleMember(bytes32,uint256)", bytes32(0), uint256(0))
    );
    require(ok, "admin lookup failed");
    admin = abi.decode(ret, (address));
  }

  function _knownLeftoverTokens() internal pure returns (address[] memory tokens) {
    tokens = new address[](4);
    tokens[0] = DytmLiveVaultData.STRCON;
    tokens[1] = DytmLiveVaultData.SPCXON;
    tokens[2] = DytmLiveVaultData.IRENON;
    tokens[3] = DytmLiveVaultData.NVDAON;
  }

  function test_setUp_leaves_the_processor_empty() public view {
    address[] memory leftovers = _knownLeftoverTokens();
    for (uint256 i; i < leftovers.length; ++i) {
      assertEq(IERC20(leftovers[i]).balanceOf(withdrawProcessor), 0, "leftover not rescued");
    }
    assertEq(IERC20(EthereumConfig.USDC).balanceOf(withdrawProcessor), 0, "processor must hold no USDC");
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Live-vault full withdrawals
  // ═══════════════════════════════════════════════════════════════════════════════

  function test_strcbull3x_top_holder_withdraws_full_balance_two_step() public {
    _assertTopHolderCanWithdrawEverything(DytmLiveVaultData.STRCBULL3X, DytmLiveVaultData.STRCBULL3X_TOP_HOLDER, false);
  }

  function test_strcbull2x_top_holder_withdraws_full_balance_two_step() public {
    _assertTopHolderCanWithdrawEverything(DytmLiveVaultData.STRCBULL2X, DytmLiveVaultData.STRCBULL2X_TOP_HOLDER, false);
  }

  function test_strcbull3x_top_holder_withdraws_full_balance_unrollAndClaim() public {
    _assertTopHolderCanWithdrawEverything(DytmLiveVaultData.STRCBULL3X, DytmLiveVaultData.STRCBULL3X_TOP_HOLDER, true);
  }

  function test_strcbull2x_top_holder_withdraws_full_balance_unrollAndClaim() public {
    _assertTopHolderCanWithdrawEverything(DytmLiveVaultData.STRCBULL2X, DytmLiveVaultData.STRCBULL2X_TOP_HOLDER, true);
  }

  /// @dev The holder's whole balance unwinds, they end up with USDC worth at least their share less
  ///      the slippage they accepted, the GM slice the signed quote was not sized to sell lands in
  ///      the vault, and the processor is as empty afterwards as it was before.
  /// @param _unrollAndClaim `true` runs the single-call path the frontend uses when the output is a
  ///        single asset; `false` runs `initWithdrawal` + `completeWithdrawal`.
  function _assertTopHolderCanWithdrawEverything(address _vault, address _holder, bool _unrollAndClaim) internal {
    uint256 poolTokens = IERC20(_vault).balanceOf(_holder);
    assertGt(poolTokens, 0, "holder must hold vault tokens");
    assertEq(IERC20(DytmLiveVaultData.STRCON).balanceOf(withdrawProcessor), 0, "processor must start empty");

    uint256 withdrawalValueUSD = (poolTokens * IPoolLogic(_vault).tokenPrice()) / 1e18;
    uint256 vaultGmBefore = IERC20(DytmLiveVaultData.STRCON).balanceOf(_vault);
    uint256 usdcBefore = IERC20(EthereumConfig.USDC).balanceOf(_holder);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildComplexAssetsData(_vault, poolTokens);

    vm.startPrank(_holder);
    IERC20(_vault).approve(easySwapperV2, poolTokens);
    if (_unrollAndClaim) {
      EasySwapperV2(easySwapperV2).unrollAndClaim(_vault, poolTokens, complexAssetsData);
    } else {
      EasySwapperV2(easySwapperV2).initWithdrawal(_vault, poolTokens, complexAssetsData);
      EasySwapperV2(easySwapperV2).completeWithdrawal();
    }
    vm.stopPrank();

    assertEq(IERC20(_vault).balanceOf(_holder), 0, "holder must have no vault tokens left");

    // Value out: USDC received, valued 1:1, against the pool-token value that went in.
    uint256 usdcGained = IERC20(EthereumConfig.USDC).balanceOf(_holder) - usdcBefore;
    uint256 receivedUSD = usdcGained * 1e12;
    uint256 floorUSD = (withdrawalValueUSD * (BPS_DENOMINATOR - DYTM_SLIPPAGE_TOLERANCE_BPS)) / BPS_DENOMINATOR;
    assertGe(receivedUSD, floorUSD, "holder received less than value minus accepted slippage");
    console.log(
      "shortfall vs. tokenPrice, bps:",
      ((withdrawalValueUSD - receivedUSD) * BPS_DENOMINATOR) / withdrawalValueUSD
    );

    // The GM slice the quote was not sized to sell went to the vault, and the processor is empty
    // again — so the next plan also starts from nothing.
    assertGt(IERC20(DytmLiveVaultData.STRCON).balanceOf(_vault), vaultGmBefore, "vault must receive the leftover");
    assertEq(IERC20(DytmLiveVaultData.STRCON).balanceOf(withdrawProcessor), 0, "processor must end empty");
    assertEq(IERC20(EthereumConfig.USDC).balanceOf(withdrawProcessor), 0, "processor must hold no USDC");
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // The sweep the patch closes
  // ═══════════════════════════════════════════════════════════════════════════════

  /// @dev A leftover appears in the processor between unwinds — a token an earlier plan produced and
  ///      stopped touching, seeded here so the invariant is tested on its own rather than on
  ///      whatever the chain happens to hold. The plan then carries the reported suffix: approve
  ///      that leftover to Multicall3 and have Multicall3 `transferFrom` it out. `_checkAction`
  ///      never sees a blocked selector, so only the emptied-before-the-plan-runs invariant stops
  ///      it — and it stops it by leaving the puller nothing to pull.
  function test_revert_plan_cannot_sweep_processor_leftover() public {
    (uint256 poolTokens, uint256 leftover, IPoolLogic.ComplexAsset[] memory complexAssetsData) = _buildSweepAttack();
    uint256 attackerBefore = IERC20(DytmLiveVaultData.IRENON).balanceOf(DytmLiveVaultData.STRCBULL3X_TOP_HOLDER);

    vm.startPrank(DytmLiveVaultData.STRCBULL3X_TOP_HOLDER);
    IERC20(DytmLiveVaultData.STRCBULL3X).approve(easySwapperV2, poolTokens);
    // Multicall3 wraps the token's own "transfer amount exceeds balance"; the processor is empty of
    // IRENon by the time the puller runs.
    vm.expectRevert("Multicall3: call failed");
    EasySwapperV2(easySwapperV2).initWithdrawal(DytmLiveVaultData.STRCBULL3X, poolTokens, complexAssetsData);
    vm.stopPrank();

    assertGt(leftover, 0, "attack must have had something to aim at");
    assertEq(
      IERC20(DytmLiveVaultData.IRENON).balanceOf(DytmLiveVaultData.STRCBULL3X_TOP_HOLDER),
      attackerBefore,
      "withdrawer must not receive the processor's leftover"
    );
  }

  /// @dev The same plan against the processor that is deployed today, to show the suite is aimed at
  ///      a live hole and not at a plan that would fail anyway.
  function test_deployed_processor_lets_the_same_plan_sweep_the_leftover() public {
    (uint256 poolTokens, uint256 leftover, IPoolLogic.ComplexAsset[] memory complexAssetsData) = _buildSweepAttack();

    // Put the deployed runtime back; the plan was built against the same state either way.
    vm.etch(withdrawProcessor, deployedProcessorCode);
    uint256 attackerBefore = IERC20(DytmLiveVaultData.IRENON).balanceOf(DytmLiveVaultData.STRCBULL3X_TOP_HOLDER);

    vm.startPrank(DytmLiveVaultData.STRCBULL3X_TOP_HOLDER);
    IERC20(DytmLiveVaultData.STRCBULL3X).approve(easySwapperV2, poolTokens);
    EasySwapperV2(easySwapperV2).initWithdrawal(DytmLiveVaultData.STRCBULL3X, poolTokens, complexAssetsData);
    vm.stopPrank();

    assertEq(
      IERC20(DytmLiveVaultData.IRENON).balanceOf(DytmLiveVaultData.STRCBULL3X_TOP_HOLDER) - attackerBefore,
      leftover,
      "deployed processor should hand the withdrawer the whole leftover"
    );
  }

  function _buildSweepAttack()
    internal
    returns (uint256 poolTokens, uint256 leftover, IPoolLogic.ComplexAsset[] memory complexAssetsData)
  {
    poolTokens = IERC20(DytmLiveVaultData.STRCBULL3X).balanceOf(DytmLiveVaultData.STRCBULL3X_TOP_HOLDER);
    leftover = 1e17;
    deal(DytmLiveVaultData.IRENON, withdrawProcessor, leftover);

    DytmWithdrawLib.UnwindPlan memory plan = _buildUnwindPlan(DytmLiveVaultData.STRCBULL3X, poolTokens);
    plan.actions = _appendSweepActions(plan.actions, leftover, DytmLiveVaultData.STRCBULL3X_TOP_HOLDER);
    complexAssetsData = _complexAssetsDataFor(DytmLiveVaultData.STRCBULL3X, plan);
  }

  function _appendSweepActions(
    DytmWithdrawLib.Action[] memory _actions,
    uint256 _leftover,
    address _recipient
  ) internal view returns (DytmWithdrawLib.Action[] memory swept) {
    IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
    calls[0] = IMulticall3.Call3({
      target: DytmLiveVaultData.IRENON,
      allowFailure: false,
      callData: abi.encodeWithSelector(IERC20.transferFrom.selector, withdrawProcessor, _recipient, _leftover)
    });

    swept = new DytmWithdrawLib.Action[](_actions.length + 2);
    for (uint256 i; i < _actions.length; ++i) {
      swept[i] = _actions[i];
    }
    swept[_actions.length] = DytmWithdrawLib.Action({
      to: DytmLiveVaultData.IRENON,
      data: abi.encodeWithSelector(IERC20.approve.selector, DytmLiveVaultData.MULTICALL3, _leftover)
    });
    swept[_actions.length + 1] = DytmWithdrawLib.Action({
      to: DytmLiveVaultData.MULTICALL3,
      data: abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls)
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Frontend plan construction, ported from the live widget
  // ═══════════════════════════════════════════════════════════════════════════════

  function _buildComplexAssetsData(
    address _vault,
    uint256 _poolTokens
  ) internal returns (IPoolLogic.ComplexAsset[] memory) {
    return _complexAssetsDataFor(_vault, _buildUnwindPlan(_vault, _poolTokens));
  }

  /// @dev `ComplexAsset[]` is positionally aligned with the pool's supported assets; only the DYTM
  ///      Office slot carries data.
  function _complexAssetsDataFor(
    address _vault,
    DytmWithdrawLib.UnwindPlan memory _plan
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    address[] memory supported = _supportedAssets(_vault);
    complexAssetsData = new IPoolLogic.ComplexAsset[](supported.length);
    for (uint256 i; i < supported.length; ++i) {
      complexAssetsData[i].supportedAsset = supported[i];
      if (supported[i] == EthereumConfig.DYTM_OFFICE) {
        complexAssetsData[i].withdrawData = abi.encode(_plan);
        complexAssetsData[i].slippageTolerance = DYTM_SLIPPAGE_TOLERANCE_BPS;
      }
    }
  }

  /// @dev Mirrors `buildUnwindPlan` in `use-fetch-dytm-withdraw-asset-data.ts`: preview, group by
  ///      split account, drop sub-$1 GM slots, emit each group's collateral unwinds then its repay,
  ///      and floor the output at the summed per-swap minimums net of the debt repaid from them.
  function _buildUnwindPlan(
    address _vault,
    uint256 _poolTokens
  ) internal returns (DytmWithdrawLib.UnwindPlan memory plan) {
    DytmParamStructs.AssetData[] memory assetData = _previewWithdrawal(_vault, _poolTokens);
    assertGt(assetData.length, 0, "preview returned no asset data");

    DytmWithdrawLib.Action[] memory actions = new DytmWithdrawLib.Action[](assetData.length * 3 + 2);
    uint256 count;
    uint256 totalAmountOutMinimum;
    uint256 totalDebt;

    uint256[] memory accountIds = _distinctAccountIds(assetData);
    for (uint256 g; g < accountIds.length; ++g) {
      for (uint256 i; i < assetData.length; ++i) {
        DytmParamStructs.AssetData memory entry = assetData[i];
        if (entry.accountId != accountIds[g] || entry.isDebt || entry.amount == 0) continue;

        if (entry.assetType == DytmLiveVaultData.ONDO_GM_ASSET_TYPE) {
          if (_isUnswappableGmDust(entry.asset, entry.amount)) continue;
          uint256 amountOutMinimum;
          (actions, count, amountOutMinimum) = _appendGmUnwind(actions, count, entry);
          totalAmountOutMinimum += amountOutMinimum;
        } else {
          require(entry.asset == EthereumConfig.USDC, "no unwind route for collateral");
          actions[count++] = _withdrawAllAction(entry);
          totalAmountOutMinimum += (entry.amount * (BPS_DENOMINATOR - OUTPUT_ASSET_FLOOR_BPS)) / BPS_DENOMINATOR;
        }
      }

      for (uint256 i; i < assetData.length; ++i) {
        DytmParamStructs.AssetData memory entry = assetData[i];
        if (entry.accountId != accountIds[g] || !entry.isDebt) continue;
        require(entry.asset == EthereumConfig.USDC, "unexpected debt asset");
        totalDebt += entry.amount;
        actions[count++] = DytmWithdrawLib.Action({
          to: EthereumConfig.USDC,
          data: abi.encodeWithSelector(IERC20.approve.selector, EthereumConfig.DYTM_OFFICE, uint256(-1))
        });
        actions[count++] = DytmWithdrawLib.Action({
          to: EthereumConfig.DYTM_OFFICE,
          data: abi.encodeWithSelector(
            IDytmOffice.repay.selector,
            DytmParamStructs.RepayParams({
              account: entry.accountId,
              key: entry.debtKey,
              withCollateralType: DytmParamStructs.TokenType.NONE,
              assets: uint256(-1),
              shares: 0,
              extraData: ""
            })
          )
        });
      }
    }

    assembly {
      mstore(actions, count)
    }
    plan.actions = actions;
    plan.outputAsset = EthereumConfig.USDC;
    plan.minOutputAmount = totalAmountOutMinimum > totalDebt ? totalAmountOutMinimum - totalDebt : 0;
  }

  /// @dev `buildDytmActions`: drain the slot by shares, approve the attested amount, redeem it.
  function _appendGmUnwind(
    DytmWithdrawLib.Action[] memory _actions,
    uint256 _count,
    DytmParamStructs.AssetData memory _collateral
  ) internal returns (DytmWithdrawLib.Action[] memory actions, uint256 count, uint256 amountOutMinimum) {
    actions = _actions;
    count = _count;

    uint256 price = _ondoSanityPrice(_collateral.asset);
    IGMTokenManager.Quote memory quote = _buildQuote(_collateral.asset, price, _collateral.amount);
    amountOutMinimum = _computeAmountOutMinimumUsdc(_collateral.amount, price);

    actions[count++] = _withdrawAllAction(_collateral);
    actions[count++] = DytmWithdrawLib.Action({
      to: _collateral.asset,
      data: abi.encodeWithSelector(IERC20.approve.selector, DytmLiveVaultData.ONDO_GM_SWAP, _collateral.amount)
    });
    actions[count++] = DytmWithdrawLib.Action({
      to: DytmLiveVaultData.ONDO_GM_SWAP,
      data: abi.encodeWithSelector(
        IOndoGMSwap.swapExactInWithAttestation.selector,
        _collateral.asset,
        _collateral.amount,
        EthereumConfig.USDC,
        amountOutMinimum,
        _signQuote(quote),
        quote
      )
    });
  }

  /// @dev `buildDytmOutputAssetWithdrawAction` / leg 1 of `buildDytmActions` — the max-shares drain.
  function _withdrawAllAction(
    DytmParamStructs.AssetData memory _collateral
  ) internal view returns (DytmWithdrawLib.Action memory) {
    return
      DytmWithdrawLib.Action({
        to: EthereumConfig.DYTM_OFFICE,
        data: abi.encodeWithSelector(
          IDytmOffice.withdraw.selector,
          DytmParamStructs.WithdrawParams({
            account: _collateral.accountId,
            tokenId: _collateral.tokenId,
            receiver: withdrawProcessor,
            assets: 0,
            shares: uint256(-1),
            extraData: ""
          })
        )
      });
  }

  /// @dev `computeAmountOutMinimumUsdc`: floor the USD value, apply the clamped slippage, ceil.
  function _computeAmountOutMinimumUsdc(uint256 _quantity, uint256 _price) internal pure returns (uint256) {
    uint256 slippageBps = SLIPPAGE_PERCENT_BPS > MAX_DISCOUNT_BPS ? MAX_DISCOUNT_BPS : SLIPPAGE_PERCENT_BPS;
    uint256 usdonValueD18 = (_quantity * _price) / 1e18;
    uint256 numerator = usdonValueD18 * (BPS_DENOMINATOR - slippageBps) * USDC_SCALE;
    uint256 denominator = BPS_DENOMINATOR * 1e18;
    return (numerator + denominator - 1) / denominator;
  }

  /// @dev `isUnswappableGmDust`: Ondo will not attest a redeem below $1.
  function _isUnswappableGmDust(address _asset, uint256 _amount) internal view returns (bool) {
    uint256 price = IHasAssetInfo(EthereumConfig.POOL_FACTORY_PROD).getAssetPrice(_asset);
    return price > 0 && (_amount * price) / 1e18 < MIN_GM_UNWIND_VALUE_USD;
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════════

  /// @dev The frontend reads this with `callStatic`; here the state change is rolled back so the
  ///      real withdrawal below starts from the same state the plan was built against.
  function _previewWithdrawal(
    address _vault,
    uint256 _poolTokens
  ) internal returns (DytmParamStructs.AssetData[] memory assetData) {
    uint256 snapshotId = vm.snapshotState();
    vm.prank(address(this), SIMULATION_ORIGIN);
    assetData = IDytmWithdrawalCalculator(dytmOfficeAssetGuard).previewWithdrawal(_vault, _poolTokens);
    require(vm.revertToState(snapshotId), "preview rollback failed");
  }

  function _distinctAccountIds(
    DytmParamStructs.AssetData[] memory _assetData
  ) internal pure returns (uint256[] memory accountIds) {
    accountIds = new uint256[](_assetData.length);
    uint256 count;
    for (uint256 i; i < _assetData.length; ++i) {
      bool seen;
      for (uint256 j; j < count; ++j) {
        if (accountIds[j] == _assetData[i].accountId) seen = true;
      }
      if (!seen) accountIds[count++] = _assetData[i].accountId;
    }
    assembly {
      mstore(accountIds, count)
    }
  }

  function _supportedAssets(address _vault) internal view returns (address[] memory assets) {
    IHasSupportedAsset.Asset[] memory supported = IHasSupportedAsset(IPoolLogic(_vault).poolManagerLogic())
      .getSupportedAssets();
    assets = new address[](supported.length);
    for (uint256 i; i < supported.length; ++i) {
      assets[i] = supported[i].asset;
    }
  }

  function _ondoSanityPrice(address _asset) internal view returns (uint256) {
    IOndoSanityCheckOracle.PriceData memory data = IGMTokenManager(EthereumConfig.ONDO_GM_TOKEN_MANAGER)
      .sanityCheckOracle()
      .prices(_asset);
    require(data.price > 0, "no Ondo sanity price");
    return data.price;
  }

  function _buildQuote(
    address _asset,
    uint256 _price,
    uint256 _quantity
  ) internal returns (IGMTokenManager.Quote memory) {
    return
      IGMTokenManager.Quote({
        chainId: 1,
        attestationId: nextAttestationId++,
        userId: DytmLiveVaultData.ONDO_USER_ID,
        asset: _asset,
        price: _price,
        quantity: _quantity,
        expiration: block.timestamp + 1 hours,
        side: uint8(IGMTokenManager.QuoteSide.SELL),
        additionalData: bytes32(0)
      });
  }

  /// @dev `address.code` only exists from 0.8.
  function _runtimeCode(address _target) internal view returns (bytes memory code) {
    assembly {
      let size := extcodesize(_target)
      code := mload(0x40)
      mstore(0x40, add(code, and(add(add(size, 0x20), 0x1f), not(0x1f))))
      mstore(code, size)
      extcodecopy(_target, add(code, 0x20), 0, size)
    }
  }

  function _signQuote(IGMTokenManager.Quote memory _quote) internal view returns (bytes memory) {
    bytes32 structHash = keccak256(
      abi.encode(
        QUOTE_TYPEHASH,
        _quote.chainId,
        _quote.attestationId,
        _quote.userId,
        _quote.asset,
        _quote.price,
        _quote.quantity,
        _quote.expiration,
        _quote.side,
        _quote.additionalData
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      ATTESTATION_SIGNER_KEY,
      keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash))
    );
    return abi.encodePacked(r, s, v);
  }
}
