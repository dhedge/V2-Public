// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {FlatMoneyV2UNITAssetGuard} from "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyV2UNITAssetGuard.sol";
import {FlatMoneyV2UNITOutsideWithdrawalAssetGuard} from "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyV2UNITOutsideWithdrawalAssetGuard.sol";
import {FlatMoneyCollateralAssetGuard} from "contracts/guards/assetGuards/flatMoney/FlatMoneyCollateralAssetGuard.sol";
import {FlatMoneyOptionsOrderAnnouncementGuard} from "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyOptionsOrderAnnouncementGuard.sol";
import {FlatMoneyBasisContractGuard} from "contracts/guards/contractGuards/flatMoney/shared/FlatMoneyBasisContractGuard.sol";
import {FlatMoneyUNITPriceAggregator} from "contracts/priceAggregators/FlatMoneyUNITPriceAggregator.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IFlatcoinVaultV2} from "contracts/interfaces/flatMoney/v2/IFlatcoinVaultV2.sol";
import {IOrderAnnouncementModule} from "contracts/interfaces/flatMoney/v2/IOrderAnnouncementModule.sol";
import {IDelayedOrder} from "contracts/interfaces/flatMoney/IDelayedOrder.sol";
import {IViewer} from "contracts/interfaces/flatMoney/IViewer.sol";
import {FlatcoinModuleKeys} from "contracts/utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {FlatMoneyV2OptionsConfig} from "contracts/guards/contractGuards/flatMoney/shared/FlatMoneyV2OptionsConfig.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";

