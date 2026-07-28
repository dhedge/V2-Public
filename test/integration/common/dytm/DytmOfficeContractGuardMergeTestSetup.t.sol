// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IDytmDelegatee} from "contracts/interfaces/dytm/IDytmDelegatee.sol";
import {IDytmAccountSplitterAndMerger} from "contracts/interfaces/dytm/IDytmAccountSplitterAndMerger.sol";
import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmOfficeContractGuard} from "contracts/interfaces/dytm/IDytmOfficeContractGuard.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {DytmConfigStructs} from "contracts/utils/dytm/DytmConfigStructs.sol";
import {DytmOfficeAssetGuard} from "contracts/guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";
import {DytmWithdrawProcessor} from "contracts/swappers/easySwapperV2/DytmWithdrawProcessor.sol";
import {OndoGMTokenAssetGuard} from "contracts/guards/assetGuards/ondo/OndoGMTokenAssetGuard.sol";
import {OndoGMSwapTestSetup} from "test/integration/common/ondo/OndoGMSwapTestSetup.t.sol";

/// @title DytmOfficeContractGuardMergeTestSetup
/// @notice Mock-DYTM environment for `DytmOfficeContractGuard` MERGE_ACCOUNTS guard-logic tests.
///         The Office + Periphery + AccountSplitter are mocks so tests can puppet account
///         ownership (`setAccountOwner`) and the post-merge health factor (`armPostCallbackHF`)
///         — states that cannot be staged deterministically against the real mainnet DYTM
///         contracts. Everything dHEDGE-side (pool, guards, NFT tracker) is real.
/// @dev    Split out of `OndoDytmCollateralIntegrationTestSetup` when that setup migrated to the
///         real mainnet DYTM market 1 (SPYon); the collateral-withdrawal integration tests run
///         against the real contracts, while the merge guard tests keep this mock surface.
abstract contract DytmOfficeContractGuardMergeTestSetup is OndoGMSwapTestSetup {
  uint256 internal constant MISMATCH_DELTA_NUMERATOR = 5; // 5 bps
  uint256 internal constant MIN_REDEEM_VALUE = 1.1e18; // $1.10
  uint256 internal constant ASSET_TYPE_ONDO_GM = 41;
  uint256 internal constant ASSET_TYPE_DYTM_OFFICE = 106;
  uint88 internal constant TEST_MARKET_ID = 1;

  // Real
  OndoGMTokenAssetGuard internal ondoGMTokenAssetGuard;

  // DYTM-side mocks
  MockDytmOffice internal mockOffice;
  MockDytmPeriphery internal mockPeriphery;
  MockDytmAccountSplitter internal mockSplitter;

  // DYTM-side real (registered against the mocks)
  DytmOfficeAssetGuard internal dytmOfficeAssetGuard;
  IDytmOfficeContractGuard internal dytmOfficeContractGuard;
  DytmWithdrawProcessor internal dytmWithdrawProcessor;

  // Test pool / actors (`investor` is inherited from BackboneSetup)
  PoolLogic internal dytmTestPool;
  PoolManagerLogic internal dytmTestPoolManagerLogic;

  function setUp() public virtual override {
    super.setUp(); // OndoGMSwapTestSetup deploys ondoGMSwap, registers GOOGLON, sets up testPool (which we ignore here)

    vm.startPrank(owner);

    // 1. Deploy DYTM-side mocks
    mockOffice = new MockDytmOffice();
    mockPeriphery = new MockDytmPeriphery();
    mockSplitter = new MockDytmAccountSplitter();

    // Tie the periphery's reported position to the office's drain signal so a fully-drained
    // account reports zero collateral post-unwind (matching a real periphery). Without this the
    // periphery returns its static configured value and the new remnant bound trips spuriously.
    mockPeriphery.setDytmOffice(address(mockOffice));

    // 2. Deploy + register Ondo asset guard for type 41 (Ondo GM)
    ondoGMTokenAssetGuard = new OndoGMTokenAssetGuard(ondoGMSwap, MISMATCH_DELTA_NUMERATOR, MIN_REDEEM_VALUE);
    governance.setAssetGuard(uint16(ASSET_TYPE_ONDO_GM), address(ondoGMTokenAssetGuard));
    address googlonAggregator = address(assetHandlerProxy.priceAggregators(GOOGLON));
    assetHandlerProxy.addAsset(GOOGLON, uint16(ASSET_TYPE_ONDO_GM), googlonAggregator);

    // 3. Register the mockOffice as a supported asset (asset type 106). The asset guard +
    //    contract guard get wired below.
    assetHandlerProxy.addAsset(address(mockOffice), uint16(ASSET_TYPE_DYTM_OFFICE), address(usdPriceAggregator));

    vm.stopPrank();

    // 4. Create a real dhedge pool with USDC + GOOGLON + mockOffice as supported assets.
    _createTestPool();

    // 5. Wire the DYTM-side asset guard + contract guard against the mocks.
    _deployAndRegisterDytmGuards();

    // 6. Add mockOffice as a supported asset on the test pool (now that the contract guard is
    //    registered — addAssetCheck requires it).
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory dytmAsset = new IHasSupportedAsset.Asset[](1);
    dytmAsset[0] = IHasSupportedAsset.Asset({asset: address(mockOffice), isDeposit: false});
    dytmTestPoolManagerLogic.changeAssets(dytmAsset, new address[](0));

    // 7. Pool approves mockOffice to pull collateral / debt.
    dytmTestPool.execTransaction(
      GOOGLON,
      abi.encodeWithSelector(IERC20.approve.selector, address(mockOffice), type(uint256).max)
    );
    dytmTestPool.execTransaction(
      usdcData.asset,
      abi.encodeWithSelector(IERC20.approve.selector, address(mockOffice), type(uint256).max)
    );
    vm.stopPrank();

    // 8. Investor deposits USDC into the pool — exercises the asset guard's getBalance against
    //    the mock surface as a wiring sanity check.
    deal(usdcData.asset, investor, 20_000e6);
    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(dytmTestPool), 20_000e6);
    dytmTestPool.deposit(usdcData.asset, 20_000e6);
    vm.stopPrank();

    // 9. Advance one second past last deposit to satisfy PoolLogic's `lastDeposit` cooldown.
    vm.warp(block.timestamp + 1);
  }

  // ───────────────────────────────────────────────────────────────────────────────
  // Setup helpers
  // ───────────────────────────────────────────────────────────────────────────────

  /// @dev Override the inherited `OndoGMSwapTestSetup.testPool` — we use our own pool with the
  ///      DYTM Office included.
  function _createTestPool() internal {
    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: GOOGLON, isDeposit: false});
    // mockOffice added in setUp step 6 (after contract guard is registered).

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

    // Deploy DYTM unwind processor first — its address is baked into the asset guard.
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

    // Deploy + register the DYTM Office asset guard.
    dytmOfficeAssetGuard = new DytmOfficeAssetGuard(
      MISMATCH_DELTA_NUMERATOR,
      address(mockOffice),
      address(poolFactoryProxy),
      address(mockPeriphery),
      address(mockSplitter),
      address(dytmWithdrawProcessor)
    );
    governance.setAssetGuard(uint16(ASSET_TYPE_DYTM_OFFICE), address(dytmOfficeAssetGuard));

    // Deploy the DYTM Office contract guard with the test pool + market id whitelisted.
    address[] memory whitelistedPools = new address[](1);
    whitelistedPools[0] = address(dytmTestPool);
    uint88[] memory whitelistedMarkets = new uint88[](1);
    whitelistedMarkets[0] = TEST_MARKET_ID;
    DytmConfigStructs.DytmConfig memory dytmConfig = DytmConfigStructs.DytmConfig({
      dytmOffice: address(mockOffice),
      dytmPeriphery: address(mockPeriphery),
      dhedgePoolFactory: address(poolFactoryProxy),
      nftTracker: address(nftTrackerStorageProxy),
      accountSplitterAndMerger: address(mockSplitter),
      maxDytmMarkets: 5,
      admin: owner
    });
    dytmOfficeContractGuard = IDytmOfficeContractGuard(
      deployCode("DytmOfficeContractGuard.sol", abi.encode(whitelistedPools, whitelistedMarkets, dytmConfig))
    );
    governance.setContractGuard(address(mockOffice), address(dytmOfficeContractGuard));

    vm.stopPrank();
  }

  // ───────────────────────────────────────────────────────────────────────────────
  // Pure helpers (mirror DYTM's tokenId encoding)
  // ───────────────────────────────────────────────────────────────────────────────

  function _escrowTokenId(address _asset, uint88 _marketId) internal pure returns (uint256) {
    // tokenType=ESCROW(1) << 248 | marketId << 160 | asset
    return (uint256(1) << 248) | (uint256(_marketId) << 160) | uint256(uint160(_asset));
  }

  function _toUserAccount(address _pool) internal pure returns (uint256) {
    return uint256(uint160(_pool));
  }
}

