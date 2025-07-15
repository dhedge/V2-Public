// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {FlatMoneyOptionsMarketAssetGuard} from "contracts/guards/assetGuards/flatMoney/v2/FlatMoneyOptionsMarketAssetGuard.sol";
import {FlatMoneyCollateralAssetGuard} from "contracts/guards/assetGuards/flatMoney/FlatMoneyCollateralAssetGuard.sol";
import {FlatMoneyOptionsOrderAnnouncementGuard} from "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyOptionsOrderAnnouncementGuard.sol";
import {FlatMoneyOptionsOrderExecutionGuard} from "contracts/guards/contractGuards/flatMoney/v2/FlatMoneyOptionsOrderExecutionGuard.sol";
import {FlatMoneyV2OptionsConfig} from "contracts/guards/contractGuards/flatMoney/shared/FlatMoneyV2OptionsConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IFlatcoinVaultV2} from "contracts/interfaces/flatMoney/v2/IFlatcoinVaultV2.sol";
import {ILeverageModuleV2} from "contracts/interfaces/flatMoney/v2/ILeverageModuleV2.sol";
import {IOracleModuleV2} from "contracts/interfaces/flatMoney/v2/IOracleModuleV2.sol";
import {IOrderAnnouncementModule} from "contracts/interfaces/flatMoney/v2/IOrderAnnouncementModule.sol";
import {IDelayedOrder} from "contracts/interfaces/flatMoney/IDelayedOrder.sol";
import {FlatcoinModuleKeys} from "contracts/utils/flatMoney/libraries/FlatcoinModuleKeys.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";

