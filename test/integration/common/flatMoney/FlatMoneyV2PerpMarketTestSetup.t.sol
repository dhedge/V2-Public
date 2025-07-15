// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {FlatMoneyV2PerpMarketAssetGuard} from "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyV2PerpMarketAssetGuard.sol";
import {FlatMoneyV2UNITAssetGuard} from "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyV2UNITAssetGuard.sol";
import {FlatMoneyCollateralAssetGuard} from "contracts/guards/assetGuards/flatMoney/FlatMoneyCollateralAssetGuard.sol";
import {FlatMoneyV2OrderAnnouncementGuard} from "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyV2OrderAnnouncementGuard.sol";
import {FlatMoneyBasisContractGuard} from "contracts/guards/contractGuards/flatMoney/shared/FlatMoneyBasisContractGuard.sol";
import {FlatMoneyV2OrderExecutionGuard} from "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyV2OrderExecutionGuard.sol";
import {FlatMoneyUNITPriceAggregator} from "contracts/priceAggregators/FlatMoneyUNITPriceAggregator.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IFlatcoinVaultV2} from "contracts/interfaces/flatMoney/v2/IFlatcoinVaultV2.sol";
import {ILeverageModuleV2} from "contracts/interfaces/flatMoney/v2/ILeverageModuleV2.sol";
import {IOracleModuleV2} from "contracts/interfaces/flatMoney/v2/IOracleModuleV2.sol";
import {IOrderAnnouncementModule} from "contracts/interfaces/flatMoney/v2/IOrderAnnouncementModule.sol";
import {IDelayedOrder} from "contracts/interfaces/flatMoney/IDelayedOrder.sol";
import {IViewer} from "contracts/interfaces/flatMoney/IViewer.sol";
import {FlatcoinModuleKeys} from "contracts/utils/flatMoney/libraries/FlatcoinModuleKeys.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";

