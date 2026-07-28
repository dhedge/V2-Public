// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmOfficeContractGuard} from "contracts/interfaces/dytm/IDytmOfficeContractGuard.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {DytmConfigStructs} from "contracts/utils/dytm/DytmConfigStructs.sol";
import {DytmOfficeAssetGuard} from "contracts/guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";
import {DytmWithdrawProcessor} from "contracts/swappers/easySwapperV2/DytmWithdrawProcessor.sol";
import {OndoGMTokenAssetGuard} from "contracts/guards/assetGuards/ondo/OndoGMTokenAssetGuard.sol";
import {OndoGMSwapContractGuard} from "contracts/guards/contractGuards/ondo/OndoGMSwapContractGuard.sol";
import {IOndoAttestationOracle} from "contracts/interfaces/ondo/IOndoAttestationOracle.sol";
import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {OndoGMSwapTestSetup} from "test/integration/common/ondo/OndoGMSwapTestSetup.t.sol";
import {IMarketConfig} from "test/integration/common/dytm/dytmInterface/IDytmMarketConfig.sol";
import {IDytmAddressAccountBaseWhitelist} from "test/integration/common/dytm/dytmInterface/IDytmAddressAccountBaseWhitelist.sol";

/// @title OndoDytmCollateralIntegrationTestSetup
/// @notice Shared setup for integration tests that exercise the DYTM dispatcher → Ondo unwind
///         path end-to-end through real `EasySwapperV2.initWithdrawal`, against the REAL mainnet
///         DYTM contracts (market 1 / S&P500 GM "SPYon" collateral) and a REAL Ondo redemption.
/// @dev    DYTM addresses are injected via the constructor (`OndoDytmConfig`), mirroring
///         `DytmTestSetup`. SPYon supply is permissionless; borrowing requires the pool's DYTM
///         account to be whitelisted on the market hook (needs `dytmMarketConfig` + `marketCreator`
///         in the config — debt scenarios only). The Ondo attestation is a fresh signed redeem
///         quote minted at the fork block; the shared `OndoGMSwapTestSetup` base (pure-Ondo tests)
///         is left untouched — all SPYon/userId/oracle-specific wiring happens in this override.
abstract contract OndoDytmCollateralIntegrationTestSetup is OndoGMSwapTestSetup {
  uint256 internal constant MISMATCH_DELTA_NUMERATOR = 5; // 5 bps
  uint256 internal constant MIN_REDEEM_VALUE = 1.1e18; // $1.10
  uint256 internal constant ASSET_TYPE_ONDO_GM = 41;
  uint256 internal constant ASSET_TYPE_DYTM_OFFICE = 106;

  // ── Fresh SPYon (S&P500 Ondo GM) SELL/redeem attestation (minted at the fork block) ──────────
  address internal constant SPYON = 0xFeDC5f4a6c38211c1338aa411018DFAf26612c08;
  bytes32 internal constant SP_USER_ID = 0x474d000000000000b50d13795402932300000000000000000000000000000000;
  uint256 internal constant SP_REDEEM_ATTESTATION_ID = 315821591805559875113850930388893030759;
  uint256 internal constant SP_REDEEM_PRICE = 752827518394666506325; // 18d (~$752.83)
  uint256 internal constant SP_REDEEM_AMOUNT_IN = 10000000000000000000; // 10 SPYon (18d)
  uint256 internal constant SP_REDEEM_EXPIRATION = 1783086113;
  uint256 internal constant SP_REDEEM_EXPECTED_OUTPUT = 7_528_275_183; // 6d USDC (= quantity*price/1e18 → /1e12)
  uint256 internal constant SP_REDEEM_MIN_RECEIVE = 7_470_000_000; // 6d USDC floor (≈0.8% under expected)
  bytes internal constant SP_REDEEM_ATTESTATION_SIGNATURE =
    hex"0c64e0dff766763709f45b65ae90cae4282755bd4c249199eca48e007a22ab5316a879498861df8aac91eb9f7d2198c796480ad8fdb60748704fed500cb14e521b";
  /// @dev dHEDGE-side mocked SPYon aggregator price (8 decimals), within the oracle's
  ///      sanityDeviationBps (10%) of the quote price.
  int256 internal constant SP_MOCK_PRICE_8DP = 75282751839; // ~$752.828

  // ── DYTM config (constructor-injected, mirror DytmTestSetup) ─────────────────────────────────
  struct OndoDytmConfig {
    address dytmOffice;
    address dytmPeriphery;
    address accountSplitterAndMerger;
    address dytmMarketConfig; // borrow-whitelist hook source; 0 if not running debt scenarios
    address marketCreator; // hook admin; 0 if not running debt scenarios
    uint88 marketId;
    address collateralGmToken; // SPYon
  }

  address internal immutable dytmOffice;
  address internal immutable dytmPeriphery;
  address internal immutable accountSplitterAndMerger;
  address internal immutable dytmMarketConfig;
  address internal immutable marketCreator;
  uint88 internal immutable marketId;
  address internal immutable collateralGmToken;

  // ── Real dHEDGE-side guards/processor ────────────────────────────────────────────────────────
  OndoGMTokenAssetGuard internal ondoGMTokenAssetGuard;
  DytmOfficeAssetGuard internal dytmOfficeAssetGuard;
  IDytmOfficeContractGuard internal dytmOfficeContractGuard;
  DytmWithdrawProcessor internal dytmWithdrawProcessor;
  address internal spyonAggregator;

  // ── Test pool / actors (`investor` is inherited from BackboneSetup) ──────────────────────────
  PoolLogic internal dytmTestPool;
  PoolManagerLogic internal dytmTestPoolManagerLogic;
  address internal investorVault;

  constructor(OndoDytmConfig memory _config) {
    dytmOffice = _config.dytmOffice;
    dytmPeriphery = _config.dytmPeriphery;
    accountSplitterAndMerger = _config.accountSplitterAndMerger;
    dytmMarketConfig = _config.dytmMarketConfig;
    marketCreator = _config.marketCreator;
    marketId = _config.marketId;
    collateralGmToken = _config.collateralGmToken;
  }

  function setUp() public virtual override {
    super.setUp(); // OndoGMSwapTestSetup: deploys ondoGMSwap, base oracle/guard (old userId), base testPool (ignored here)

    // 1. SPYon Ondo wiring — register the GM token (type 41) + re-point the attestation oracle /
    //    identity registry at the FRESH userId (the base used the old one).
    _setupSpyonOndo();

    vm.startPrank(owner);
    // 2. Register the real DYTM Office as a supported asset type (106), priced in USD.
    assetHandlerProxy.addAsset(dytmOffice, uint16(ASSET_TYPE_DYTM_OFFICE), address(usdPriceAggregator));
    // 3. Disable exit cooldown so the investor can withdraw inside the attestation's validity window.
    poolFactoryProxy.setExitCooldown(0);
    vm.stopPrank();

    // 4. Create the dHEDGE pool (USDC + SPYon; DYTM Office added after the contract guard is set).
    _createTestPool();

    // 5. Wire the real DYTM asset guard + contract guard (marketId + pool whitelisted).
    _deployAndRegisterDytmGuards();

    // 6. Add the DYTM Office as a supported asset (addAssetCheck requires the contract guard) +
    //    approve the Office to pull collateral / debt.
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory dytmAsset = new IHasSupportedAsset.Asset[](1);
    dytmAsset[0] = IHasSupportedAsset.Asset({asset: dytmOffice, isDeposit: false});
    dytmTestPoolManagerLogic.changeAssets(dytmAsset, new address[](0));
    dytmTestPool.execTransaction(
      collateralGmToken,
      abi.encodeWithSelector(IERC20.approve.selector, dytmOffice, type(uint256).max)
    );
    dytmTestPool.execTransaction(
      usdcData.asset,
      abi.encodeWithSelector(IERC20.approve.selector, dytmOffice, type(uint256).max)
    );
    vm.stopPrank();

    // 7. Investor deposits USDC — sole depositor so `portion = 1.0e18` on a full withdrawal.
    deal(usdcData.asset, investor, 20_000e6);
    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(dytmTestPool), 20_000e6);
    dytmTestPool.deposit(usdcData.asset, 20_000e6);
    vm.stopPrank();

    // 8. Predict investor's WithdrawalVault + clear the lastDeposit cooldown.
    _computeInvestorWithdrawalVault();
    vm.warp(block.timestamp + 1);
  }

  // ───────────────────────────────────────────────────────────────────────────────
  // Setup helpers
  // ───────────────────────────────────────────────────────────────────────────────

  /// @dev Register SPYon as Ondo asset type 41 with a mocked aggregator, and re-point Ondo's
  ///      identity registry + attestation oracle at the FRESH userId carried by our attestation.
  ///      Re-deploys the oracle + swap contract guard (the base init'd them with the old userId)
  ///      so the shared `OndoGMSwapTestSetup` base stays untouched for the pure-Ondo tests.
  function _setupSpyonOndo() internal {
    vm.startPrank(owner);

    ondoGMTokenAssetGuard = new OndoGMTokenAssetGuard(ondoGMSwap, MISMATCH_DELTA_NUMERATOR, MIN_REDEEM_VALUE);
    governance.setAssetGuard(uint16(ASSET_TYPE_ONDO_GM), address(ondoGMTokenAssetGuard));

    spyonAggregator = makeAddr("spyon_aggregator");
    vm.mockCall(
      spyonAggregator,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(uint80(0), SP_MOCK_PRICE_8DP, uint256(0), block.timestamp, uint80(0))
    );
    vm.mockCall(spyonAggregator, abi.encodeWithSignature("decimals()"), abi.encode(uint8(8)));
    vm.mockCallRevert(spyonAggregator, abi.encodeWithSignature("oracleHeartbeat()"), "");
    assetHandlerProxy.addAsset(collateralGmToken, uint16(ASSET_TYPE_ONDO_GM), spyonAggregator);

    // Fresh-userId Ondo identity + attestation oracle (base used the old userId).
    vm.mockCall(
      ONDO_IDENTITY_REGISTRY,
      abi.encodeWithSignature("getRegisteredID(address,address)", ONDO_IDENTITY_GROUP, ondoGMSwap),
      abi.encode(SP_USER_ID)
    );
    address oracleImpl = deployCode("OndoAttestationOracle.sol:OndoAttestationOracle");
    attestationOracle = address(new TransparentUpgradeableProxy(oracleImpl, proxyAdmin, ""));
    (bool oracleOk, ) = attestationOracle.call(
      abi.encodePacked(
        INITIALIZE_ORACLE_SELECTOR,
        abi.encode(
          owner,
          GM_TOKEN_MANAGER,
          SP_USER_ID,
          uint256(3600), // maxProofAge
          uint256(1000), // sanityDeviationBps (10%)
          uint256(1e18), // minQuoteValue
          uint256(1_000_000e18) // maxQuoteValue
        )
      )
    );
    require(oracleOk, "OndoAttestationOracle init failed");
    ondoGMSwapGuard = new OndoGMSwapContractGuard(
      address(slippageAccumulator),
      MAX_SLIPPAGE_BPS,
      IOndoAttestationOracle(attestationOracle)
    );
    governance.setContractGuard(ondoGMSwap, address(ondoGMSwapGuard));

    vm.stopPrank();
  }

  /// @dev Pool with USDC (deposit) + SPYon (non-deposit). Investor is the SOLE depositor so
  ///      `portion = 1.0e18` on a full withdrawal (keeps the calculator's portion-scaled
  ///      callStatic view and the dispatcher's raw runtime view numerically identical).
  function _createTestPool() internal {
    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: collateralGmToken, isDeposit: false});

    dytmTestPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "DytmOndoManager",
        _fundName: "DytmOndoTestVault",
        _fundSymbol: "DOTV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    dytmTestPoolManagerLogic = PoolManagerLogic(dytmTestPool.poolManagerLogic());

    vm.stopPrank();
  }

  function _deployAndRegisterDytmGuards() internal {
    vm.startPrank(owner);

    // Processor first — its address is baked into the asset guard.
    dytmWithdrawProcessor = new DytmWithdrawProcessor(
      address(easySwapperV2Proxy),
      address(poolFactoryProxy),
      usdcData.asset
    );

    // Whitelist the processor on OndoGMSwap (redeems GM → USDC during the unwind).
    (bool setProcessorOk, ) = ondoGMSwap.call(
      abi.encodeWithSignature("setAuthorizedCaller(address,bool)", address(dytmWithdrawProcessor), true)
    );
    require(setProcessorOk, "setAuthorizedCaller failed");

    dytmOfficeAssetGuard = new DytmOfficeAssetGuard(
      MISMATCH_DELTA_NUMERATOR,
      dytmOffice,
      address(poolFactoryProxy),
      dytmPeriphery,
      accountSplitterAndMerger,
      address(dytmWithdrawProcessor)
    );
    governance.setAssetGuard(uint16(ASSET_TYPE_DYTM_OFFICE), address(dytmOfficeAssetGuard));

    address[] memory whitelistedPools = new address[](1);
    whitelistedPools[0] = address(dytmTestPool);
    uint88[] memory whitelistedMarkets = new uint88[](1);
    whitelistedMarkets[0] = marketId;
    DytmConfigStructs.DytmConfig memory dytmConfig = DytmConfigStructs.DytmConfig({
      dytmOffice: dytmOffice,
      dytmPeriphery: dytmPeriphery,
      dhedgePoolFactory: address(poolFactoryProxy),
      nftTracker: address(nftTrackerStorageProxy),
      accountSplitterAndMerger: accountSplitterAndMerger,
      maxDytmMarkets: 5,
      admin: owner
    });
    dytmOfficeContractGuard = IDytmOfficeContractGuard(
      deployCode("DytmOfficeContractGuard.sol", abi.encode(whitelistedPools, whitelistedMarkets, dytmConfig))
    );
    governance.setContractGuard(dytmOffice, address(dytmOfficeContractGuard));

    vm.stopPrank();
  }

  function _computeInvestorWithdrawalVault() internal {
    address existing = easySwapperV2Proxy.withdrawalContracts(investor);
    investorVault = existing != address(0)
      ? existing
      : vm.computeCreateAddress(address(easySwapperV2Proxy), vm.getNonce(address(easySwapperV2Proxy)));
  }

  // ───────────────────────────────────────────────────────────────────────────────
  // Scenario state setters (real DYTM supply / borrow)
  // ───────────────────────────────────────────────────────────────────────────────

  /// @dev Supply `_gmAmount` of SPYon as ESCROW collateral into market `marketId` from the pool.
  ///      Registers the market in the contract guard and creates the real escrow position.
  function _seedNoDebtPosition(uint256 _gmAmount) internal {
    deal(collateralGmToken, address(dytmTestPool), _gmAmount);
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: _toUserAccount(address(dytmTestPool)),
          tokenId: _escrowTokenId(collateralGmToken, marketId),
          assets: _gmAmount,
          extraData: ""
        })
      )
    );
  }

  /// @dev Supply SPYon escrow collateral, whitelist the pool's DYTM account for borrowing, seed
  ///      market liquidity for `_debtAsset`, then borrow `_debtAssets` of it from the pool.
  ///      Requires `dytmMarketConfig` + `marketCreator` (borrowing is gated, supply is not).
  function _seedDebtPosition(uint256 _gmAmount, address _debtAsset, uint256 _debtAssets) internal {
    require(dytmMarketConfig != address(0) && marketCreator != address(0), "borrow scenario needs config");

    _seedNoDebtPosition(_gmAmount);

    // Pool's DYTM account must be whitelisted on the market hook to borrow. Resolve `hooks()`
    // before the prank — otherwise the staticcall consumes the single-shot `vm.prank`.
    address hook = IMarketConfig(dytmMarketConfig).hooks();
    vm.prank(marketCreator);
    IDytmAddressAccountBaseWhitelist(hook).setAddressWhitelist(address(dytmTestPool), true);

    // A funder supplies LEND liquidity so the pool can borrow `_debtAsset`.
    uint256 lendAmount = _debtAssets * 10;
    deal(_debtAsset, investor, lendAmount);
    vm.startPrank(investor);
    IERC20(_debtAsset).approve(dytmOffice, lendAmount);
    IDytmOffice(dytmOffice).supply(
      DytmParamStructs.SupplyParams({
        account: _toUserAccount(investor),
        tokenId: _lendTokenId(_debtAsset, marketId),
        assets: lendAmount,
        extraData: ""
      })
    );
    vm.stopPrank();

    _ensurePoolSupportsAsset(_debtAsset);
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: _toUserAccount(address(dytmTestPool)),
          key: _reserveKey(_debtAsset, marketId),
          receiver: address(dytmTestPool),
          assets: _debtAssets,
          extraData: ""
        })
      )
    );
  }

  /// @dev Add `_asset` to the pool's supported assets if not already supported.
  function _ensurePoolSupportsAsset(address _asset) internal {
    IHasSupportedAsset.Asset[] memory supported = dytmTestPoolManagerLogic.getSupportedAssets();
    for (uint256 i; i < supported.length; ++i) {
      if (supported[i].asset == _asset) return;
    }
    IHasSupportedAsset.Asset[] memory toAdd = new IHasSupportedAsset.Asset[](1);
    toAdd[0] = IHasSupportedAsset.Asset({asset: _asset, isDeposit: false});
    vm.prank(manager);
    dytmTestPoolManagerLogic.changeAssets(toAdd, new address[](0));
  }

  /// @dev Build the per-asset complexAssetsData array for the pool's withdrawal, packing the DYTM
  ///      Office slot with the provided `_dytmWithdrawData`.
  function _buildComplexAssetsData(
    bytes memory _dytmWithdrawData,
    uint256 _slippageTolerance
  ) internal view returns (IPoolLogic.ComplexAsset[] memory) {
    IHasSupportedAsset.Asset[] memory supported = dytmTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssets = new IPoolLogic.ComplexAsset[](supported.length);
    for (uint256 i; i < supported.length; ++i) {
      complexAssets[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supported[i].asset,
        withdrawData: supported[i].asset == dytmOffice ? _dytmWithdrawData : new bytes(0),
        slippageTolerance: _slippageTolerance
      });
    }
    return complexAssets;
  }

  /// @dev Helper to build the redeem `IGMTokenManager.Quote` for the fresh SPYon attestation.
  function _spRedeemQuote() internal pure returns (IGMTokenManager.Quote memory) {
    return
      IGMTokenManager.Quote({
        chainId: 1,
        attestationId: SP_REDEEM_ATTESTATION_ID,
        userId: SP_USER_ID,
        asset: SPYON,
        price: SP_REDEEM_PRICE,
        quantity: SP_REDEEM_AMOUNT_IN,
        expiration: SP_REDEEM_EXPIRATION,
        side: uint8(IGMTokenManager.QuoteSide.SELL),
        additionalData: bytes32(0)
      });
  }

  // ───────────────────────────────────────────────────────────────────────────────
  // Pure helpers (mirror DYTM's tokenId / reserveKey encoding)
  // ───────────────────────────────────────────────────────────────────────────────

  function _escrowTokenId(address _asset, uint88 _marketId) internal pure returns (uint256) {
    // tokenType=ESCROW(1) << 248 | marketId << 160 | asset
    return (uint256(1) << 248) | (uint256(_marketId) << 160) | uint256(uint160(_asset));
  }

  function _lendTokenId(address _asset, uint88 _marketId) internal pure returns (uint256) {
    // tokenType=LEND(2) << 248 | marketId << 160 | asset
    return (uint256(2) << 248) | (uint256(_marketId) << 160) | uint256(uint160(_asset));
  }

  function _reserveKey(address _asset, uint88 _marketId) internal pure returns (uint248) {
    return (uint248(_marketId) << 160) | uint248(uint160(_asset));
  }

  function _toUserAccount(address _pool) internal pure returns (uint256) {
    return uint256(uint160(_pool));
  }
}