// TODO: Adjust token amounts used in tests once required to reuse, currently set for WBTC (8 decimals)
abstract contract FlatMoneyOptionsTestSetup is BackboneSetup, IntegrationDeployer {
  struct MintData {
    uint256 margin;
    uint256 tradeFee;
    uint256 tokenId;
  }

  IFlatcoinVaultV2 internal immutable vault;
  address internal immutable collateralAssetPriceFeed;
  PoolFactory internal immutable poolFactoryProd;
  address internal immutable nftTrackerProd;
  PoolLogic internal immutable whitelistedPool;
  uint256 internal immutable keeperFee;

  address internal orderAnnouncementModule;
  address internal orderExecutionModule;
  address internal leverageModule;
  address internal oracleModule;
  address internal collateralAsset;
  uint8 internal collateralAssetDecimals;
  FlatMoneyOptionsOrderAnnouncementGuard internal flatMoneyOptionsOrderAnnouncementGuard;
  PoolManagerLogic internal whitelistedPoolManagerLogic;
  address internal whitelistedPoolManager;

  constructor(
    address _flatcoinVault,
    address _collateralAssetPriceFeed,
    address _poolFactoryProd,
    address _nftTrackerProd,
    address _whitelistedPool,
    uint256 _keeperFee
  ) {
    vault = IFlatcoinVaultV2(_flatcoinVault);
    collateralAssetPriceFeed = _collateralAssetPriceFeed;
    poolFactoryProd = PoolFactory(_poolFactoryProd);
    nftTrackerProd = _nftTrackerProd;
    whitelistedPool = PoolLogic(_whitelistedPool);
    keeperFee = _keeperFee;
  }

  function deployIntegration(PoolFactory _poolFactory, address _nftTracker, address, address) public override {
    // Get contracts to roll deployments on
    Governance governance = Governance(_poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    // Two contract guards
    flatMoneyOptionsOrderAnnouncementGuard = new FlatMoneyOptionsOrderAnnouncementGuard(
      _nftTracker,
      FlatMoneyV2OptionsConfig.NFT_TYPE,
      FlatMoneyV2OptionsConfig.MAX_POSITIONS,
      new FlatMoneyOptionsOrderAnnouncementGuard.PoolSetting[](0),
      FlatMoneyV2OptionsConfig.MAX_ALLOWED_LEVERAGE
    );
    FlatMoneyOptionsOrderExecutionGuard flatMoneyOptionsOrderExecutionGuard = new FlatMoneyOptionsOrderExecutionGuard(
      _nftTracker,
      vault
    );
    governance.setContractGuard(orderAnnouncementModule, address(flatMoneyOptionsOrderAnnouncementGuard));
    // This is because OrderExecutionModule mints NFTs to the pool
    governance.setContractGuard(orderExecutionModule, address(flatMoneyOptionsOrderExecutionGuard));

    // Two asset guards
    FlatMoneyOptionsMarketAssetGuard optionsMarketAssetGuard = new FlatMoneyOptionsMarketAssetGuard();
    FlatMoneyCollateralAssetGuard collateralAssetGuard = new FlatMoneyCollateralAssetGuard(
      address(orderAnnouncementModule)
    );
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_OPTIONS_MARKET), address(optionsMarketAssetGuard));
    governance.setAssetGuard(uint16(AssetTypeIncomplete.FLAT_MONEY_COLLATERAL), address(collateralAssetGuard));

    // Add collateral asset and "options position" asset to the AssetHandler
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](2);
    assets[0] = IAssetHandler.Asset({
      asset: leverageModule,
      assetType: uint16(AssetTypeIncomplete.FLAT_MONEY_OPTIONS_MARKET),
      aggregator: address(usdPriceAggregator)
    });
    assets[1] = IAssetHandler.Asset({
      asset: collateralAsset,
      assetType: uint16(AssetTypeIncomplete.FLAT_MONEY_COLLATERAL),
      aggregator: collateralAssetPriceFeed
    });
    assetHandler.addAssets(assets);

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

    deployIntegration(poolFactoryProd, nftTrackerProd, address(0), address(0));

    // Store whitelisted pool details
    whitelistedPoolManagerLogic = PoolManagerLogic(whitelistedPool.poolManagerLogic());
    whitelistedPoolManager = whitelistedPoolManagerLogic.manager();

    // Enable necessary assets in whitelisted pool
    vm.startPrank(whitelistedPoolManager);
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: leverageModule, isDeposit: false});
    whitelistedPoolManagerLogic.changeAssets(supportedAssets, new address[](0));

    // Deposit collateral asset into whitelisted pool
    deal(collateralAsset, whitelistedPoolManager, 1e8);
    IERC20(collateralAsset).approve(address(whitelistedPool), 1e8);
    whitelistedPool.deposit(collateralAsset, 1e8);

    // Max approve spending collateral asset from within the whitelisted pool
    whitelistedPool.execTransaction(
      collateralAsset,
      abi.encodeWithSelector(IERC20.approve.selector, orderAnnouncementModule, type(uint256).max)
    );

    vm.stopPrank();

    // Mock ArbGasPriceOracle contract calls
    address arbGasPriceOracle = 0x000000000000000000000000000000000000006C;
    vm.mockCall(
      arbGasPriceOracle,
      abi.encodeWithSignature("getPricesInWei()"),
      abi.encode(178130008000, 1272357200, 211480000000, 10000000, 574000, 10574000) // Values as fetched from the ArbGasInfo contract.
    );
    vm.mockCall(
      arbGasPriceOracle,
      abi.encodeWithSignature("getL1BaseFeeEstimate()"),
      abi.encode(67499283) // Value as fetched from the ArbGasInfo contract.
    );
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

    uint256[] memory tokenIds = flatMoneyOptionsOrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIds.length, 1);

    uint256 totalValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    _burnLeverageNFT(tokenIds[0]);

    // After closing (burning), the position is still in track until a new one is minted
    uint256[] memory tokenIdsAfter = flatMoneyOptionsOrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIdsAfter.length, 1);

    uint256 totalValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.001e18); // 0.1% tolerance
  }

  function test_should_correctly_track_NFT_when_opened_again_after_close() public {
    _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    uint256[] memory tokenIds = flatMoneyOptionsOrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIds.length, 1);

    _burnLeverageNFT(tokenIds[0]);

    uint256 totalValueBefore = whitelistedPoolManagerLogic.totalFundValue();
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    // After opening a new position, the old one is removed from track
    uint256[] memory tokenIdsAfter = flatMoneyOptionsOrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIdsAfter.length, 1);
    assertEq(tokenIdsAfter[0], mintData.tokenId);

    uint256 totalValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.001e18); // 0.1% tolerance
  }

  function test_revert_when_announce_leverage_open_on_non_whitelisted() public {
    PoolLogic newPool = _createTestPool();

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("UnauthorizedReceiver(address)")), address(newPool)));
    newPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceLeverageOpen.selector, 1e5, 2e5, 0, keeperFee)
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

  // NOTE: Flat Money V2 Options Deployment has `leverageMax` set to 5x anyway
  function test_revert_when_announce_leverage_open_with_leverage_too_high() public {
    vm.startPrank(whitelistedPoolManager);

    // Try opening 10.1x leverage position
    vm.expectRevert("leverage too high");
    whitelistedPool.execTransaction(
      orderAnnouncementModule,
      abi.encodeWithSelector(IOrderAnnouncementModule.announceLeverageOpen.selector, 1e5, 9.1e5, 200_000e18, keeperFee)
    );
  }

  // NOTE: Flat Money V2 Options Deployment has `leverageMax` set to 5x anyway
  function test_revert_when_announce_leverage_adjust_with_more_than_max_allowed_leverage() public {
    // Open 3x leverage position
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    // Try adjusting to 10.1x leverage
    vm.expectRevert("leverage too high");
    _announceLeverageAdjust(mintData.tokenId, 0, 7.1e5, 200_000e18);
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

  function test_revert_when_removing_collateral_asset_after_leverage_adjust_order_announced() public {
    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageAdjust(mintData.tokenId, 1e5, 3e5, 200_000e18);

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;

    deal(collateralAsset, address(whitelistedPool), 0);

    vm.startPrank(whitelistedPoolManager);

    vm.expectRevert("order in progress");
    whitelistedPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removedAssets);
  }

  function test_revert_when_removing_collateral_asset_after_leverage_close_order_announced() public {
    deal(collateralAsset, address(whitelistedPool), 0);

    MintData memory mintData = _mintLeverageNFTIntoAddress(address(whitelistedPool), 1e5, 2e5);

    _announceLeverageClose(mintData.tokenId);

    address[] memory removedAssets = new address[](1);
    removedAssets[0] = collateralAsset;

    deal(collateralAsset, address(whitelistedPool), 0);

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
    PoolLogic nonWhitelistedPool = _createTestPool();

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
    uint256[] memory tokenIdsBefore = flatMoneyOptionsOrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
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

    uint256[] memory tokenIdsAfter = flatMoneyOptionsOrderAnnouncementGuard.getOwnedTokenIds(address(whitelistedPool));
    assertEq(tokenIdsAfter.length, 0);

    uint256 totalValueAfter = whitelistedPoolManagerLogic.totalFundValue();
    assertEq(totalValueAfter, totalValueBefore);
  }

  function _createTestPool() internal returns (PoolLogic) {
    IHasSupportedAsset.Asset[] memory assets = new IHasSupportedAsset.Asset[](2);
    assets[0] = IHasSupportedAsset.Asset({asset: collateralAsset, isDeposit: true});
    assets[1] = IHasSupportedAsset.Asset({asset: leverageModule, isDeposit: false});

    return
      PoolLogic(
        poolFactoryProd.createFund(false, whitelistedPoolManager, "Test Pool", "TP", "manager name", 0, 0, assets)
      );
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

    uint256 tokenId = flatMoneyOptionsOrderAnnouncementGuard.getOwnedTokenIds(receiver)[0];

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
}
