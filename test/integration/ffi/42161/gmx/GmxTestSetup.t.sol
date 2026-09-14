// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {ChainlinkPythPriceAggregator} from "contracts/priceAggregators/ChainlinkPythPriceAggregator.sol";
import {GmxPerpMarketAssetGuard} from "contracts/guards/assetGuards/gmx/GmxPerpMarketAssetGuard.sol";
import {GmxExchangeRouterContractGuard} from "contracts/guards/contractGuards/gmx/GmxExchangeRouterContractGuard.sol";
import {ClosedContractGuard} from "contracts/guards/contractGuards/ClosedContractGuard.sol";
import {GmxStructs} from "contracts/utils/gmx/GmxStructs.sol";
import {ChainlinkPythPriceLib} from "contracts/utils/chainlinkPyth/ChainlinkPythPriceLib.sol";
import {PythPriceLib} from "contracts/utils/pyth/PythPriceLib.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IPyth} from "contracts/interfaces/pyth/IPyth.sol";
import {IGmxExchangeRouter} from "contracts/interfaces/gmx/IGmxExchangeRouter.sol";
import {IGmxDataStore} from "contracts/interfaces/gmx/IGmxDataStore.sol";
import {IGmxRoleStore} from "contracts/interfaces/gmx/IGmxRoleStore.sol";
import {IGmxReader} from "contracts/interfaces/gmx/IGmxReader.sol";
import {IGmxMarket} from "contracts/interfaces/gmx/IGmxMarket.sol";
import {IGmxBaseOrderUtils} from "contracts/interfaces/gmx/IGmxBaseOrderUtils.sol";
import {IGmxOrderHandler} from "contracts/interfaces/gmx/IGmxOrderHandler.sol";
import {IGmxDepositHandler} from "contracts/interfaces/gmx/IGmxDepositHandler.sol";
import {IGmxWithdrawalHandler} from "contracts/interfaces/gmx/IGmxWithdrawalHandler.sol";
import {IGmxOracleUtils} from "contracts/interfaces/gmx/IGmxOracleUtils.sol";
import {Order} from "contracts/interfaces/gmx/IGmxOrder.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {GmxTestSharedData} from "test/integration/arbitrum/gmx/GmxTestSharedData.sol";
import {GmxLivePrices} from "./GmxLivePrices.sol";