// TODO: Adjust token amounts used in tests once required to reuse, currently set for WBTC (8 decimals)
abstract contract FlatMoneyV2PerpMarketTestSetup is BackboneSetup, IntegrationDeployer {
  struct MintData {
    uint256 margin;
    uint256 tradeFee;
    uint256 tokenId;
  }

  IFlatcoinVaultV2 internal immutable vault;
  address internal immutable viewer;
  address internal immutable collateralAssetPriceFeed;
  uint256 internal immutable keeperFee;

  address internal orderAnnouncementModule;
  address internal orderExecutionModule;
  address internal leverageModule;
  address internal oracleModule;
  address internal stableModule;
  address internal collateralAsset;
  uint8 internal collateralAssetDecimals;
  FlatMoneyV2OrderAnnouncementGuard internal flatMoneyV2OrderAnnouncementGuard;
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

    // Add collateral asset, "perp position" asset and UNIT to the AssetHandler
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](3);
    assets[0] = IAssetHandler.Asset({
      asset: collateralAsset,
      assetType: uint16(AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      aggregator: collateralAssetPriceFeed
    });
    assets[1] = IAssetHandler.Asset({
      asset: leverageModule,
      assetType: uint16(AssetTypeIncomplete.FLAT_MONEY_V2_PERP_MARKET),
      aggregator: address(usdPriceAggregator)
    });
    assets[2] = IAssetHandler.Asset({
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
    FlatMoneyV2OrderAnnouncementGuard.PoolSetting[]
      memory whitelistedPoolSettings = new FlatMoneyV2OrderAnnouncementGuard.PoolSetting[](1);
    whitelistedPoolSettings[0] = FlatMoneyBasisContractGuard.PoolSetting({
      poolLogic: address(whitelistedPool),
      withdrawalAsset: collateralAsset
    });
    flatMoneyV2OrderAnnouncementGuard = new FlatMoneyV2OrderAnnouncementGuard(_nftTracker, whitelistedPoolSettings);
    FlatMoneyV2OrderExecutionGuard flatMoneyV2OrderExecutionGuard = new FlatMoneyV2OrderExecutionGuard(
      _nftTracker,
      whitelistedPoolSettings
    );
    governance.setContractGuard(orderAnnouncementModule, address(flatMoneyV2OrderAnnouncementGuard));
    // This is because OrderExecutionModule mints NFTs to the pool
    governance.setContractGuard(orderExecutionModule, address(flatMoneyV2OrderExecutionGuard));

    // Three asset guards
    FlatMoneyV2PerpMarketAssetGuard perpMarketAssetGuard = new FlatMoneyV2PerpMarketAssetGuard();
    FlatMoneyV2UNITAssetGuard unitAssetGuard = new FlatMoneyV2UNITAssetGuard();
    FlatMoneyCollateralAssetGuard collateralAssetGuard = new FlatMoneyCollateralAssetGuard(
      address(orderAnnouncementModule)
    );
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_V2_PERP_MARKET), address(perpMarketAssetGuard));
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_V2_UNIT), address(unitAssetGuard));
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_COLLATERAL), address(collateralAssetGuard));

    vm.startPrank(whitelistedPoolManager);
    IHasSupportedAsset.Asset[] memory newAssets = new IHasSupportedAsset.Asset[](3);
    newAssets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});
    newAssets[1] = IHasSupportedAsset.Asset({asset: leverageModule, isDeposit: false});
    newAssets[2] = IHasSupportedAsset.Asset({asset: stableModule, isDeposit: true});
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
    leverageModule = vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY);
    oracleModule = vault.moduleAddress(FlatcoinModuleKeys._ORACLE_MODULE_KEY);
    stableModule = vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY);

    deployIntegration(poolFactoryProxy, address(nftTrackerStorageProxy), address(0), address(0));

    // Deposit collateral asset into whitelisted pool
    vm.startPrank(whitelistedPoolManager);

    deal(collateralAsset, whitelistedPoolManager, 1e8);
    IERC20(collateralAsset).approve(address(whitelistedPool), 1e8);
    whitelistedPool.deposit(collateralAsset, 1e8);

    // Max approve spending collateral asset from within the whitelisted pool
    whitelistedPool.execTransaction(
      collateralAsset,
      abi.encodeWithSelector(IERC20.approve.selector, orderAnnouncementModule, type(uint256).max)
    );

    vm.stopPrank();
  }

  function test_should_be_able_to_announce_leverage_open() public {
    _announceLeverageOpen();

    IOrderAnnouncementModule.Order memory order = IOrderAnnouncementModule(orderAnnouncementModule).getAnnouncedOrder(
      address(whitelistedPool)
    );
    assertEq(uint256(order.orderType), 3, "Order should be leverage open");
  }

  function test_should_be_able_to_announce_leverage_adjust() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageAdjust(mintData.tokenId, 1e5, 3e5, 200_000e18);

    IOrderAnnouncementModule.Order memory order = IOrderAnnouncementModule(orderAnnouncementModule).getAnnouncedOrder(
      address(whitelistedPool)
    );
    assertEq(uint256(order.orderType), 5, "Order should be leverage adjust");
  }

  function test_should_be_able_to_announce_leverage_close() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageClose(mintData.tokenId);

    IOrderAnnouncementModule.Order memory order = IOrderAnnouncementModule(orderAnnouncementModule).getAnnouncedOrder(
      address(whitelistedPool)
    );
    assertEq(uint256(order.orderType), 4, "Order should be leverage close");
  }

  function test_should_be_able_to_cancel_pending_order() public {
    _announceLeverageOpen();

    skip(600); // 10 minutes

    vm.startPrank(whitelistedPoolManager);

    IDelayedOrder(orderExecutionModule).cancelExistingOrder(address(whitelistedPool));
    IOrderAnnouncementModule.Order memory order = IOrderAnnouncementModule(orderAnnouncementModule).getAnnouncedOrder(
      address(whitelistedPool)
    );
    assertEq(uint256(order.orderType), 0, "Order should be cancelled");
  }

  function test_should_correctly_account_for_leverage_NFT() public {
    uint256 totalValueBefore = whitelistedPoolManagerLogic.totalFundValue();

    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    (uint256 priceD18, ) = IOracleModuleV2(oracleModule).getPrice(collateralAsset);
    uint256 positionValueD18 = ((mintData.margin - mintData.tradeFee) * priceD18) / (10 ** collateralAssetDecimals);

    uint256 totalValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    assertApproxEqRel(totalValueAfter, totalValueBefore + positionValueD18, 0.001e18); // 0.1% tolerance
  }

  function test_should_correctly_track_NFT_after_close() public {
    _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    uint256[] memory tokenIds = flatMoneyV2OrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIds.length, 1);

    uint256 totalValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    _burnLeverageNFT(tokenIds[0]);

    // After closing (burning), the position is still in track until a new one is minted
    uint256[] memory tokenIdsAfter = flatMoneyV2OrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIdsAfter.length, 1);

    uint256 totalValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0011e18); // 0.11% tolerance
  }

  function test_should_correctly_track_NFT_when_opened_again_after_close() public {
    _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    uint256[] memory tokenIds = flatMoneyV2OrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIds.length, 1);

    _burnLeverageNFT(tokenIds[0]);

    uint256 totalValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    // After opening a new position, the old one is removed from track
    uint256[] memory tokenIdsAfter = flatMoneyV2OrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIdsAfter.length, 1);
    assertEq(tokenIdsAfter[0], mintData.tokenId);

    uint256 totalValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0011e18); // 0.11% tolerance
  }

  function test_revert_when_announce_leverage_open_on_non_whitelisted() public {
    PoolLogic newPool = _createTestPool(poolFactoryProxy);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("not whitelisted");
    newPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceLeverageOpen.selector, 1e5, 2e5, 0, keeperFee)
    );
  }

  function test_revert_when_announce_leverage_adjust_on_non_whitelisted() public {
    PoolLogic newPool = _createTestPool(poolFactoryProxy);
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("not whitelisted");
    newPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(
        IOrderAnnouncementModule.announceLeverageAdjust.selector,
        mintData.tokenId,
        1e5,
        3e5,
        200_000e18,
        keeperFee
      )
    );
  }

  function test_revert_when_announce_leverage_close_on_non_whitelisted() public {
    PoolLogic newPool = _createTestPool(poolFactoryProxy);
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("not whitelisted");
    newPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceLeverageClose.selector, mintData.tokenId, 0, keeperFee)
    );
  }

  function test_revert_when_announce_leverage_open_with_position_asset_disabled() public {
    address[] memory removedAssets = new address[](1);
    removedAssets[0] = leverageModule;

    vm.startPrank(whitelistedPoolManager);
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);

    vm.expectRevert("unsupported destination asset");
    _announceLeverageOpen();
  }

  function test_revert_when_announce_leverage_adjust_with_collateral_asset_disabled() public {
    deal(collateralAsset, address(whitelistedPool), 0);

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;

    IHasSupportedAsset.Asset[] memory addedAssets = new IHasSupportedAsset.Asset[](2);
    addedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    addedAssets[1] = IHasSupportedAsset.Asset({asset: leverageModule, isDeposit: false});

    vm.startPrank(whitelistedPoolManager);
    whitelistedPoolManagerLogic.changeAssets(addedAssets, removedAssets);

    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.expectRevert("unsupported destination asset");
    _announceLeverageAdjust(mintData.tokenId, 1e5, 3e5, 200_000e18);
  }

  function test_revert_when_announce_leverage_adjust_with_position_asset_disabled() public {
    deal(collateralAsset, address(whitelistedPool), 0);

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = leverageModule;

    IHasSupportedAsset.Asset[] memory addedAssets = new IHasSupportedAsset.Asset[](1);
    addedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.startPrank(whitelistedPoolManager);
    whitelistedPoolManagerLogic.changeAssets(addedAssets, removedAssets);

    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.expectRevert("unsupported destination asset");
    _announceLeverageAdjust(mintData.tokenId, 1e5, 3e5, 200_000e18);
  }

  function test_revert_when_announce_leverage_close_with_collateral_asset_disabled() public {
    deal(collateralAsset, address(whitelistedPool), 0);

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;

    IHasSupportedAsset.Asset[] memory addedAssets = new IHasSupportedAsset.Asset[](1);
    addedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.startPrank(whitelistedPoolManager);
    whitelistedPoolManagerLogic.changeAssets(addedAssets, removedAssets);

    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.expectRevert("unsupported destination asset");
    _announceLeverageClose(mintData.tokenId);
  }

  function test_revert_when_announce_leverage_open_with_leverage_too_high() public {
    vm.startPrank(whitelistedPoolManager);

    // Try opening 7.1x leverage position
    vm.expectRevert("leverage too high");
    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceLeverageOpen.selector, 1e5, 6.1e5, 200_000e18, keeperFee)
    );
  }

  function test_revert_when_announce_leverage_adjust_with_more_than_max_allowed_leverage() public {
    // Open 3x leverage position
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    // Try adjusting to 7.1x leverage
    vm.expectRevert("leverage too high");
    _announceLeverageAdjust(mintData.tokenId, 0, 4.1e5, 200_000e18);
  }

  function test_revert_when_announce_leverage_adjust_on_not_owned_position() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.expectRevert("position is not in track");
    _announceLeverageAdjust(mintData.tokenId + 1, 1e5, 3e5, 200_000e18);
  }

  function test_revert_when_announce_leverage_close_on_not_owned_position() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.expectRevert("position is not in track");
    _announceLeverageClose(mintData.tokenId + 1);
  }

  function test_revert_when_max_positions_reached() public {
    _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    vm.expectRevert("max position reached");
    _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);
  }

  function test_revert_when_removing_position_asset_after_leverage_open_order_announced() public {
    _announceLeverageOpen();

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = leverageModule;

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("order in progress");
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);
  }

  function test_revert_on_deposits_withdrawals_if_leverage_open_order_announced() public {
    _announceLeverageOpen();

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("order in progress");
    whitelistedPool.deposit(collateralAsset, 1e8);

    skip(1 days);

    vm.expectRevert("order in progress");
    whitelistedPool.withdraw(1e18);
  }

  function test_revert_on_deposits_withdrawals_if_leverage_adjust_order_announced() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageAdjust(mintData.tokenId, 1e5, 3e5, 200_000e18);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("order in progress");
    whitelistedPool.deposit(collateralAsset, 1e8);

    skip(1 days);

    vm.expectRevert("order in progress");
    whitelistedPool.withdraw(1e18);
  }

  function test_revert_on_deposits_withdrawals_if_leverage_close_order_announced() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageClose(mintData.tokenId);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("order in progress");
    whitelistedPool.deposit(collateralAsset, 1e8);

    skip(1 days);

    vm.expectRevert("order in progress");
    whitelistedPool.withdraw(1e18);
  }

  function test_revert_when_trying_to_send_leverage_NFT_via_safeTransfer() public {
    vm.startPrank(orderExecutionModule);

    ILeverageModuleV2(leverageModule).executeOpen(
      whitelistedPoolManager,
      IOrderAnnouncementModule.Order({
        executableAtTime: uint64(block.timestamp - 12 hours),
        keeperFee: keeperFee,
        orderType: IOrderAnnouncementModule.OrderType.LeverageOpen,
        orderData: abi.encode(
          ILeverageModuleV2.AnnouncedLeverageOpen({
            margin: 1e5,
            additionalSize: 2e5,
            maxFillPrice: type(uint256).max,
            stopLossPrice: 0,
            profitTakePrice: type(uint256).max,
            tradeFee: 1e2,
            announcedBy: orderAnnouncementModule
          })
        )
      })
    );

    vm.stopPrank();

    uint256 tokenId = IERC721Enumerable(leverageModule).tokenOfOwnerByIndex(whitelistedPoolManager, 0);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("only guarded address");
    IERC721Enumerable(leverageModule).safeTransferFrom(whitelistedPoolManager, address(whitelistedPool), tokenId);
  }

  function test_revert_when_non_whitelisted_pool_receives_nft() public {
    PoolLogic nonWhitelistedPool = _createTestPool(poolFactoryProxy);

    vm.startPrank(orderExecutionModule);

    vm.expectRevert("not whitelisted");
    ILeverageModuleV2(leverageModule).executeOpen(
      address(nonWhitelistedPool),
      IOrderAnnouncementModule.Order({
        executableAtTime: uint64(block.timestamp - 12 hours),
        keeperFee: keeperFee,
        orderType: IOrderAnnouncementModule.OrderType.LeverageOpen,
        orderData: abi.encode(
          ILeverageModuleV2.AnnouncedLeverageOpen({
            margin: 1e5,
            additionalSize: 2e5,
            maxFillPrice: type(uint256).max,
            stopLossPrice: 0,
            profitTakePrice: type(uint256).max,
            tradeFee: 1e2,
            announcedBy: orderAnnouncementModule
          })
        )
      })
    );
  }

  function test_should_not_account_for_leverage_NFT_received_using_transfer() public {
    uint256[] memory tokenIdsBefore = flatMoneyV2OrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIdsBefore.length, 0);

    uint256 totalValueBefore = whitelistedPoolManagerLogic.totalFundValue();

    vm.startPrank(orderExecutionModule);

    ILeverageModuleV2(leverageModule).executeOpen(
      whitelistedPoolManager,
      IOrderAnnouncementModule.Order({
        executableAtTime: uint64(block.timestamp - 12 hours),
        keeperFee: keeperFee,
        orderType: IOrderAnnouncementModule.OrderType.LeverageOpen,
        orderData: abi.encode(
          ILeverageModuleV2.AnnouncedLeverageOpen({
            margin: 1e5,
            additionalSize: 2e5,
            maxFillPrice: type(uint256).max,
            stopLossPrice: 0,
            profitTakePrice: type(uint256).max,
            tradeFee: 1e2,
            announcedBy: orderAnnouncementModule
          })
        )
      })
    );

    vm.stopPrank();

    uint256 tokenId = IERC721Enumerable(leverageModule).tokenOfOwnerByIndex(whitelistedPoolManager, 0);
    vm.startPrank(whitelistedPoolManager);
    IERC721Enumerable(leverageModule).transferFrom(whitelistedPoolManager, address(whitelistedPool), tokenId);

    uint256[] memory tokenIdsAfter = flatMoneyV2OrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIdsAfter.length, 0);

    uint256 totalValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    assertEq(totalValueAfter, totalValueBefore);
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
    IERC20(collateralAsset).approve(address(whitelistedPool), 1e8);
    whitelistedPool.deposit(collateralAsset, 1e8);

    uint256 amountOfUnitInVault = _mintUNITIntoVault();

    uint256 totalFundValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    uint256 amountOfVaultTokensToWithdraw = whitelistedPool.balanceOf(investor);
    uint256 balanceOfUnitBefore = IERC20(stableModule).balanceOf(investor);
    assertEq(balanceOfUnitBefore, 0, "UNIT should not be held by investor");

    skip(1 seconds);

    whitelistedPool.withdraw(amountOfVaultTokensToWithdraw);
    uint256 totalFundValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    uint256 balanceOfUnitAfter = IERC20(stableModule).balanceOf(investor);
    uint256 balanceOfUnitInVault = IERC20(stableModule).balanceOf(address(whitelistedPool));

    assertEq(balanceOfUnitAfter, amountOfUnitInVault / 2, "investor UNIT amount after withdraw incorrect");
    assertEq(balanceOfUnitInVault, amountOfUnitInVault / 2, "vault UNIT amount incorrect");
    assertEq(totalFundValueAfter, totalFundValueBefore / 2, "UNIT withdrawn incorrectly");
  }

  function test_revert_if_removing_collateral_asset_after_leverage_adjust_order_announced() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageAdjust(mintData.tokenId, 1e5, 3e5, 200_000e18);

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;
    deal(collateralAsset, address(whitelistedPool), 0);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("order in progress");
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);
  }

  function test_revert_if_removing_collateral_asset_after_leverage_close_order_announced() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageClose(mintData.tokenId);

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;
    deal(collateralAsset, address(whitelistedPool), 0);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("order in progress");
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);
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
    IHasSupportedAsset.Asset[] memory assets = new IHasSupportedAsset.Asset[](2);
    assets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});
    assets[1] = IHasSupportedAsset.Asset({asset: leverageModule, isDeposit: false});

    return PoolLogic(_poolFactory.createFund(false, manager, "Test Pool", "TP", "manager name", 0, 0, assets));
  }

  function _announceLeverageOpen() internal {
    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceLeverageOpen.selector, 1e5, 2e5, 200_000e18, keeperFee)
    );

    vm.stopPrank();
  }

  function _announceLeverageAdjust(
    uint256 tokenId,
    uint256 marginAdjust,
    uint256 sizeAdjust,
    uint256 fillPrice
  ) internal {
    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(
        IOrderAnnouncementModule.announceLeverageAdjust.selector,
        tokenId,
        marginAdjust,
        sizeAdjust,
        fillPrice,
        keeperFee
      )
    );

    vm.stopPrank();
  }

  function _announceLeverageClose(uint256 tokenId) internal {
    vm.startPrank(whitelistedPoolManager);

    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceLeverageClose.selector, tokenId, 0, keeperFee)
    );

    vm.stopPrank();
  }

  function _mintLeverageNFTIntoAddress(
    address receiver,
    uint256 margin,
    uint256 additionalSize
  ) internal returns (MintData memory) {
    vm.startPrank(orderExecutionModule);

    uint256 executableAtTime = block.timestamp - 12 hours; // Accept 12 hours maxAge for testing purposes
    uint256 maxFillPrice = type(uint256).max;
    uint256 tradeFee = 1e2;

    ILeverageModuleV2(leverageModule).executeOpen(
      receiver,
      IOrderAnnouncementModule.Order({
        executableAtTime: uint64(executableAtTime),
        keeperFee: keeperFee,
        orderType: IOrderAnnouncementModule.OrderType.LeverageOpen,
        orderData: abi.encode(
          ILeverageModuleV2.AnnouncedLeverageOpen({
            margin: margin,
            additionalSize: additionalSize,
            maxFillPrice: maxFillPrice,
            stopLossPrice: 0,
            profitTakePrice: type(uint256).max,
            tradeFee: tradeFee,
            announcedBy: orderAnnouncementModule
          })
        )
      })
    );

    vm.stopPrank();

    uint256 tokenId = flatMoneyV2OrderAnnouncementGuard.getOwnedTokenIds(receiver)[0];

    return MintData({margin: margin, tradeFee: tradeFee, tokenId: tokenId});
  }

  function _burnLeverageNFT(uint256 tokenId) internal {
    vm.startPrank(orderExecutionModule);

    uint256 executableAtTime = block.timestamp - 12 hours;
    uint256 minFillPrice = 0;
    uint256 tradeFee = 1e2;

    ILeverageModuleV2(leverageModule).executeClose(
      IOrderAnnouncementModule.Order({
        executableAtTime: uint64(executableAtTime),
        keeperFee: keeperFee,
        orderType: IOrderAnnouncementModule.OrderType.LeverageClose,
        orderData: abi.encode(
          ILeverageModuleV2.AnnouncedLeverageClose({tokenId: tokenId, minFillPrice: minFillPrice, tradeFee: tradeFee})
        )
      })
    );

    vm.stopPrank();
  }

  function _mintUNITIntoVault() internal returns (uint256 amountOfUnitDeposited) {
    amountOfUnitDeposited = 10e18;
    deal(stableModule, address(whitelistedPool), amountOfUnitDeposited);
  }
}
