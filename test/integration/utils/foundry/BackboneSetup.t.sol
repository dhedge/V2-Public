// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/ProxyAdmin.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {SlippageAccumulator} from "contracts/utils/SlippageAccumulator.sol";
import {USDPriceAggregator} from "contracts/priceAggregators/USDPriceAggregator.sol";
import {ERC20Guard} from "contracts/guards/assetGuards/ERC20Guard.sol";
import {DhedgeNftTrackerStorage} from "contracts/utils/tracker/DhedgeNftTrackerStorage.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {WithdrawalVault} from "contracts/swappers/easySwapperV2/WithdrawalVault.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

abstract contract BackboneSetup is Test {
  enum AssetTypeIncomplete {
    CHAINLINK, // 0
    SNX_SYNTH, // 1
    SUSHI_LP, // 2
    AAVE_V2, // 3
    LENDING_ENABLED, // 4
    QUICK_LP, // 5
    BALANCER_LP, // 6
    UNISWAP_V3, // 7
    AAVE_V3, // 8
    ARRAKIS_GAUGE, // 9
    BALANCER_V2_GAUGE, // 10
    NOT_ASSIGNED_0, // 11
    NOT_ASSIGNED_1, // 12
    NOT_ASSIGNED_2, // 13
    SNX_SYNTH_LENDING_ENABLED, // 14
    VELODROME_LP, // 15
    STARGATE_LP, // 16
    MAI_VAULT, // 17
    NOT_ASSIGNED_3, // 18
    NOT_ASSIGNED_4, // 19
    RAMSES_LP, // 20
    FLAT_MONEY_UNIT, // 21
    FLAT_MONEY_COLLATERAL, // 22
    NOT_ASSGIGNED_5, // 23
    NOT_ASSIGNED_6, // 24
    VELODROME_V2_LP, // 25
    VELODROME_CL, // 26
    FLAT_MONEY_LEVERAGE, // 27
    COMPOUND_V3_COMET, // 28
    RAMSES_CL, // 29
    EASYSWAPPER_V2_UNROLLED, // 30
    PANCAKE_CL, // 31
    FLAT_MONEY_OPTIONS_MARKET, // 32
    FLAT_MONEY_COLLATERAL_LENDING_ENABLED, // 33
    FLUID_TOKEN, // 34
    FLAT_MONEY_V2_UNIT, // 35
    FLAT_MONEY_V2_PERP_MARKET, // 36
    PENDLE_PRINCIPAL_TOKEN // 37
  }

  address public owner = makeAddr("owner");
  address public dao = makeAddr("dao");
  address public manager = makeAddr("manager");
  address public investor = makeAddr("investor");

  address public proxyAdmin;
  Governance public governance;
  address public poolLogic;
  address public poolManagerLogic;
  address public assetHandler;
  AssetHandler public assetHandlerProxy;
  address public poolFactory;
  PoolFactory public poolFactoryProxy;
  SlippageAccumulator public slippageAccumulator;
  USDPriceAggregator public usdPriceAggregator;
  address public erc20Guard;
  address public nftTrackerStorage;
  DhedgeNftTrackerStorage public nftTrackerStorageProxy;
  address public withdrawalVault;
  address public easySwapperV2;
  EasySwapperV2 public easySwapperV2Proxy;

  AssetHandler.Asset public usdcData;
  AssetHandler.Asset public wethData;
  AssetHandler.Asset public daiData;

  constructor(AssetHandler.Asset memory _usdc, AssetHandler.Asset memory _weth, AssetHandler.Asset memory _dai) {
    usdcData = _usdc;
    wethData = _weth;
    daiData = _dai;
  }

  function setUp() public virtual {
    vm.startPrank(owner);

    proxyAdmin = address(new ProxyAdmin());
    governance = new Governance();
    poolLogic = address(new PoolLogic());
    poolManagerLogic = address(new PoolManagerLogic());
    assetHandler = address(new AssetHandler());
    poolFactory = address(new PoolFactory());
    usdPriceAggregator = new USDPriceAggregator();
    erc20Guard = address(new ERC20Guard());
    nftTrackerStorage = address(new DhedgeNftTrackerStorage());
    withdrawalVault = address(new WithdrawalVault());

    assetHandlerProxy = AssetHandler(address(new TransparentUpgradeableProxy(assetHandler, proxyAdmin, "")));
    poolFactoryProxy = PoolFactory(address(new TransparentUpgradeableProxy(poolFactory, proxyAdmin, "")));
    slippageAccumulator = new SlippageAccumulator(address(poolFactoryProxy), 21600, 5e4); // 6 hours, 5%
    nftTrackerStorageProxy = DhedgeNftTrackerStorage(
      address(new TransparentUpgradeableProxy(nftTrackerStorage, proxyAdmin, ""))
    );
    easySwapperV2Proxy = EasySwapperV2(
      address(new TransparentUpgradeableProxy(address(new EasySwapperV2()), proxyAdmin, ""))
    );

    AssetHandler.Asset[] memory assets = new AssetHandler.Asset[](3);
    assets[0] = usdcData;
    assets[1] = wethData;
    assets[2] = daiData;
    nftTrackerStorageProxy.initialize(address(poolFactoryProxy));
    assetHandlerProxy.initialize(assets);
    poolFactoryProxy.initialize({
      _poolLogic: poolLogic,
      _managerLogic: poolManagerLogic,
      _assetHandlerAddress: address(assetHandlerProxy),
      _daoAddress: dao,
      _governanceAddress: address(governance)
    });
    easySwapperV2Proxy.initialize({
      _vaultLogic: withdrawalVault,
      _weth: wethData.asset,
      _wrappedNativeToken: IWETH(wethData.asset),
      _swapper: ISwapper(0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D), // Hardcoded because same address on all chains, unlikely to change
      _customCooldown: 3600 // 1 hour
    });
    easySwapperV2Proxy.setdHedgePoolFactory(address(poolFactoryProxy));
    poolFactoryProxy.addCustomCooldownWhitelist(address(easySwapperV2Proxy));

    governance.setAssetGuard(uint16(AssetTypeIncomplete.CHAINLINK), erc20Guard);

    // Disable chainlink expiry timeout.
    assetHandlerProxy.setChainlinkTimeout(86400 * 365); // 1 year

    vm.label(address(governance), "Governance");
    vm.label(address(assetHandlerProxy), "AssetHandler");
    vm.label(address(poolFactoryProxy), "PoolFactory");
    vm.label(address(slippageAccumulator), "SlippageAccumulator");
    vm.label(address(easySwapperV2Proxy), "EasySwapperV2");

    vm.stopPrank();
  }

  function _getEmptyPoolComplexAssetsData(
    address _pool
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    complexAssetsData = new IPoolLogic.ComplexAsset[](
      IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic()).getSupportedAssets().length
    );
  }
}
