// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {GmxPerpMarketAssetGuard} from "contracts/guards/assetGuards/gmx/GmxPerpMarketAssetGuard.sol";
import {EasySwapperV2ContractGuard} from "contracts/guards/contractGuards/EasySwapperV2ContractGuard.sol";
import {GmxExchangeRouterContractGuard} from "contracts/guards/contractGuards/gmx/GmxExchangeRouterContractGuard.sol";
import {OneInchV6Guard} from "contracts/guards/contractGuards/OneInchV6Guard.sol";
import {KyberSwapRouterV2ContractGuard} from "contracts/guards/contractGuards/kyberSwap/KyberSwapRouterV2ContractGuard.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IMetaAggregationRouterV2} from "contracts/interfaces/kyberSwap/IMetaAggregationRouterV2.sol";
import {IAggregationExecutor, IAggregationRouterV6} from "contracts/interfaces/oneInch/IAggregationRouterV6.sol";
import {IUniswapV2Factory} from "contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {GmxStructs} from "contracts/utils/gmx/GmxStructs.sol";

import {MockSwapExecutor} from "test/integration/common/oneInch/MockSwapExecutor.sol";
import {GmxTestSharedData} from "test/integration/arbitrum/gmx/GmxTestSharedData.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/// @notice Regression tests ensuring a GMX market token cannot be sold through a generic swap router.
///         Its raw token units are priced inside the composite GMX position, while the registered asset
///         oracle is fixed at $1 for that already-USD-denominated position value.
contract GmxMarketTokenExfiltrationTest is ArbitrumSetup {
  address internal constant UNISWAP_V2_FACTORY = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9;
  address internal immutable GMX_MARKET = GmxTestSharedData.GMX_AAVE_AAVEUSDC_MARKET;
  address internal immutable ONE_INCH_ROUTER = EthereumConfig.ONE_INCH_V6_ROUTER;
  address internal immutable KYBER_ROUTER = EthereumConfig.KYBER_SWAP_ROUTER_V2;
  uint256 internal constant MARKET_TOKEN_AMOUNT = 100e18;
  uint256 internal constant USDC_OUT = 100e6;

  PoolLogic internal vault;
  PoolLogic internal targetVault;
  PoolManagerLogic internal vaultManagerLogic;
  address internal thief = makeAddr("thief");

  constructor() ArbitrumSetup(ForkBlocks.ARBITRUM) {}

  function setUp() public override {
    super.setUp();

    _createVault();
    _createEasySwapperTargetVault();
    _deployGmxIntegration();
    _deploySwapGuards();

    deal(GMX_MARKET, address(vault), MARKET_TOKEN_AMOUNT);
    assertEq(IERC20(GMX_MARKET).balanceOf(address(vault)), MARKET_TOKEN_AMOUNT, "market tokens funded");
  }

  function test_gmx_market_token_source_via_one_inch_reverts() public {
    _assertGmxMarketTokenSourceReverts(ONE_INCH_ROUTER);
  }

  function test_gmx_market_token_source_via_kyberswap_reverts() public {
    _assertGmxMarketTokenSourceReverts(KYBER_ROUTER);
  }

  function test_gmx_market_token_source_via_easy_swapper_v2_reverts() public {
    _assertGmxMarketTokenSourceViaEasySwapperReverts(false);
  }

  function test_gmx_market_token_source_via_easy_swapper_v2_referral_reverts() public {
    _assertGmxMarketTokenSourceViaEasySwapperReverts(true);
  }

  function _assertGmxMarketTokenSourceReverts(address _router) internal {
    MockSwapExecutor executor = new MockSwapExecutor(GMX_MARKET, ArbitrumConfig.USDC, thief, USDC_OUT);
    deal(ArbitrumConfig.USDC, address(executor), USDC_OUT);

    bytes memory swapData;
    if (_router == ONE_INCH_ROUTER) {
      swapData = _buildOneInchSwapData(address(executor));
    } else {
      assertEq(_router, KYBER_ROUTER, "unexpected router");
      swapData = _buildKyberSwapData(address(executor));
    }

    vm.startPrank(manager);
    vault.execTransaction(GMX_MARKET, abi.encodeWithSelector(IERC20.approve.selector, _router, MARKET_TOKEN_AMOUNT));

    vm.expectRevert("accounted token source");
    vault.execTransaction(_router, swapData);
    vm.stopPrank();

    assertEq(IERC20(GMX_MARKET).balanceOf(address(vault)), MARKET_TOKEN_AMOUNT, "market tokens retained");
    assertEq(IERC20(GMX_MARKET).balanceOf(thief), 0, "attacker got nothing");
  }

  function _assertGmxMarketTokenSourceViaEasySwapperReverts(bool _withReferral) internal {
    MockSwapExecutor executor = new MockSwapExecutor(GMX_MARKET, ArbitrumConfig.USDC, thief, USDC_OUT);
    deal(ArbitrumConfig.USDC, address(executor), USDC_OUT);

    IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
      srcToken: GMX_MARKET,
      dstToken: ArbitrumConfig.USDC,
      srcReceiver: payable(address(executor)),
      dstReceiver: payable(ArbitrumConfig.SWAPPER),
      amount: MARKET_TOKEN_AMOUNT,
      minReturnAmount: USDC_OUT,
      flags: 0
    });
    bytes memory aggregatorSwapData = abi.encodeWithSelector(
      IAggregationRouterV6.swap.selector,
      address(executor),
      desc,
      bytes("")
    );

    EasySwapperV2.SingleInSingleOutData memory zapData = EasySwapperV2.SingleInSingleOutData({
      srcData: ISwapper.SrcTokenSwapDetails({
        token: IERC20(GMX_MARKET),
        amount: MARKET_TOKEN_AMOUNT,
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32("ONE_INCH"), swapData: aggregatorSwapData})
      }),
      destData: ISwapper.DestData({destToken: IERC20(ArbitrumConfig.USDC), minDestAmount: USDC_OUT})
    });

    bytes memory easySwapperTxData;
    if (_withReferral) {
      easySwapperTxData = abi.encodeWithSignature(
        "zapDepositWithCustomCooldown(address,((address,uint256,(bytes32,bytes)),(address,uint256)),uint256,bytes)",
        address(targetVault),
        zapData,
        0,
        bytes("")
      );
    } else {
      easySwapperTxData = abi.encodeWithSignature(
        "zapDepositWithCustomCooldown(address,((address,uint256,(bytes32,bytes)),(address,uint256)),uint256)",
        address(targetVault),
        zapData,
        0
      );
    }

    vm.startPrank(manager);
    vault.execTransaction(
      GMX_MARKET,
      abi.encodeWithSelector(IERC20.approve.selector, address(easySwapperV2Proxy), MARKET_TOKEN_AMOUNT)
    );

    vm.expectRevert("accounted token source");
    vault.execTransaction(address(easySwapperV2Proxy), easySwapperTxData);
    vm.stopPrank();

    assertEq(IERC20(GMX_MARKET).balanceOf(address(vault)), MARKET_TOKEN_AMOUNT, "market tokens retained");
    assertEq(IERC20(GMX_MARKET).balanceOf(thief), 0, "attacker got nothing");
  }

  function _createVault() internal {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: ArbitrumConfig.USDC, isDeposit: true});

    vm.prank(manager);
    vault = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "GMX Market Token Exfiltration Test",
        _fundSymbol: "GMX-EXFIL",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    vaultManagerLogic = PoolManagerLogic(vault.poolManagerLogic());
  }

  function _createEasySwapperTargetVault() internal {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: ArbitrumConfig.USDC, isDeposit: true});

    vm.prank(manager);
    targetVault = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Target Manager",
        _fundName: "EasySwapper Target",
        _fundSymbol: "ES-TARGET",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );

    address targetVaultAggregator = deployCode("DHedgePoolAggregator.sol", abi.encode(address(targetVault)));

    EasySwapperV2.WhitelistSetting[] memory whitelistSettings = new EasySwapperV2.WhitelistSetting[](1);
    whitelistSettings[0] = EasySwapperV2.WhitelistSetting({toWhitelist: address(targetVault), whitelisted: true});

    vm.startPrank(owner);
    assetHandlerProxy.addAsset(address(targetVault), uint16(AssetTypeIncomplete.CHAINLINK), targetVaultAggregator);
    easySwapperV2Proxy.setCustomCooldownWhitelist(whitelistSettings);
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory toAdd = new IHasSupportedAsset.Asset[](1);
    toAdd[0] = IHasSupportedAsset.Asset({asset: address(targetVault), isDeposit: false});
    vm.prank(manager);
    vaultManagerLogic.changeAssets(toAdd, new address[](0));
  }

  function _deployGmxIntegration() internal {
    GmxStructs.PoolSetting[] memory poolSettings = new GmxStructs.PoolSetting[](1);
    poolSettings[0] = GmxStructs.PoolSetting({poolLogic: address(vault), withdrawalAsset: ArbitrumConfig.USDC});

    vm.startPrank(owner);
    GmxExchangeRouterContractGuard gmxContractGuard = new GmxExchangeRouterContractGuard(
      GmxTestSharedData.getGmxContractGuardConfig(),
      poolSettings,
      GmxTestSharedData.getVirtualTokenResolver(),
      address(slippageAccumulator),
      address(nftTrackerStorageProxy)
    );
    governance.setContractGuard(GmxTestSharedData.GMX_EXCHANGE_ROUTER, address(gmxContractGuard));

    GmxPerpMarketAssetGuard gmxAssetGuard = new GmxPerpMarketAssetGuard(GmxTestSharedData.GMX_EXCHANGE_ROUTER);
    governance.setAssetGuard(GmxTestSharedData.GMX_PEPRS_MARKET_ASSET_TYPE, address(gmxAssetGuard));
    assetHandlerProxy.addAsset(GMX_MARKET, GmxTestSharedData.GMX_PEPRS_MARKET_ASSET_TYPE, address(usdPriceAggregator));
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory toAdd = new IHasSupportedAsset.Asset[](1);
    toAdd[0] = IHasSupportedAsset.Asset({asset: GMX_MARKET, isDeposit: false});
    vm.prank(manager);
    vaultManagerLogic.changeAssets(toAdd, new address[](0));
  }

  function _deploySwapGuards() internal {
    vm.startPrank(owner);
    governance.setContractGuard(
      ONE_INCH_ROUTER,
      address(
        new OneInchV6Guard(
          address(slippageAccumulator),
          IUniswapV2Factory(UNISWAP_V2_FACTORY),
          IUniswapV3Factory(ArbitrumConfig.UNISWAP_V3_FACTORY),
          address(0)
        )
      )
    );
    governance.setContractGuard(
      KYBER_ROUTER,
      address(new KyberSwapRouterV2ContractGuard(address(slippageAccumulator)))
    );
    governance.setContractGuard(
      address(easySwapperV2Proxy),
      address(new EasySwapperV2ContractGuard(address(slippageAccumulator), 200))
    );
    vm.stopPrank();
  }

  function _buildOneInchSwapData(address _executor) internal view returns (bytes memory) {
    IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
      srcToken: GMX_MARKET,
      dstToken: ArbitrumConfig.USDC,
      srcReceiver: payable(_executor),
      dstReceiver: payable(address(vault)),
      amount: MARKET_TOKEN_AMOUNT,
      minReturnAmount: 1,
      flags: 0
    });

    return abi.encodeWithSelector(IAggregationRouterV6.swap.selector, _executor, desc, bytes(""));
  }

  function _buildKyberSwapData(address _executor) internal view returns (bytes memory) {
    address[] memory srcReceivers = new address[](1);
    srcReceivers[0] = _executor;
    uint256[] memory srcAmounts = new uint256[](1);
    srcAmounts[0] = MARKET_TOKEN_AMOUNT;

    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
      srcToken: GMX_MARKET,
      dstToken: ArbitrumConfig.USDC,
      srcReceivers: srcReceivers,
      srcAmounts: srcAmounts,
      feeReceivers: new address[](0),
      feeAmounts: new uint256[](0),
      dstReceiver: address(vault),
      amount: MARKET_TOKEN_AMOUNT,
      minReturnAmount: 1,
      flags: 0,
      permit: bytes("")
    });
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
      callTarget: _executor,
      approveTarget: _executor,
      targetData: abi.encodeWithSelector(IAggregationExecutor.execute.selector, address(vault)),
      desc: desc,
      clientData: bytes("")
    });

    return abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);
  }
}
