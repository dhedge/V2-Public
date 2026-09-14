// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {VelodromeV2RouterGuard} from "contracts/guards/contractGuards/velodrome/VelodromeV2RouterGuard.sol";
// solhint-disable-next-line max-line-length
import {VelodromeV2GaugeContractGuard} from "contracts/guards/contractGuards/velodrome/VelodromeV2GaugeContractGuard.sol";
import {VelodromeV2LPAssetGuard} from "contracts/guards/assetGuards/velodrome/VelodromeV2LPAssetGuard.sol";
import {RewardAssetGuard} from "contracts/guards/assetGuards/RewardAssetGuard.sol";
import {VelodromeStableLPAggregator} from "contracts/priceAggregators/VelodromeStableLPAggregator.sol";
import {VelodromeVariableLPAggregator} from "contracts/priceAggregators/VelodromeVariableLPAggregator.sol";
import {IVelodromeV2Router} from "contracts/interfaces/velodrome/IVelodromeV2Router.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {SingleFundTestSetup} from "test/integration/utils/foundry/SingleFundTestSetup.t.sol";

/// @notice Shared fixture for the Velodrome V2 (and Aerodrome) guards: a vault that may add and
/// remove liquidity through the router, stake the resulting LP in a gauge, and claim emissions.
/// @dev The live pools are quoted in the chain's pool-side stablecoin, which is not always the same
/// token the backbone registers as USDC, so it is supplied separately and registered here.
abstract contract VelodromeV2TestSetup is SingleFundTestSetup {
  uint16 internal constant REWARD_ASSET_TYPE = 200;

  struct VelodromeV2Config {
    address router;
    address voter;
    address protocolToken; // VELO / AERO
    address protocolTokenOracle;
    address poolStable; // the stablecoin the live pools are quoted in
    address poolStableOracle;
    address stablePool; // poolStable/DAI
    address stableGauge;
    address variablePool; // WETH/poolStable
    address variableGauge;
  }

  VelodromeV2Config internal velo;

  VelodromeV2LPAssetGuard internal lpAssetGuard;

  constructor(VelodromeV2Config memory _config) {
    velo = _config;
  }

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    governance.setContractGuard({extContract: velo.router, guardAddress: address(new VelodromeV2RouterGuard())});

    address gaugeGuard = address(new VelodromeV2GaugeContractGuard());
    governance.setContractGuard({extContract: velo.stableGauge, guardAddress: gaugeGuard});
    governance.setContractGuard({extContract: velo.variableGauge, guardAddress: gaugeGuard});

    lpAssetGuard = new VelodromeV2LPAssetGuard(velo.voter);
    governance.setAssetGuard({
      assetType: uint16(AssetTypeIncomplete.VELODROME_V2_LP),
      guardAddress: address(lpAssetGuard)
    });

    // Emissions are paid in the protocol token, which is only valuable to a vault holding the LP.
    RewardAssetGuard.RewardAssetSetting[] memory rewardSettings = new RewardAssetGuard.RewardAssetSetting[](1);
    uint16[] memory linkedAssetTypes = new uint16[](1);
    linkedAssetTypes[0] = uint16(AssetTypeIncomplete.VELODROME_V2_LP);
    rewardSettings[0] = RewardAssetGuard.RewardAssetSetting({
      rewardToken: velo.protocolToken,
      linkedAssetTypes: linkedAssetTypes,
      linkedAssets: new address[](0)
    });
    governance.setAssetGuard({
      assetType: REWARD_ASSET_TYPE,
      guardAddress: address(new RewardAssetGuard(rewardSettings))
    });

    IAssetHandler.Asset[] memory assetsToAdd = new IAssetHandler.Asset[](4);
    assetsToAdd[0] = IAssetHandler.Asset({
      asset: velo.poolStable,
      assetType: uint16(AssetTypeIncomplete.CHAINLINK),
      aggregator: velo.poolStableOracle
    });
    assetsToAdd[1] = IAssetHandler.Asset({
      asset: velo.stablePool,
      assetType: uint16(AssetTypeIncomplete.VELODROME_V2_LP),
      aggregator: address(new VelodromeStableLPAggregator(velo.stablePool, address(poolFactoryProxy)))
    });
    assetsToAdd[2] = IAssetHandler.Asset({
      asset: velo.variablePool,
      assetType: uint16(AssetTypeIncomplete.VELODROME_V2_LP),
      aggregator: address(new VelodromeVariableLPAggregator(velo.variablePool, address(poolFactoryProxy)))
    });
    assetsToAdd[3] = IAssetHandler.Asset({
      asset: velo.protocolToken,
      assetType: REWARD_ASSET_TYPE,
      aggregator: velo.protocolTokenOracle
    });
    assetHandlerProxy.addAssets(assetsToAdd);

    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](6);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: velo.poolStable, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: daiData.asset, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    supportedAssets[3] = IHasSupportedAsset.Asset({asset: velo.stablePool, isDeposit: false});
    supportedAssets[4] = IHasSupportedAsset.Asset({asset: velo.variablePool, isDeposit: false});
    supportedAssets[5] = IHasSupportedAsset.Asset({asset: velo.protocolToken, isDeposit: false});

    vm.prank(manager);
    fund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "VelodromeV2Test",
        _fundSymbol: "VV2",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    _seedFund();
  }

  /* ========== HELPERS ========== */

  function _seedFund() internal {
    _makeDeposit(fund, investor, velo.poolStable, 20_000e6);
    _makeDeposit(fund, investor, daiData.asset, 20_000e18);
    _makeDeposit(fund, investor, wethData.asset, 5e18);
  }

  function _approveRouter(address _token, uint256 _amount) internal {
    _managerExec(_token, abi.encodeWithSelector(IERC20.approve.selector, velo.router, _amount));
  }

  function _addLiquidityCalldata(
    address _tokenA,
    address _tokenB,
    bool _stable,
    uint256 _amountA,
    uint256 _amountB,
    address _recipient
  ) internal pure returns (bytes memory data) {
    data = abi.encodeWithSelector(
      IVelodromeV2Router.addLiquidity.selector,
      _tokenA,
      _tokenB,
      _stable,
      _amountA,
      _amountB,
      0,
      0,
      _recipient,
      type(uint256).max
    );
  }

  function _removeLiquidityCalldata(
    address _tokenA,
    address _tokenB,
    bool _stable,
    uint256 _liquidity,
    address _recipient
  ) internal pure returns (bytes memory data) {
    data = abi.encodeWithSelector(
      IVelodromeV2Router.removeLiquidity.selector,
      _tokenA,
      _tokenB,
      _stable,
      _liquidity,
      0,
      0,
      _recipient,
      type(uint256).max
    );
  }

  /// @dev Adds stable-pool liquidity as the manager and returns the LP received.
  function _addStableLiquidity() internal returns (uint256 lpReceived) {
    _approveRouter(velo.poolStable, 10_000e6);
    _approveRouter(daiData.asset, 10_000e18);

    _managerExec(
      velo.router,
      _addLiquidityCalldata(velo.poolStable, daiData.asset, true, 10_000e6, 10_000e18, address(fund))
    );

    lpReceived = IERC20(velo.stablePool).balanceOf(address(fund));
  }

  function _approveGauge(uint256 _amount) internal {
    _managerExec(velo.stablePool, abi.encodeWithSelector(IERC20.approve.selector, velo.stableGauge, _amount));
  }

  /// @dev Stakes the vault's stable-pool LP into its gauge.
  function _stakeLp(uint256 _lp) internal {
    _approveGauge(_lp);
    _managerExec(velo.stableGauge, abi.encodeWithSignature("deposit(uint256)", _lp));
  }
}