abstract contract GmxTestSetup is BackboneSetup, GmxLivePrices {
  uint16 internal constant GMX_MARKET_ASSET_TYPE = 105;

  address internal constant GMX_APPROVAL_ROUTER = 0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;
  address internal constant GMX_ORACLE_PROVIDER = 0x7BA7Ae61887F1aca28E0FE5aB1434ce85b6606aa;
  address internal constant GMX_UI_FEE_RECEIVER = 0xff00000000000000000000000000000000000001;

  bytes32 internal constant PYTH_USDC_PRICE_ID = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;

  uint256 internal constant DEFAULT_SIZE_DELTA_USD = 1_000e30;
  uint256 internal constant USDC_TEST_AMOUNT = 1_000e6;
  uint256 internal constant WETH_TEST_AMOUNT = 1 ether;

  struct MarketConfig {
    string name;
    address market;
    address indexToken;
    address longToken;
    address shortToken;
    address longCollateralToken;
    uint256 longCollateralAmount;
    address longCollateralOracle;
    bytes32 longCollateralPythPriceId;
    uint256 sizeDeltaUsd;
    uint256 claimImpactMultiplier;
  }

  struct OpenOrderParams {
    address uiFeeReceiver;
    address orderVault;
    address receiver;
    address collateralToken;
    address callbackContract;
    bool onlySendTokens;
    bool decreasePosition;
    bool isShort;
    bool useZeroCallback;
    bool hasSizeDeltaUsd;
    bool hasInitialCollateralDeltaAmount;
    bool hasAcceptablePrice;
    bool hasCallbackGasLimit;
    uint256 sizeDeltaUsd;
    uint256 initialCollateralDeltaAmount;
    uint256 acceptablePrice;
    uint256 callbackGasLimit;
  }

  struct ResolvedOpenOrderParams {
    address orderVault;
    address receiver;
    address collateralToken;
    address callbackContract;
    address uiFeeReceiver;
    uint256 sizeDeltaUsd;
    uint256 collateralAmount;
    uint256 acceptablePrice;
    uint256 callbackGasLimit;
    bool isLong;
  }

  MarketConfig internal marketConfig;
  LivePrices internal livePrices;
  uint256 internal livePriceReportIndex;
  IGmxMarket.Props internal gmxMarket;

  PoolLogic internal testPool;
  PoolManagerLogic internal testPoolManagerLogic;
  GmxExchangeRouterContractGuard internal gmxContractGuard;

  IGmxExchangeRouter internal constant GMX_EXCHANGE_ROUTER =
    IGmxExchangeRouter(0x7dE39FF2e232A2203196788d37e234cF8F1b83f1);
  IGmxDataStore internal constant GMX_DATA_STORE = IGmxDataStore(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8);
  IGmxReader internal constant GMX_READER = IGmxReader(0xfA26cBb46e2614609406de08CA1Dc7f70a684184);

  IGmxOrderHandler internal orderHandler;
  IGmxDepositHandler internal depositHandler;
  IGmxWithdrawalHandler internal withdrawalHandler;
  address internal gmxOrderVault;
  address internal gmxDepositVault;
  address internal gmxWithdrawalVault;
  address internal keeper;

  constructor()
    BackboneSetup(
      IAssetHandler.Asset({
        asset: ArbitrumConfig.USDC,
        assetType: uint16(AssetTypeIncomplete.CHAINLINK),
        aggregator: ArbitrumConfig.USDC_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: ArbitrumConfig.WETH,
        assetType: uint16(AssetTypeIncomplete.CHAINLINK),
        aggregator: ArbitrumConfig.WETH_CHAINLINK_ORACLE
      }),
      IAssetHandler.Asset({
        asset: ArbitrumConfig.DAI,
        assetType: uint16(AssetTypeIncomplete.CHAINLINK),
        aggregator: ArbitrumConfig.DAI_CHAINLINK_ORACLE
      })
    )
  {}

  function _getMarketConfig() internal pure virtual returns (MarketConfig memory);

  function setUp() public virtual override {
    marketConfig = _getMarketConfig();

    address[] memory requestedTokens = _getOracleTokens(marketConfig);
    livePrices = _getLivePrices(requestedTokens);

    vm.createSelectFork("arbitrum", livePrices.forkBlockNumber);
    _prepareRequestTimestamp();
    super.setUp();

    gmxMarket = GMX_READER.getMarket(GMX_DATA_STORE, marketConfig.market);
    assertEq(gmxMarket.indexToken, marketConfig.indexToken, "unexpected GMX index token");
    assertEq(gmxMarket.longToken, marketConfig.longToken, "unexpected GMX long token");
    assertEq(gmxMarket.shortToken, marketConfig.shortToken, "unexpected GMX short token");

    _deployGmxIntegration();
    _fundPool();
    _loadGmxExecutionContracts();
  }

  function _deployGmxIntegration() internal {
    vm.startPrank(owner);

    GmxPerpMarketAssetGuard gmxAssetGuard = new GmxPerpMarketAssetGuard(address(GMX_EXCHANGE_ROUTER));

    governance.setAssetGuard(GMX_MARKET_ASSET_TYPE, address(gmxAssetGuard));

    _installTestPriceAggregators();
    assetHandlerProxy.addAsset(marketConfig.market, GMX_MARKET_ASSET_TYPE, address(usdPriceAggregator));

    IHasSupportedAsset.Asset[] memory supportedAssets = _getSupportedAssets();
    vm.stopPrank();

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "manager",
        _fundName: string(abi.encodePacked("GMX ", marketConfig.name)),
        _fundSymbol: "dHGMX",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    vm.startPrank(owner);
    GmxStructs.PoolSetting[] memory poolSettings = new GmxStructs.PoolSetting[](1);
    poolSettings[0] = GmxStructs.PoolSetting({
      poolLogic: address(testPool),
      withdrawalAsset: marketConfig.longCollateralToken
    });

    gmxContractGuard = new GmxExchangeRouterContractGuard(
      GmxStructs.GmxContractGuardConfig({
        gmxExchangeRouter: address(GMX_EXCHANGE_ROUTER),
        feeReceiver: GMX_UI_FEE_RECEIVER,
        dataStore: address(GMX_DATA_STORE),
        reader: address(GMX_READER),
        referralStorage: GmxTestSharedData.GMX_REFERRAL_STORAGE
      }),
      poolSettings,
      GmxTestSharedData.getVirtualTokenResolver(),
      address(slippageAccumulator),
      address(nftTrackerStorageProxy)
    );

    governance.setContractGuard(address(GMX_EXCHANGE_ROUTER), address(gmxContractGuard));
    governance.setContractGuard(GMX_APPROVAL_ROUTER, address(new ClosedContractGuard()));
    poolFactoryProxy.setExitCooldown(0);
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory marketAsset = new IHasSupportedAsset.Asset[](1);
    marketAsset[0] = IHasSupportedAsset.Asset({asset: marketConfig.market, isDeposit: false});
    vm.prank(manager);
    testPoolManagerLogic.changeAssets(marketAsset, new address[](0));

    vm.prank(manager);
    testPool.execTransaction(
      marketConfig.market,
      abi.encodeWithSelector(IERC20.approve.selector, GMX_APPROVAL_ROUTER, type(uint256).max)
    );
  }

  function _installTestPriceAggregators() internal {
    _installPriceAggregator(ArbitrumConfig.USDC, ArbitrumConfig.USDC_CHAINLINK_ORACLE, PYTH_USDC_PRICE_ID);
    _installPriceAggregator(
      ArbitrumConfig.WETH,
      ArbitrumConfig.WETH_CHAINLINK_ORACLE,
      ArbitrumConfig.PYTH_ETH_PRICE_ID
    );

    if (
      marketConfig.longCollateralToken != ArbitrumConfig.USDC && marketConfig.longCollateralToken != ArbitrumConfig.WETH
    ) {
      _installPriceAggregator(
        marketConfig.longCollateralToken,
        marketConfig.longCollateralOracle,
        marketConfig.longCollateralPythPriceId
      );
    }

    _installIndexPriceAggregator();
  }

  // Most markets use a GMX virtual index token and need no dHEDGE price aggregator.
  // solhint-disable-next-line no-empty-blocks
  function _installIndexPriceAggregator() internal virtual {}

  function _installPriceAggregator(address token, address chainlinkOracle, bytes32 pythPriceId) internal {
    _installPriceAggregator(token, chainlinkOracle, pythPriceId, uint16(AssetTypeIncomplete.CHAINLINK));
  }

  function _installPriceAggregator(
    address token,
    address chainlinkOracle,
    bytes32 pythPriceId,
    uint16 assetType
  ) internal {
    ChainlinkPythPriceLib.OracleData memory oracleData = ChainlinkPythPriceLib.OracleData({
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(chainlinkOracle),
        maxAge: 90_000
      }),
      offchainOracle: PythPriceLib.OffchainOracle({priceId: pythPriceId, maxAge: 86_400, minConfidenceRatio: 50})
    });

    ChainlinkPythPriceAggregator aggregator = new ChainlinkPythPriceAggregator(
      token,
      IPyth(ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT),
      oracleData
    );
    assetHandlerProxy.addAsset(token, assetType, address(aggregator));
  }

  function _getSupportedAssets() internal view returns (IHasSupportedAsset.Asset[] memory assets) {
    uint256 count = marketConfig.longCollateralToken == ArbitrumConfig.WETH ? 2 : 3;
    assets = new IHasSupportedAsset.Asset[](count);
    assets[0] = IHasSupportedAsset.Asset({asset: marketConfig.longCollateralToken, isDeposit: true});
    assets[1] = IHasSupportedAsset.Asset({asset: ArbitrumConfig.USDC, isDeposit: true});

    if (count == 3) {
      assets[2] = IHasSupportedAsset.Asset({asset: ArbitrumConfig.WETH, isDeposit: true});
    }
  }

  function _fundPool() internal {
    _depositAndApprove(marketConfig.longCollateralToken, marketConfig.longCollateralAmount * 2);

    if (marketConfig.longCollateralToken != ArbitrumConfig.USDC) {
      _depositAndApprove(ArbitrumConfig.USDC, USDC_TEST_AMOUNT * 2);
    }

    if (marketConfig.longCollateralToken != ArbitrumConfig.WETH) {
      _depositAndApprove(ArbitrumConfig.WETH, WETH_TEST_AMOUNT * 2);
    }
  }

  function _depositAndApprove(address token, uint256 amount) internal {
    deal(token, owner, amount);
    vm.startPrank(owner);
    IERC20(token).approve(address(testPool), amount);
    testPool.deposit(token, amount);
    vm.stopPrank();

    vm.prank(manager);
    testPool.execTransaction(
      token,
      abi.encodeWithSelector(IERC20.approve.selector, GMX_APPROVAL_ROUTER, type(uint256).max)
    );
  }

  function _loadGmxExecutionContracts() internal {
    orderHandler = GMX_EXCHANGE_ROUTER.orderHandler();
    depositHandler = GMX_EXCHANGE_ROUTER.depositHandler();
    withdrawalHandler = GMX_EXCHANGE_ROUTER.withdrawalHandler();
    gmxOrderVault = orderHandler.orderVault();
    gmxDepositVault = depositHandler.depositVault();
    gmxWithdrawalVault = withdrawalHandler.withdrawalVault();

    address roleStore = GMX_DATA_STORE.roleStore();
    address[] memory keepers = IGmxRoleStore(roleStore).getRoleMembers(_hashString("ORDER_KEEPER"), 0, 1);
    require(keepers.length == 1, "GMX keeper missing");
    keeper = keepers[0];
    vm.deal(keeper, 100 ether);
  }

  function _openOrder(OpenOrderParams memory params) internal {
    _prepareRequestTimestamp();
    ResolvedOpenOrderParams memory resolved = _resolveOpenOrderParams(params);

    bytes[] memory calls = _buildOrderCalls(params, resolved);

    vm.prank(manager);
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(IGmxExchangeRouter.multicall.selector, calls)
    );
  }

  function _openExternalOrder(address account, OpenOrderParams memory params) internal {
    _prepareRequestTimestamp();
    ResolvedOpenOrderParams memory resolved = _resolveOpenOrderParams(params);
    resolved.receiver = params.receiver == address(0) ? account : params.receiver;

    deal(ArbitrumConfig.WETH, account, WETH_TEST_AMOUNT * 2);
    deal(resolved.collateralToken, account, resolved.collateralAmount * 2);
    vm.startPrank(account);
    IERC20(ArbitrumConfig.WETH).approve(GMX_APPROVAL_ROUTER, type(uint256).max);
    IERC20(resolved.collateralToken).approve(GMX_APPROVAL_ROUTER, type(uint256).max);
    GMX_EXCHANGE_ROUTER.multicall(_buildOrderCalls(params, resolved));
    vm.stopPrank();
  }

  function _buildOrderCalls(
    OpenOrderParams memory params,
    ResolvedOpenOrderParams memory resolved
  ) internal view returns (bytes[] memory calls) {
    uint256 tokenCallCount = params.decreasePosition ? 1 : 2;
    calls = new bytes[](tokenCallCount + (params.onlySendTokens ? 0 : 1));
    calls[0] = abi.encodeWithSelector(
      IGmxExchangeRouter.sendTokens.selector,
      ArbitrumConfig.WETH,
      resolved.orderVault,
      WETH_TEST_AMOUNT / 2
    );

    uint256 createOrderIndex;
    if (!params.decreasePosition) {
      calls[1] = abi.encodeWithSelector(
        IGmxExchangeRouter.sendTokens.selector,
        resolved.collateralToken,
        resolved.orderVault,
        resolved.collateralAmount
      );
      createOrderIndex = 2;
    } else {
      createOrderIndex = 1;
    }

    if (!params.onlySendTokens) {
      IGmxBaseOrderUtils.CreateOrderParams memory createParams = _getCreateOrderParams(
        resolved,
        params.decreasePosition
      );
      calls[createOrderIndex] = abi.encodeWithSelector(IGmxExchangeRouter.createOrder.selector, createParams);
    }
  }

  function _resolveOpenOrderParams(
    OpenOrderParams memory params
  ) internal view returns (ResolvedOpenOrderParams memory resolved) {
    resolved.orderVault = params.orderVault == address(0) ? gmxOrderVault : params.orderVault;
    resolved.collateralToken = params.collateralToken == address(0) ? ArbitrumConfig.USDC : params.collateralToken;
    resolved.receiver = params.receiver == address(0) ? address(testPool) : params.receiver;
    resolved.callbackContract = params.useZeroCallback
      ? address(0)
      : params.callbackContract == address(0)
        ? address(gmxContractGuard)
        : params.callbackContract;
    resolved.uiFeeReceiver = params.uiFeeReceiver == address(0) ? GMX_UI_FEE_RECEIVER : params.uiFeeReceiver;
    resolved.sizeDeltaUsd = params.hasSizeDeltaUsd
      ? params.sizeDeltaUsd
      : params.decreasePosition
        ? marketConfig.sizeDeltaUsd / 2
        : marketConfig.sizeDeltaUsd;

    uint256 defaultCollateralAmount = resolved.collateralToken == ArbitrumConfig.USDC
      ? USDC_TEST_AMOUNT
      : marketConfig.longCollateralAmount;
    resolved.collateralAmount = params.hasInitialCollateralDeltaAmount
      ? params.initialCollateralDeltaAmount
      : params.decreasePosition
        ? defaultCollateralAmount / 4
        : defaultCollateralAmount / 2;
    resolved.acceptablePrice = params.hasAcceptablePrice
      ? params.acceptablePrice
      : params.decreasePosition
        ? 0
        : type(uint256).max;
    resolved.callbackGasLimit = params.hasCallbackGasLimit ? params.callbackGasLimit : 2_000_000;
    resolved.isLong = !params.isShort;
  }

  function _getCreateOrderParams(
    ResolvedOpenOrderParams memory resolved,
    bool decreasePosition
  ) internal view returns (IGmxBaseOrderUtils.CreateOrderParams memory params) {
    params.addresses = IGmxBaseOrderUtils.CreateOrderParamsAddresses({
      receiver: resolved.receiver,
      cancellationReceiver: address(0),
      callbackContract: resolved.callbackContract,
      uiFeeReceiver: resolved.uiFeeReceiver,
      market: marketConfig.market,
      initialCollateralToken: resolved.collateralToken,
      swapPath: new address[](0)
    });
    params.numbers = IGmxBaseOrderUtils.CreateOrderParamsNumbers({
      sizeDeltaUsd: resolved.sizeDeltaUsd,
      initialCollateralDeltaAmount: decreasePosition ? resolved.collateralAmount : 0,
      triggerPrice: 0,
      acceptablePrice: resolved.acceptablePrice,
      executionFee: WETH_TEST_AMOUNT / 2,
      callbackGasLimit: resolved.callbackGasLimit,
      minOutputAmount: 0,
      validFromTime: 0
    });
    params.orderType = decreasePosition ? Order.OrderType.MarketDecrease : Order.OrderType.MarketIncrease;
    params.decreasePositionSwapType = Order.DecreasePositionSwapType.NoSwap;
    params.isLong = resolved.isLong;
    params.shouldUnwrapNativeToken = false;
    params.autoCancel = false;
    params.referralCode = bytes32(0);
    params.dataList = new bytes32[](0);
  }

  function _executeOrder() internal {
    _executeOrderFor(address(testPool));
  }

  function _executeOrderFor(address account) internal {
    _prepareExecutionTimestamp();
    bytes32 orderKey = _getLastAccountKey(account, "ORDER");
    vm.prank(keeper);
    orderHandler.executeOrder(orderKey, _getOracleParams());
    _consumeLivePriceReport();
  }

  function _getOracleParams() internal view returns (IGmxOracleUtils.SetPricesParams memory params) {
    address[] memory providers = new address[](livePrices.tokens.length);
    for (uint256 i; i < providers.length; ++i) {
      providers[i] = GMX_ORACLE_PROVIDER;
    }
    params = IGmxOracleUtils.SetPricesParams({
      tokens: livePrices.tokens,
      providers: providers,
      data: livePrices.blobs[livePriceReportIndex]
    });
  }

  function _getLastAccountKey(address account, string memory requestType) internal view returns (bytes32) {
    bytes32 listKey = keccak256(
      abi.encode(_hashString(string(abi.encodePacked("ACCOUNT_", requestType, "_LIST"))), account)
    );
    uint256 count = GMX_DATA_STORE.getBytes32Count(listKey);
    require(count > 0, "GMX request missing");
    bytes32[] memory keys = GMX_DATA_STORE.getBytes32ValuesAt(listKey, count - 1, count);
    return keys[0];
  }

  function _getOracleTokens(MarketConfig memory config) internal pure returns (address[] memory tokens) {
    if (config.indexToken == config.longToken) {
      tokens = new address[](2);
      tokens[0] = config.indexToken;
      tokens[1] = config.shortToken;
      return tokens;
    }

    if (config.indexToken == config.shortToken || config.longToken == config.shortToken) {
      tokens = new address[](2);
      tokens[0] = config.indexToken;
      tokens[1] = config.longToken;
      return tokens;
    }

    tokens = new address[](3);
    tokens[0] = config.indexToken;
    tokens[1] = config.longToken;
    tokens[2] = config.shortToken;
  }

  function _hashString(string memory value) internal pure returns (bytes32) {
    return keccak256(abi.encode(value));
  }

  function _emptyOrderParams() internal pure returns (OpenOrderParams memory) {
    return
      OpenOrderParams({
        uiFeeReceiver: address(0),
        orderVault: address(0),
        receiver: address(0),
        collateralToken: address(0),
        callbackContract: address(0),
        onlySendTokens: false,
        decreasePosition: false,
        isShort: false,
        useZeroCallback: false,
        hasSizeDeltaUsd: false,
        hasInitialCollateralDeltaAmount: false,
        hasAcceptablePrice: false,
        hasCallbackGasLimit: false,
        sizeDeltaUsd: 0,
        initialCollateralDeltaAmount: 0,
        acceptablePrice: 0,
        callbackGasLimit: 0
      });
  }

  function _snapshot() internal returns (uint256) {
    return vm.snapshotState();
  }

  function _restore(uint256 snapshotId) internal {
    require(vm.revertToState(snapshotId), "snapshot restore failed");
  }

  function _prepareRequestTimestamp() internal {
    require(livePriceReportIndex < livePrices.reportTimestamps.length, "GMX price reports exhausted");
    uint256 requestTimestamp = livePrices.reportTimestamps[livePriceReportIndex] - 1;
    require(requestTimestamp >= block.timestamp, "GMX request timestamp moved backwards");
    vm.warp(requestTimestamp);
  }

  function _prepareExecutionTimestamp() internal {
    require(livePriceReportIndex < livePrices.reportTimestamps.length, "GMX price reports exhausted");
    vm.warp(livePrices.reportTimestamps[livePriceReportIndex]);
  }

  function _consumeLivePriceReport() internal {
    livePriceReportIndex += 1;
  }
}