// TODO: Adjust token amounts used in tests once required to reuse, currently set for WBTC (8 decimals)
abstract contract FlatMoneyOptionsLPTestSetup is BackboneSetup, IntegrationDeployer {
  IFlatcoinVaultV2 internal immutable vault;
  address internal immutable viewer;
  address internal immutable collateralAssetPriceFeed;
  uint256 internal immutable keeperFee;

  address internal orderAnnouncementModule;
  address internal orderExecutionModule;
  address internal stableModule;
  address internal collateralAsset;
  uint8 internal collateralAssetDecimals;
  FlatMoneyOptionsOrderAnnouncementGuard internal contractGuard;
  PoolLogic internal whitelistedPool;
  PoolManagerLogic internal whitelistedPoolManagerLogic;
  address internal whitelistedPoolManager;

  constructor(address _flatcoinVault, address _viewer, address _collateralAssetPriceFeed, uint256 _keeperFee) {
    vault = IFlatcoinVaultV2(_flatcoinVault);
    viewer = _viewer;
    collateralAssetPriceFeed = _collateralAssetPriceFeed;
    keeperFee = _keeperFee;
  }

  function deployIntegration(PoolFactory _poolFactory, address _nftTracker, address, address) public override {
    // Get contracts to roll deployments on
    Governance governance = Governance(_poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    FlatMoneyUNITPriceAggregator unitOracle = new FlatMoneyUNITPriceAggregator(IViewer(viewer));

    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](2);
    assets[0] = IAssetHandler.Asset({
      asset: collateralAsset,
      assetType: uint16(AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      aggregator: collateralAssetPriceFeed
    });
    assets[1] = IAssetHandler.Asset({
      asset: stableModule,
      assetType: uint16(AssetTypeIncomplete.FLAT_MONEY_V2_UNIT),
      aggregator: address(unitOracle)
    });
    assetHandler.addAssets(assets);

    // Create a new pool for testing
    whitelistedPool = _createTestPool(_poolFactory);
    whitelistedPoolManagerLogic = PoolManagerLogic(whitelistedPool.poolManagerLogic());
    whitelistedPoolManager = whitelistedPoolManagerLogic.manager();

    // Two contract guards
    FlatMoneyOptionsOrderAnnouncementGuard.PoolSetting[]
      memory whitelistedPoolSettings = new FlatMoneyOptionsOrderAnnouncementGuard.PoolSetting[](1);
    whitelistedPoolSettings[0] = FlatMoneyBasisContractGuard.PoolSetting({
      poolLogic: address(whitelistedPool),
      withdrawalAsset: collateralAsset
    });
    contractGuard = new FlatMoneyOptionsOrderAnnouncementGuard(
      _nftTracker,
      FlatMoneyV2OptionsConfig.NFT_TYPE,
      FlatMoneyV2OptionsConfig.MAX_POSITIONS,
      whitelistedPoolSettings,
      FlatMoneyV2OptionsConfig.MAX_ALLOWED_LEVERAGE
    );
    governance.setContractGuard(orderAnnouncementModule, address(contractGuard));

    FlatMoneyV2UNITAssetGuard unitAssetGuard = new FlatMoneyV2UNITAssetGuard();
    FlatMoneyCollateralAssetGuard collateralAssetGuard = new FlatMoneyCollateralAssetGuard(
      address(orderAnnouncementModule)
    );
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_V2_UNIT), address(unitAssetGuard));
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_COLLATERAL), address(collateralAssetGuard));

    vm.startPrank(whitelistedPoolManager);
    IHasSupportedAsset.Asset[] memory newAssets = new IHasSupportedAsset.Asset[](2);
    newAssets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});
    newAssets[1] = IHasSupportedAsset.Asset({asset: stableModule, isDeposit: true});
    whitelistedPoolManagerLogic.changeAssets(newAssets, new address[](0));

    vm.stopPrank();
  }

  function setUp() public virtual override {
    super.setUp();

    // Remove max skew check to avoid reverts
    vm.prank(vault.owner());
    vault.setSkewFractionMax(type(uint256).max);

    // Store collateral asset used for the contracts set to test
    collateralAsset = vault.collateral();
    collateralAssetDecimals = IERC20Extended(collateralAsset).decimals();

    orderAnnouncementModule = vault.moduleAddress(FlatcoinModuleKeys._ORDER_ANNOUNCEMENT_MODULE_KEY);
    orderExecutionModule = vault.moduleAddress(FlatcoinModuleKeys._ORDER_EXECUTION_MODULE_KEY);
    stableModule = vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY);

    deployIntegration(poolFactoryProxy, address(nftTrackerStorageProxy), address(0), address(0));

    // Deposit collateral asset into whitelisted pool
    vm.startPrank(whitelistedPoolManager);

    deal(collateralAsset, whitelistedPoolManager, 1e8);
    IERC20Extended(collateralAsset).approve(address(whitelistedPool), 1e8);
    whitelistedPool.deposit(collateralAsset, 1e8);

    // Max approve spending collateral asset from within the whitelisted pool
    whitelistedPool.execTransaction(
      collateralAsset,
      abi.encodeWithSelector(IERC20Extended.approve.selector, orderAnnouncementModule, type(uint256).max)
    );

    vm.stopPrank();

    // Mock ArbGasPriceOracle contract calls
    address arbGasPriceOracle = 0x000000000000000000000000000000000000006C;
    vm.mockCall(
      arbGasPriceOracle,
      abi.encodeWithSignature("getPricesInWei()"),
      abi.encode(2951661440, 337332736, 6421120000000, 320000000, 1056000, 20066000)
    );
    vm.mockCall(arbGasPriceOracle, abi.encodeWithSignature("getL1BaseFeeEstimate()"), abi.encode(1317706));
  }

  function test_should_be_able_to_cancel_pending_order() public {
    vm.prank(whitelistedPoolManager);
    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableDeposit.selector, 1e5, 0, keeperFee)
    );

    skip(600); // 10 minutes

    vm.startPrank(whitelistedPoolManager);

    IDelayedOrder(orderExecutionModule).cancelExistingOrder(address(whitelistedPool));
    IOrderAnnouncementModule.Order memory order = IOrderAnnouncementModule(orderAnnouncementModule).getAnnouncedOrder(
      address(whitelistedPool)
    );
    assertEq(uint256(order.orderType), 0, "Order should be cancelled");
  }

  function test_should_be_able_to_announce_stable_deposit() public {
    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableDeposit.selector, 1e5, 0, keeperFee)
    );

    IOrderAnnouncementModule.Order memory order = IOrderAnnouncementModule(orderAnnouncementModule).getAnnouncedOrder(
      address(whitelistedPool)
    );
    assertEq(uint256(order.orderType), 1, "Order should be stable deposit");
  }

  function test_revert_if_announcing_stable_deposit_when_UNIT_is_disabled() public {
    vm.startPrank(whitelistedPoolManager);
    address[] memory removedAssets = new address[](1);
    removedAssets[0] = stableModule;
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);

    vm.expectRevert("unsupported destination asset");
    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableDeposit.selector, 1e5, 0, keeperFee)
    );
  }

  function test_should_be_able_to_announce_stable_withdraw() public {
    uint256 amountOfUnitDeposited = _mintUNITIntoVault();

    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(
        IOrderAnnouncementModule.announceStableWithdraw.selector,
        amountOfUnitDeposited,
        0,
        keeperFee
      )
    );

    IOrderAnnouncementModule.Order memory order = IOrderAnnouncementModule(orderAnnouncementModule).getAnnouncedOrder(
      address(whitelistedPool)
    );
    assertEq(uint256(order.orderType), 2, "Order should be stable withdraw");
  }

  function test_revert_if_announcing_stable_withdraw_when_collateral_asset_is_disabled() public {
    uint256 amountOfUnitDeposited = _mintUNITIntoVault();

    vm.startPrank(whitelistedPoolManager);
    deal(collateralAsset, address(whitelistedPool), 0);
    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);

    vm.expectRevert("unsupported destination asset");
    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(
        IOrderAnnouncementModule.announceStableWithdraw.selector,
        amountOfUnitDeposited,
        0,
        keeperFee
      )
    );
  }

  function test_revert_if_removing_UNIT_after_stable_deposit_order_announced() public {
    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableDeposit.selector, 1e5, 0, keeperFee)
    );

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = stableModule;

    vm.expectRevert("order in progress");
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);
  }

  function test_revert_on_deposits_if_stable_deposit_order_announced() public {
    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableDeposit.selector, 1e5, 0, keeperFee)
    );

    vm.expectRevert("order in progress");
    whitelistedPool.deposit(collateralAsset, 1e5);
  }

  function test_revert_on_deposits_if_stable_withdraw_order_announced() public {
    uint256 amountOfUnitDeposited = _mintUNITIntoVault();

    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(
        IOrderAnnouncementModule.announceStableWithdraw.selector,
        amountOfUnitDeposited,
        0,
        keeperFee
      )
    );

    vm.expectRevert("order in progress");
    whitelistedPool.deposit(collateralAsset, 1e5);
  }

  function test_revert_on_withdrawals_if_stable_deposit_order_announced() public {
    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableDeposit.selector, 1e5, 0, keeperFee)
    );

    skip(1 days);

    vm.expectRevert("order in progress");
    whitelistedPool.withdraw(1e18);
  }

  function test_revert_on_withdrawals_if_stable_withdraw_order_announced() public {
    uint256 amountOfUnitDeposited = _mintUNITIntoVault();

    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(
        IOrderAnnouncementModule.announceStableWithdraw.selector,
        amountOfUnitDeposited,
        0,
        keeperFee
      )
    );

    skip(1 days);

    vm.expectRevert("order in progress");
    whitelistedPool.withdraw(1e18);
  }

  function test_revert_when_announce_stable_deposit_on_non_whitelisted() public {
    PoolLogic newPool = _createTestPool(poolFactoryProxy);

    vm.startPrank(manager);
    vm.expectRevert("not whitelisted");
    newPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableDeposit.selector, 1e5, 0, keeperFee)
    );
  }

  function test_revert_when_announce_stable_withdraw_on_non_whitelisted() public {
    PoolLogic newPool = _createTestPool(poolFactoryProxy);

    vm.prank(manager);
    vm.expectRevert("not whitelisted");
    newPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceStableWithdraw.selector, 1e16, 0, keeperFee)
    );
  }

  function test_revert_when_adding_UNIT_on_non_whitelisted() public {
    PoolLogic newPool = _createTestPool(poolFactoryProxy);

    PoolManagerLogic newPoolManagerLogic = PoolManagerLogic(newPool.poolManagerLogic());
    IHasSupportedAsset.Asset[] memory newAssets = new IHasSupportedAsset.Asset[](1);
    newAssets[0] = IHasSupportedAsset.Asset({asset: stableModule, isDeposit: true});

    vm.prank(manager);
    vm.expectRevert("not whitelisted");
    newPoolManagerLogic.changeAssets(newAssets, new address[](0));
  }

  function test_correctly_account_for_UNIT_in_the_vault() public {
    uint256 totalFundValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    uint256 amountOfUnitDeposited = _mintUNITIntoVault();

    uint256 unitValue = whitelistedPoolManagerLogic.assetValue(stableModule, amountOfUnitDeposited);
    uint256 totalFundValueAfter = whitelistedPoolManagerLogic.totalFundValue();

    assertEq(totalFundValueAfter, totalFundValueBefore + unitValue, "UNIT should be accounted in total fund value");
  }

  function test_correctly_withdraws_from_vault_holding_UNIT() public {
    vm.prank(owner);
    poolFactoryProxy.setExitCooldown(1 seconds);

    vm.startPrank(investor);

    // This makes investor shares in the vault equal to existing shares of whitelistedPoolManager
    deal(collateralAsset, investor, 1e8);
    IERC20Extended(collateralAsset).approve(address(whitelistedPool), 1e8);
    whitelistedPool.deposit(collateralAsset, 1e8);

    uint256 amountOfUnitInVault = _mintUNITIntoVault();

    uint256 totalFundValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    uint256 amountOfVaultTokensToWithdraw = whitelistedPool.balanceOf(investor);
    uint256 balanceOfUnitBefore = IERC20Extended(stableModule).balanceOf(investor);
    assertEq(balanceOfUnitBefore, 0, "UNIT should not be held by investor");

    skip(1 seconds);

    whitelistedPool.withdraw(amountOfVaultTokensToWithdraw);
    uint256 totalFundValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    uint256 balanceOfUnitAfter = IERC20Extended(stableModule).balanceOf(investor);
    uint256 balanceOfUnitInVault = IERC20Extended(stableModule).balanceOf(address(whitelistedPool));

    assertEq(balanceOfUnitAfter, amountOfUnitInVault / 2, "investor UNIT amount after withdraw incorrect");
    assertEq(balanceOfUnitInVault, amountOfUnitInVault / 2, "vault UNIT amount incorrect");
    assertApproxEqRel(totalFundValueAfter, totalFundValueBefore / 2, 0.00000001e18, "UNIT withdrawn incorrectly");
  }

  function test_revert_if_removing_collateral_asset_after_stable_withdraw_order_announced() public {
    uint256 amountOfUnitDeposited = _mintUNITIntoVault();

    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(
        IOrderAnnouncementModule.announceStableWithdraw.selector,
        amountOfUnitDeposited,
        0,
        keeperFee
      )
    );

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;
    deal(collateralAsset, address(whitelistedPool), 0);

    vm.expectRevert("order in progress");
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);
  }

  function _createTestPool(PoolFactory _poolFactory) internal returns (PoolLogic) {
    IHasSupportedAsset.Asset[] memory assets = new IHasSupportedAsset.Asset[](1);
    assets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});

    return PoolLogic(_poolFactory.createFund(false, manager, "Test Pool", "TP", "manager name", 0, 0, 0, 0, assets));
  }

  function _mintUNITIntoVault() internal returns (uint256 amountOfUnitDeposited) {
    amountOfUnitDeposited = 10e18;
    deal(stableModule, address(whitelistedPool), amountOfUnitDeposited);
  }

  /// @notice Tests the FlatMoneyV2UNITOutsideWithdrawalAssetGuard which withdraws collateral instead of UNIT
  /// @dev This test switches from the regular FlatMoneyV2UNITAssetGuard to the OutsideWithdrawal variant,
  ///      verifies accounting stays correct, and tests that withdrawals receive collateral while UNIT stays in vault.
  function test_outsideWithdrawal_withdraws_collateral_instead_of_UNIT() public {
    vm.prank(owner);
    poolFactoryProxy.setExitCooldown(1 seconds);

    // Mint UNIT into vault and record state before switching guards
    uint256 amountOfUnitInVault = _mintUNITIntoVault();
    uint256 totalFundValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    uint256 tokenPriceBefore = whitelistedPool.tokenPrice();

    // Switch to FlatMoneyV2UNITOutsideWithdrawalAssetGuard with USDPriceAggregator
    _switchToOutsideWithdrawalGuard();

    // Verify accounting stays the same after switching guards
    assertApproxEqRel(
      whitelistedPoolManagerLogic.totalFundValue(),
      totalFundValueBefore,
      2, // Delta of 2 = 0.0000000000000002% tolerance for rounding differences between price aggregators
      "fund value should stay same after guard switch"
    );
    assertApproxEqRel(
      whitelistedPool.tokenPrice(),
      tokenPriceBefore,
      2, // Delta of 2 = 0.0000000000000002% tolerance for rounding differences between price aggregators
      "token price should stay same after guard switch"
    );

    // Some address makes a deposit which technically adds liquidity to provide backing for UNIT withdrawals
    vm.startPrank(dao);
    deal(collateralAsset, dao, 5e8);
    IERC20Extended(collateralAsset).approve(address(whitelistedPool), 5e8);
    whitelistedPool.deposit(collateralAsset, 5e8);
    vm.stopPrank();

    // Investor deposits to get their share
    vm.startPrank(investor);
    deal(collateralAsset, investor, 1e8);
    IERC20Extended(collateralAsset).approve(address(whitelistedPool), 1e8);
    whitelistedPool.deposit(collateralAsset, 1e8);
    assertEq(
      IERC20Extended(collateralAsset).balanceOf(investor),
      0,
      "investor has zero collateral balance before withdraw"
    );

    uint256 totalFundValueBeforeWithdraw = whitelistedPoolManagerLogic.totalFundValue();
    uint256 amountOfVaultTokensToWithdraw = whitelistedPool.balanceOf(investor);
    uint256 tokenPrice = whitelistedPool.tokenPrice();
    uint256 expectedWithdrawValue = (tokenPrice * amountOfVaultTokensToWithdraw) / 1e18;

    skip(1 seconds);

    whitelistedPool.withdrawSafe(
      amountOfVaultTokensToWithdraw,
      _getEmptyPoolComplexAssetsData(address(whitelistedPool))
    );

    // With OutsidePositionWithdrawalHelper, UNIT stays in vault and investor receives collateral
    assertEq(
      IERC20Extended(stableModule).balanceOf(address(whitelistedPool)),
      amountOfUnitInVault,
      "UNIT should remain unchanged in vault"
    );
    assertEq(IERC20Extended(stableModule).balanceOf(investor), 0, "investor should not receive UNIT");
    assertGt(IERC20Extended(collateralAsset).balanceOf(investor), 0, "investor should receive collateral");
    assertApproxEqRel(
      whitelistedPoolManagerLogic.totalFundValue(),
      totalFundValueBeforeWithdraw - expectedWithdrawValue,
      1e10, // 0.000001% tolerance for rounding
      "fund value should decrease by investor share"
    );
  }

  /// @notice Tests that FlatMoneyV2UNITOutsideWithdrawalAssetGuard rejects UNIT as deposit asset
  function test_outsideWithdrawalGuard_revert_if_adding_UNIT_with_isDeposit_true() public {
    _switchToOutsideWithdrawalGuard();

    // First remove UNIT so we can try to add it again
    vm.startPrank(whitelistedPoolManager);
    address[] memory removedAssets = new address[](1);
    removedAssets[0] = stableModule;
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);

    // Now try to add UNIT with isDeposit: true - should revert
    IHasSupportedAsset.Asset[] memory newAssets = new IHasSupportedAsset.Asset[](1);
    newAssets[0] = IHasSupportedAsset.Asset({asset: stableModule, isDeposit: true});

    vm.expectRevert("deposit not supported");
    whitelistedPoolManagerLogic.changeAssets(newAssets, new address[](0));
    vm.stopPrank();
  }

  /// @notice Tests that FlatMoneyV2UNITOutsideWithdrawalAssetGuard accepts UNIT with isDeposit: false
  function test_outsideWithdrawalGuard_allows_adding_UNIT_with_isDeposit_false() public {
    _switchToOutsideWithdrawalGuard();

    // First remove UNIT so we can try to add it again
    vm.startPrank(whitelistedPoolManager);
    address[] memory removedAssets = new address[](1);
    removedAssets[0] = stableModule;
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);

    // Now add UNIT with isDeposit: false - should succeed
    IHasSupportedAsset.Asset[] memory newAssets = new IHasSupportedAsset.Asset[](1);
    newAssets[0] = IHasSupportedAsset.Asset({asset: stableModule, isDeposit: false});
    whitelistedPoolManagerLogic.changeAssets(newAssets, new address[](0));
    vm.stopPrank();

    // Verify UNIT was added successfully
    assertTrue(whitelistedPoolManagerLogic.isSupportedAsset(stableModule), "UNIT should be supported");
  }

  function _switchToOutsideWithdrawalGuard() internal {
    vm.startPrank(owner);
    Governance governance = Governance(poolFactoryProxy.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(poolFactoryProxy.getAssetHandler());

    // Deploy new guard and set it
    FlatMoneyV2UNITOutsideWithdrawalAssetGuard newUnitAssetGuard = new FlatMoneyV2UNITOutsideWithdrawalAssetGuard(
      collateralAsset
    );
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_V2_UNIT), address(newUnitAssetGuard));

    // Update price aggregator to USDPriceAggregator since getBalance now returns USD value
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: stableModule,
      assetType: uint16(AssetTypeIncomplete.FLAT_MONEY_V2_UNIT),
      aggregator: address(usdPriceAggregator)
    });
    assetHandler.addAssets(assets);
    vm.stopPrank();
  }
}
