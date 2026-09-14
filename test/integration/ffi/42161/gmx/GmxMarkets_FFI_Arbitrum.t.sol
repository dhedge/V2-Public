// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {GmxTestScenarios} from "./GmxTests_FFI_Arbitrum.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {GmxTestSharedData} from "test/integration/arbitrum/gmx/GmxTestSharedData.sol";
import {IGmxExchangeRouter} from "contracts/interfaces/gmx/IGmxExchangeRouter.sol";
import {GmxTimeKeyViewer} from "contracts/test/GmxTimeKeyViewer.sol";

abstract contract GmxCollateralConfig is GmxTestScenarios {
  function _wethCollateralConfig(
    string memory name,
    address market,
    address indexToken
  ) internal pure returns (MarketConfig memory config) {
    config = MarketConfig({
      name: name,
      market: market,
      indexToken: indexToken,
      longToken: ArbitrumConfig.WETH,
      shortToken: ArbitrumConfig.USDC,
      longCollateralToken: ArbitrumConfig.WETH,
      longCollateralAmount: 1 ether,
      longCollateralOracle: ArbitrumConfig.WETH_CHAINLINK_ORACLE,
      longCollateralPythPriceId: ArbitrumConfig.PYTH_ETH_PRICE_ID,
      sizeDeltaUsd: DEFAULT_SIZE_DELTA_USD,
      claimImpactMultiplier: 20_000
    });
  }

  function _wbtcCollateralConfig(
    string memory name,
    address market,
    address indexToken
  ) internal pure returns (MarketConfig memory config) {
    config = MarketConfig({
      name: name,
      market: market,
      indexToken: indexToken,
      longToken: ArbitrumConfig.WBTC,
      shortToken: ArbitrumConfig.USDC,
      longCollateralToken: ArbitrumConfig.WBTC,
      longCollateralAmount: 1e6,
      longCollateralOracle: ArbitrumConfig.WBTC_CHAINLINK_ORACLE,
      longCollateralPythPriceId: GmxTestSharedData.PYTH_WBTC_PRICE_ID,
      sizeDeltaUsd: DEFAULT_SIZE_DELTA_USD,
      claimImpactMultiplier: 20_000
    });
  }
}

