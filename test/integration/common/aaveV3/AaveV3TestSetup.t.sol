// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {Governance} from "contracts/Governance.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {AaveLendingPoolGuardV3} from "contracts/guards/contractGuards/AaveLendingPoolGuardV3.sol";
import {AaveLendingPoolGuardV3L2Pool} from "contracts/guards/contractGuards/AaveLendingPoolGuardV3L2Pool.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";
import {DhedgeUniV3V2Router} from "contracts/routers/DhedgeUniV3V2Router.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IV3SwapRouter} from "contracts/interfaces/uniswapV3/IV3SwapRouter.sol";
import {DhedgeSuperSwapper} from "contracts/routers/DhedgeSuperSwapper.sol";
import {IUniswapV2Router} from "contracts/interfaces/uniswapV2/IUniswapV2Router.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IAaveV3Pool} from "contracts/interfaces/aave/v3/IAaveV3Pool.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IPYieldContractFactory} from "contracts/interfaces/pendle/IPYieldContractFactory.sol";
import {PendlePTAssetGuard} from "contracts/guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {RewardAssetGuard} from "contracts/guards/assetGuards/RewardAssetGuard.sol";

abstract contract AaveV3TestSetup is BackboneSetup, IntegrationDeployer {
  address public immutable swapper;
  address public immutable aaveV3Pool;
  address public immutable uniV3Factory;
  address public immutable uniV3Router;
  address[] public uniV2LikeRouters;
  address public immutable token0ToLend;
  address public immutable token1ToLend;
  address public immutable tokenToBorrow;
  uint256 public immutable token0AmountNormalized;
  uint256 public immutable token1AmountNormalized;
  uint256 public immutable tokenToBorrowAmountNormalized;
  address public immutable token0Oracle;
  address public immutable token1Oracle;
  address public immutable tokenToBorrowOracle;
  bool public immutable isL2;
  address public immutable pendleYieldContractFactory;
  address public immutable pendleStaticRouter;
  address public immutable token0ToLendPendleMarket;
  address public immutable token0ToLendUnderlying;
  address public immutable token0ToLendUnderlyingOracle;
  uint8 public immutable useEMode;

  PoolLogic public aaveTestPool;
  PoolManagerLogic public aaveTestPoolManagerLogic;
  AaveLendingPoolAssetGuard public aaveLendingPoolAssetGuard;

  struct AaveV3TestConfig {
    address swapper;
    address aaveV3Pool;
    address uniV3Factory;
    address uniV3Router;
    address[] uniV2LikeRouters;
    address token0ToLend;
    address token1ToLend;
    address tokenToBorrow;
    uint256 token0AmountNormalized;
    uint256 token1AmountNormalized;
    uint256 tokenToBorrowAmountNormalized;
    address token0Oracle;
    address token1Oracle;
    address tokenToBorrowOracle;
    bool isL2;
    address pendleYieldContractFactory;
    address pendleStaticRouter;
    address token0ToLendPendleMarket;
    address token0ToLendUnderlying;
    address token0ToLendUnderlyingOracle;
    uint8 useEMode;
  }

  constructor(AaveV3TestConfig memory config) {
    swapper = config.swapper;
    aaveV3Pool = config.aaveV3Pool;
    uniV3Factory = config.uniV3Factory;
    uniV3Router = config.uniV3Router;
    uniV2LikeRouters = config.uniV2LikeRouters;
    token0ToLend = config.token0ToLend;
    token1ToLend = config.token1ToLend;
    tokenToBorrow = config.tokenToBorrow;
    token0AmountNormalized = config.token0AmountNormalized;
    token1AmountNormalized = config.token1AmountNormalized;
    tokenToBorrowAmountNormalized = config.tokenToBorrowAmountNormalized;
    token0Oracle = config.token0Oracle;
    token1Oracle = config.token1Oracle;
    tokenToBorrowOracle = config.tokenToBorrowOracle;
    isL2 = config.isL2;
    pendleYieldContractFactory = config.pendleYieldContractFactory;
    pendleStaticRouter = config.pendleStaticRouter;
    token0ToLendPendleMarket = config.token0ToLendPendleMarket;
    token0ToLendUnderlying = config.token0ToLendUnderlying;
    token0ToLendUnderlyingOracle = config.token0ToLendUnderlyingOracle;
    useEMode = config.useEMode;
  }

  function deployIntegration(PoolFactory _poolFactory, address, address, address _usdPriceAggregator) public override {
    // Get contracts to roll deployments on
    Governance governance = Governance(_poolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    address aaveLendingPoolGuardV3 = isL2
      ? address(new AaveLendingPoolGuardV3L2Pool())
      : address(new AaveLendingPoolGuardV3());
    governance.setContractGuard(aaveV3Pool, aaveLendingPoolGuardV3);

    DhedgeUniV3V2Router uniV3V2Router = new DhedgeUniV3V2Router(
      IUniswapV3Factory(uniV3Factory),
      IV3SwapRouter(uniV3Router)
    );

    IUniswapV2Router[] memory routersToUse = new IUniswapV2Router[](uniV2LikeRouters.length + 1);
    for (uint256 i = 0; i < uniV2LikeRouters.length; i++) {
      routersToUse[i] = IUniswapV2Router(uniV2LikeRouters[i]);
    }
    routersToUse[uniV2LikeRouters.length] = IUniswapV2Router(address(uniV3V2Router));
    DhedgeSuperSwapper superSwapper = new DhedgeSuperSwapper(routersToUse, new DhedgeSuperSwapper.RouteHint[](0));

    aaveLendingPoolAssetGuard = new AaveLendingPoolAssetGuard(
      aaveV3Pool,
      swapper,
      address(superSwapper),
      pendleYieldContractFactory,
      pendleStaticRouter,
      150, // setting to 1.5% mismatch allowed for the sake of tests, production value should be around 5 (0.05%)
      10_000,
      10_000
    );
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.AAVE_V3), address(aaveLendingPoolAssetGuard));
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), erc20Guard); // Set ERC20Guard once again (needed for dryrun tests)

    uint16 assetType0 = _selectAssetType(token0ToLend);
    uint16 assetType1 = _selectAssetType(token1ToLend);

    assetHandler.addAsset(aaveV3Pool, uint16(BackboneSetup.AssetTypeIncomplete.AAVE_V3), _usdPriceAggregator);
    assetHandler.addAsset(token0ToLend, assetType0, token0Oracle);
    assetHandler.addAsset(token1ToLend, assetType1, token1Oracle);
    assetHandler.addAsset(tokenToBorrow, uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK), tokenToBorrowOracle);

    if (
      assetType0 == uint16(BackboneSetup.AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN) ||
      assetType1 == uint16(BackboneSetup.AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN)
    ) {
      address[] memory knownPendleMarkets = new address[](1);
      knownPendleMarkets[0] = token0ToLendPendleMarket;

      PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(
        EthereumConfig.PENDLE_MARKET_FACTORY,
        knownPendleMarkets
      );

      RewardAssetGuard.RewardAssetSetting[] memory rewardAssetSettings = new RewardAssetGuard.RewardAssetSetting[](1);
      address[] memory linkedAssets = new address[](1);
      linkedAssets[0] = token0ToLend;
      rewardAssetSettings[0].rewardToken = token0ToLendUnderlying;
      rewardAssetSettings[0].linkedAssets = linkedAssets;
      RewardAssetGuard rewardAssetGuard = new RewardAssetGuard(rewardAssetSettings);

      governance.setAssetGuard(uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN), address(pendlePTAssetGuard));
      governance.setAssetGuard(200, address(rewardAssetGuard));
      assetHandler.addAsset(token0ToLendUnderlying, 200, token0ToLendUnderlyingOracle);
    }

    vm.stopPrank();
  }

  function setUp() public virtual override {
    super.setUp();

    deployIntegration(poolFactoryProxy, address(0), address(0), address(usdPriceAggregator));

    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](4);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: aaveV3Pool, isDeposit: false});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: token0ToLend, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: token1ToLend, isDeposit: true});
    supportedAssets[3] = IHasSupportedAsset.Asset({asset: tokenToBorrow, isDeposit: true});

    aaveTestPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Aave V3 Tester",
        _fundName: "Aave V3 Test Pool",
        _fundSymbol: "ATP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );
    aaveTestPoolManagerLogic = PoolManagerLogic(aaveTestPool.poolManagerLogic());

    aaveTestPool.execTransaction(
      token0ToLend,
      abi.encodeWithSelector(IERC20Extended.approve.selector, aaveV3Pool, type(uint256).max)
    );
    aaveTestPool.execTransaction(
      token1ToLend,
      abi.encodeWithSelector(IERC20Extended.approve.selector, aaveV3Pool, type(uint256).max)
    );
    aaveTestPool.execTransaction(
      tokenToBorrow,
      abi.encodeWithSelector(IERC20Extended.approve.selector, aaveV3Pool, type(uint256).max)
    );

    vm.startPrank(investor);

    uint256 token0Amount = token0AmountNormalized * (10 ** IERC20Extended(token0ToLend).decimals());

    deal(token0ToLend, investor, token0Amount);
    IERC20Extended(token0ToLend).approve(address(aaveTestPool), type(uint256).max);
    aaveTestPool.deposit(token0ToLend, token0Amount);

    vm.stopPrank();
  }

  function test_can_set_efficiency_mode() public {
    uint256 eMode = IAaveV3Pool(aaveV3Pool).getUserEMode(address(aaveTestPool));

    assertEq(eMode, 0, "Efficiency mode should be 0 before setting");

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    vm.prank(manager);
    aaveTestPool.execTransaction(aaveV3Pool, abi.encodeWithSelector(IAaveV3Pool.setUserEMode.selector, 1));

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    assertEq(totalValueAfter, totalValueBefore, "Total value should not change after setting efficiency mode");
    assertEq(
      IAaveV3Pool(aaveV3Pool).getUserEMode(address(aaveTestPool)),
      1,
      "Efficiency mode should be set to 1 after setting"
    );
  }

  function test_can_supply_into_aave() public {
    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    _supply();

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    assertEq(
      IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool)),
      0,
      "Test pool should have no token 0 left after supply"
    );
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after supply");
  }

  function test_can_deposit_deprecated_into_aave() public {
    vm.startPrank(manager);

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    uint256 amountToSupply = IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool));
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.deposit.selector, token0ToLend, amountToSupply, address(aaveTestPool), 0)
    );

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    assertEq(
      IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool)),
      0,
      "Test pool should have no token 0 left after deposit"
    );
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after deposit");
  }

  function test_can_supply_multiple_assets_into_aave() public {
    uint256 token1Amount = token1AmountNormalized * (10 ** IERC20Extended(token1ToLend).decimals());
    deal(token1ToLend, address(aaveTestPool), token1Amount);

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    _supply();

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, token1ToLend, token1Amount, address(aaveTestPool), 0)
    );

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after next supply");
  }

  function test_can_withdraw_from_aave() public {
    _supply();

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.withdraw.selector, token0ToLend, type(uint256).max, address(aaveTestPool))
    );

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    address aToken = IAaveV3Pool(aaveV3Pool).getReserveAToken(token0ToLend);
    assertEq(
      IERC20Extended(aToken).balanceOf(address(aaveTestPool)),
      0,
      "Test pool should have no aToken left after withdraw"
    );
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after withdraw");
  }

  function test_can_setUserUseReserveAsCollateral_to_true() public {
    _supply();

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.setUserUseReserveAsCollateral.selector, token0ToLend, true)
    );
  }

  function test_can_setUserUseReserveAsCollateral_to_false() public {
    _supply();

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.setUserUseReserveAsCollateral.selector, token0ToLend, false)
    );
  }

  function test_can_borrow_from_aave() public {
    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();
    uint256 tokenToBorrowBalanceBefore = IERC20Extended(tokenToBorrow).balanceOf(address(aaveTestPool));
    assertEq(tokenToBorrowBalanceBefore, 0, "Test pool should have no token to borrow before borrow");

    uint256 borrowed = _supplyAndBorrow();

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();
    uint256 tokenToBorrowBalanceAfter = IERC20Extended(tokenToBorrow).balanceOf(address(aaveTestPool));

    assertEq(tokenToBorrowBalanceAfter, borrowed, "Test pool should have borrowed token after borrow");
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after borrow");
  }

  function test_can_repay_to_aave() public {
    _supplyAndBorrow();

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repay.selector, tokenToBorrow, type(uint256).max, 2, address(aaveTestPool))
    );

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();
    address variableDebtToken = IAaveV3Pool(aaveV3Pool).getReserveVariableDebtToken(tokenToBorrow);

    assertEq(
      IERC20Extended(variableDebtToken).balanceOf(address(aaveTestPool)),
      0,
      "Test pool should have no variable debt token left after repay"
    );
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after repay");
  }

  function test_can_repayWithATokens_to_aave() public {
    uint256 borrowed = _supplyAndBorrow();

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, tokenToBorrow, borrowed, address(aaveTestPool), 0)
    );

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repayWithATokens.selector, tokenToBorrow, type(uint256).max, 2)
    );

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore,
      0.0001e18,
      "Total value should not change after repay with aTokens"
    );
  }

  // ========== Revert Tests ==========

  /**
   * @notice Test revert when using unsupported asset in supply
   */
  function test_revert_supply_unsupported_asset() public {
    address unsupportedToken = address(0x1); // Arbitrary unsupported token address

    vm.expectRevert("unsupported assets");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, unsupportedToken, 1000, address(aaveTestPool), 0)
    );
  }

  /**
   * @notice Test revert when using deprecated deposit function with unsupported asset
   */
  function test_revert_deposit_unsupported_asset() public {
    address unsupportedToken = address(0x1); // Arbitrary unsupported token address

    vm.expectRevert("unsupported assets");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.deposit.selector, unsupportedToken, 1000, address(aaveTestPool), 0)
    );
  }

  /**
   * @notice Test revert when supplying to a recipient that's not the pool
   */
  function test_revert_supply_invalid_recipient() public {
    address invalidRecipient = address(0xdead);

    vm.expectRevert("recipient is not pool");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, token0ToLend, 1000, invalidRecipient, 0)
    );
  }

  /**
   * @notice Test revert when using deprecated deposit with invalid recipient
   */
  function test_revert_deposit_invalid_recipient() public {
    address invalidRecipient = address(0xdead);

    vm.expectRevert("recipient is not pool");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.deposit.selector, token0ToLend, 1000, invalidRecipient, 0)
    );
  }

  /**
   * @notice Test revert using unsupported asset in withdraw
   */
  function test_revert_withdraw_unsupported_asset() public {
    address unsupportedToken = address(0x1); // Arbitrary unsupported token address

    vm.expectRevert("unsupported assets");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.withdraw.selector, unsupportedToken, 1000, address(aaveTestPool))
    );
  }

  /**
   * @notice Test revert when withdrawing to a recipient that's not the pool
   */
  function test_revert_withdraw_invalid_recipient() public {
    // First supply so we have something to withdraw
    _supply();

    address invalidRecipient = address(0xdead);

    vm.expectRevert("recipient is not pool");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.withdraw.selector, token0ToLend, 1000, invalidRecipient)
    );
  }

  /**
   * @notice Test revert when setting an unsupported asset as collateral
   */
  function test_revert_set_unsupported_asset_as_collateral() public {
    address unsupportedToken = address(0x1); // Arbitrary unsupported token address

    vm.expectRevert("unsupported assets");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.setUserUseReserveAsCollateral.selector, unsupportedToken, true)
    );
  }

  /**
   * @notice Test revert when borrowing an unsupported asset
   */
  function test_revert_borrow_unsupported_asset() public {
    // Supply first to have collateral
    _supply();

    address unsupportedToken = address(0x1); // Arbitrary unsupported token address

    vm.expectRevert("unsupported assets");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.borrow.selector, unsupportedToken, 1000, 2, 0, address(aaveTestPool))
    );
  }

  /**
   * @notice Test revert when borrowing to a recipient that's not the pool
   */
  function test_revert_borrow_invalid_recipient() public {
    // Supply first to have collateral
    _supply();

    address invalidRecipient = address(0xdead);

    vm.expectRevert("recipient is not pool");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.borrow.selector, tokenToBorrow, 1000, 2, 0, invalidRecipient)
    );
  }

  /**
   * @notice Test revert when borrowing a second asset when one is already borrowed
   */
  function test_revert_borrow_multiple_assets() public {
    // First, supply and borrow one token
    _supplyAndBorrow();

    // Try to borrow another asset, which should fail because we already have one borrowed asset
    vm.expectRevert("borrowing asset exists");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.borrow.selector, token1ToLend, 0, 2, 0, address(aaveTestPool))
    );
    vm.stopPrank();
  }

  /**
   * @notice Test revert when repaying an unsupported asset
   */
  function test_revert_repay_unsupported_asset() public {
    address unsupportedToken = address(0x1); // Arbitrary unsupported token address

    vm.expectRevert("unsupported assets");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repay.selector, unsupportedToken, 1000, 2, address(aaveTestPool))
    );
  }

  /**
   * @notice Test revert when repaying on behalf of a recipient that's not the pool
   */
  function test_revert_repay_invalid_recipient() public {
    // First borrow so we have something to repay
    _supplyAndBorrow();

    address invalidRecipient = address(0xdead);

    vm.expectRevert("recipient is not pool");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repay.selector, tokenToBorrow, 1000, 2, invalidRecipient)
    );
  }

  /**
   * @notice Test revert when repaying with aTokens for an unsupported asset
   */
  function test_revert_repayWithATokens_unsupported_asset() public {
    address unsupportedToken = address(0x1); // Arbitrary unsupported token address

    vm.expectRevert("unsupported assets");
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repayWithATokens.selector, unsupportedToken, 1000, 2)
    );
  }

  function test_revert_when_aave_v3_asset_is_not_enabled() public {
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = aaveV3Pool;

    vm.startPrank(manager);
    aaveTestPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    vm.expectRevert("unsupported assets");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, token0ToLend, 0, address(aaveTestPool), 0)
    );

    vm.expectRevert("unsupported assets");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.deposit.selector, token0ToLend, 0, address(aaveTestPool), 0)
    );

    vm.expectRevert("unsupported assets");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.withdraw.selector, token0ToLend, 0, address(aaveTestPool))
    );

    vm.expectRevert("unsupported assets");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.setUserUseReserveAsCollateral.selector, token0ToLend, true)
    );

    vm.expectRevert("unsupported assets");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.borrow.selector, tokenToBorrow, 0, 2, 0, address(aaveTestPool))
    );

    vm.expectRevert("unsupported assets");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repay.selector, tokenToBorrow, 0, 2, address(aaveTestPool))
    );

    vm.expectRevert("unsupported assets");
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repayWithATokens.selector, tokenToBorrow, 0, 2)
    );
  }

  function test_revert_when_removing_token_supplied_in_aave() public {
    _supply();

    uint256 balanceAfterSupply = IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool));

    // Assert that the pool has no balance of token0ToLend after supply
    assertEq(balanceAfterSupply, 0, "Test pool should have no token 0 left after supply");

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = token0ToLend;

    vm.expectRevert("withdraw Aave collateral first");
    vm.prank(manager);
    aaveTestPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);
  }

  function test_revert_when_removing_token_borrowed_in_aave() public {
    uint256 amountToBorrow = _supplyAndBorrow();

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = tokenToBorrow;

    // Borrowed token has non zero balance in the pool, so it cannot be removed
    vm.startPrank(manager);
    vm.expectRevert("cannot remove non-empty asset");
    aaveTestPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);

    // Suuply everything what's been borrowed to make borrowed token balance zero
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, tokenToBorrow, amountToBorrow, address(aaveTestPool), 0)
    );

    // Still can not remove borrowed token, as it is accounted towards Aave debt
    vm.expectRevert("repay Aave debt first");
    aaveTestPoolManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), assetsToRemove);
  }

  function test_can_withdraw_from_pool_with_aave_v3_asset_enabled_but_empty() public {
    skip(1 days);

    // 50% of the pool
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    uint256 token0ToLendBalanceBefore = IERC20Extended(token0ToLend).balanceOf(investor);
    assertEq(token0ToLendBalanceBefore, 0, "Investor should have no token 0 before withdraw");

    uint256 token0ToLendPoolBalanceBefore = IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool));

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    vm.startPrank(investor);
    aaveTestPool.withdrawSafe(amountToWithdraw, _getEmptyPoolComplexAssetsData(address(aaveTestPool)));

    uint256 token0ToLendBalanceAfter = IERC20Extended(token0ToLend).balanceOf(investor);
    uint256 token0ToLendPoolBalanceAfter = IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool));
    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.0001e18,
      "Total value should become twice less after withdraw"
    );
    assertEq(
      token0ToLendBalanceAfter,
      token0ToLendPoolBalanceBefore / 2,
      "Investor should have half of token 0 after withdraw"
    );
    assertEq(
      token0ToLendPoolBalanceAfter,
      token0ToLendPoolBalanceBefore / 2,
      "Test pool should have half of token 0 after withdraw"
    );
  }

  function test_can_withdraw_from_pool_with_asset_supplied_into_aave_v3() public {
    skip(1 days);

    // 50% of the pool
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    uint256 token0ToLendBalanceBefore = IERC20Extended(token0ToLend).balanceOf(investor);
    assertEq(token0ToLendBalanceBefore, 0, "Investor should have no token 0 before withdraw");

    uint256 token0ToLendPoolBalanceBefore = IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool));

    _supply();

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    vm.startPrank(investor);
    aaveTestPool.withdrawSafe(amountToWithdraw, _getEmptyPoolComplexAssetsData(address(aaveTestPool)));

    uint256 token0ToLendBalanceAfter = IERC20Extended(token0ToLend).balanceOf(investor);
    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();

    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.0001e18,
      "Total value should become twice less after withdraw"
    );
    assertEq(
      token0ToLendBalanceAfter,
      token0ToLendPoolBalanceBefore / 2,
      "Investor should have half of token 0 after withdraw"
    );
  }

  function test_can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_no_swapdata() public {
    // Skip the test if token to lend is PT token: onchain legacy way of withdrawing doesn't support PT tokens
    bool shouldSkip = _selectAssetType(token0ToLend) ==
      uint16(BackboneSetup.AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN);

    vm.skip(shouldSkip);

    skip(1 days);

    // 50% of the pool
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    uint256 valueToWithdraw = (aaveTestPool.tokenPrice() * amountToWithdraw) / 1e18;

    uint256 token0ToLendBalanceBefore = IERC20Extended(token0ToLend).balanceOf(investor);
    uint256 tokenToBorrowBalanceBefore = IERC20Extended(tokenToBorrow).balanceOf(investor);

    assertEq(tokenToBorrowBalanceBefore, 0, "Investor should have no token to borrow before withdraw");

    _supplyAndBorrow();

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(aaveTestPool));
    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].slippageTolerance = 50; // 0.5%
    }

    vm.prank(investor);
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();
    uint256 token0ToLendBalanceAfter = IERC20Extended(token0ToLend).balanceOf(investor);
    uint256 tokenToBorrowBalanceAfter = IERC20Extended(tokenToBorrow).balanceOf(investor);
    uint256 valueWithdrawn = aaveTestPoolManagerLogic.assetValue(tokenToBorrow, tokenToBorrowBalanceAfter);

    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.0001e18,
      "Total value should become twice less after withdraw"
    );
    assertEq(
      token0ToLendBalanceBefore,
      token0ToLendBalanceAfter,
      "Investor balance of token 0 to lend should not change after withdraw"
    );

    assertGt(tokenToBorrowBalanceAfter, 0, "Investor should receive token to borrow after withdraw");
    assertApproxEqRel(
      valueWithdrawn,
      valueToWithdraw,
      0.002e18, // 0.2%
      "Value withdrawn should be approximately equal to the value of the withdrawn pool share"
    );
  }

  // ========== Offchain swap data revert tests ==========

  function test_revert_withdraw_with_swap_data_length_mismatch() public {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);

    // Create source data with incorrect length (always shorter than required)
    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](
      swapDataParams.srcData.length > 0 ? swapDataParams.srcData.length - 1 : 0
    );
    withdrawData.srcData = abi.encode(srcData);

    // Create complex assets data for withdrawal
    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Should revert with "swap data length mismatch" because srcData length does not match expected length
    vm.prank(investor);
    vm.expectRevert("swap data length mismatch");
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  function test_revert_withdraw_with_src_token_mismatch() public {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);

    // Create source data with incorrect token address
    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);

    for (uint256 i = 0; i < srcData.length; i++) {
      if (i == 0) {
        // Use tokenToBorrow as the source token for the first entry (which should be different from actual source)
        srcData[i].token = IERC20(tokenToBorrow);
      } else {
        srcData[i].token = IERC20(swapDataParams.srcData[i].asset);
      }
      srcData[i].amount = swapDataParams.srcData[i].amount;
    }

    withdrawData.srcData = abi.encode(srcData);

    // Create complex assets data for withdrawal
    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Should revert with "src asset mismatch" because source token is incorrect
    vm.prank(investor);
    vm.expectRevert("src asset mismatch");
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  function test_revert_withdraw_with_src_amount_too_high() public {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);

    // Create source data with amount higher than expected
    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);

    for (uint256 i = 0; i < srcData.length; i++) {
      srcData[i].token = IERC20(swapDataParams.srcData[i].asset);

      if (i == 0) {
        // Set amount higher than expected
        srcData[i].amount = swapDataParams.srcData[i].amount * 2;
      } else {
        srcData[i].amount = swapDataParams.srcData[i].amount;
      }
    }

    withdrawData.srcData = abi.encode(srcData);

    // Create complex assets data for withdrawal
    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Should revert with "amount too high" because source amount is too high
    vm.prank(investor);
    vm.expectRevert("amount too high");
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  function test_revert_withdraw_with_src_amount_mismatch() public {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);

    // Create source data with amount too low (beyond allowed mismatch delta)
    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);

    for (uint256 i = 0; i < srcData.length; i++) {
      srcData[i].token = IERC20(swapDataParams.srcData[i].asset);

      if (i == 0 && swapDataParams.srcData[i].amount > 0) {
        // Set amount to be much lower than expected (beyond the mismatch tolerance)
        // The mismatch tolerance is set to 150 (1.5%) in the constructor for tests
        srcData[i].amount = swapDataParams.srcData[i].amount / 10; // Reducing by 90% should exceed the tolerance
      } else {
        srcData[i].amount = swapDataParams.srcData[i].amount;
      }
    }

    withdrawData.srcData = abi.encode(srcData);

    // Create complex assets data for withdrawal
    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Should revert with "src amount mismatch" because source amount is too low
    vm.prank(investor);
    vm.expectRevert("src amount mismatch");
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  function test_revert_withdraw_with_dst_token_mismatch() public {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    // Set incorrect destination token
    withdrawData.destData.destToken = IERC20(token0ToLend); // Use token0ToLend instead of the correct destination token
    withdrawData.destData.minDestAmount = swapDataParams.dstData.amount;

    // Set correct source tokens
    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);

    for (uint256 i = 0; i < srcData.length; i++) {
      srcData[i].token = IERC20(swapDataParams.srcData[i].asset);
      srcData[i].amount = swapDataParams.srcData[i].amount;
    }

    withdrawData.srcData = abi.encode(srcData);

    // Create complex assets data for withdrawal
    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Should revert with "dst asset mismatch" because destination token is incorrect
    vm.prank(investor);
    vm.expectRevert("dst asset mismatch");
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  function test_revert_withdraw_with_dst_amount_mismatch() public {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);

    // Set incorrect destination amount (beyond allowed mismatch delta)
    // The mismatch tolerance is set to 150 (1.5%) in the constructor for tests
    withdrawData.destData.minDestAmount = swapDataParams.dstData.amount * 2; // Double the expected amount

    // Set correct source tokens
    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);

    for (uint256 i = 0; i < srcData.length; i++) {
      srcData[i].token = IERC20(swapDataParams.srcData[i].asset);
      srcData[i].amount = swapDataParams.srcData[i].amount;
    }

    withdrawData.srcData = abi.encode(srcData);

    // Create complex assets data for withdrawal
    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Should revert with "dst amount mismatch" because destination amount is out of allowed range
    vm.prank(investor);
    vm.expectRevert("dst amount mismatch");
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  // ========== Helper Functions ==========

  function _supply() internal {
    uint256 amountToSupply = IERC20Extended(token0ToLend).balanceOf(address(aaveTestPool));
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, token0ToLend, amountToSupply, address(aaveTestPool), 0)
    );
  }

  function _supplyAndBorrow() internal returns (uint256 amountToBorrow) {
    _supply();

    // Enable eMode if configured in test setup
    if (useEMode != 0) {
      vm.prank(manager);
      aaveTestPool.execTransaction(aaveV3Pool, abi.encodeWithSelector(IAaveV3Pool.setUserEMode.selector, useEMode));
    }

    amountToBorrow = tokenToBorrowAmountNormalized * (10 ** IERC20Extended(tokenToBorrow).decimals());

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.borrow.selector, tokenToBorrow, amountToBorrow, 2, 0, address(aaveTestPool))
    );
  }

  function _selectAssetType(address _asset) internal view returns (uint16 assetType) {
    if (pendleYieldContractFactory == address(0)) return uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK);

    assetType = IPYieldContractFactory(pendleYieldContractFactory).isPT(_asset)
      ? uint16(BackboneSetup.AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN)
      : uint16(BackboneSetup.AssetTypeIncomplete.CHAINLINK);
  }
}