// ─────────────────────────────────────────────────────────────────────────────────
// Mock contracts (inline; small enough that splitting into separate files isn't worth it)
// ─────────────────────────────────────────────────────────────────────────────────

/// @notice Stand-in for the AccountSplitterAndMerger delegatee. Returns a fake account id when
///         the asset guard delegationCalls it during withdrawal-time account splitting.
///
/// @dev    For merge-flow tests that need to simulate a post-merge change in the pool's HF
///         (which the real `MERGE_ACCOUNTS` op would cause), `armPostCallbackHF` lets the test
///         arm a one-shot mutation: on the next callback, the splitter writes the configured HF
///         into the bound periphery so the contract guard's afterTxGuard sees a different value
///         than its pre-snapshot. Disarms automatically after firing.
contract MockDytmAccountSplitter is IDytmDelegatee {
  uint256 public nextAccountId = 1;

  address public peripheryToMutate;
  uint256 public postCallbackHF;
  bool public postCallbackHFArmed;

  function armPostCallbackHF(address _periphery, uint256 _hf) external {
    peripheryToMutate = _periphery;
    postCallbackHF = _hf;
    postCallbackHFArmed = true;
  }

  function onDelegationCallback(bytes calldata _data) external override returns (bytes memory) {
    if (postCallbackHFArmed) {
      postCallbackHFArmed = false;
      DytmParamStructs.AccountPosition memory pos;
      pos.healthFactor = postCallbackHF;
      pos.isHealthy = postCallbackHF >= 1.01e18;
      MockDytmPeriphery(peripheryToMutate).setPosition(pos);
    }
    // Mirror the real AccountSplitterAndMerger: SPLIT returns the new account id; MERGE returns empty.
    IDytmAccountSplitterAndMerger.CallbackData memory cbData = abi.decode(
      _data,
      (IDytmAccountSplitterAndMerger.CallbackData)
    );
    if (cbData.operation == IDytmAccountSplitterAndMerger.Operation.MERGE_ACCOUNTS) {
      return "";
    }
    return abi.encode(nextAccountId++);
  }
}

