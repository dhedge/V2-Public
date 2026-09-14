// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
// solhint-disable-next-line max-line-length
import {VelodromeNonfungiblePositionGuard} from "contracts/guards/contractGuards/velodrome/VelodromeNonfungiblePositionGuard.sol";
// solhint-disable-next-line max-line-length
import {VelodromeCLGaugeContractGuard} from "contracts/guards/contractGuards/velodrome/VelodromeCLGaugeContractGuard.sol";
import {VelodromeCLAssetGuard} from "contracts/guards/assetGuards/velodrome/VelodromeCLAssetGuard.sol";
import {RewardAssetGuard} from "contracts/guards/assetGuards/RewardAssetGuard.sol";
// solhint-disable-next-line max-line-length
import {IVelodromeNonfungiblePositionManager} from "contracts/interfaces/velodrome/IVelodromeNonfungiblePositionManager.sol";
import {IVelodromeCLFactory} from "contracts/interfaces/velodrome/IVelodromeCLFactory.sol";
import {IVelodromeCLPool} from "contracts/interfaces/velodrome/IVelodromeCLPool.sol";
import {IVelodromeCLGauge} from "contracts/interfaces/velodrome/IVelodromeCLGauge.sol";
import {ERC20Asset} from "contracts/test/TestAssets.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {SingleFundTestSetup} from "test/integration/utils/foundry/SingleFundTestSetup.t.sol";

