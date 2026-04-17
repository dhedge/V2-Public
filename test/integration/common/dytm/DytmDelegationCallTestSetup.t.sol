// SPDX-License-Identifier: MIT
// solhint-disable no-unused-vars

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {Governance} from "contracts/Governance.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IDytmOfficeContractGuard} from "contracts/interfaces/dytm/IDytmOfficeContractGuard.sol";
import {DytmOfficeAssetGuard} from "contracts/guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmPeriphery} from "contracts/interfaces/dytm/IDytmPeriphery.sol";
import {IDytmDelegatee} from "contracts/interfaces/dytm/IDytmDelegatee.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {DytmConfigStructs} from "contracts/utils/dytm/DytmConfigStructs.sol";
import {IDytmAddressAccountBaseWhitelist} from "./dytmInterface/IDytmAddressAccountBaseWhitelist.sol";
import {IMarketConfig} from "./dytmInterface/IDytmMarketConfig.sol";
import {IDytmOracleModule} from "./dytmInterface/IDytmOracleModule.sol";
import {IDytmSimpleMarketConfig} from "./dytmInterface/IDytmSimpleMarketConfig.sol";
import {IDytmWeights} from "./dytmInterface/IDytmWeights.sol";
import {OdosAPIHelper} from "../odos/OdosAPIHelper.sol";
import {OdosV3ContractGuard} from "contracts/guards/contractGuards/odos/OdosV3ContractGuard.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {EasySwapperV2ContractGuard} from "contracts/guards/contractGuards/EasySwapperV2ContractGuard.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import {WithdrawalVault} from "contracts/swappers/easySwapperV2/WithdrawalVault.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {DytmSplitTokenIdTracker} from "contracts/guards/assetGuards/dytm/DytmSplitTokenIdTracker.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/ProxyAdmin.sol";