/// @notice Stand-in for IDytmPeriphery. Single-position storage; the test pre-configures the
///         position via `setPosition` to model whatever scenario it's exercising.
contract MockDytmPeriphery {
  DytmParamStructs.DebtInfo internal _debt;
  DytmParamStructs.CollateralInfo[] internal _collaterals;
  uint256 internal _totalCollateralValueUSD;
  uint256 internal _totalWeightedCollateralValueUSD;
  // Mirrors the real DYTMPeriphery's no-debt sentinel: when debtValueUSD == 0 (including an
  // account with no position at all) it returns HF = type(uint256).max and isHealthy = true.
  uint256 internal _healthFactor = type(uint256).max;
  bool internal _isHealthy = true;
  address internal _dytmOffice;

  function setPosition(DytmParamStructs.AccountPosition memory _position) external {
    _debt = _position.debt;
    delete _collaterals;
    for (uint256 i; i < _position.collaterals.length; ++i) {
      _collaterals.push(_position.collaterals[i]);
    }
    _totalCollateralValueUSD = _position.totalCollateralValueUSD;
    _totalWeightedCollateralValueUSD = _position.totalWeightedCollateralValueUSD;
    _healthFactor = _position.healthFactor;
    _isHealthy = _position.isHealthy;
  }

  /// @dev Optional office reference. When set, a fully-drained account (no collateral IDs in the
  ///      office) reports a zeroed position so the post-unwind remnant bound sees 0 — mirroring a
  ///      real periphery. Left unset, the static configured position is always returned.
  function setDytmOffice(address office) external {
    _dytmOffice = office;
  }

  function getAccountPosition(
    uint256 account,
    uint88 market
  ) external view returns (DytmParamStructs.AccountPosition memory pos) {
    if (_dytmOffice != address(0) && IDytmOffice(_dytmOffice).getAllCollateralIds(account, market).length == 0) {
      // Drained account: no collateral, no debt. Zero values except the real periphery's
      // no-debt sentinel (HF = max, healthy).
      pos.healthFactor = type(uint256).max;
      pos.isHealthy = true;
      return pos;
    }
    pos.debt = _debt;
    DytmParamStructs.CollateralInfo[] memory collaterals = new DytmParamStructs.CollateralInfo[](_collaterals.length);
    for (uint256 i; i < _collaterals.length; ++i) {
      collaterals[i] = _collaterals[i];
    }
    pos.collaterals = collaterals;
    pos.totalCollateralValueUSD = _totalCollateralValueUSD;
    pos.totalWeightedCollateralValueUSD = _totalWeightedCollateralValueUSD;
    pos.healthFactor = _healthFactor;
    pos.isHealthy = _isHealthy;
  }
}