contract GmxEthTestFFIArbitrum is GmxTestScenarios {
  event TransactionExecuted(address pool, address manager, uint16 transactionType, uint256 time);

  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = MarketConfig({
      name: "ETH",
      market: 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336,
      indexToken: ArbitrumConfig.WETH,
      longToken: ArbitrumConfig.WETH,
      shortToken: ArbitrumConfig.USDC,
      longCollateralToken: ArbitrumConfig.WETH,
      longCollateralAmount: 1 ether,
      longCollateralOracle: ArbitrumConfig.WETH_CHAINLINK_ORACLE,
      longCollateralPythPriceId: ArbitrumConfig.PYTH_ETH_PRICE_ID,
      sizeDeltaUsd: DEFAULT_SIZE_DELTA_USD,
      claimImpactMultiplier: 20_000
    });
  }

  // The guard must allow a pool to register itself (and only itself) as the GMX saved
  // callback contract on a real GMX market, as a standalone ExchangeRouter call.
  function test_savedCallbackRegistration() public {
    // 1. successful manager registration through the pool
    _registerSavedCallback();
    assertEq(_savedCallbackAddress(marketConfig.market), address(gmxContractGuard), "saved callback not registered");

    // 2. repeating the registration succeeds and leaves the same value
    _registerSavedCallback();
    assertEq(_savedCallbackAddress(marketConfig.market), address(gmxContractGuard), "saved callback changed");

    // 3. TransactionExecuted reports transaction type 135
    vm.expectEmit(true, true, false, true, address(testPool));
    emit TransactionExecuted(address(testPool), manager, 135, block.timestamp);
    _registerSavedCallback();

    // 4. zero callback is rejected
    vm.prank(manager);
    vm.expectRevert(bytes("invalid callback contract"));
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(IGmxExchangeRouter.setSavedCallbackContract.selector, marketConfig.market, address(0))
    );

    // 5. an arbitrary callback contract is rejected
    vm.prank(manager);
    vm.expectRevert(bytes("invalid callback contract"));
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(
        IGmxExchangeRouter.setSavedCallbackContract.selector,
        marketConfig.market,
        makeAddr("arbitrary callback")
      )
    );

    // 6. a supported non-market asset such as WETH is rejected
    vm.prank(manager);
    vm.expectRevert(bytes("invalid market"));
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(
        IGmxExchangeRouter.setSavedCallbackContract.selector,
        ArbitrumConfig.WETH,
        address(gmxContractGuard)
      )
    );

    // 7. a real GMX market that is not supported by this pool is rejected
    vm.prank(manager);
    vm.expectRevert(bytes("unsupported market"));
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(
        IGmxExchangeRouter.setSavedCallbackContract.selector,
        GmxTestSharedData.GMX_SUI_MARKET,
        address(gmxContractGuard)
      )
    );

    // 8. wrapping the setter in ExchangeRouter.multicall remains rejected
    bytes[] memory calls = new bytes[](1);
    calls[0] = abi.encodeWithSelector(
      IGmxExchangeRouter.setSavedCallbackContract.selector,
      marketConfig.market,
      address(gmxContractGuard)
    );
    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    testPool.execTransaction(
      address(GMX_EXCHANGE_ROUTER),
      abi.encodeWithSelector(IGmxExchangeRouter.multicall.selector, calls)
    );
  }

  // A real GMX liquidation credits claimable collateral to the pool, but without a saved
  // callback registration it is not immediately tracked. A later ordinary decrease in the same
  // hourly bucket can register the cumulative bucket. With the registration, the guard is invoked
  // through GMX's real callback path and the claimable collateral is tracked and valued immediately.
  function test_liquidationRecordsClaimableCollateral() public {
    _prepareForcedDecreaseState();
    _makePoolLongLiquidatable();

    GmxTimeKeyViewer viewer = new GmxTimeKeyViewer();
    _assertNoClaimableCollateral(viewer);
    require(_positionSizeInUsd(address(testPool), ArbitrumConfig.USDC, true) > 0, "liquidation position missing");

    uint256 executionSnapshot = _snapshot();

    // --- unregistered control branch: real keeper liquidates through the real handler ---
    _executeLiquidation();
    assertEq(
      _positionSizeInUsd(address(testPool), ArbitrumConfig.USDC, true),
      0,
      "unregistered position not liquidated"
    );

    uint256 timeKey = _currentGmxTimeKey();
    uint256 rawLong = _rawClaimableAmount(marketConfig.longToken, timeKey);
    uint256 rawShort = _rawClaimableAmount(marketConfig.shortToken, timeKey);
    require(rawLong > 0 || rawShort > 0, "liquidation produced no claimable collateral");
    assertEq(_claimTimeKeys(viewer, marketConfig.longToken).length, 0, "unregistered long time key tracked");
    assertEq(_claimTimeKeys(viewer, marketConfig.shortToken).length, 0, "unregistered short time key tracked");

    uint256 unregisteredMarketValue = testPoolManagerLogic.assetValue(marketConfig.market);
    uint256 unregisteredFundValue = testPoolManagerLogic.totalFundValue();

    // --- registered branch: same state, guard registered, identical liquidation ---
    _restore(executionSnapshot);
    _registerSavedCallback();
    _executeLiquidation();

    assertEq(_positionSizeInUsd(address(testPool), ArbitrumConfig.USDC, true), 0, "registered position not liquidated");

    _assertRegisteredTracking(viewer, timeKey, rawLong, rawShort, unregisteredMarketValue, unregisteredFundValue);
  }

  // A real GMX ADL (a keeper-created MarketDecrease order) takes its callback from the
  // saved-callback registry too. Registered, it flows through the existing market-decrease
  // branch and the claimable collateral created by the partial ADL is tracked and valued.
  function test_adlRecordsClaimableCollateral() public {
    _prepareForcedDecreaseState();
    _prepareAdlState();

    GmxTimeKeyViewer viewer = new GmxTimeKeyViewer();
    uint256 sizeBefore = _positionSizeInUsd(address(testPool), ArbitrumConfig.USDC, true);
    require(sizeBefore > 0, "ADL position missing");
    uint256 adlSize = sizeBefore / 2;

    uint256 executionSnapshot = _snapshot();

    // --- unregistered control branch ---
    _executeAdl(adlSize);
    uint256 sizeAfterUnregistered = _positionSizeInUsd(address(testPool), ArbitrumConfig.USDC, true);
    assertEq(sizeBefore - sizeAfterUnregistered, adlSize, "ADL did not reduce the position");

    uint256 timeKey = _currentGmxTimeKey();
    uint256 rawLong = _rawClaimableAmount(marketConfig.longToken, timeKey);
    uint256 rawShort = _rawClaimableAmount(marketConfig.shortToken, timeKey);
    require(rawLong > 0 || rawShort > 0, "ADL produced no claimable collateral");
    assertEq(_claimTimeKeys(viewer, marketConfig.longToken).length, 0, "unregistered long time key tracked");
    assertEq(_claimTimeKeys(viewer, marketConfig.shortToken).length, 0, "unregistered short time key tracked");

    uint256 unregisteredMarketValue = testPoolManagerLogic.assetValue(marketConfig.market);
    uint256 unregisteredFundValue = testPoolManagerLogic.totalFundValue();

    // --- registered branch: same state, guard registered, identical ADL ---
    _restore(executionSnapshot);
    _registerSavedCallback();
    _executeAdl(adlSize);

    assertEq(
      _positionSizeInUsd(address(testPool), ArbitrumConfig.USDC, true),
      sizeAfterUnregistered,
      "registered ADL size differs"
    );

    _assertRegisteredTracking(viewer, timeKey, rawLong, rawShort, unregisteredMarketValue, unregisteredFundValue);
  }
}

