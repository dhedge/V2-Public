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
import {AssetTypes} from "test/integration/utils/foundry/AssetTypes.sol";
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
import {RewardAssetGuard} from "contracts/guards/assetGuards/RewardAssetGuard.sol";
import {AaveWithdrawTrickContract} from "contracts/test/AaveWithdrawTrickContract.sol";

abstract contract AaveV3TestSetup is BackboneSetup, IntegrationDeployer {
  /// @dev The swapper's registry key for the 1inch aggregation router, whitelisted on every live
  /// chain. Used by the code-injection tests, which need a router the swapper will dispatch to.
  bytes32 private constant ONE_INCH_ROUTER_KEY = bytes32("ONE_INCH");

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
  address public immutable token1ToLendPendleMarket;
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
    address token1ToLendPendleMarket;
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
    token1ToLendPendleMarket = config.token1ToLendPendleMarket;
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
      150 // setting to 1.5% mismatch allowed for the sake of tests, production value should be around 5 (0.05%)
    );
    governance.setAssetGuard(uint16(AssetTypes.AssetTypeIncomplete.AAVE_V3), address(aaveLendingPoolAssetGuard));
    governance.setAssetGuard(uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK), erc20Guard); // Set ERC20Guard once again (needed for dryrun tests)

    uint16 assetType0 = _selectAssetType(token0ToLend);
    uint16 assetType1 = _selectAssetType(token1ToLend);

    assetHandler.addAsset(aaveV3Pool, uint16(AssetTypes.AssetTypeIncomplete.AAVE_V3), _usdPriceAggregator);
    assetHandler.addAsset(token0ToLend, assetType0, token0Oracle);
    assetHandler.addAsset(token1ToLend, assetType1, token1Oracle);
    assetHandler.addAsset(tokenToBorrow, uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK), tokenToBorrowOracle);

    if (token0ToLendPendleMarket != address(0) || token1ToLendPendleMarket != address(0)) {
      // Count non-zero markets
      uint256 marketCount = 0;
      if (token0ToLendPendleMarket != address(0)) marketCount++;
      if (token1ToLendPendleMarket != address(0)) marketCount++;

      // Fill array with non-zero markets
      address[] memory knownPendleMarkets = new address[](marketCount);
      uint256 index = 0;
      if (token0ToLendPendleMarket != address(0)) {
        knownPendleMarkets[index++] = token0ToLendPendleMarket;
      }
      if (token1ToLendPendleMarket != address(0)) {
        knownPendleMarkets[index++] = token1ToLendPendleMarket;
      }

      PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(knownPendleMarkets);

      RewardAssetGuard.RewardAssetSetting[] memory rewardAssetSettings = new RewardAssetGuard.RewardAssetSetting[](1);
      address[] memory linkedAssets = new address[](1);
      linkedAssets[0] = token0ToLend;
      rewardAssetSettings[0].rewardToken = token0ToLendUnderlying;
      rewardAssetSettings[0].linkedAssets = linkedAssets;
      RewardAssetGuard rewardAssetGuard = new RewardAssetGuard(rewardAssetSettings);

      governance.setAssetGuard(uint16(AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN), address(pendlePTAssetGuard));
      governance.setAssetGuard(200, address(rewardAssetGuard));
      // PT underlying == borrow asset: it is already registered above as CHAINLINK, so skip the duplicate addAsset.
      // - the unrolled underlying is valued/withdrawn as that first-class debt asset (reward linkage not needed).
      if (token0ToLendUnderlying != tokenToBorrow) {
        assetHandler.addAsset(token0ToLendUnderlying, 200, token0ToLendUnderlyingOracle);
      }
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
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
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
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after supply"); // 0.01%
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
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after deposit"); // 0.01%
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

    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after next supply"); // 0.01%
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
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after withdraw"); // 0.01%
  }

  function test_can_setUserUseReserveAsCollateral_to_true() public {
    _supply();

    // Turn it off first so switching it back on is what the assertion observes.
    _setReserveAsCollateral(false);
    assertEq(_totalCollateralBase(), 0, "supplied asset should not count as collateral once disabled");

    _setReserveAsCollateral(true);
    assertGt(_totalCollateralBase(), 0, "enabling the reserve should make it count as collateral");
  }

  function test_can_setUserUseReserveAsCollateral_to_false() public {
    _supply();
    assertGt(_totalCollateralBase(), 0, "a supplied asset counts as collateral by default");

    _setReserveAsCollateral(false);
    assertEq(_totalCollateralBase(), 0, "disabling the reserve should drop it from collateral");
  }

  function test_can_borrow_from_aave() public {
    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();
    uint256 tokenToBorrowBalanceBefore = IERC20Extended(tokenToBorrow).balanceOf(address(aaveTestPool));
    assertEq(tokenToBorrowBalanceBefore, 0, "Test pool should have no token to borrow before borrow");

    uint256 borrowed = _supplyAndBorrow();

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();
    uint256 tokenToBorrowBalanceAfter = IERC20Extended(tokenToBorrow).balanceOf(address(aaveTestPool));

    assertEq(tokenToBorrowBalanceAfter, borrowed, "Test pool should have borrowed token after borrow");
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after borrow"); // 0.01%
  }

  function test_can_repay_to_aave() public {
    _supplyAndBorrow();

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();
    uint256 repayAmount = IERC20Extended(tokenToBorrow).balanceOf(address(aaveTestPool));

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repay.selector, tokenToBorrow, repayAmount, 2, address(aaveTestPool))
    );

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();
    address variableDebtToken = IAaveV3Pool(aaveV3Pool).getReserveVariableDebtToken(tokenToBorrow);

    assertApproxEqAbs(
      IERC20Extended(variableDebtToken).balanceOf(address(aaveTestPool)),
      0,
      2,
      "Test pool should have no variable debt token left after repay"
    );
    assertApproxEqRel(totalValueAfter, totalValueBefore, 0.0001e18, "Total value should not change after repay"); // 0.01%
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
      0.0001e18, // 0.01%
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

  function test_revert_when_removing_the_aave_pool_asset_while_a_position_is_open() public {
    _supplyAndBorrow();

    // The Aave lending pool asset aggregates all collateral and debt, so its own removal check
    // refuses while the position still holds value.
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = aaveV3Pool;

    vm.prank(manager);
    vm.expectRevert("cannot remove non-empty asset");
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
      0.0001e18, // 0.01%
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
      0.0001e18, // 0.01%
      "Total value should become twice less after withdraw"
    );
    assertApproxEqAbs(
      token0ToLendBalanceAfter,
      token0ToLendPoolBalanceBefore / 2,
      1, // 1 for rounding errors
      "Investor should have half of token 0 after withdraw"
    );
  }

  function test_can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_no_swapdata() public {
    // Skip the test if token to lend is PT token: onchain legacy way of withdrawing doesn't support PT tokens
    // Skip the test if uniV3Factory is not set: only offchain swap data withdrawal is supported in that case
    bool shouldSkip = _selectAssetType(token0ToLend) == uint16(AssetTypes.AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN) ||
      uniV3Factory == address(0);

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
      0.0001e18, // 0.01%
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

  function test_revert_withdraw_with_swap_data_length_mismatch() public virtual {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    vm.prank(address(this), address(0));
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

  function test_revert_withdraw_with_src_token_mismatch() public virtual {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    vm.prank(address(this), address(0));
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

  function test_revert_withdraw_with_src_amount_too_high() public virtual {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    vm.prank(address(this), address(0));
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

  function test_revert_withdraw_with_src_amount_mismatch() public virtual {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    vm.prank(address(this), address(0));
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

    vm.prank(address(this), address(0));
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

  function test_revert_withdraw_with_dst_amount_mismatch() public virtual {
    skip(1 days);

    _supplyAndBorrow();

    // Prepare data for withdrawal
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    vm.prank(address(this), address(0));
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

  // Test for an out-of-bounds read in `AaveLendingPoolAssetGuard._withdrawCollateralTransactions` (offchain
  // swap path). When the debt asset is also supplied as collateral, that collateral is excluded from the swap data, so
  // its index must not advance the src-token cursor. Before the fix, iterating it after the last src asset read past the
  // end of `srcData`, reverting with the `INVALID` (0xFE) opcode.
  function test_withdrawSafe_builds_collateral_txs_when_debt_asset_collateral_is_after_last_src_asset() public virtual {
    skip(1 days);

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    _supplyAndBorrow();

    uint256 debtAssetBalance = IERC20Extended(tokenToBorrow).balanceOf(address(aaveTestPool));

    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, tokenToBorrow, debtAssetBalance, address(aaveTestPool), 0)
    );

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    vm.prank(address(this), address(0));
    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    // The case under test only exists when there is a src-token cursor for the debt-asset
    // collateral to advance past. A fixture whose collateral needs no swap must override this
    // test and skip it, rather than have it pass without exercising the guard.
    assertGt(swapDataParams.srcData.length, 0, "no swap leg: fixture must override and skip");

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);
    withdrawData.destData.minDestAmount = swapDataParams.dstData.amount;

    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);

    for (uint256 i = 0; i < srcData.length; i++) {
      srcData[i].token = IERC20(swapDataParams.srcData[i].asset);
      srcData[i].amount = swapDataParams.srcData[i].amount;
    }

    withdrawData.srcData = abi.encode(srcData);

    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Execution now reaches the swap step and reverts with `InvalidAggregator(bytes32)` (0x76c68c3b) because the
    // placeholder swap data carries no aggregator.
    vm.prank(investor);
    vm.expectRevert(abi.encodeWithSelector(bytes4(0x76c68c3b), bytes32(0)));
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  // ========== Bad debt: the position must freeze, not price itself at zero ==========

  /// @dev Drives the position underwater by inflating the reported variable debt. Any real move that
  ///      leaves debt value above collateral value (a liquidation cascade leaving bad debt) does the
  ///      same. Scaling the reported balance rather than the oracle keeps this independent of each
  ///      chain's assets, decimals and collateral-to-debt ratio.
  function _forcePositionUnderwater() internal {
    address variableDebtToken = IAaveV3Pool(aaveV3Pool).getReserveVariableDebtToken(tokenToBorrow);
    uint256 realDebt = IERC20Extended(variableDebtToken).balanceOf(address(aaveTestPool));

    vm.mockCall(
      variableDebtToken,
      abi.encodeWithSelector(IERC20Extended.balanceOf.selector, address(aaveTestPool)),
      abi.encode(realDebt * 1_000)
    );
  }

  function test_revert_getBalance_when_position_is_underwater() public {
    _supplyAndBorrow();

    assertGt(aaveLendingPoolAssetGuard.getBalance(address(aaveTestPool), aaveV3Pool), 0, "healthy position prices");

    _forcePositionUnderwater();

    // Reporting 0 here would overstate totalFundValue by the whole shortfall and let deposits keep
    // minting against it, so the position must refuse to price itself instead.
    vm.expectRevert(bytes("aave position underwater"));
    aaveLendingPoolAssetGuard.getBalance(address(aaveTestPool), aaveV3Pool);

    vm.expectRevert(bytes("aave position underwater"));
    aaveTestPoolManagerLogic.totalFundValue();
  }

  function test_revert_deposit_when_position_is_underwater() public {
    _supplyAndBorrow();
    _forcePositionUnderwater();

    // token0ToLend is a deposit asset on every chain config and is the asset ::setUp already deals.
    uint256 depositAmount = token0AmountNormalized * (10 ** IERC20Extended(token0ToLend).decimals());
    deal(token0ToLend, investor, depositAmount);

    vm.startPrank(investor);
    IERC20Extended(token0ToLend).approve(address(aaveTestPool), depositAmount);
    vm.expectRevert(bytes("aave position underwater"));
    aaveTestPool.deposit(token0ToLend, depositAmount);
    vm.stopPrank();
  }

  /// @dev The freeze must leave a way out: pricing is blocked but trading is not, so the manager can
  ///      repay debt to bring the position back above water.
  function test_manager_can_repay_to_recover_from_underwater_position() public {
    uint256 amountBorrowed = _supplyAndBorrow();
    _forcePositionUnderwater();

    vm.expectRevert(bytes("aave position underwater"));
    aaveTestPoolManagerLogic.totalFundValue();

    // Pricing is frozen but trading is not: the repay still goes through.
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.repay.selector, tokenToBorrow, amountBorrowed, 2, address(aaveTestPool))
    );

    vm.clearMockedCalls();
    assertGt(aaveTestPoolManagerLogic.totalFundValue(), 0, "vault prices again once the debt is repaid");
  }

  // ========== Degenerate portion ==========

  /// @dev A withdrawal small enough that the debt share scales to zero must take the no-debt branch.
  ///      Entering the flashloan path there borrows nothing and has Aave reject repay(0).
  function test_dust_withdrawal_does_not_enter_the_flashloan_path() public {
    _supplyAndBorrow();
    skip(1 days);

    uint256 supplyBefore = IERC20Extended(address(aaveTestPool)).totalSupply();

    vm.prank(investor);
    aaveTestPool.withdraw(1); // portion rounds to 0

    assertEq(
      IERC20Extended(address(aaveTestPool)).totalSupply(),
      supplyBefore - 1,
      "dust withdrawal is a clean no-op, not a revert inside Aave"
    );
  }

  // ========== The single-borrow-asset limit ==========

  /// @dev `_borrow` enforces at most one variable debt asset, which `_calculateBorrowAsset` depends
  ///      on. `flashLoan` with interest rate mode 2 is the other way to open variable debt: it does
  ///      not repay, it opens a position for `onBehalfOf`, and it never passes through `_borrow`.
  ///      The limit is only complete because the guard has no branch for it and PoolLogic rejects
  ///      unhandled types, so pin that here rather than in `_borrow`'s own tests.
  function test_revert_flashLoan_cannot_open_a_second_debt_position() public {
    _supplyAndBorrow();

    address[] memory assets = new address[](1);
    assets[0] = token1ToLend;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 10 ** IERC20Extended(token1ToLend).decimals();
    uint256[] memory modes = new uint256[](1);
    modes[0] = 2; // do not repay - open variable debt instead

    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSignature(
        "flashLoan(address,address[],uint256[],uint256[],address,bytes,uint16)",
        address(aaveTestPool),
        assets,
        amounts,
        modes,
        address(aaveTestPool),
        bytes(""),
        uint16(0)
      )
    );
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

  function _setReserveAsCollateral(bool _use) internal {
    vm.prank(manager);
    aaveTestPool.execTransaction(
      aaveV3Pool,
      abi.encodeWithSelector(IAaveV3Pool.setUserUseReserveAsCollateral.selector, token0ToLend, _use)
    );
  }

  function _totalCollateralBase() internal view returns (uint256 totalCollateralBase) {
    (totalCollateralBase, , , , , ) = IAaveV3Pool(aaveV3Pool).getUserAccountData(address(aaveTestPool));
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
    if (pendleYieldContractFactory == address(0)) return uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK);

    assetType = IPYieldContractFactory(pendleYieldContractFactory).isPT(_asset)
      ? uint16(AssetTypes.AssetTypeIncomplete.PENDLE_PRINCIPAL_TOKEN)
      : uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK);
  }

  // ========== Offchain swap data code injection tests ==========

  /// @notice `withdrawSafe` hands control to an offchain-supplied aggregator during the swap. A
  /// withdrawer who points that calldata back at themselves gets to run code while the vault is
  /// mid-withdrawal, with its accounting in flight. Both ways of abusing that must be rejected.
  /// @dev The attacker rewrites the aggregator calldata so the swapper calls back into
  /// `AaveWithdrawTrickContract.execute`, which repays the swapper and then re-enters the vault.
  function test_revert_withdrawSafe_code_injection_cannot_inflate_tvl_and_mint_fees() public virtual {
    _runWithdrawSafeInjectionAttack(AaveWithdrawTrickContract.AttackType.InflateSend);
  }

  function test_revert_withdrawSafe_code_injection_cannot_reenter_deposit() public virtual {
    // Only reachable if the manager has (unintentionally) made the debt asset depositable.
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: tokenToBorrow, isDeposit: true});

    vm.prank(manager);
    aaveTestPoolManagerLogic.changeAssets(assetsToAdd, new address[](0));

    _runWithdrawSafeInjectionAttack(AaveWithdrawTrickContract.AttackType.InflateDeposit);
  }

  /// @dev Searches the revert data for the vault's reason, which the swapper nests inside its own
  /// error rather than re-throwing.
  function _isReentrantCallRevert(bytes memory _err) internal pure returns (bool) {
    bytes memory needle = bytes("ReentrancyGuard: reentrant call");
    if (_err.length < needle.length) return false;

    for (uint256 i; i <= _err.length - needle.length; ++i) {
      bool matches = true;
      for (uint256 j; j < needle.length; ++j) {
        if (_err[i + j] != needle[j]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }

    return false;
  }

  function _runWithdrawSafeInjectionAttack(AaveWithdrawTrickContract.AttackType _attackType) internal {
    skip(1 days);

    _supplyAndBorrow();

    AaveWithdrawTrickContract attacker = new AaveWithdrawTrickContract();

    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;

    // Start from the swap data an honest withdrawal would use.
    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    vm.prank(address(this), address(0));
    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    // The attack only exists when there is an aggregator call to point back at the attacker. A
    // fixture whose collateral underlying is already the debt asset needs no swap, so it must
    // override these tests and skip them rather than have them pass without attacking anything.
    assertGt(swapDataParams.srcData.length, 0, "no swap leg: fixture must override and skip");

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);
    withdrawData.destData.minDestAmount = swapDataParams.dstData.amount;

    // Point the injected swap at a router the swapper actually dispatches to. With the key left
    // unset the whitelist lookup fails first and the attacker's callback never runs, which is the
    // difference between testing the vault and testing the aggregator whitelist.
    address whitelistedRouter = ISwapper(swapper).getRouter(ONE_INCH_ROUTER_KEY);
    assertTrue(whitelistedRouter != address(0), "no whitelisted 1inch router: fixture must override and skip");

    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);
    for (uint256 i; i < srcData.length; ++i) {
      srcData[i].token = IERC20(swapDataParams.srcData[i].asset);
      srcData[i].amount = swapDataParams.srcData[i].amount;
      srcData[i].aggregatorData.routerKey = ONE_INCH_ROUTER_KEY;
    }
    withdrawData.srcData = abi.encode(srcData);

    // The attacker rewrites the aggregator calldata to route execution through itself.
    attacker.setSwapData(abi.encode(withdrawData), address(aaveTestPool), swapper);

    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);
    for (uint256 i; i < complexAssetsData.length; ++i) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = attacker.mSwapData();
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    // Fund the attacker so it can repay the swapper and still have plenty left to inflate with.
    deal(address(withdrawData.destData.destToken), address(attacker), swapDataParams.dstData.amount * 1_000);

    vm.prank(investor);
    IERC20Extended(address(aaveTestPool)).transfer(address(attacker), amountToWithdraw);

    // Guard against the attack "failing" for a trivial setup reason rather than being rejected.
    assertGt(IERC20Extended(address(aaveTestPool)).balanceOf(address(attacker)), 0, "attacker holds no shares");
    assertGt(attacker.mSwapData().length, 0, "no injected swap data");

    // The swap now reaches the real router, which hands control to the attacker-nominated
    // executor mid-withdrawal. The callback tops up the vault's balance and then re-enters it -
    // `mintManagerFee` for InflateSend, `deposit` for InflateDeposit - and the vault's reentrancy
    // guard rejects it, taking the whole withdrawal down. The swapper wraps the router's revert,
    // so the vault's reason arrives nested inside the error data.
    bool rejected;
    try attacker.attack(amountToWithdraw, complexAssetsData, _attackType) {
      rejected = false;
    } catch (bytes memory err) {
      rejected = true;
      assertTrue(_isReentrantCallRevert(err), "expected the vault's reentrancy guard to reject the callback");
    }
    assertTrue(rejected, "withdrawSafe code injection was not rejected");
  }
}