/// @notice Stand-in for IDytmOffice. Implements just enough of the surface for the dispatcher's
///         caller chain to work end-to-end (delegationCall, withdraw, transfer, supply, borrow,
///         repay, accrueInterest, callerContext, getAccountCount, getAllCollateralIds,
///         isHealthyAccount). Single collateral + debt asset, configured by the test setup.
contract MockDytmOffice {
  address public callerContext;
  address public collateralAsset;
  address public debtAsset;
  uint256 public debtBalance;
  uint96 public accountCount;
  uint256 internal _escrowTokenIdHint;
  uint256 internal _debtIdHint;
  mapping(uint256 => address) internal _isolatedAccountOwner;

  /// @dev Register the owner of an ISOLATED_ACCOUNT, mirroring DYTM's `Registry.ownerOf` storage.
  ///      User accounts derive their owner from the embedded address and need no registration.
  function setAccountOwner(uint256 _account, address _owner) external {
    _isolatedAccountOwner[_account] = _owner;
  }

  /// @dev Mirrors `Registry.ownerOf`: user accounts resolve to their embedded address; isolated
  ///      accounts resolve to the registered owner.
  function ownerOf(uint256 _account) external view returns (address) {
    uint160 addressField = uint160(_account);
    uint96 count = uint96(_account >> 160);
    if (addressField != 0 && count == 0) return address(addressField); // user account
    return _isolatedAccountOwner[_account]; // isolated account
  }

  function setCollateralAsset(address _asset) external {
    collateralAsset = _asset;
  }

  function setDebtAsset(address _asset) external {
    debtAsset = _asset;
  }

  function setEscrowTokenIdHint(uint256 _tokenId) external {
    _escrowTokenIdHint = _tokenId;
  }

  function setDebtIdHint(uint256 _debtId) external {
    _debtIdHint = _debtId;
  }

  function delegationCall(
    DytmParamStructs.DelegationCallParams calldata params
  ) external returns (bytes memory returnData) {
    address prev = callerContext;
    callerContext = msg.sender;
    returnData = params.delegatee.onDelegationCallback(params.callbackData);
    callerContext = prev;
  }

  function withdraw(DytmParamStructs.WithdrawParams calldata p) external returns (uint256) {
    if (collateralAsset != address(0) && IERC20(collateralAsset).balanceOf(address(this)) > 0) {
      uint256 amount = p.shares > 0 ? p.shares : p.assets;
      uint256 bal = IERC20(collateralAsset).balanceOf(address(this));
      if (amount > bal) amount = bal;
      _safeTransfer(collateralAsset, p.receiver, amount);
      // Reflect the drained balance in `getAllCollateralIds` so the dispatcher's "no collateral
      // remaining" post-condition matches reality once the position is empty.
      if (IERC20(collateralAsset).balanceOf(address(this)) == 0) {
        _escrowTokenIdHint = 0;
      }
      return amount;
    }
    return 0;
  }

  function supply(DytmParamStructs.SupplyParams calldata p) external returns (uint256) {
    if (collateralAsset != address(0) && p.assets > 0) {
      _safeTransferFrom(collateralAsset, msg.sender, address(this), p.assets);
    }
    return p.assets;
  }

  function borrow(DytmParamStructs.BorrowParams calldata p) external returns (uint256) {
    if (debtAsset != address(0) && p.assets > 0) {
      _safeTransfer(debtAsset, p.receiver, p.assets);
      debtBalance += p.assets;
    }
    return p.assets;
  }

  function repay(DytmParamStructs.RepayParams calldata p) external returns (uint256) {
    uint256 toRepay = p.assets;
    if (toRepay > debtBalance) toRepay = debtBalance;
    if (debtAsset != address(0) && toRepay > 0) {
      _safeTransferFrom(debtAsset, msg.sender, address(this), toRepay);
      debtBalance -= toRepay;
    }
    return toRepay;
  }

  function transfer(address, uint256, uint256) external pure returns (bool) {
    return true;
  }

  function isHealthyAccount(uint256, uint88) external pure returns (bool) {
    return true;
  }

  function getAccountCount() external view returns (uint96) {
    return accountCount;
  }

  function accrueInterest(uint248) external pure returns (uint256) {
    return 0;
  }

  function getAllCollateralIds(uint256, uint88) external view returns (uint256[] memory ids) {
    if (_escrowTokenIdHint == 0) return ids;
    ids = new uint256[](1);
    ids[0] = _escrowTokenIdHint;
  }

  function getDebtId(uint256, uint88) external view returns (uint256) {
    return _debtIdHint;
  }

  function _safeTransfer(address _token, address _to, uint256 _amount) internal {
    (bool ok, bytes memory ret) = _token.call(abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount));
    require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "mock transfer failed");
  }

  function _safeTransferFrom(address _token, address _from, address _to, uint256 _amount) internal {
    (bool ok, bytes memory ret) = _token.call(
      abi.encodeWithSelector(IERC20.transferFrom.selector, _from, _to, _amount)
    );
    require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "mock transferFrom failed");
  }
}