contract GmxBtcTestFFIArbitrum is GmxTestScenarios {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = MarketConfig({
      name: "BTC",
      market: 0x47c031236e19d024b42f8AE6780E44A573170703,
      indexToken: GmxTestSharedData.GMX_BTC_VIRTUAL_TOKEN,
      longToken: ArbitrumConfig.WBTC,
      shortToken: ArbitrumConfig.USDC,
      longCollateralToken: ArbitrumConfig.WBTC,
      longCollateralAmount: 1e6,
      longCollateralOracle: ArbitrumConfig.WBTC_CHAINLINK_ORACLE,
      longCollateralPythPriceId: GmxTestSharedData.PYTH_WBTC_PRICE_ID,
      sizeDeltaUsd: DEFAULT_SIZE_DELTA_USD,
      claimImpactMultiplier: 20_000
    });
  }
}

contract GmxSolTestFFIArbitrum is GmxTestScenarios {
  address internal constant WRAPPED_SOL = 0x2bcC6D6CdBbDC0a4071e48bb3B969b06B3330c07;

  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = MarketConfig({
      name: "SOL",
      market: 0x09400D9DB990D5ed3f35D7be61DfAEB900Af03C9,
      indexToken: WRAPPED_SOL,
      longToken: WRAPPED_SOL,
      shortToken: ArbitrumConfig.USDC,
      longCollateralToken: WRAPPED_SOL,
      longCollateralAmount: 5e9,
      longCollateralOracle: 0x24ceA4b8ce57cdA5058b924B9B9987992450590c,
      longCollateralPythPriceId: 0xef0d8b6fda2ceba41da15d4095d1da392a0d2f8ed0c6c7bc0f4cfac8c280b56d,
      sizeDeltaUsd: DEFAULT_SIZE_DELTA_USD,
      claimImpactMultiplier: 20_000
    });
  }
}

contract GmxSuiTestFFIArbitrum is GmxCollateralConfig {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = _wethCollateralConfig("SUI", GmxTestSharedData.GMX_SUI_MARKET, GmxTestSharedData.GMX_SUI_VIRTURAL_TOKEN);
  }
}

contract GmxDogeTestFFIArbitrum is GmxCollateralConfig {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = _wethCollateralConfig(
      "DOGE",
      GmxTestSharedData.GMX_DOGECOIN_MARKET,
      GmxTestSharedData.GMX_DOGECOIN_VIRTURAL_TOKEN
    );
  }
}

contract GmxXrpTestFFIArbitrum is GmxCollateralConfig {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = _wethCollateralConfig("XRP", GmxTestSharedData.GMX_XRP_MARKET, GmxTestSharedData.GMX_XRP_VIRTURAL_TOKEN);
  }
}

contract GmxHypeTestFFIArbitrum is GmxCollateralConfig {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = _wbtcCollateralConfig(
      "HYPE",
      GmxTestSharedData.GMX_HYPE_MARKET,
      GmxTestSharedData.GMX_HYPE_VIRTURAL_TOKEN
    );
  }
}

contract GmxBnbTestFFIArbitrum is GmxCollateralConfig {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = _wbtcCollateralConfig("BNB", GmxTestSharedData.GMX_BNB_BTCUSDC_MARKET, ArbitrumConfig.WRAPPED_BNB);
  }

  function _installIndexPriceAggregator() internal override {
    _installPriceAggregator(
      ArbitrumConfig.WRAPPED_BNB,
      ArbitrumConfig.WRAPPED_BNB_CHAINLINK_ORACLE,
      GmxTestSharedData.PYTH_BNB_PRICE_ID
    );
  }
}

contract GmxCrvTestFFIArbitrum is GmxCollateralConfig {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = _wethCollateralConfig("CRV", GmxTestSharedData.GMX_CRV_MARKET, GmxTestSharedData.GMX_CRV_VIRTURAL_TOKEN);
  }
}

contract GmxPumpTestFFIArbitrum is GmxCollateralConfig {
  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = _wbtcCollateralConfig(
      "PUMP",
      GmxTestSharedData.GMX_PUMP_MARKET,
      GmxTestSharedData.GMX_PUMP_VIRTURAL_TOKEN
    );
  }
}

contract GmxAaveTestFFIArbitrum is GmxTestScenarios {
  address internal constant AAVE = 0xba5DdD1f9d7F570dc94a51479a000E3BCE967196;

  function _getMarketConfig() internal pure override returns (MarketConfig memory config) {
    config = MarketConfig({
      name: "AAVE",
      market: GmxTestSharedData.GMX_AAVE_AAVEUSDC_MARKET,
      indexToken: AAVE,
      longToken: AAVE,
      shortToken: ArbitrumConfig.USDC,
      longCollateralToken: AAVE,
      longCollateralAmount: 5 ether,
      longCollateralOracle: 0xaD1d5344AaDE45F43E596773Bcc4c423EAbdD034,
      longCollateralPythPriceId: 0x2b9ab1e972a281585084148ba1389800799bd4be63b957507db1349314e47445,
      sizeDeltaUsd: DEFAULT_SIZE_DELTA_USD,
      claimImpactMultiplier: 20_000
    });
  }
}