/// @notice Shared fixture for the Velodrome/Aerodrome concentrated liquidity guards: a vault that
/// can mint CL positions, stake them in a gauge for emissions, and be valued and unwound while
/// holding them.
abstract contract VelodromeCLTestSetup is SingleFundTestSetup {
  uint16 internal constant REWARD_ASSET_TYPE = 200;
  uint256 internal constant MAX_POSITIONS = 3;
  uint256 internal constant DEADLINE = type(uint256).max;
  bytes32 internal constant VELODROME_NFT_TYPE = keccak256("VELODROME_NFT_TYPE");

  struct VelodromeCLConfig {
    address nonfungiblePositionManager;
    address clFactory;
    address protocolToken; // VELO / AERO
    address protocolTokenOracle;
    address token0;
    address token1;
    address token0Oracle;
    address token1Oracle;
    int24 tickSpacing;
    address gauge;
    uint256 amount0;
    uint256 amount1;
  }

  VelodromeCLConfig internal cl;

  IVelodromeNonfungiblePositionManager internal nftManager;
  VelodromeNonfungiblePositionGuard internal positionGuard;
  VelodromeCLAssetGuard internal clAssetGuard;

  /// @dev Supported by the vault and priceable, but has no CL pool.
  /// @dev Never added to the vault's supported assets.
  ERC20Asset internal unsupportedToken;

  constructor(VelodromeCLConfig memory _config) {
    cl = _config;
  }

  function setUp() public virtual override {
    super.setUp();

    nftManager = IVelodromeNonfungiblePositionManager(cl.nonfungiblePositionManager);

    vm.startPrank(owner);

    positionGuard = new VelodromeNonfungiblePositionGuard(MAX_POSITIONS, address(nftTrackerStorageProxy));
    governance.setContractGuard({extContract: cl.nonfungiblePositionManager, guardAddress: address(positionGuard)});
    governance.setContractGuard({extContract: cl.gauge, guardAddress: address(new VelodromeCLGaugeContractGuard())});

    clAssetGuard = new VelodromeCLAssetGuard();
    governance.setAssetGuard({
      assetType: uint16(AssetTypeIncomplete.VELODROME_CL),
      guardAddress: address(clAssetGuard)
    });

    // Emissions are only worth holding for a vault that holds the position earning them.
    RewardAssetGuard.RewardAssetSetting[] memory rewardSettings = new RewardAssetGuard.RewardAssetSetting[](1);
    uint16[] memory linkedAssetTypes = new uint16[](1);
    linkedAssetTypes[0] = uint16(AssetTypeIncomplete.VELODROME_CL);
    rewardSettings[0] = RewardAssetGuard.RewardAssetSetting({
      rewardToken: cl.protocolToken,
      linkedAssetTypes: linkedAssetTypes,
      linkedAssets: new address[](0)
    });
    governance.setAssetGuard({
      assetType: REWARD_ASSET_TYPE,
      guardAddress: address(new RewardAssetGuard(rewardSettings))
    });

    unsupportedToken = new ERC20Asset("Unsupported", "UNS");

    IAssetHandler.Asset[] memory assetsToAdd = new IAssetHandler.Asset[](4);
    assetsToAdd[0] = _chainlinkAsset(cl.token0, cl.token0Oracle);
    assetsToAdd[1] = _chainlinkAsset(cl.token1, cl.token1Oracle);
    assetsToAdd[2] = IAssetHandler.Asset({
      asset: cl.nonfungiblePositionManager,
      assetType: uint16(AssetTypeIncomplete.VELODROME_CL),
      aggregator: address(usdPriceAggregator)
    });
    assetsToAdd[3] = IAssetHandler.Asset({
      asset: cl.protocolToken,
      assetType: REWARD_ASSET_TYPE,
      aggregator: cl.protocolTokenOracle
    });
    assetHandlerProxy.addAssets(assetsToAdd);

    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: cl.token0, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: cl.token1, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: cl.protocolToken, isDeposit: false});

    vm.prank(manager);
    fund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "VelodromeCLTest",
        _fundSymbol: "VCL",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    // Enough for the position cap tests to mint four times over.
    _makeDeposit(fund, investor, cl.token0, cl.amount0 * 6);
    _makeDeposit(fund, investor, cl.token1, cl.amount1 * 6);

    // Clear the post-deposit lockup up front. It is core behaviour covered by the core suites, and
    // waiting it out mid-test would accrue emissions between a measurement and the withdrawal it
    // is being compared against.
    skip(poolFactoryProxy.getExitCooldown() + 1);
  }

  /* ========== HELPERS ========== */

  function _chainlinkAsset(address _asset, address _oracle) internal pure returns (IAssetHandler.Asset memory asset) {
    asset = IAssetHandler.Asset({asset: _asset, assetType: uint16(AssetTypeIncomplete.CHAINLINK), aggregator: _oracle});
  }

  function _enableNftPosition() internal {
    vm.prank(manager);
    fundManagerLogic.changeAssets(_toSupportedAssets(cl.nonfungiblePositionManager, false), new address[](0));
  }

  function _currentTick() internal view returns (int24 tick) {
    address pool = IVelodromeCLFactory(cl.clFactory).getPool(cl.token0, cl.token1, cl.tickSpacing);
    require(pool != address(0), "CL pool missing on fork");

    (, tick, , , , ) = IVelodromeCLPool(pool).slot0();
  }

  /// @dev Distinct, in-range tick bands so a vault can hold several positions at once.
  function _tickRange(uint256 _widthMultiple) internal view returns (int24 lower, int24 upper) {
    int24 spacing = cl.tickSpacing;
    int24 aligned = (_currentTick() / spacing) * spacing;
    int24 width = spacing * int24(_widthMultiple);

    (lower, upper) = (aligned - width, aligned + width);
  }

  function _mintCalldata(
    address _token0,
    address _token1,
    int24 _lower,
    int24 _upper,
    address _recipient
  ) internal view returns (bytes memory data) {
    data = abi.encodeWithSelector(
      IVelodromeNonfungiblePositionManager.mint.selector,
      IVelodromeNonfungiblePositionManager.MintParams({
        token0: _token0,
        token1: _token1,
        tickSpacing: cl.tickSpacing,
        tickLower: _lower,
        tickUpper: _upper,
        amount0Desired: cl.amount0,
        amount1Desired: cl.amount1,
        amount0Min: 0,
        amount1Min: 0,
        recipient: _recipient,
        deadline: DEADLINE,
        sqrtPriceX96: 0
      })
    );
  }

  /// @dev Approves both tokens and mints in one batch, as a manager would.
  function _mintAsPool(uint256 _widthMultiple) internal returns (uint256 tokenId) {
    (int24 lower, int24 upper) = _tickRange(_widthMultiple);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](3);
    txs[0] = PoolLogic.TxToExecute({
      to: cl.token0,
      data: abi.encodeWithSelector(IERC20.approve.selector, cl.nonfungiblePositionManager, type(uint256).max)
    });
    txs[1] = PoolLogic.TxToExecute({
      to: cl.token1,
      data: abi.encodeWithSelector(IERC20.approve.selector, cl.nonfungiblePositionManager, type(uint256).max)
    });
    txs[2] = PoolLogic.TxToExecute({
      to: cl.nonfungiblePositionManager,
      data: _mintCalldata(cl.token0, cl.token1, lower, upper, address(fund))
    });

    vm.prank(manager);
    fund.execTransactions(txs);

    tokenId = nftManager.tokenOfOwnerByIndex(address(fund), nftManager.balanceOf(address(fund)) - 1);
  }

  function _trackedTokenIds() internal view returns (uint256[] memory tokenIds) {
    tokenIds = nftTrackerStorageProxy.getAllUintIds(VELODROME_NFT_TYPE, address(fund));
  }

  /// @dev Approves the position NFT to the gauge and stakes it for emissions.
  function _stake(uint256 _tokenId) internal {
    _managerExec(cl.nonfungiblePositionManager, abi.encodeWithSelector(IERC20.approve.selector, cl.gauge, _tokenId));
    _managerExec(cl.gauge, abi.encodeWithSelector(IVelodromeCLGauge.deposit.selector, _tokenId));
  }
}
