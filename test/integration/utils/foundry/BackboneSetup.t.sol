// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

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
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {AssetTypes} from "test/integration/utils/foundry/AssetTypes.sol";
import {PoolTestHelpers} from "test/integration/utils/foundry/PoolTestHelpers.t.sol";

abstract contract BackboneSetup is PoolTestHelpers, AssetTypes {
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
    slippageAccumulator = new SlippageAccumulator(address(poolFactoryProxy), 86400, 10e4); // 24 hours, 10% (prod values)
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
    easySwapperV2Proxy.initialize(
      withdrawalVault,
      address(0), // unused (deprecated) parameter
      IWETH(wethData.asset),
      ISwapper(EthereumConfig.SWAPPER), // Hardcoded because same address on all chains, unlikely to change
      3600 // 1 hour
    );
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
}