abstract contract DytmDelegationCallTestSetup is BackboneSetup, IntegrationDeployer, OdosAPIHelper {
  // DYTM Configuration
  address public immutable dytmOffice;
  address public immutable dytmPeriphery;
  address public immutable dytmMarketConfig;
  address public immutable accountSplitterAndMerger;
  address public immutable nftTracker;

  // Asset Configuration
  address public immutable collateralAsset;
  address public immutable borrowAsset;
  address public immutable swapToAsset; // Configurable swap destination asset (e.g., WETH)
  address public immutable collateralOracle;
  address public immutable borrowOracle;
  address public immutable swapToAssetOracle;

  // Amount Configuration
  uint256 public immutable collateralAmountNormalized;
  uint256 public immutable borrowAmountNormalized;

  // Other Configuration
  uint256 public immutable maxDytmMarkets;
  bool public immutable isCollateralDhedgePoolToken;
  address public immutable marketCreator;
  PoolFactory public immutable dhedgePoolFactory;
  uint88 public marketId;
  address public immutable slippageAccumulatorAddress; // Add slippage accumulator

  // Odos Configuration
  address public immutable odosRouter;
  uint256 public immutable chainId;

  // Pendle PT Configuration
  address public immutable pendlePT;
  address public immutable pendleMarket;
  address public immutable pendlePTUnderlying;
  address public immutable pendleStaticRouter;

  bytes4 private constant DEPOSIT_CUSTOM_COOLDOWN_SELECTOR =
    bytes4(keccak256("depositWithCustomCooldown(address,address,uint256,uint256)"));

  // Contract Instances
  PoolLogic public dytmTestPool;
  PoolManagerLogic public dytmTestPoolManagerLogic;
  IDytmOfficeContractGuard public dytmOfficeContractGuard;
  DytmOfficeAssetGuard public dytmOfficeAssetGuard;
  OdosV3ContractGuard public odosContractGuard;
  EasySwapperV2 public easySwapperV2Instance; // Renamed to avoid conflict with BackboneSetup
  EasySwapperV2ContractGuard public easySwapperV2ContractGuard;
  ProxyAdmin public proxyAdminProd;

  struct DytmDelegationCallTestConfig {
    address dhedgePoolFactory;
    address dytmOffice;
    address dytmPeriphery;
    address dytmMarketConfig;
    address accountSplitterAndMerger;
    address nftTracker;
    address collateralAsset;
    address borrowAsset;
    address swapToAsset;
    uint256 collateralAmountNormalized;
    uint256 borrowAmountNormalized;
    address collateralOracle;
    address borrowOracle;
    address swapToAssetOracle;
    uint256 maxDytmMarkets;
    bool isCollateralDhedgePoolToken;
    address marketCreator;
    uint88 dytmMarketId;
    address odosRouter;
    uint256 chainId;
    address slippageAccumulator; // Add this field
    address easySwapperV2Instance;
    address proxyAdmin;
    // Pendle PT Configuration (optional, address(0) = no PT)
    address pendlePT;
    address pendleMarket;
    address pendlePTUnderlying;
    address pendleStaticRouter;
  }

  constructor(DytmDelegationCallTestConfig memory config) {
    dhedgePoolFactory = PoolFactory(config.dhedgePoolFactory);
    dytmOffice = config.dytmOffice;
    dytmPeriphery = config.dytmPeriphery;
    dytmMarketConfig = config.dytmMarketConfig;
    accountSplitterAndMerger = config.accountSplitterAndMerger;
    nftTracker = config.nftTracker;
    collateralAsset = config.collateralAsset;
    borrowAsset = config.borrowAsset;
    swapToAsset = config.swapToAsset;
    collateralAmountNormalized = config.collateralAmountNormalized;
    borrowAmountNormalized = config.borrowAmountNormalized;
    collateralOracle = config.collateralOracle;
    borrowOracle = config.borrowOracle;
    swapToAssetOracle = config.swapToAssetOracle;
    maxDytmMarkets = config.maxDytmMarkets;
    isCollateralDhedgePoolToken = config.isCollateralDhedgePoolToken;
    marketCreator = config.marketCreator;
    marketId = config.dytmMarketId;
    odosRouter = config.odosRouter;
    chainId = config.chainId;
    slippageAccumulatorAddress = config.slippageAccumulator; // Store it
    easySwapperV2Instance = EasySwapperV2(config.easySwapperV2Instance);
    proxyAdminProd = ProxyAdmin(config.proxyAdmin);
    pendlePT = config.pendlePT;
    pendleMarket = config.pendleMarket;
    pendlePTUnderlying = config.pendlePTUnderlying;
    pendleStaticRouter = config.pendleStaticRouter;
  }

  function deployIntegration(PoolFactory _poolFactory, address, address, address _usdPriceAggregator) public override {
    Governance governance = Governance(_poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    // Deploy Dytm Office Asset Guard
    dytmOfficeAssetGuard = new DytmOfficeAssetGuard(
      5,
      pendleStaticRouter,
      dytmOffice,
      address(_poolFactory),
      dytmPeriphery,
      accountSplitterAndMerger,
      address(0) // dytmWithdrawProcessor — set later when deployed
    );
    governance.setAssetGuard(uint16(106), address(dytmOfficeAssetGuard)); // Asset type 106 for DYTM

    // Add dytm office as supported asset
    assetHandler.addAsset(dytmOffice, uint16(106), _usdPriceAggregator);

    // Add collateral asset
    if (isCollateralDhedgePoolToken) {
      // Deploy DHedgePoolAggregator via deployCode (0.8.28 contract, can't use `new` from 0.7.6)
      address dhedgePoolAggregator = deployCode("DHedgePoolAggregator.sol", abi.encode(collateralAsset));
      assetHandler.addAsset(collateralAsset, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), dhedgePoolAggregator);
    } else {
      assetHandler.addAsset(collateralAsset, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), collateralOracle);
    }

    // Add borrow asset
    assetHandler.addAsset(borrowAsset, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), borrowOracle);

    // Add swap destination asset (e.g., WETH)
    assetHandler.addAsset(swapToAsset, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), swapToAssetOracle);

    assetHandler.addAsset(
      address(easySwapperV2Instance),
      uint16(BackboneSetup.AssetTypeIncomplete.EASYSWAPPER_V2_UNROLLED),
      _usdPriceAggregator
    );

    vm.stopPrank();
  }

  function deployContractGuards(PoolFactory _poolFactory, PoolLogic testPoolLogic) internal {
    Governance governance = Governance(_poolFactory.governanceAddress());

    vm.startPrank(_poolFactory.owner());

    // Deploy Odos V3 Contract Guard - use slippageAccumulatorAddress
    odosContractGuard = new OdosV3ContractGuard(slippageAccumulatorAddress);
    governance.setContractGuard(odosRouter, address(odosContractGuard));

    // Deploy EasySwapperV2 Contract Guard - use slippageAccumulatorAddress
    easySwapperV2ContractGuard = new EasySwapperV2ContractGuard(slippageAccumulatorAddress, 200); // 2% max slippage
    governance.setContractGuard(address(easySwapperV2Instance), address(easySwapperV2ContractGuard));

    // Create whitelisted pools and markets
    address[] memory whitelistedPools = new address[](1);
    whitelistedPools[0] = address(testPoolLogic);

    uint88[] memory whitelistedMarkets = new uint88[](1);
    whitelistedMarkets[0] = marketId;

    // Create dytm config
    DytmConfigStructs.DytmConfig memory dytmConfig = DytmConfigStructs.DytmConfig({
      dytmOffice: dytmOffice,
      dytmPeriphery: dytmPeriphery,
      dhedgePoolFactory: address(_poolFactory),
      nftTracker: nftTracker,
      maxDytmMarkets: maxDytmMarkets
    });

    // Deploy DytmOfficeContractGuard via deployCode (0.8.28 contract, can't use `new` from 0.7.6)
    dytmOfficeContractGuard = IDytmOfficeContractGuard(
      deployCode("DytmOfficeContractGuard.sol", abi.encode(whitelistedPools, whitelistedMarkets, dytmConfig))
    );
    governance.setContractGuard(dytmOffice, address(dytmOfficeContractGuard));

    vm.stopPrank();
  }

  function setUp() public virtual override {
    super.setUp();
    __OdosAPIHelper_init(true);

    vm.startPrank(dhedgePoolFactory.owner());
    // add timeout to asset Handler
    AssetHandler assetHandler = AssetHandler(dhedgePoolFactory.getAssetHandler());
    assetHandler.setChainlinkTimeout(86400 * 365); // 1 year
    vm.stopPrank();

    _extendDytmOracleStaleness();

    vm.startPrank(dhedgePoolFactory.owner());
    dhedgePoolFactory.setPerformanceFeeNumeratorChangeDelay(0);
    // Add EasySwapperV2 to custom cooldown whitelist
    dhedgePoolFactory.addCustomCooldownWhitelist(address(easySwapperV2Instance));
    vm.stopPrank();

    deployIntegration(dhedgePoolFactory, address(0), address(0), address(usdPriceAggregator));

    vm.startPrank(manager);

    // Create pool without DYTM Office initially (contract guard must be set before addAssetCheck)
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](4);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: borrowAsset, isDeposit: false});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: swapToAsset, isDeposit: false});
    supportedAssets[3] = IHasSupportedAsset.Asset({asset: address(easySwapperV2Instance), isDeposit: false});

    dytmTestPool = PoolLogic(
      dhedgePoolFactory.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Dytm Delegation Tester",
        _fundName: "Dytm Delegation Test Pool",
        _fundSymbol: "DDTP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    dytmTestPoolManagerLogic = PoolManagerLogic(dytmTestPool.poolManagerLogic());

    vm.stopPrank();

    //

    // Upgrade PoolFactory implementation to support valueManipulationCheck
    vm.startPrank(dhedgePoolFactory.owner());
    proxyAdminProd.upgrade(
      TransparentUpgradeableProxy(payable(address(dhedgePoolFactory))),
      address(new PoolFactory())
    );

    // Deploy new PoolLogic implementation with onDelegationCallback support
    PoolLogic newPoolLogicImplementation = new PoolLogic();
    // Get the current PoolManagerLogic implementation
    address currentPoolManagerLogicImpl = dhedgePoolFactory.getLogic(1); // Logic type 1 is PoolManagerLogic

    dhedgePoolFactory.setLogic(address(newPoolLogicImplementation), currentPoolManagerLogicImpl); // Logic type 2 is PoolLogic

    // dhedgePoolFactory.addReceiverWhitelist(easySwapperV2Instance)

    vm.stopPrank();

    // Whitelist the pool in DYTM market
    vm.startPrank(marketCreator);
    address hook = IMarketConfig(dytmMarketConfig).hooks();
    IDytmAddressAccountBaseWhitelist(hook).setAddressWhitelist(address(dytmTestPool), true);
    vm.stopPrank();

    // If collateralAsset is a dHedge pool token, whitelist it in EasySwapperV2 for custom cooldown deposits
    if (isCollateralDhedgePoolToken) {
      address collateralPoolManager = PoolLogic(collateralAsset).poolManagerLogic();
      vm.startPrank(PoolManagerLogic(collateralPoolManager).manager());
      PoolManagerLogic(collateralPoolManager).announceFeeIncrease(0, 0, 10, 0); // Announce 0.1% entry fee

      PoolManagerLogic(collateralPoolManager).commitFeeIncrease(); // Execute the fee increase
      vm.stopPrank();
      vm.startPrank(dhedgePoolFactory.owner());
      EasySwapperV2.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2.WhitelistSetting[](1);
      whitelistSettings[0] = EasySwapperV2.WhitelistSetting({toWhitelist: collateralAsset, whitelisted: true});
      easySwapperV2Instance.setCustomCooldownWhitelist(whitelistSettings);

      // Deploy new EasySwapperV2 implementation
      address newEasySwapperV2Implementation = address(new EasySwapperV2());

      // Get the TransparentUpgradeableProxy for EasySwapperV2
      TransparentUpgradeableProxy easySwapperProxy = TransparentUpgradeableProxy(
        payable(address(easySwapperV2Instance))
      );

      // Upgrade the proxy to point to the new implementation
      ProxyAdmin(proxyAdminProd).upgrade(easySwapperProxy, newEasySwapperV2Implementation);

      // Deploy new WithdrawalVault logic implementation
      address newWithdrawalVaultLogic = address(new WithdrawalVault());
      easySwapperV2Instance.setLogic(newWithdrawalVaultLogic);

      //
      address existingVault = easySwapperV2Instance.withdrawalContracts(address(dytmTestPool));
      address predictedVault;
      if (existingVault != address(0)) {
        // Vault already exists, use it
        predictedVault = existingVault;
      } else {
        // Vault will be created, predict its address
        uint64 nonce = vm.getNonce(address(easySwapperV2Instance));
        predictedVault = vm.computeCreateAddress(address(easySwapperV2Instance), nonce);
      }
      dhedgePoolFactory.addReceiverWhitelist(predictedVault);

      vm.stopPrank();
    }

    // Deploy contract guards after pool is created (needs pool address for whitelisting)
    deployContractGuards(dhedgePoolFactory, dytmTestPool);

    // Add DYTM Office asset after contract guard is set (addAssetCheck requires it)
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory dytmAsset = new IHasSupportedAsset.Asset[](1);
    dytmAsset[0] = IHasSupportedAsset.Asset({asset: dytmOffice, isDeposit: false});
    dytmTestPoolManagerLogic.changeAssets(dytmAsset, new address[](0));
    vm.stopPrank();

    vm.startPrank(manager);
    // Approve all necessary contracts and assets
    dytmTestPool.execTransaction(
      collateralAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, dytmOffice, type(uint256).max)
    );
    dytmTestPool.execTransaction(
      borrowAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, dytmOffice, type(uint256).max)
    );
    dytmTestPool.execTransaction(
      borrowAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, odosRouter, type(uint256).max)
    );
    dytmTestPool.execTransaction(
      swapToAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, dytmOffice, type(uint256).max)
    );
    dytmTestPool.execTransaction(
      swapToAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, odosRouter, type(uint256).max)
    );
    dytmTestPool.execTransaction(
      swapToAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, address(easySwapperV2Instance), type(uint256).max)
    );
    vm.stopPrank();

    // Investor setup
    vm.startPrank(investor);

    uint256 collateralAmount = collateralAmountNormalized * (10 ** IERC20Extended(collateralAsset).decimals());

    // Investor deposits collateral into the dytm test pool
    deal(collateralAsset, investor, collateralAmount);
    IERC20Extended(collateralAsset).approve(address(dytmTestPool), type(uint256).max);
    dytmTestPool.deposit(collateralAsset, collateralAmount);

    // Investor also deposits into dytm market so that the pool can borrow later
    uint256 amountToSupplyBorrowAsset = borrowAmountNormalized * 10 * (10 ** IERC20Extended(borrowAsset).decimals());
    deal(borrowAsset, investor, amountToSupplyBorrowAsset);
    IERC20Extended(borrowAsset).approve(dytmOffice, type(uint256).max);
    IDytmOffice(dytmOffice).supply(
      DytmParamStructs.SupplyParams({
        account: uint256(uint160(address(investor))),
        tokenId: _getTokenIdForLend(borrowAsset),
        assets: amountToSupplyBorrowAsset,
        extraData: ""
      })
    );

    vm.stopPrank();
  }

  // ========== DYTM Oracle Staleness Extension ==========

  function _extendDytmOracleStaleness() internal {
    address oracleModule = IMarketConfig(dytmMarketConfig).oracleModule();
    IDytmOracleModule dytmOracle = IDytmOracleModule(oracleModule);

    vm.startPrank(marketCreator);

    _extendOracleStalenessIfSet(dytmOracle, borrowAsset);
    _extendOracleStalenessIfSet(dytmOracle, swapToAsset);
    if (!isCollateralDhedgePoolToken) {
      _extendOracleStalenessIfSet(dytmOracle, collateralAsset);
    }

    vm.stopPrank();
  }

  function _extendOracleStalenessIfSet(IDytmOracleModule dytmOracle, address asset) internal {
    (address oracle, , ) = dytmOracle.oracles(asset);
    if (oracle != address(0)) {
      dytmOracle.setOracle(asset, oracle, 86400 * 365);
    }
  }

  // ========== Test Helper Functions ==========

  /**
   * @notice Helper to build swap data for Odos V3
   */
  function _getSwapData(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    uint8 slippage
  ) internal returns (uint256 destAmount, bytes memory swapData) {
    OdosAPIHelper.OdosFunctionStruct memory params = OdosAPIHelper.OdosFunctionStruct({
      srcAmount: srcAmount,
      srcToken: srcToken,
      destToken: destToken,
      user: address(dytmTestPool),
      slippage: slippage
    });
    (destAmount, swapData) = getDataFromOdos(params, chainId, true, "v3");
  }

  //a simple test for delegation call to one supply tx
  function test_delegation_call_to_supply_tx() public {
    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    // uint256 supplyAmount = 1000 * (10 ** IERC20Extended(collateralAsset).decimals());
    // Prepare the delegation call
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](1);
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

    // Execute the delegation call
    vm.startPrank(manager);
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
    vm.stopPrank();
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    // Assertions
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore,
      0.0001e18,
      "Total value should remain similar (0.01% tolerance)"
    );
  }

  function _leverage_up() internal {
    // Step 1: Supply initial collateral to DYTM
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    // Step 2: Prepare leverage-up multicall transaction
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());

    // Get swap data for borrowAsset -> swapToAsset
    (uint256 expectedSwapToAssetAmount, bytes memory swapData) = _getSwapData({
      srcToken: borrowAsset,
      destToken: swapToAsset,
      srcAmount: borrowAmount,
      slippage: 1 // 1% slippage
    });
    uint256 expectedSwapToAssetAmountAdjusted = (expectedSwapToAssetAmount * 99) / 100; // 1% slippage adjustment

    // Build multicall data for delegation call using PoolLogic.TxToExecute
    // If collateralAsset is a dHedge pool token, we need to deposit swapToAsset into it via EasySwapperV2
    uint256 callCount = isCollateralDhedgePoolToken ? 4 : 3;
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](callCount);

    // Call 1: Borrow from DYTM
    txs[0] = PoolLogic.TxToExecute({
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

    // Call 2: Swap borrowed asset to swapToAsset via Odos
    txs[1] = PoolLogic.TxToExecute({to: odosRouter, data: swapData});

    if (isCollateralDhedgePoolToken) {
      // Get expected pool tokens from depositQuote
      uint256 expectedPoolTokens = easySwapperV2Instance.depositQuote(
        collateralAsset,
        swapToAsset,
        expectedSwapToAssetAmountAdjusted
      );
      uint256 expectedPoolTokensAdjusted = (expectedPoolTokens * 99) / 100; // 1% slippage adjustment

      // Call 3: Deposit swapToAsset into collateralAsset pool via EasySwapperV2 with custom cooldown
      txs[2] = PoolLogic.TxToExecute({
        to: address(easySwapperV2Instance),
        data: abi.encodeWithSelector(
          DEPOSIT_CUSTOM_COOLDOWN_SELECTOR,
          collateralAsset, // dHedge vault
          swapToAsset, // deposit token
          expectedSwapToAssetAmountAdjusted, // deposit amount
          expectedPoolTokensAdjusted // expected amount received (slippage protection)
        )
      });

      // Call 4: Supply the received collateralAsset pool tokens to DYTM as collateral
      txs[3] = PoolLogic.TxToExecute({
        to: dytmOffice,
        data: abi.encodeWithSelector(
          IDytmOffice.supply.selector,
          DytmParamStructs.SupplyParams({
            account: uint256(uint160(address(dytmTestPool))),
            tokenId: _getTokenIdForEscrow(collateralAsset),
            assets: expectedPoolTokensAdjusted,
            extraData: ""
          })
        )
      });
    } else {
      // Call 3: Supply swapToAsset as collateral into DYTM directly
      txs[2] = PoolLogic.TxToExecute({
        to: dytmOffice,
        data: abi.encodeWithSelector(
          IDytmOffice.supply.selector,
          DytmParamStructs.SupplyParams({
            account: uint256(uint160(address(dytmTestPool))),
            tokenId: _getTokenIdForEscrow(swapToAsset),
            assets: expectedSwapToAssetAmountAdjusted,
            extraData: ""
          })
        )
      });
    }

    // Execute delegation call
    vm.startPrank(manager);
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

    vm.stopPrank();
  }

  /**
   * @notice Test leverage up: supply collateral, borrow, swap to swapToAsset, deposit into collateral pool, supply to DYTM
   * @dev This simulates a complete leverage-up flow in a single delegationCall
   * If collateralAsset is a dHedge pool token, we:
   *   1. Borrow borrowAsset
   *   2. Swap borrowAsset -> swapToAsset
   *   3. Deposit swapToAsset into collateralAsset pool via EasySwapperV2 (to get pool tokens)
   *   4. Supply the received pool tokens to DYTM as collateral
   */
  function test_can_leverage_up_with_delegation_call() public {
    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    _leverage_up();

    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();

    // Assertions
    assertEq(IERC20Extended(borrowAsset).balanceOf(address(dytmTestPool)), 0, "Should have no borrow asset left");
    if (!isCollateralDhedgePoolToken) {
      assertEq(
        IERC20Extended(swapToAsset).balanceOf(address(dytmTestPool)),
        0,
        "Should have no swap asset left (all supplied)"
      );
    }
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.01e18, "Total value should remain similar (1% tolerance)");

    // Verify position has both collateral and debt
    DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    assertGt(position.totalCollateralValueUSD, 0, "Should have collateral");
    assertGt(position.debt.debtAssets, 0, "Should have debt");
    assertGt(position.healthFactor, 1.01e18, "Health factor should be above minimum");
  }

  function test_can_leverage_down_with_delegation_call() public {
    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Leverage up first
    _leverage_up();

    // Get position after leverage up
    DytmParamStructs.AccountPosition memory positionAfterLeverageUp = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    uint256 totalValueAfterLeverageUp = dytmTestPoolManagerLogic.totalFundValue();

    // Now leverage down
    _leverage_down();

    // Get position after leverage down
    DytmParamStructs.AccountPosition memory positionAfterLeverageDown = IDytmPeriphery(dytmPeriphery)
      .getAccountPosition(uint256(uint160(address(dytmTestPool))), marketId);

    uint256 totalValueAfterLeverageDown = dytmTestPoolManagerLogic.totalFundValue();

    // Assertions for leverage down
    assertLt(
      positionAfterLeverageDown.debt.debtAssets,
      positionAfterLeverageUp.debt.debtAssets,
      "Debt should be reduced after leverage down"
    );
    assertLt(
      positionAfterLeverageDown.totalCollateralValueUSD,
      positionAfterLeverageUp.totalCollateralValueUSD,
      "Collateral should be reduced after leverage down"
    );
    assertGt(
      positionAfterLeverageDown.healthFactor,
      positionAfterLeverageUp.healthFactor,
      "Health factor should improve after leverage down"
    );
    assertGt(positionAfterLeverageDown.healthFactor, 1.01e18, "Health factor should remain above minimum");

    // Verify total value is preserved (accounting for fees and slippage)
    assertApproxEqRel(
      totalValueAfterLeverageDown,
      totalValueBefore,
      0.03e18,
      "Total value should remain similar (3% tolerance for fees and slippage)"
    );

    assertApproxEqRel(
      totalValueAfterLeverageDown,
      totalValueAfterLeverageUp,
      0.03e18,
      "Total value should remain similar (3% tolerance for fees and slippage)"
    );

    // Verify we still have some debt (we only repaid half)
    assertGt(positionAfterLeverageDown.debt.debtAssets, 0, "Should still have remaining debt after partial repay");
    assertApproxEqRel(
      positionAfterLeverageDown.debt.debtAssets,
      positionAfterLeverageUp.debt.debtAssets / 2,
      0.05e18,
      "Should have approximately half the debt remaining (5% tolerance)"
    );
  }

  function _leverage_down() internal {
    // Approve EasySwapperV2 to spend collateral tokens if needed
    if (isCollateralDhedgePoolToken) {
      vm.prank(manager);
      dytmTestPool.execTransaction(
        collateralAsset,
        abi.encodeWithSelector(IERC20Extended.approve.selector, address(easySwapperV2Instance), type(uint256).max)
      );
    }

    // Get current position info
    DytmParamStructs.AccountPosition memory positionBefore = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    // We want to repay half of the debt
    // In leverage-up, we borrowed borrowAmount and swapped it to get swapToAssetAmount
    // To reverse this, we need to figure out how much swapToAsset we need to swap back

    // Step 1: Calculate how much swapToAsset we got during leverage-up
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());

    // We need to get the actual swap quote to know how much swapToAsset we received
    // This is approximately what we got during leverage-up
    (uint256 swapToAssetReceivedDuringLeverageUp, ) = _getSwapData({
      srcToken: borrowAsset,
      destToken: swapToAsset,
      srcAmount: borrowAmount,
      slippage: 1
    });

    // Step 2: Calculate proportion we want to deleverage (50% since we're repaying half)
    uint256 proportionToDeleverage = 1e18 / 2; // 50% = 0.5 in 18 decimals

    // Step 3: Calculate how much swapToAsset we need to withdraw and swap back
    uint256 swapToAssetToSwapBack = (swapToAssetReceivedDuringLeverageUp * proportionToDeleverage) / 1e18;

    // Step 5: Calculate collateral to withdraw
    uint256 collateralToWithdraw;
    if (isCollateralDhedgePoolToken) {
      // We need to calculate how many pool tokens represent swapToAssetToSwapBack
      // 1. Get the USD value of swapToAssetToSwapBack
      // 2. Divide by pool token price to get number of pool tokens

      uint256 poolTokenPrice = PoolLogic(collateralAsset).tokenPrice();

      // Get the price of swapToAsset in USD (18 decimals)
      IAssetHandler assetHandler = IAssetHandler(dhedgePoolFactory.getAssetHandler());
      uint256 swapToAssetPriceUSD = assetHandler.getUSDPrice(swapToAsset);

      // Calculate USD value of swapToAssetToSwapBack
      // swapToAssetToSwapBack is in swapToAsset decimals, multiply by price (18 decimals)
      // Result is in 18 + 18 decimals, so divide by 10^swapToAssetDecimals to get USD value in 18 decimals
      uint256 swapToAssetDecimals = IERC20Extended(swapToAsset).decimals();
      uint256 usdValueOfSwapToAsset = (swapToAssetToSwapBack * swapToAssetPriceUSD) / (10 ** swapToAssetDecimals);

      // Calculate pool tokens needed: USD value / pool token price
      // Both are in 18 decimals, so result is in 18 decimals (pool token amount)
      // Add 2% buffer for fees and slippage
      collateralToWithdraw = (usdValueOfSwapToAsset * 102 * (10 ** 18)) / (poolTokenPrice * 100);
    } else {
      // Direct collateral case: withdraw the swapToAsset amount
      collateralToWithdraw = swapToAssetToSwapBack;
    }

    // Build deleverage multicall in REVERSE order
    uint256 callCount = isCollateralDhedgePoolToken ? 5 : 3; // Added +1 for the swap after unroll
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](callCount);

    // REVERSE ORDER (opposite of leverage up):
    // Leverage up: 1. Borrow, 2. Swap, 3. Deposit pool, 4. Supply
    // Leverage down: 1. Withdraw, 2. Unroll pool, 3. Swap unrolled assets to swapToAsset, 4. Swap to borrowAsset, 5. Repay

    // Call 1 (REVERSE): Withdraw collateral from DYTM
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(isCollateralDhedgePoolToken ? collateralAsset : swapToAsset),
          receiver: address(dytmTestPool),
          assets: collateralToWithdraw,
          shares: 0,
          extraData: ""
        })
      )
    });

    if (isCollateralDhedgePoolToken) {
      // After unrolling, we'll receive the underlying assets from the pool
      // We need to estimate what we'll receive to craft the swap transactions

      // Get the supported assets of the collateral pool
      IHasSupportedAsset.Asset[] memory supportedAssets = PoolManagerLogic(
        PoolLogic(collateralAsset).poolManagerLogic()
      ).getSupportedAssets();
      uint256 totalPoolSupply = IERC20Extended(collateralAsset).totalSupply();
      uint256 withdrawProportion = (collateralToWithdraw * 1e18) / totalPoolSupply;

      // Calculate expected amount of swapToAsset we'll receive after unrolling
      uint256 swapToAssetBalanceInPool = IERC20Extended(swapToAsset).balanceOf(collateralAsset);
      uint256 expectedSwapToAssetFromUnroll = (swapToAssetBalanceInPool * withdrawProportion) / 1e18;

      // Call 2 (REVERSE): Unroll collateral pool tokens via EasySwapperV2
      IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](supportedAssets.length);
      for (uint256 i = 0; i < complexAssetsData.length; i++) {
        complexAssetsData[i] = IPoolLogic.ComplexAsset({
          supportedAsset: supportedAssets[i].asset,
          withdrawData: new bytes(0), // at the moment could be only struct ComplexAssetSwapData
          slippageTolerance: 100 // 100 is 1% slippage tolerance
        });
      }
      txs[1] = PoolLogic.TxToExecute({
        to: address(easySwapperV2Instance),
        data: abi.encodeWithSelector(
          EasySwapperV2.initWithdrawal.selector,
          collateralAsset,
          collateralToWithdraw,
          complexAssetsData
        )
      });

      // Call 3 (REVERSE): Complete withdrawal from EasySwapperV2
      // This will return the underlying assets to the pool
      txs[2] = PoolLogic.TxToExecute({
        to: address(easySwapperV2Instance),
        data: abi.encodeWithSignature("completeWithdrawal()")
      });

      // Call 3 (NEW): Handle other supported assets if any
      // For each supported asset that's not swapToAsset or borrowAsset, swap to swapToAsset first
      // Then we'll have all value in swapToAsset before the final swap to borrowAsset
      uint256 totalSwapToAssetAmount = expectedSwapToAssetFromUnroll;

      for (uint256 i = 0; i < supportedAssets.length; i++) {
        address asset = supportedAssets[i].asset;
        if (asset == swapToAsset || asset == borrowAsset || asset == address(0)) {
          continue; // Skip swapToAsset and borrowAsset
        }

        uint256 assetBalanceInPool = IERC20Extended(asset).balanceOf(collateralAsset);
        uint256 expectedAssetAmount = (assetBalanceInPool * withdrawProportion) / 1e18;

        if (expectedAssetAmount > 0) {
          // Get swap data for this asset -> swapToAsset
          (uint256 expectedSwapToAssetFromThisSwap, ) = _getSwapData({
            srcToken: asset,
            destToken: swapToAsset,
            srcAmount: expectedAssetAmount,
            slippage: 1
          });

          totalSwapToAssetAmount += expectedSwapToAssetFromThisSwap;

          // Note: For simplicity, we're not adding these intermediate swaps to the tx array
          // In a production system, you'd need to dynamically resize the array
          // For this test, we assume the pool primarily holds swapToAsset
        }
      }

      // Check if pool holds any borrowAsset directly
      uint256 borrowAssetBalanceInPool = IERC20Extended(borrowAsset).balanceOf(collateralAsset);
      uint256 expectedBorrowAssetFromUnroll = (borrowAssetBalanceInPool * withdrawProportion) / 1e18;

      // Call 4 (REVERSE): Swap swapToAsset -> borrowAsset
      // Step 4: Get swap data for swapToAsset -> borrowAsset with the amount we'll receive from unroll
      (uint256 expectedBorrowAssetFromSwap, bytes memory swapDataDown) = _getSwapData({
        srcToken: swapToAsset,
        destToken: borrowAsset,
        srcAmount: expectedSwapToAssetFromUnroll, // Use the actual amount we'll receive from unroll
        slippage: 1 // 1% slippage
      });

      txs[3] = PoolLogic.TxToExecute({to: odosRouter, data: swapDataDown});

      // Call 5 (REVERSE): Repay debt to DYTM
      // Total borrowAsset = from swap + any borrowAsset directly from unroll
      // Apply 2% haircut to account for prediction inaccuracy (withdrawal fees, slippage, rounding)
      uint256 totalBorrowAssetToRepay = ((expectedBorrowAssetFromSwap + expectedBorrowAssetFromUnroll) * 98) / 100;

      txs[4] = PoolLogic.TxToExecute({
        to: dytmOffice,
        data: abi.encodeWithSelector(
          IDytmOffice.repay.selector,
          DytmParamStructs.RepayParams({
            account: uint256(uint160(address(dytmTestPool))),
            key: _getReserveKey(borrowAsset),
            withCollateralType: DytmParamStructs.TokenType.NONE,
            assets: totalBorrowAssetToRepay, // Use total from swap + unroll
            shares: 0,
            extraData: ""
          })
        )
      });
    } else {
      // Step 4: Get swap data for swapToAsset -> borrowAsset (this tells us how much borrowAsset we'll get)
      (uint256 expectedBorrowAssetFromSwap, bytes memory swapDataDown) = _getSwapData({
        srcToken: swapToAsset,
        destToken: borrowAsset,
        srcAmount: swapToAssetToSwapBack, // Correct: this is in swapToAsset units (WETH)
        slippage: 1 // 1% slippage
      });

      // Call 2 (REVERSE): Swap swapToAsset -> borrowAsset
      txs[1] = PoolLogic.TxToExecute({to: odosRouter, data: swapDataDown});

      // Call 3 (REVERSE): Repay debt to DYTM
      txs[2] = PoolLogic.TxToExecute({
        to: dytmOffice,
        data: abi.encodeWithSelector(
          IDytmOffice.repay.selector,
          DytmParamStructs.RepayParams({
            account: uint256(uint160(address(dytmTestPool))),
            key: _getReserveKey(borrowAsset),
            assets: expectedBorrowAssetFromSwap, // Use actual swap output
            withCollateralType: DytmParamStructs.TokenType.NONE,
            shares: 0,
            extraData: ""
          })
        )
      });
    }

    // Execute deleverage delegation call
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

    // Verify position changed as expected after leverage down
    DytmParamStructs.AccountPosition memory positionAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );
    assertLt(
      positionAfter.debt.debtAssets,
      positionBefore.debt.debtAssets,
      "Debt should be reduced after leverage down"
    );
    assertLt(
      positionAfter.totalCollateralValueUSD,
      positionBefore.totalCollateralValueUSD,
      "Collateral should be reduced after leverage down"
    );
    assertGt(
      positionAfter.healthFactor,
      positionBefore.healthFactor,
      "Health factor should improve after leverage down"
    );
    assertTrue(positionAfter.isHealthy, "Position should remain healthy after leverage down");
  }

  /**
   * @notice Helper to check if an address is a dHedge pool token
   */
  function _isDhedgePool(address asset) internal view returns (bool) {
    try PoolLogic(asset).factory() returns (address factory) {
      return factory == address(dhedgePoolFactory);
    } catch {
      return false;
    }
  }

  /**
   * @notice Test that delegation call properly tracks markets for health factor checking
   */
  function test_delegation_call_checks_health_factor_after_execution() public {
    uint256 supplied = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();
    // Supply initial collateral
    _supplyForEscrow({asset: collateralAsset, amountToSupply: supplied});

    // Prepare a delegation call that borrows and withdraws (should check HF)
    uint256 borrowAmount = (borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals())) / 10;

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);

    // Borrow
    txs[0] = PoolLogic.TxToExecute({
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

    // Withdraw some collateral (this will trigger HF check)
    uint256 withdrawAmount = supplied / 10;
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          receiver: address(dytmTestPool),
          assets: withdrawAmount,
          shares: 0,
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
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();

    // Assertions
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.01e18, "Total value should remain similar (1% tolerance)");

    // Verify health factor is still good
    DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    assertGt(position.healthFactor, 1.01e18, "Health factor should be above minimum after delegation call");
  }

  /**
   * @notice Test that nested delegation calls are prevented
   */
  function test_revert_nested_delegation_call() public {
    // Create a delegation call that tries to call another delegation call
    PoolLogic.TxToExecute[] memory nestedTxs = new PoolLogic.TxToExecute[](1);
    nestedTxs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(new PoolLogic.TxToExecute[](0))
        })
      )
    });

    vm.expectRevert("nested delegate call");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(nestedTxs)
        })
      )
    );
  }

  function test_revert_delegation_callback_cannot_self_call() public {
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](1);
    txs[0] = PoolLogic.TxToExecute({
      to: address(dytmTestPool),
      data: abi.encodeWithSelector(PoolLogic.deposit.selector, collateralAsset, 1e18)
    });

    vm.expectRevert(bytes("dh36"));
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
  }

  function test_revert_delegation_call_borrow_mixed_debt_assets() public {
    // 1. Create market 2 and redeploy guard
    uint88 market2Id = _setupSecondMarket();

    // 2. Supply collateral on market 1 (before delegation call, so it's tracked)
    uint256 collateralBalance = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: collateralBalance / 2});

    // 3. Build delegation call: [supply collateral market 2, borrow USDC market 1, borrow WETH market 2]
    PoolLogic.TxToExecute[] memory txs = _buildMixedDebtDelegationCallTxs(market2Id, collateralBalance / 2);

    // 4. Execute delegation call — afterTxGuard should revert with mixed debt
    vm.expectRevert("mixed debt assets not supported");
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
  }

  function _setupSecondMarket() internal returns (uint88 market2Id) {
    // Add swapToAsset (WETH) as borrowable on the market config
    IDytmSimpleMarketConfig marketConfig = IDytmSimpleMarketConfig(dytmMarketConfig);
    vm.prank(marketConfig.owner());
    IDytmSimpleMarketConfig.AssetConfig[] memory assets = new IDytmSimpleMarketConfig.AssetConfig[](1);
    assets[0] = IDytmSimpleMarketConfig.AssetConfig({asset: swapToAsset, isBorrowable: true});
    marketConfig.addSupportedAssets(assets);

    // Create market 2 using existing market config (officer = marketCreator)
    vm.prank(marketCreator);
    market2Id = IDytmOffice(dytmOffice).createMarket(marketCreator, dytmMarketConfig);

    // Configure weights for collateralAsset(ESCROW)/WETH debt pair on market 2
    _configureWeightsForMarket2(market2Id);

    // Redeploy guard with [marketId, market2Id] whitelisted
    _redeployGuardWithMarkets(market2Id);

    // Supply investor's swapToAsset (WETH) liquidity to market 2
    _supplyInvestorLiquidityToMarket2(market2Id);
  }

  function _configureWeightsForMarket2(uint88 market2Id) internal {
    IDytmWeights weights = IDytmWeights(IMarketConfig(dytmMarketConfig).weights());

    // collateralTokenId for ESCROW type on market 2: tokenType(1) << 248 | market2Id << 160 | asset
    uint256 escrowTokenId = _getTokenIdForMarket(collateralAsset, market2Id, 1);
    // debt reserve key for WETH on market 2
    uint248 debtKey = _getReserveKeyForMarket(swapToAsset, market2Id);

    // Set weight (0.85e18 = 85%) — officer of market 2 is marketCreator
    vm.prank(marketCreator);
    weights.setWeight(escrowTokenId, debtKey, uint64(0.85e18));
  }

  function _redeployGuardWithMarkets(uint88 market2Id) internal {
    Governance governance = Governance(dhedgePoolFactory.governanceAddress());
    vm.startPrank(dhedgePoolFactory.owner());

    address[] memory whitelistedPools = new address[](1);
    whitelistedPools[0] = address(dytmTestPool);

    uint88[] memory whitelistedMarkets = new uint88[](2);
    whitelistedMarkets[0] = marketId;
    whitelistedMarkets[1] = market2Id;

    DytmConfigStructs.DytmConfig memory dytmConfig = DytmConfigStructs.DytmConfig({
      dytmOffice: dytmOffice,
      dytmPeriphery: dytmPeriphery,
      dhedgePoolFactory: address(dhedgePoolFactory),
      nftTracker: nftTracker,
      maxDytmMarkets: 2
    });

    dytmOfficeContractGuard = IDytmOfficeContractGuard(
      deployCode("DytmOfficeContractGuard.sol", abi.encode(whitelistedPools, whitelistedMarkets, dytmConfig))
    );
    governance.setContractGuard(dytmOffice, address(dytmOfficeContractGuard));
    vm.stopPrank();
  }

  function _supplyInvestorLiquidityToMarket2(uint88 market2Id) internal {
    uint256 liquidity = 1 * (10 ** IERC20Extended(swapToAsset).decimals());
    deal(swapToAsset, investor, liquidity);
    vm.startPrank(investor);
    IERC20Extended(swapToAsset).approve(dytmOffice, type(uint256).max);
    IDytmOffice(dytmOffice).supply(
      DytmParamStructs.SupplyParams({
        account: uint256(uint160(investor)),
        tokenId: _getTokenIdForMarket(swapToAsset, market2Id, 2), // LEND type
        assets: liquidity,
        extraData: ""
      })
    );
    vm.stopPrank();
  }

  function _buildMixedDebtDelegationCallTxs(
    uint88 market2Id,
    uint256 collateralForMarket2
  ) internal view returns (PoolLogic.TxToExecute[] memory txs) {
    // Use small borrow amounts since collateral is split across 2 markets
    uint256 borrowAmount = (borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals())) / 4;
    uint256 swapToAssetBorrowAmount = (10 ** IERC20Extended(swapToAsset).decimals()) / 100;
    uint256 poolAccount = uint256(uint160(address(dytmTestPool)));

    txs = new PoolLogic.TxToExecute[](3);

    // Call 1: Supply collateral on market 2 (so WETH borrow has collateral backing)
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, market2Id, 1), // ESCROW type
          assets: collateralForMarket2,
          extraData: ""
        })
      )
    });

    // Call 2: Borrow USDC on market 1
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: poolAccount,
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    });

    // Call 3: Borrow WETH on market 2 (different debt asset → should revert)
    txs[2] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: poolAccount,
          key: _getReserveKeyForMarket(swapToAsset, market2Id),
          receiver: address(dytmTestPool),
          assets: swapToAssetBorrowAmount,
          extraData: ""
        })
      )
    });
  }

  // ========== Internal Helper Functions ==========

  function _supplyForEscrow(address asset, uint256 amountToSupply) internal {
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(asset),
          assets: amountToSupply,
          extraData: ""
        })
      )
    );
  }

  function _getTokenIdForLend(address asset) internal view returns (uint256) {
    return _getTokenIdForMarket(asset, marketId, 2);
  }

  function _getTokenIdForEscrow(address asset) internal view returns (uint256) {
    return _getTokenIdForMarket(asset, marketId, 1);
  }

  function _getTokenIdForMarket(address asset, uint88 _marketId, uint256 tokenType) internal pure returns (uint256) {
    // TokenId structure: tokenType (8 bits) + marketId (88 bits) + assetId (160 bits)
    uint256 tokenId = (uint256(tokenType) << 248) | (uint256(_marketId) << 160) | uint256(uint160(asset));
    return tokenId;
  }

  function _getReserveKey(address asset) internal view returns (uint248) {
    return _getReserveKeyForMarket(asset, marketId);
  }

  function _getReserveKeyForMarket(address asset, uint88 _marketId) internal pure returns (uint248) {
    // ReserveKey structure: marketId (88 bits) + assetId (160 bits)
    uint248 reserveKey = (uint248(_marketId) << 160) | uint248(uint160(asset));
    return reserveKey;
  }

  // ========== Direct Pool Withdrawal Tests ==========

  function _buildComplexAssetsData() internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
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

  /// @notice Calculates the total USD value of an investor's isolated DYTM accounts after withdrawal
  function _getInvestorDytmValueUSD(address _investor) internal view returns (uint256 totalValueUSD) {
    DytmSplitTokenIdTracker.SplitPosition[] memory positions = dytmOfficeAssetGuard.getSplitPositions(_investor);
    for (uint256 i = 0; i < positions.length; i++) {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        positions[i].tokenId,
        positions[i].marketId
      );
      if (pos.isHealthy) {
        totalValueUSD += pos.totalCollateralValueUSD - pos.debt.debtValueUSD;
      }
    }
  }

  function test_pool_withdraw_dytm_empty_position() public {
    // Pool has DYTM as supported asset but no position (zero balance)
    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokens / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildComplexAssetsData();

    vm.warp(block.timestamp + 86401); // Advance past deposit cooldown (86400s exit cooldown + 1)
    vm.prank(investor);
    dytmTestPool.withdrawSafe(withdrawAmount, complexAssetsData);

    // Investor should have received collateral asset directly (no DYTM splitting)
    uint256 investorCollateralBalance = IERC20Extended(collateralAsset).balanceOf(investor);
    uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
    IAssetHandler assetHandler = IAssetHandler(dhedgePoolFactory.getAssetHandler());
    uint256 collateralPriceD18 = assetHandler.getUSDPrice(collateralAsset);
    uint256 collateralDecimals = IERC20Extended(collateralAsset).decimals();
    uint256 investorCollateralValueD18 = (investorCollateralBalance * collateralPriceD18) / (10 ** collateralDecimals);

    assertApproxEqRel(
      investorCollateralValueD18,
      expectedValueD18,
      0.01e18,
      "Investor collateral value should match withdrawn pool token value (1% tolerance)"
    );

    // No DYTM split positions should exist
    DytmSplitTokenIdTracker.SplitPosition[] memory positions = dytmOfficeAssetGuard.getSplitPositions(investor);
    assertEq(positions.length, 0, "No split positions should exist for empty DYTM");
  }

  function test_pool_withdraw_dytm_no_debt() public {
    // Supply collateral to DYTM (no borrowing)
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    // Capture DYTM position value before withdrawal
    uint256 dytmValueBefore = dytmOfficeAssetGuard.getBalance(address(dytmTestPool), dytmOffice);
    assertGt(dytmValueBefore, 0, "Pool should have DYTM position value");

    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokens / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildComplexAssetsData();

    vm.warp(block.timestamp + 86401); // Advance past deposit cooldown (86400s exit cooldown + 1)
    vm.prank(investor);
    dytmTestPool.withdrawSafe(withdrawAmount, complexAssetsData);

    // Pool's DYTM value should be reduced
    uint256 dytmValueAfter = dytmOfficeAssetGuard.getBalance(address(dytmTestPool), dytmOffice);
    assertLt(dytmValueAfter, dytmValueBefore, "Pool DYTM value should decrease after withdrawal");

    // Investor should have received isolated DYTM accounts
    DytmSplitTokenIdTracker.SplitPosition[] memory positions = dytmOfficeAssetGuard.getSplitPositions(investor);
    assertGt(positions.length, 0, "Investor should have split DYTM positions");

    // Verify value of investor's isolated accounts matches expected portion
    uint256 investorDytmValueUSD = _getInvestorDytmValueUSD(investor);
    uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
    assertApproxEqRel(
      investorDytmValueUSD,
      expectedValueD18,
      0.01e18,
      "Investor DYTM position value should match withdrawn pool token value (1% tolerance)"
    );
  }

  function test_pool_withdraw_dytm_with_debt() public {
    // Leverage up: supply collateral, borrow, swap, supply more
    _leverage_up();

    // Capture position before withdrawal
    DytmParamStructs.AccountPosition memory positionBefore = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );
    assertGt(positionBefore.totalCollateralValueUSD, 0, "Should have collateral");
    assertGt(positionBefore.debt.debtAssets, 0, "Should have debt");

    uint256 dytmValueBefore = dytmOfficeAssetGuard.getBalance(address(dytmTestPool), dytmOffice);
    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokens / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildComplexAssetsData();

    vm.warp(block.timestamp + 86401); // Advance past deposit cooldown (86400s exit cooldown + 1)

    vm.prank(investor);
    dytmTestPool.withdrawSafe(withdrawAmount, complexAssetsData);

    // Pool's DYTM value should be reduced
    uint256 dytmValueAfter = dytmOfficeAssetGuard.getBalance(address(dytmTestPool), dytmOffice);
    assertLt(dytmValueAfter, dytmValueBefore, "Pool DYTM value should decrease");

    // Pool's collateral and debt should both be reduced
    DytmParamStructs.AccountPosition memory positionAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );
    assertLt(
      positionAfter.totalCollateralValueUSD,
      positionBefore.totalCollateralValueUSD,
      "Pool collateral should decrease"
    );
    assertLt(positionAfter.debt.debtAssets, positionBefore.debt.debtAssets, "Pool debt should decrease");

    // Investor should have received isolated DYTM accounts with proportional debt
    DytmSplitTokenIdTracker.SplitPosition[] memory positions = dytmOfficeAssetGuard.getSplitPositions(investor);
    assertGt(positions.length, 0, "Investor should have split DYTM positions");

    // Verify value of investor's isolated accounts (net: collateral - debt) matches expected portion
    uint256 investorDytmValueUSD = _getInvestorDytmValueUSD(investor);
    uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
    assertApproxEqRel(
      investorDytmValueUSD,
      expectedValueD18,
      0.02e18,
      "Investor DYTM net position value should match withdrawn pool token value (2% tolerance)"
    );

    // Verify investor's position has debt
    for (uint256 i = 0; i < positions.length; i++) {
      DytmParamStructs.AccountPosition memory investorPos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        positions[i].tokenId,
        positions[i].marketId
      );
      assertGt(investorPos.debt.debtAssets, 0, "Investor split position should have debt");
      assertTrue(investorPos.isHealthy, "Investor split position should be healthy");
    }
  }
}
