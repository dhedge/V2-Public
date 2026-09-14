// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";
import {AaveLendingPoolGuardV3L2Pool} from "contracts/guards/contractGuards/AaveLendingPoolGuardV3L2Pool.sol";
import {OneInchV6Guard} from "contracts/guards/contractGuards/OneInchV6Guard.sol";
import {KyberSwapRouterV2ContractGuard} from "contracts/guards/contractGuards/kyberSwap/KyberSwapRouterV2ContractGuard.sol";
import {ERC20Guard} from "contracts/guards/assetGuards/ERC20Guard.sol";
import {IAccountedTokenAssetGuard} from "contracts/interfaces/guards/IAccountedTokenAssetGuard.sol";
import {IAaveV3Pool} from "contracts/interfaces/aave/v3/IAaveV3Pool.sol";
import {IAggregationRouterV6, IAggregationExecutor} from "contracts/interfaces/oneInch/IAggregationRouterV6.sol";
import {IMetaAggregationRouterV2} from "contracts/interfaces/kyberSwap/IMetaAggregationRouterV2.sol";
import {IUniswapV2Factory} from "contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

import {MockSwapExecutor} from "test/integration/common/oneInch/MockSwapExecutor.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/// @notice Regression tests: aTokens are valued via the Aave umbrella asset but are unregistered, so a
///         manager could swap them out for dust. The fix refuses a source token an asset guard accounts for
///         (declared via `IAccountedTokenAssetGuard`) plus a net fund-value guard; unaccounted tokens
///         (e.g. rewards) still swap. Run against the real 1inch/KyberSwap routers with production guards.
contract AaveATokenExfiltrationTest is OptimismSetup {
  address public immutable AAVE_V3_POOL = OptimismConfig.AAVE_V3_LENDING_POOL;
  address public immutable WETH = OptimismConfig.WETH;
  address public immutable USDC = OptimismConfig.USDC;

  // Real production router addresses (present on the Optimism fork).
  address public immutable ONE_INCH_ROUTER = EthereumConfig.ONE_INCH_V6_ROUTER;
  address public immutable KYBER_ROUTER = EthereumConfig.KYBER_SWAP_ROUTER_V2;

  uint256 public constant WETH_SUPPLIED = 10e18;
  /// @dev Unused asset type for the mock umbrella integration.
  uint16 public constant MOCK_UMBRELLA_ASSET_TYPE = 9999;

  PoolLogic public vault;
  PoolManagerLogic public vaultManagerLogic;
  OneInchV6Guard public oneInchV6Guard;
  KyberSwapRouterV2ContractGuard public kyberGuard;

  address public aWeth;
  address public thief = makeAddr("thief");

  constructor() OptimismSetup(155959582) {}

  function setUp() public override {
    super.setUp();

    _deployAaveIntegration();
    _deploySwapGuards();
    _createVaultAndSupplyToAave();
  }

  /// @notice The aToken sweep via the real 1inch router is now caught by the net fund-value guard.
  function test_aToken_sweep_via_oneInch_reverts() public {
    uint256 aTokenBefore = _assertAtokenHeldButInvisible();

    MockSwapExecutor executor = new MockSwapExecutor(aWeth, USDC, thief, 1); // returns 1 wei USDC dust
    deal(USDC, address(executor), 1);

    vm.startPrank(manager);
    // The approve still succeeds (ERC20Guard fallback): the fix is on the swap, not the approve.
    vault.execTransaction(aWeth, abi.encodeWithSelector(IERC20.approve.selector, ONE_INCH_ROUTER, aTokenBefore));

    IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
      srcToken: aWeth,
      dstToken: USDC,
      srcReceiver: payable(address(executor)),
      dstReceiver: payable(address(vault)),
      amount: aTokenBefore,
      minReturnAmount: 1,
      flags: 0
    });
    // Refused in txGuard: the Aave guard claims the aToken.
    vm.expectRevert("accounted token source");
    vault.execTransaction(
      ONE_INCH_ROUTER,
      abi.encodeWithSelector(IAggregationRouterV6.swap.selector, address(executor), desc, bytes(""))
    );
    vm.stopPrank();

    // The revert unwound everything: the vault still holds all its aTokens.
    assertEq(IERC20(aWeth).balanceOf(address(vault)), aTokenBefore, "aTokens retained");
    assertEq(IERC20(aWeth).balanceOf(thief), 0, "attacker got nothing");
  }

  /// @notice The aToken sweep via the real KyberSwap router is now caught by the net fund-value guard.
  function test_aToken_sweep_via_kyberswap_reverts() public {
    uint256 aTokenBefore = _assertAtokenHeldButInvisible();

    MockSwapExecutor executor = new MockSwapExecutor(aWeth, USDC, thief, 1);
    deal(USDC, address(executor), 1);

    vm.startPrank(manager);
    vault.execTransaction(aWeth, abi.encodeWithSelector(IERC20.approve.selector, KYBER_ROUTER, aTokenBefore));

    vm.expectRevert("accounted token source");
    vault.execTransaction(KYBER_ROUTER, _buildKyberSwapData(address(executor), aWeth, USDC, aTokenBefore));
    vm.stopPrank();

    assertEq(IERC20(aWeth).balanceOf(address(vault)), aTokenBefore, "aTokens retained");
    assertEq(IERC20(aWeth).balanceOf(thief), 0, "attacker got nothing");
  }

  /// @notice Legitimate flow: selling an unaccounted reward token raises fund value, so it passes.
  function test_legitimate_reward_swap_via_oneInch_succeeds() public {
    RewardToken reward = new RewardToken();
    uint256 rewardAmount = 1_000e18;
    reward.mint(address(vault), rewardAmount);

    assertFalse(vaultManagerLogic.isSupportedAsset(address(reward)), "reward is unsupported/unaccounted");

    uint256 usdcOut = 100e6; // the reward genuinely swaps to $100 of a supported asset
    MockSwapExecutor executor = new MockSwapExecutor(address(reward), USDC, thief, usdcOut);
    deal(USDC, address(executor), usdcOut);

    uint256 fundValueBefore = vaultManagerLogic.totalFundValue();

    vm.startPrank(manager);
    vault.execTransaction(
      address(reward),
      abi.encodeWithSelector(IERC20.approve.selector, ONE_INCH_ROUTER, rewardAmount)
    );

    IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
      srcToken: address(reward),
      dstToken: USDC,
      srcReceiver: payable(address(executor)),
      dstReceiver: payable(address(vault)),
      amount: rewardAmount,
      minReturnAmount: 1,
      flags: 0
    });
    // No revert: value goes up.
    vault.execTransaction(
      ONE_INCH_ROUTER,
      abi.encodeWithSelector(IAggregationRouterV6.swap.selector, address(executor), desc, bytes(""))
    );
    vm.stopPrank();

    assertEq(IERC20(USDC).balanceOf(address(vault)), usdcOut, "vault received the swapped-in USDC");
    assertGt(vaultManagerLogic.totalFundValue(), fundValueBefore, "reward swap bumped fund value");
  }

  /// @notice Extensibility: a new integration is covered by implementing `IAccountedTokenAssetGuard` alone.
  ///         Same reward token as above, but now a guard claims it, so the swap is refused.
  function test_new_integration_can_block_its_own_accounted_token() public {
    RewardToken reward = new RewardToken();
    uint256 rewardAmount = 1_000e18;
    reward.mint(address(vault), rewardAmount);

    // A dummy umbrella asset whose guard accounts for `reward`.
    DummyToken umbrella = new DummyToken();
    MockUmbrellaAssetGuard umbrellaGuard = new MockUmbrellaAssetGuard(address(reward));
    vm.startPrank(owner);
    governance.setAssetGuard(MOCK_UMBRELLA_ASSET_TYPE, address(umbrellaGuard));
    assetHandlerProxy.addAsset(address(umbrella), MOCK_UMBRELLA_ASSET_TYPE, address(usdPriceAggregator));
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory toAdd = new IHasSupportedAsset.Asset[](1);
    toAdd[0] = IHasSupportedAsset.Asset({asset: address(umbrella), isDeposit: false});
    vm.prank(manager);
    vaultManagerLogic.changeAssets(toAdd, new address[](0));

    MockSwapExecutor executor = new MockSwapExecutor(address(reward), USDC, thief, 100e6);
    deal(USDC, address(executor), 100e6);

    vm.startPrank(manager);
    vault.execTransaction(
      address(reward),
      abi.encodeWithSelector(IERC20.approve.selector, ONE_INCH_ROUTER, rewardAmount)
    );

    IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
      srcToken: address(reward),
      dstToken: USDC,
      srcReceiver: payable(address(executor)),
      dstReceiver: payable(address(vault)),
      amount: rewardAmount,
      minReturnAmount: 1,
      flags: 0
    });
    vm.expectRevert("accounted token source");
    vault.execTransaction(
      ONE_INCH_ROUTER,
      abi.encodeWithSelector(IAggregationRouterV6.swap.selector, address(executor), desc, bytes(""))
    );
    vm.stopPrank();
  }

  /// @notice CONTROL: draining a SUPPORTED src for dust is still caught by per-asset slippage accounting.
  function test_supported_token_sweep_is_blocked_by_slippage_accumulator() public {
    deal(WETH, address(vault), 5e18);
    uint256 wethBalance = IERC20(WETH).balanceOf(address(vault));
    assertTrue(vaultManagerLogic.isSupportedAsset(WETH), "WETH is a supported asset");

    MockSwapExecutor executor = new MockSwapExecutor(WETH, USDC, thief, 1);
    deal(USDC, address(executor), 1);

    vm.startPrank(manager);
    vault.execTransaction(WETH, abi.encodeWithSelector(IERC20.approve.selector, ONE_INCH_ROUTER, wethBalance));

    IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
      srcToken: WETH,
      dstToken: USDC,
      srcReceiver: payable(address(executor)),
      dstReceiver: payable(address(vault)),
      amount: wethBalance,
      minReturnAmount: 1,
      flags: 0
    });
    vm.expectRevert("slippage impact exceeded");
    vault.execTransaction(
      ONE_INCH_ROUTER,
      abi.encodeWithSelector(IAggregationRouterV6.swap.selector, address(executor), desc, bytes(""))
    );
    vm.stopPrank();
  }

  /// @notice The net fund-value guard in isolation: reverts past the cap, no-op when value holds or rises.
  ///         Backstop for any accounted source a guard has not declared.
  function test_net_value_guard_reverts_on_drop_and_allows_gain() public {
    address pml = address(vaultManagerLogic);
    vm.startPrank(address(oneInchV6Guard)); // only the router's registered guard may call the accumulator

    // Backbone cap is 10%; a 50% drop is way over.
    vm.expectRevert("slippage impact exceeded");
    slippageAccumulator.updateSlippageImpactByValue(pml, ONE_INCH_ROUTER, 100e18, 50e18);

    // Value preserved or increased -> no-op.
    slippageAccumulator.updateSlippageImpactByValue(pml, ONE_INCH_ROUTER, 100e18, 100e18);
    slippageAccumulator.updateSlippageImpactByValue(pml, ONE_INCH_ROUTER, 100e18, 120e18);

    vm.stopPrank();
  }

  /* ----------------------------------------------------------------------- */
  /*                                 HELPERS                                  */
  /* ----------------------------------------------------------------------- */

  function _assertAtokenHeldButInvisible() internal view returns (uint256 aTokenBefore) {
    aTokenBefore = IERC20(aWeth).balanceOf(address(vault));
    assertGt(aTokenBefore, 0, "vault should hold aTokens");
    // The aToken is invisible to dHEDGE: neither registered nor supported.
    assertFalse(poolFactoryProxy.isValidAsset(aWeth), "aToken must not be a registered asset");
    assertFalse(vaultManagerLogic.isSupportedAsset(aWeth), "aToken must not be a supported asset");
  }

  function _buildKyberSwapData(
    address _executor,
    address _srcToken,
    address _dstToken,
    uint256 _amount
  ) internal view returns (bytes memory) {
    address[] memory srcReceivers = new address[](1);
    srcReceivers[0] = _executor; // router sends the source tokens to our executor
    uint256[] memory srcAmounts = new uint256[](1);
    srcAmounts[0] = _amount;

    IMetaAggregationRouterV2.SwapDescriptionV2 memory desc = IMetaAggregationRouterV2.SwapDescriptionV2({
      srcToken: _srcToken,
      dstToken: _dstToken,
      srcReceivers: srcReceivers,
      srcAmounts: srcAmounts,
      feeReceivers: new address[](0), // guard requires `feeReceivers.length == 0`
      feeAmounts: new uint256[](0),
      dstReceiver: address(vault), // satisfies `dstReceiver == poolLogic`
      amount: _amount,
      minReturnAmount: 1,
      flags: 0,
      permit: bytes("") // guard requires `permit.length == 0`
    });
    IMetaAggregationRouterV2.SwapExecutionParams memory execution = IMetaAggregationRouterV2.SwapExecutionParams({
      callTarget: _executor, // arbitrary executor -- the router calls it via `callBytes`
      approveTarget: _executor,
      targetData: abi.encodeWithSelector(IAggregationExecutor.execute.selector, address(vault)),
      desc: desc,
      clientData: bytes("")
    });
    return abi.encodeWithSelector(IMetaAggregationRouterV2.swap.selector, execution);
  }

  /* ----------------------------------------------------------------------- */
  /*                                 SETUP                                    */
  /* ----------------------------------------------------------------------- */

  function _deployAaveIntegration() internal {
    vm.startPrank(owner);

    governance.setContractGuard(AAVE_V3_POOL, address(new AaveLendingPoolGuardV3L2Pool()));

    AaveLendingPoolAssetGuard aaveAssetGuard = new AaveLendingPoolAssetGuard({
      _aaveLendingPool: AAVE_V3_POOL,
      _swapper: OptimismConfig.SWAPPER,
      _onchainSwapRouter: OptimismConfig.LEGACY_ONCHAIN_SWAP_ROUTER,
      _pendleYieldContractFactory: address(0),
      _pendleRouterStatic: address(0),
      _mismatchDelta: 150
    });
    governance.setAssetGuard(uint16(AssetTypeIncomplete.AAVE_V3), address(aaveAssetGuard));

    assetHandlerProxy.addAsset(AAVE_V3_POOL, uint16(AssetTypeIncomplete.AAVE_V3), address(usdPriceAggregator));

    vm.stopPrank();
  }

  function _deploySwapGuards() internal {
    vm.startPrank(owner);

    // Unmodified production guards, registered for the REAL router addresses (bytecode exists on the fork).
    oneInchV6Guard = new OneInchV6Guard({
      _slippageAccumulator: address(slippageAccumulator),
      _uniswapV2Factory: IUniswapV2Factory(OptimismConfig.UNISWAP_V2_FACTORY),
      _uniswapV3Factory: IUniswapV3Factory(OptimismConfig.UNISWAP_V3_FACTORY),
      _quickswapV2Factory: address(0)
    });
    governance.setContractGuard(ONE_INCH_ROUTER, address(oneInchV6Guard));

    kyberGuard = new KyberSwapRouterV2ContractGuard(address(slippageAccumulator));
    governance.setContractGuard(KYBER_ROUTER, address(kyberGuard));

    vm.stopPrank();
  }

  function _createVaultAndSupplyToAave() internal {
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: AAVE_V3_POOL, isDeposit: false}); // umbrella
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: WETH, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: USDC, isDeposit: true});

    vm.prank(manager);
    vault = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Aave Tester",
        _fundName: "Aave aToken Exfil PoC",
        _fundSymbol: "ATP",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    vaultManagerLogic = PoolManagerLogic(vault.poolManagerLogic());

    deal(WETH, investor, WETH_SUPPLIED);
    vm.startPrank(investor);
    IERC20(WETH).approve(address(vault), WETH_SUPPLIED);
    vault.deposit(WETH, WETH_SUPPLIED);
    vm.stopPrank();

    // Manager lends the WETH into Aave -> the pool receives aWETH: unregistered, yet counted as collateral.
    vm.startPrank(manager);
    vault.execTransaction(WETH, abi.encodeWithSelector(IERC20.approve.selector, AAVE_V3_POOL, type(uint256).max));
    vault.execTransaction(
      AAVE_V3_POOL,
      abi.encodeWithSelector(IAaveV3Pool.supply.selector, WETH, WETH_SUPPLIED, address(vault), uint16(0))
    );
    vm.stopPrank();

    aWeth = IAaveV3Pool(AAVE_V3_POOL).getReserveAToken(WETH);
  }
}

/// @notice A plain unsupported ERC20 standing in for a reward/airdrop token the vault happens to hold.
contract RewardToken is ERC20 {
  constructor() ERC20("Reward", "RWD") {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

/// @notice A dummy supported asset standing in for a new integration's "umbrella" asset.
contract DummyToken is ERC20 {
  constructor() ERC20("Dummy", "DUM") {}
}

/// @notice A new integration's asset guard, declaring it accounts for `accountedToken`. The shared
///         swap-guard code knows nothing about it.
contract MockUmbrellaAssetGuard is ERC20Guard, IAccountedTokenAssetGuard {
  // solhint-disable-next-line const-name-snakecase
  bool public constant override isAccountedTokenAssetGuard = true;

  address public immutable accountedToken;

  constructor(address _accountedToken) {
    accountedToken = _accountedToken;
  }

  function isAccountedToken(address, address, address _token) external view override returns (bool) {
    return _token == accountedToken;
  }
}
