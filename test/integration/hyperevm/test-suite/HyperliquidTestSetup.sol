// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {HyperliquidBackboneSetup, IChangeAssets} from "./HyperliquidBackboneSetup.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "contracts/interfaces/IPoolManagerLogic.sol";

// Hyperliquid Guards - Using interfaces only due to version incompatibility
// Guards are deployed using deployCode in deployIntegration()

// Hyperliquid Interfaces
import {ICoreWriter} from "contracts/interfaces/hyperliquid/ICoreWriter.sol";
import {ICoreDepositWallet} from "contracts/interfaces/hyperliquid/ICoreDepositWallet.sol";
import {IHyperliquidCoreWriterContractGuard} from "contracts/interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";

import {CoreSimulatorLib} from "test/integration/hyperevm/test-suite/hyperevm-lib/CoreSimulatorLib.sol";
import {HyperCore} from "test/integration/hyperevm/test-suite/hyperevm-lib/HyperCore.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";

import {HyperliquidSpotPriceAggregator} from "contracts/priceAggregators/HyperliquidSpotPriceAggregator.sol";

/// @title Hyperliquid Test Setup for Foundry integration tests
/// @notice Abstract contract providing setup for Hyperliquid integration testing on HyperEVM
/// @dev Extend this contract and implement chain-specific configuration in child contracts
abstract contract HyperliquidTestSetup is HyperliquidBackboneSetup {
  /////////////////////////////////////////////
  //                 State                   //
  /////////////////////////////////////////////

  /// @notice Test pool for Hyperliquid integration testing
  address public hyperliquidTestPool;

  /// @notice PoolManagerLogic of the test pool
  address public hyperliquidTestPoolManagerLogic;

  /// @notice Deployed HyperliquidCoreWriterContractGuard instance
  IHyperliquidCoreWriterContractGuard public hyperliquidCoreWriterContractGuard;

  /// @dev Core simulator instance for HyperEVM
  HyperCore public hyperCore;

  /// @notice Deployed HyperliquidCoreDepositWalletContractGuard instance
  address public hyperliquidCoreDepositWalletGuard;

  /// @notice Deployed HyperliquidPositionGuard instance
  address public hyperliquidPositionGuard;

  /// @notice Deployed HyperliquidSpotGuard instance (for spot assets like XAUT0)
  address public hyperliquidSpotGuard;

  /// @notice Deployed HyperliquidSpotPriceAggregator for XAUT0
  address public xaut0PriceAggregator;

  address public constant coreWriter = HyperEVMConfig.CORE_WRITER;
  address public constant coreDepositWallet = HyperEVMConfig.CORE_DEPOSIT_WALLET;
  address public constant usdc = HyperEVMConfig.USDC_TOKEN_ADDRESS;
  address public constant xaut = HyperEVMConfig.XAUT0_TOKEN_ADDRESS;

  /////////////////////////////////////////////
  //           Integration Deployment        //
  /////////////////////////////////////////////

  /// @notice Deploys all Hyperliquid-related contracts and guards
  function deployIntegration() internal {
    vm.startPrank(owner);

    // Deploy HyperliquidCoreWriterContractGuard implementation
    address coreWriterGuardImplementation = deployCode("HyperliquidCoreWriterContractGuard.sol");

    // Encode the initialize call for the proxy
    // maxSlippagePerSpotTrade = 2% (in WAD format)
    bytes memory initializeData = abi.encodeWithSelector(
      IHyperliquidCoreWriterContractGuard.initialize.selector,
      owner,
      uint64(0.02e18)
    );

    // Deploy TransparentUpgradeableProxy with the implementation and initialization data
    hyperliquidCoreWriterContractGuard = IHyperliquidCoreWriterContractGuard(
      address(new TransparentUpgradeableProxy(coreWriterGuardImplementation, proxyAdmin, initializeData))
    );

    // Deploy HyperliquidCoreDepositWalletContractGuard for USDC bridging using deployCode
    hyperliquidCoreDepositWalletGuard = deployCode("HyperliquidCoreDepositWalletContractGuard.sol");

    // Deploy HyperliquidPositionGuard using deployCode
    hyperliquidPositionGuard = deployCode("HyperliquidPositionGuard.sol");

    // Deploy the HyperliquidSpotGuard using deployCode
    hyperliquidSpotGuard = deployCode("HyperliquidSpotGuard.sol");

    // Set contract guards
    governance.setContractGuard(coreWriter, address(hyperliquidCoreWriterContractGuard));
    governance.setContractGuard(coreDepositWallet, address(hyperliquidCoreDepositWalletGuard));

    // Set asset guards
    governance.setAssetGuard(uint16(AssetTypeIncomplete.HYPERLIQUID_PERPS_ASSET), address(hyperliquidPositionGuard));
    governance.setAssetGuard(uint16(AssetTypeIncomplete.HYPERLIQUID_SPOT), address(hyperliquidSpotGuard));

    // Add assets to the asset handler
    // CoreWriter address is used as the asset address for perps positions
    assetHandlerProxy.addAsset(coreWriter, uint16(AssetTypeIncomplete.HYPERLIQUID_PERPS_ASSET), usdPriceAggregator);
    // USDC is now a regular ERC20 asset - uses Chainlink price feed for USDC/USD
    assetHandlerProxy.addAsset(usdc, uint16(AssetTypeIncomplete.CHAINLINK), HyperEVMConfig.USDC_USD_PRICE_FEED);

    // Deploy price aggregator for XAUT0
    xaut0PriceAggregator = address(
      new HyperliquidSpotPriceAggregator(HyperEVMConfig.XAUT0_SPOT_INDEX, HyperEVMConfig.USDC_USD_PRICE_FEED)
    );

    // Add XAUT0 system address as an asset (type 40 - HYPERLIQUID_SPOT)
    assetHandlerProxy.addAsset(
      HyperEVMConfig.XAUT0_SYSTEM_ADDRESS,
      uint16(AssetTypeIncomplete.HYPERLIQUID_SPOT),
      xaut0PriceAggregator
    );

    vm.stopPrank();
  }

  /////////////////////////////////////////////
  //                  Setup                  //
  /////////////////////////////////////////////

  function setUp() public virtual override {
    hyperCore = CoreSimulatorLib.init();

    super.setUp();

    deployIntegration();

    vm.startPrank(manager);

    // Create supported assets for the test pool
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);

    // USDC as deposit asset
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdc, isDeposit: true});

    // Create the test pool
    hyperliquidTestPool = poolFactoryProxy.createFund({
      _privatePool: false,
      _manager: manager,
      _managerName: "Hyperliquid Tester",
      _fundName: "Hyperliquid Test Pool",
      _fundSymbol: "HTP",
      _performanceFeeNumerator: 0,
      _managerFeeNumerator: 0,
      _entryFeeNumerator: 0,
      _exitFeeNum: 0,
      _supportedAssets: supportedAssets
    });

    // NOTE: If we don't force activate the account the addition of the new asset (coreWriter) will fail
    //       the `addAssetCheck` since the account won't be activated yet.
    CoreSimulatorLib.forceAccountActivation(hyperliquidTestPool);

    hyperliquidTestPoolManagerLogic = IPoolLogic(hyperliquidTestPool).poolManagerLogic();

    // Whitelist the test pool for Hyperliquid
    IHyperliquidCoreWriterContractGuard.WhitelistSetting[]
      memory poolWhitelistSettings = new IHyperliquidCoreWriterContractGuard.WhitelistSetting[](1);
    poolWhitelistSettings[0] = IHyperliquidCoreWriterContractGuard.WhitelistSetting({
      poolLogic: address(hyperliquidTestPool),
      whitelisted: true
    });

    vm.startPrank(owner);
    hyperliquidCoreWriterContractGuard.setDhedgePoolsWhitelist(poolWhitelistSettings);

    vm.startPrank(manager);

    // Create supported assets for the test pool
    // For now keep it empty as addition of spot and perp assets will require activation of the HyperCore account.
    supportedAssets = new IHasSupportedAsset.Asset[](2);

    // CoreWriter address for perps positions (not a deposit asset)
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: coreWriter, isDeposit: false});

    // XAUT0 system address for spot trading (not a deposit asset)
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: HyperEVMConfig.XAUT0_SYSTEM_ADDRESS, isDeposit: false});

    // Add supported assets to the pool
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(supportedAssets, new address[](0));

    // Approve USDC for CoreDepositWallet
    IPoolLogic(hyperliquidTestPool).execTransaction(
      usdc,
      abi.encodeWithSelector(IERC20Extended.approve.selector, coreDepositWallet, type(uint256).max)
    );

    // Fund the investor and manager with USDC for testing
    uint256 usdcAmount = 100_000_000e6;
    deal(usdc, investor, usdcAmount);
    deal(usdc, manager, usdcAmount);

    // Fund the investor and approve the test pool to spend investor's USDC.
    vm.startPrank(investor);
    IERC20Extended(usdc).approve(hyperliquidTestPool, type(uint256).max);

    vm.startPrank(manager);
    IERC20Extended(usdc).approve(hyperliquidTestPool, type(uint256).max);

    // Make initial deposit (by manager) to establish token price
    uint256 initialDepositAmount = 10_000e6; // 10,000 USDC
    IPoolLogic(hyperliquidTestPool).deposit(usdc, initialDepositAmount);

    vm.stopPrank();
  }

  /////////////////////////////////////////////
  //              Helper Functions           //
  /////////////////////////////////////////////

  /// @notice Bridges USDC to HyperCore via CoreDepositWallet
  /// @param amount Amount of USDC to bridge
  /// @param destinationDex Destination dex ID on HyperCore
  function _bridgeUSDCToCore(uint256 amount, uint32 destinationDex) internal {
    vm.prank(manager);
    IPoolLogic(hyperliquidTestPool).execTransaction(
      coreDepositWallet,
      abi.encodeWithSelector(ICoreDepositWallet.deposit.selector, amount, destinationDex)
    );
  }

  /// @notice Places a limit order on Hyperliquid via CoreWriter
  /// @param actionData The encoded action data for the limit order
  function _placeLimitOrder(bytes memory actionData) internal {
    vm.prank(manager);
    IPoolLogic(hyperliquidTestPool).execTransaction(
      coreWriter,
      abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, actionData)
    );
  }

  /// @notice Gets the total fund value of the test pool
  /// @return value The total fund value
  function _getTotalFundValue() internal view returns (uint256 value) {
    return IPoolManagerLogic(hyperliquidTestPoolManagerLogic).totalFundValue();
  }

  /// @notice Gets the USDC balance of the test pool
  /// @return balance The USDC balance
  function _getPoolUSDCBalance() internal view returns (uint256 balance) {
    return IERC20(usdc).balanceOf(address(hyperliquidTestPool));
  }
}
