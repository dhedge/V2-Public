// SPDX-License-Identifier: MIT

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
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {DytmConfigStructs} from "contracts/utils/dytm/DytmConfigStructs.sol";
import {IDytmAddressAccountBaseWhitelist} from "./dytmInterface/IDytmAddressAccountBaseWhitelist.sol";
import {IMarketConfig} from "./dytmInterface/IDytmMarketConfig.sol";
import {IDytmWeights} from "./dytmInterface/IDytmWeights.sol";

abstract contract DytmTestSetup is BackboneSetup, IntegrationDeployer {
  address public immutable dytmOffice;
  address public immutable dytmPeriphery;
  address public immutable dytmMarketConfig;
  address public immutable accountSplitterAndMerger;
  address public immutable nftTracker;

  address public immutable collateralAsset;
  address public immutable borrowAsset;
  uint256 public immutable collateralAmountNormalized;
  uint256 public immutable borrowAmountNormalized;
  address public immutable collateralOracle;
  address public immutable borrowOracle;
  uint256 public immutable maxDytmMarkets;
  bool public immutable isCollateralDhedgePoolToken;
  address public immutable marketCreator;
  PoolFactory public immutable dhedgePoolFactory;
  uint88 public marketId;

  PoolLogic public dytmTestPool;
  PoolManagerLogic public dytmTestPoolManagerLogic;
  IDytmOfficeContractGuard public dytmOfficeContractGuard;
  DytmOfficeAssetGuard public dytmOfficeAssetGuard;

  struct DytmTestConfig {
    address dhedgePoolFactory;
    address dytmOffice;
    address dytmPeriphery;
    address dytmMarketConfig; // for creating market
    address accountSplitterAndMerger;
    address nftTracker;
    address collateralAsset;
    address borrowAsset;
    uint256 collateralAmountNormalized;
    uint256 borrowAmountNormalized;
    address collateralOracle;
    address borrowOracle;
    uint256 maxDytmMarkets;
    bool isCollateralDhedgePoolToken;
    address marketCreator;
    uint88 dytmMarketId;
  }

  constructor(DytmTestConfig memory config) {
    dytmOffice = config.dytmOffice;
    dytmPeriphery = config.dytmPeriphery;
    dytmMarketConfig = config.dytmMarketConfig;
    accountSplitterAndMerger = config.accountSplitterAndMerger;
    nftTracker = config.nftTracker;
    collateralAsset = config.collateralAsset;
    borrowAsset = config.borrowAsset;
    collateralAmountNormalized = config.collateralAmountNormalized;
    borrowAmountNormalized = config.borrowAmountNormalized;
    collateralOracle = config.collateralOracle;
    borrowOracle = config.borrowOracle;
    maxDytmMarkets = config.maxDytmMarkets;
    isCollateralDhedgePoolToken = config.isCollateralDhedgePoolToken;
    dhedgePoolFactory = PoolFactory(config.dhedgePoolFactory);
    marketCreator = config.marketCreator;
    marketId = config.dytmMarketId;
  }

  function deployIntegration(PoolFactory _poolFactory, address, address, address _usdPriceAggregator) public override {
    // Get contracts to roll deployments on
    Governance governance = Governance(_poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    // Deploy Dytm Office Asset Guard
    dytmOfficeAssetGuard = new DytmOfficeAssetGuard(
      5,
      address(0),
      dytmOffice,
      address(_poolFactory),
      dytmPeriphery,
      accountSplitterAndMerger,
      address(0) // dytmWithdrawProcessor — set later when deployed
    );
    governance.setAssetGuard(uint16(106), address(dytmOfficeAssetGuard)); // Asset type 106 for DYTM

    // Add dytm office as supported asset
    assetHandler.addAsset(dytmOffice, uint16(106), _usdPriceAggregator);
    if (isCollateralDhedgePoolToken) {
      // Deploy DHedgePoolAggregator via deployCode (0.8.28 contract, can't use `new` from 0.7.6)
      address dhedgePoolAggregator = deployCode("DHedgePoolAggregator.sol", abi.encode(collateralAsset));
      assetHandler.addAsset(collateralAsset, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), dhedgePoolAggregator);
    } else {
      assetHandler.addAsset(collateralAsset, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), collateralOracle);
    }

    assetHandler.addAsset(borrowAsset, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), borrowOracle);

    vm.stopPrank();
  }

  function deployContractGuard(PoolFactory _poolFactory, PoolLogic tesPoolLogic) internal {
    Governance governance = Governance(_poolFactory.governanceAddress());

    vm.startPrank(_poolFactory.owner());

    // Create whitelisted pools and markets
    address[] memory whitelistedPools = new address[](1);
    whitelistedPools[0] = address(tesPoolLogic);

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

    deployIntegration(dhedgePoolFactory, address(0), address(0), address(usdPriceAggregator));

    vm.startPrank(manager);

    // Create pool without DYTM Office initially (contract guard must be set before addAssetCheck)
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: borrowAsset, isDeposit: true});

    dytmTestPool = PoolLogic(
      dhedgePoolFactory.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Dytm Tester",
        _fundName: "Dytm Test Pool",
        _fundSymbol: "DTP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    dytmTestPoolManagerLogic = PoolManagerLogic(dytmTestPool.poolManagerLogic());

    // create the DYTM market
    vm.startPrank(marketCreator);
    // marketId = IDytmOffice(dytmOffice).createMarket(owner, dytmMarketConfig);
    address hook = IMarketConfig(dytmMarketConfig).hooks();
    IDytmAddressAccountBaseWhitelist(hook).setAddressWhitelist(address(dytmTestPool), true);
    vm.stopPrank();

    // Deploy contract guard after pool is created (needs pool address for whitelisting)
    deployContractGuard(dhedgePoolFactory, dytmTestPool);

    // Add DYTM Office asset after contract guard is set (addAssetCheck requires it)
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory dytmAsset = new IHasSupportedAsset.Asset[](1);
    dytmAsset[0] = IHasSupportedAsset.Asset({asset: dytmOffice, isDeposit: false});
    dytmTestPoolManagerLogic.changeAssets(dytmAsset, new address[](0));
    vm.stopPrank();

    vm.startPrank(manager);
    // Approve dytm office to spend pool's tokens
    dytmTestPool.execTransaction(
      collateralAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, dytmOffice, type(uint256).max)
    );
    dytmTestPool.execTransaction(
      borrowAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, dytmOffice, type(uint256).max)
    );

    vm.stopPrank();

    vm.startPrank(investor);

    uint256 collateralAmount = collateralAmountNormalized * (10 ** IERC20Extended(collateralAsset).decimals());

    // investor deposits collateral into the dytm test pool
    deal(collateralAsset, investor, collateralAmount);
    IERC20Extended(collateralAsset).approve(address(dytmTestPool), type(uint256).max);
    dytmTestPool.deposit(collateralAsset, collateralAmount);

    // investor also deposits into dytm market via office, so that the pool can borrow later
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

  // ========== Test Functions ==========

  function test_can_supply_into_dytm() public {
    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();
    _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();

    assertEq(
      IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      0,
      "Test pool should have no collateral left after supply"
    );
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after supply"); // 0.01%
  }

  function test_can_withdraw_from_dytm() public {
    uint256 suppliedAmount = _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();
    uint256 collateralBalanceBefore = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          receiver: address(dytmTestPool),
          assets: suppliedAmount / 2,
          shares: 0,
          extraData: ""
        })
      )
    );

    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    uint256 collateralBalanceAfter = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));

    assertGt(collateralBalanceAfter, collateralBalanceBefore, "Test pool should have more collateral after withdraw");
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after withdraw"); // 0.01%
  }

  function test_can_borrow_from_dytm() public {
    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();
    uint256 borrowAssetBalanceBefore = IERC20Extended(borrowAsset).balanceOf(address(dytmTestPool));
    assertEq(borrowAssetBalanceBefore, 0, "Test pool should have no borrow asset before borrow");

    uint256 borrowed = _supplyAndBorrow();

    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    uint256 borrowAssetBalanceAfter = IERC20Extended(borrowAsset).balanceOf(address(dytmTestPool));

    assertEq(borrowAssetBalanceAfter, borrowed, "Test pool should have borrowed asset after borrow");
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after borrow"); // 0.01%
  }

  function test_can_repay_to_dytm() public {
    uint256 amountToBorrow = _supplyAndBorrow();

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    DytmParamStructs.AccountPosition memory positionBefore = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );
    assertApproxEqAbs(
      positionBefore.debt.debtAssets,
      amountToBorrow,
      2,
      "Test pool should have no debt left after repay"
    );

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.repay.selector,
        DytmParamStructs.RepayParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          withCollateralType: DytmParamStructs.TokenType.NONE,
          assets: amountToBorrow / 2,
          shares: 0,
          extraData: ""
        })
      )
    );

    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();

    // Check that debt is close to amountToBorrow / 2
    DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    assertApproxEqAbs(
      position.debt.debtAssets,
      amountToBorrow / 2,
      2,
      "Test pool should have no debt left after repay"
    );
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after repay"); // 0.01%
  }

  function test_can_switch_collateral_escrow_to_lend() public {
    uint256 suppliedAmount = _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();
    DytmParamStructs.AccountPosition memory positionBefore = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.switchCollateral.selector,
        DytmParamStructs.SwitchCollateralParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: suppliedAmount / 2,
          shares: 0
        })
      )
    );

    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    DytmParamStructs.AccountPosition memory positionAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore,
      0.0001e18,
      "Total value should not change after switch collateral"
    );
    assertApproxEqRel(
      positionAfter.totalCollateralValueUSD,
      positionBefore.totalCollateralValueUSD,
      0.0001e18,
      "Collateral value should not change after switch (just moved between reserve types)"
    );
  }

  function test_can_switch_collateral_lend_to_escrow() public {
    uint256 suppliedAmount = _supplyForLend({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();
    DytmParamStructs.AccountPosition memory positionBefore = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.switchCollateral.selector,
        DytmParamStructs.SwitchCollateralParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForLend(collateralAsset),
          assets: suppliedAmount / 2,
          shares: 0
        })
      )
    );

    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    DytmParamStructs.AccountPosition memory positionAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );

    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore,
      0.0001e18,
      "Total value should not change after switch collateral"
    );
    assertApproxEqRel(
      positionAfter.totalCollateralValueUSD,
      positionBefore.totalCollateralValueUSD,
      0.0001e18,
      "Collateral value should not change after switch (just moved between reserve types)"
    );
  }

  // ========== Revert Tests ==========

  function test_revert_addAsset_pool_not_whitelisted() public {
    // Create a new pool without DYTM Office
    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: borrowAsset, isDeposit: true});

    PoolLogic nonWhitelistedPool = PoolLogic(
      dhedgePoolFactory.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Non Whitelisted",
        _fundName: "Non Whitelisted Pool",
        _fundSymbol: "NWP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );

    // Non-whitelisted pool should not be able to add DYTM Office as asset
    PoolManagerLogic nonWhitelistedPoolManager = PoolManagerLogic(nonWhitelistedPool.poolManagerLogic());
    IHasSupportedAsset.Asset[] memory dytmAsset = new IHasSupportedAsset.Asset[](1);
    dytmAsset[0] = IHasSupportedAsset.Asset({asset: dytmOffice, isDeposit: false});

    vm.expectRevert("pool not whitelisted");
    nonWhitelistedPoolManager.changeAssets(dytmAsset, new address[](0));

    vm.stopPrank();
  }

  function test_revert_supply_unsupported_asset() public {
    address unsupportedAsset = address(0x1);

    vm.expectRevert("unsupported asset");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForLend(unsupportedAsset),
          assets: 1000,
          extraData: ""
        })
      )
    );
  }

  function test_revert_supply_invalid_user_account() public {
    address invalidAccount = address(0xdead);

    vm.expectRevert("recipient is not pool");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(invalidAccount)),
          tokenId: _getTokenIdForLend(collateralAsset),
          assets: 1000,
          extraData: ""
        })
      )
    );
  }

  function test_revert_supply_invalid_market() public {
    uint88 invalidMarketId = 999;

    vm.expectRevert("invalid market");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForMarket(collateralAsset, invalidMarketId, 1),
          assets: 1000,
          extraData: ""
        })
      )
    );
  }

  function test_revert_withdraw_unsupported_asset() public {
    _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    address unsupportedAsset = address(0x1);

    vm.expectRevert("unsupported asset");

    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(unsupportedAsset),
          receiver: address(dytmTestPool),
          assets: 1000,
          shares: 0,
          extraData: ""
        })
      )
    );
  }

  function test_revert_withdraw_invalid_receiver() public {
    _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    address invalidReceiver = address(0xdead);

    vm.expectRevert("invalid receiver");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForLend(collateralAsset),
          receiver: invalidReceiver,
          assets: 1000,
          shares: 0,
          extraData: ""
        })
      )
    );
  }

  function test_revert_borrow_unsupported_asset() public {
    _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    address unsupportedAsset = address(0x1);

    vm.expectRevert("unsupported asset");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(unsupportedAsset),
          receiver: address(dytmTestPool),
          assets: 1000,
          extraData: ""
        })
      )
    );
  }

  function test_revert_switchCollateral_invalid_user_account() public {
    address invalidAccount = address(0xdead);

    vm.expectRevert("recipient is not pool");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.switchCollateral.selector,
        DytmParamStructs.SwitchCollateralParams({
          account: uint256(uint160(invalidAccount)),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: 1000,
          shares: 0
        })
      )
    );
  }

  function test_revert_switchCollateral_invalid_market() public {
    uint88 invalidMarketId = 999;

    vm.expectRevert("invalid market");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.switchCollateral.selector,
        DytmParamStructs.SwitchCollateralParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForMarket(collateralAsset, invalidMarketId, 1),
          assets: 1000,
          shares: 0
        })
      )
    );
  }

  function test_revert_switchCollateral_unsupported_asset() public {
    address unsupportedAsset = address(0x1);

    vm.expectRevert("unsupported asset");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.switchCollateral.selector,
        DytmParamStructs.SwitchCollateralParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(unsupportedAsset),
          assets: 1000,
          shares: 0
        })
      )
    );
  }

  function test_revert_borrow_mixed_debt_assets() public {
    _supplyAndBorrow();

    vm.expectRevert("mixed debt assets not supported");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(collateralAsset),
          receiver: address(dytmTestPool),
          assets: 1000,
          extraData: ""
        })
      )
    );
  }

  function test_revert_borrow_invalid_receiver() public {
    _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    address invalidReceiver = address(0xdead);

    vm.expectRevert("invalid receiver");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: invalidReceiver,
          assets: 1000,
          extraData: ""
        })
      )
    );
  }

  function test_revert_when_dytm_office_asset_is_not_enabled() public {
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = dytmOffice;

    vm.startPrank(manager);
    dytmTestPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    vm.expectRevert("unsupported asset");
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: 0,
          extraData: ""
        })
      )
    );

    vm.expectRevert("unsupported asset");
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          receiver: address(dytmTestPool),
          assets: 0,
          shares: 0,
          extraData: ""
        })
      )
    );

    vm.expectRevert("unsupported asset");
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: 0,
          extraData: ""
        })
      )
    );

    vm.expectRevert("unsupported asset");
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.repay.selector,
        DytmParamStructs.RepayParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          withCollateralType: DytmParamStructs.TokenType.NONE,
          assets: 0,
          shares: 0,
          extraData: ""
        })
      )
    );

    vm.expectRevert("unsupported asset");
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.switchCollateral.selector,
        DytmParamStructs.SwitchCollateralParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: 0,
          shares: 0
        })
      )
    );
  }

  // ========== Helper Functions ==========

  function _supply(
    address asset,
    address onBehalfOf,
    uint256 amountToSupply,
    bool isHedgePool,
    uint256 tokenType
  ) internal returns (uint256) {
    if (isHedgePool) {
      vm.prank(manager);
      dytmTestPool.execTransaction(
        dytmOffice,
        abi.encodeWithSelector(
          IDytmOffice.supply.selector,
          DytmParamStructs.SupplyParams({
            account: uint256(uint160(address(dytmTestPool))),
            tokenId: _getTokenIdForMarket(asset, marketId, tokenType),
            assets: amountToSupply,
            extraData: ""
          })
        )
      );
    } else {
      deal(asset, onBehalfOf, amountToSupply);
      vm.prank(onBehalfOf);
      IDytmOffice(dytmOffice).supply(
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(onBehalfOf))),
          tokenId: _getTokenIdForMarket(asset, marketId, tokenType),
          assets: amountToSupply,
          extraData: ""
        })
      );
    }

    return amountToSupply;
  }

  function _supplyForLend(
    address asset,
    address onBehalfOf,
    uint256 amountToSupply,
    bool isHedgePool
  ) internal returns (uint256) {
    return _supply(asset, onBehalfOf, amountToSupply, isHedgePool, 2);
  }

  function _supplyForEscrow(
    address asset,
    address onBehalfOf,
    uint256 amountToSupply,
    bool isHedgePool
  ) internal returns (uint256) {
    return _supply(asset, onBehalfOf, amountToSupply, isHedgePool, 1);
  }

  function _supplyAndBorrow() internal returns (uint256 amountToBorrow) {
    _supplyForEscrow({
      onBehalfOf: address(dytmTestPool),
      asset: collateralAsset,
      amountToSupply: IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool)),
      isHedgePool: true
    });

    amountToBorrow = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: amountToBorrow,
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

  /// @dev Encodes a DYTM token ID from its components
  /// TokenId structure: tokenType (8 bits) | marketId (88 bits) | assetId (160 bits)
  /// tokenType: 1 = ESCROW (collateral backing borrows), 2 = LEND (collateral earning yield)
  function _getTokenIdForMarket(address asset, uint88 _marketId, uint256 tokenType) internal pure returns (uint256) {
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

  // ========== Multi-Market Tracking Tests ==========

  /// @notice Tests multi-market tracking with inactive market cleanup (3 markets, maxDytmMarkets = 2)
  /// 1. Supply into market 1 & 2 → 2 tracked
  /// 2. Try supply into market 3 → reverts "max position reached" (already at limit)
  /// 3. Withdraw all collateral from market 2 → still 2 tracked (withdraw doesn't trigger cleanup)
  /// 4. Supply into market 3 → cleanup removes inactive market 2, adds market 3 → 2 tracked (market 1 & 3)
  /// 5. Withdraw all from market 3, supply into market 1 → cleanup removes market 3 → 1 tracked (market 1)
  function test_cleanup_removes_inactive_market_from_tracking() public {
    // Setup 3 markets with maxDytmMarkets = 2
    (uint88 market2Id, uint88 market3Id) = _setupThreeMarkets();

    uint256 collateralBalance = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    uint256 thirdCollateral = collateralBalance / 3;
    uint256 poolAccount = uint256(uint160(address(dytmTestPool)));

    // 1. Supply collateral into market 1 and market 2
    vm.startPrank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, marketId, 1),
          assets: thirdCollateral,
          extraData: ""
        })
      )
    );
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, market2Id, 1),
          assets: thirdCollateral,
          extraData: ""
        })
      )
    );
    vm.stopPrank();

    // Verify both markets are tracked
    uint256[] memory tracked = dytmOfficeContractGuard.getOwnedTokenIds(address(dytmTestPool));
    assertEq(tracked.length, 2, "Both markets should be tracked");

    // 2. Supply into market 3 should fail — max position reached (2 active markets)
    vm.expectRevert("max position reached");
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, market3Id, 1),
          assets: thirdCollateral,
          extraData: ""
        })
      )
    );

    // 3. Withdraw ALL collateral from market 2
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, market2Id, 1),
          receiver: address(dytmTestPool),
          assets: thirdCollateral,
          shares: 0,
          extraData: ""
        })
      )
    );

    // Market 2 still tracked (withdraw doesn't trigger cleanup)
    tracked = dytmOfficeContractGuard.getOwnedTokenIds(address(dytmTestPool));
    assertEq(tracked.length, 2, "Both markets still tracked after withdraw");

    // 4. Supply into market 3 — triggers cleanup (removes inactive market 2), then adds market 3
    deal(collateralAsset, address(dytmTestPool), thirdCollateral);
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, market3Id, 1),
          assets: thirdCollateral,
          extraData: ""
        })
      )
    );

    // Verify: still 2 tracked but now market 1 and market 3 (market 2 was cleaned up)
    tracked = dytmOfficeContractGuard.getOwnedTokenIds(address(dytmTestPool));
    assertEq(tracked.length, 2, "Should still have 2 tracked markets");
    _assertContainsMarket(tracked, marketId, "Market 1 should be tracked");
    _assertContainsMarket(tracked, market3Id, "Market 3 should be tracked");

    // 5. Withdraw all from market 3, then supply into market 1 to trigger final cleanup
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, market3Id, 1),
          receiver: address(dytmTestPool),
          assets: thirdCollateral,
          shares: 0,
          extraData: ""
        })
      )
    );

    uint256 smallAmount = 1 * (10 ** IERC20Extended(collateralAsset).decimals());
    deal(collateralAsset, address(dytmTestPool), smallAmount);
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: poolAccount,
          tokenId: _getTokenIdForMarket(collateralAsset, marketId, 1),
          assets: smallAmount,
          extraData: ""
        })
      )
    );

    // 6. Only market 1 remains
    tracked = dytmOfficeContractGuard.getOwnedTokenIds(address(dytmTestPool));
    assertEq(tracked.length, 1, "Only market 1 should remain tracked");
    assertEq(tracked[0], uint256(marketId), "Market 1 should be the only tracked market");
  }

  // ========== Multi-Market Setup Helpers ==========

  function _setupThreeMarkets() internal returns (uint88 market2Id, uint88 market3Id) {
    IDytmWeights weights = IDytmWeights(IMarketConfig(dytmMarketConfig).weights());

    // Create market 2
    vm.prank(marketCreator);
    market2Id = IDytmOffice(dytmOffice).createMarket(marketCreator, dytmMarketConfig);
    vm.prank(marketCreator);
    weights.setWeight(
      _getTokenIdForMarket(collateralAsset, market2Id, 1),
      _getReserveKeyForMarket(borrowAsset, market2Id),
      uint64(0.85e18)
    );

    // Create market 3
    vm.prank(marketCreator);
    market3Id = IDytmOffice(dytmOffice).createMarket(marketCreator, dytmMarketConfig);
    vm.prank(marketCreator);
    weights.setWeight(
      _getTokenIdForMarket(collateralAsset, market3Id, 1),
      _getReserveKeyForMarket(borrowAsset, market3Id),
      uint64(0.85e18)
    );

    // Redeploy guard with all 3 markets whitelisted, maxDytmMarkets = 2
    Governance governance = Governance(dhedgePoolFactory.governanceAddress());
    vm.startPrank(dhedgePoolFactory.owner());

    address[] memory whitelistedPools = new address[](1);
    whitelistedPools[0] = address(dytmTestPool);

    uint88[] memory whitelistedMarkets = new uint88[](3);
    whitelistedMarkets[0] = marketId;
    whitelistedMarkets[1] = market2Id;
    whitelistedMarkets[2] = market3Id;

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

  function _assertContainsMarket(
    uint256[] memory trackedIds,
    uint88 expectedMarketId,
    string memory message
  ) internal pure {
    bool found;
    for (uint256 i; i < trackedIds.length; ++i) {
      if (trackedIds[i] == uint256(expectedMarketId)) {
        found = true;
        break;
      }
    }
    assertTrue(found, message);
  }
}
