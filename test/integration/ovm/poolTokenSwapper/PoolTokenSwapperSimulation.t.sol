// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolTokenSwapper} from "contracts/swappers/poolTokenSwapper/PoolTokenSwapper.sol";
import {DeploymentDryRunOptimism} from "test/integration/utils/foundry/dryRun/DeploymentDryRunOptimism.t.sol";
import {Governance} from "contracts/Governance.sol";
import {PoolTokenSwapperGuard} from "contracts/guards/contractGuards/PoolTokenSwapperGuard.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {AllowApproveContractGuard} from "contracts/guards/contractGuards/AllowApproveContractGuard.sol";
import {SlippageAccumulator} from "contracts/utils/SlippageAccumulator.sol";

import {console} from "forge-std/console.sol";

contract PoolTokenSwapperSimulation is DeploymentDryRunOptimism {
  PoolTokenSwapper public poolTokenSwapper = PoolTokenSwapper(0xE2F9b946C4Dcc6EbD1e00A8791E1570E4e6D74D9);
  address public assetToPurge = OptimismConfig.USDpy;
  address public anyone = makeAddr("anyone");
  address public owner;

  // Block number should not be updated, as USDpy purge already happened in production.
  constructor() DeploymentDryRunOptimism(137055979, new address[](0)) {}

  function setUp() public override {
    super.setUp();

    Governance governance = Governance(poolFactory.governanceAddress());
    owner = poolFactory.owner();

    address slippageAccumulator = address(new SlippageAccumulator(OptimismConfig.POOL_FACTORY_PROD, 86400, 10e4));
    PoolTokenSwapperGuard poolTokenSwapperGuard = new PoolTokenSwapperGuard(slippageAccumulator);
    AllowApproveContractGuard allowApproveGuard = new AllowApproveContractGuard(address(poolTokenSwapper));

    vm.startPrank(owner);

    // Here we set updated contract guard for PoolTokenSwapper which makes swap function public
    governance.setContractGuard(address(poolTokenSwapper), address(poolTokenSwapperGuard));

    // Here we set specific contract guard for USDpy asset to allow approve on PoolTokenSwapper
    governance.setContractGuard(assetToPurge, address(allowApproveGuard));

    // Here we add USDC as an asset to swap through PoolTokenSwapper (currently only USDCe is set)
    PoolTokenSwapper.AssetConfig[] memory assets = new PoolTokenSwapper.AssetConfig[](1);
    assets[0] = PoolTokenSwapper.AssetConfig({asset: OptimismConfig.USDC, assetEnabled: true});
    poolTokenSwapper.setAssets(assets);

    // This is to allow vaults which hold USDpy to call swap on PoolTokenSwapper
    address[] memory vaultsToPurge = _getVaultsToPurgeForUSDC();
    PoolTokenSwapper.SwapWhitelistConfig[] memory swapWhitelist = new PoolTokenSwapper.SwapWhitelistConfig[](
      vaultsToPurge.length
    );
    for (uint256 i; i < swapWhitelist.length; i++) {
      swapWhitelist[i].sender = vaultsToPurge[i];
      swapWhitelist[i].status = true;
    }
    poolTokenSwapper.setSwapWhitelist(swapWhitelist);

    vaultsToPurge = _getVaultsToPurgeForUSDCe();
    swapWhitelist = new PoolTokenSwapper.SwapWhitelistConfig[](vaultsToPurge.length);
    for (uint256 i; i < swapWhitelist.length; i++) {
      swapWhitelist[i].sender = vaultsToPurge[i];
      swapWhitelist[i].status = true;
    }
    poolTokenSwapper.setSwapWhitelist(swapWhitelist);

    // This is to set lowest fee possible instead of upgrading PoolTokenSwapper. In PoolTokenSwapper fee must be above 0. Changes swap fee for USDpy from 0.05% to 0.01%.
    PoolTokenSwapper.PoolConfig[] memory poolConfigs = new PoolTokenSwapper.PoolConfig[](1);
    poolConfigs[0] = PoolTokenSwapper.PoolConfig({pool: assetToPurge, poolSwapFee: 1, poolEnabled: true});
    poolTokenSwapper.setPools(poolConfigs);

    vm.stopPrank();
  }

  function test_can_purge_assets() public {
    _can_purge_assets_to(OptimismConfig.USDC, _getVaultsToPurgeForUSDC());

    _can_purge_assets_to(OptimismConfig.USDCe, _getVaultsToPurgeForUSDCe());
  }

  function _can_purge_assets_to(address _assetToReceive, address[] memory _vaultsToPurge) internal {
    uint256 assetToReceiveBalance = IERC20(_assetToReceive).balanceOf(address(poolTokenSwapper));
    uint256 totalAmountOut;

    for (uint256 i; i < _vaultsToPurge.length; i++) {
      totalAmountOut += _can_purge_asset(_vaultsToPurge[i], _assetToReceive);
    }

    if (assetToReceiveBalance < totalAmountOut) {
      uint256 amountToTopUp = totalAmountOut - assetToReceiveBalance;
      console.log("PoolTokenSwapper needs to be topped up with:", amountToTopUp);
    }
  }

  function _can_purge_asset(address _vault, address _assetToReceive) internal returns (uint256 amountOut) {
    uint256 vaultTokenPriceBefore = PoolLogic(_vault).tokenPrice();
    uint256 assetToPurgeBalanceBefore = IERC20(assetToPurge).balanceOf(_vault);
    uint256 assetToPurgePTSBalanceBefore = IERC20(assetToPurge).balanceOf(address(poolTokenSwapper));
    uint256 assetToReceivePTSBalanceBefore = IERC20(_assetToReceive).balanceOf(address(poolTokenSwapper));

    assertGt(assetToPurgeBalanceBefore, 0, "Vault should have some asset to purge");

    PoolManagerLogic poolManagerLogic = PoolManagerLogic(PoolLogic(_vault).poolManagerLogic());

    bool assetToReceiveSupported = poolManagerLogic.isSupportedAsset(_assetToReceive);

    assertTrue(assetToReceiveSupported, "Asset to receive should be supported");

    amountOut = poolTokenSwapper.getSwapQuote(assetToPurge, _assetToReceive, assetToPurgeBalanceBefore);

    assertGt(assetToReceivePTSBalanceBefore, amountOut, "PoolTokenSwapper should have enough asset to receive");

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({
      to: assetToPurge,
      data: abi.encodeWithSelector(IERC20.approve.selector, address(poolTokenSwapper), assetToPurgeBalanceBefore)
    });
    txs[1] = PoolLogic.TxToExecute({
      to: address(poolTokenSwapper),
      data: abi.encodeWithSelector(
        PoolTokenSwapper.swap.selector,
        assetToPurge,
        _assetToReceive,
        assetToPurgeBalanceBefore,
        amountOut
      )
    });
    bytes memory execData = abi.encodeWithSelector(PoolLogic.execTransactions.selector, txs);

    // If AllowApproveContractGuard and PoolTokenSwapperGuard allow public calls, can purge assets from any msg.sender.
    // vm.prank(anyone);
    // Otherwise, manager can do it.
    vm.prank(poolManagerLogic.manager());
    (bool success, ) = _vault.call(execData);
    require(success, "Vault should execute transactions successfully");

    uint256 assetToPurgeBalanceAfter = IERC20(assetToPurge).balanceOf(_vault);
    uint256 assetToReceiveBalanceAfter = IERC20(_assetToReceive).balanceOf(_vault);
    uint256 assetToPurgePTSBalanceAfter = IERC20(assetToPurge).balanceOf(address(poolTokenSwapper));

    assertEq(
      assetToPurgePTSBalanceAfter,
      assetToPurgePTSBalanceBefore + assetToPurgeBalanceBefore,
      "PoolTokenSwapper should have received asset to purge"
    );

    assertApproxEqRel(
      PoolLogic(_vault).tokenPrice(),
      vaultTokenPriceBefore,
      0.0001e18, // 0.01% tolerance
      "Vault token price should not change after swap"
    );
    assertEq(assetToPurgeBalanceAfter, 0, "Vault should have 0 asset to purge after swap");
    assertGe(assetToReceiveBalanceAfter, amountOut, "Vault should possess asset to receive after swap");

    // Extra step to disable USDpy, not strictly necessary
    address[] memory removedAssets = new address[](1);
    removedAssets[0] = assetToPurge;

    vm.prank(owner);
    poolManagerLogic.changeAssets(new PoolManagerLogic.Asset[](0), removedAssets);
  }

  function _getVaultsToPurgeForUSDC() internal pure returns (address[] memory vaultsToPurge) {
    vaultsToPurge = new address[](9);
    vaultsToPurge[0] = 0xC3F232c00AB6cE31a332126331dA3F74Ca1D51CC;
    vaultsToPurge[1] = 0x9D3c3232B3821804Abe5f6C2182057188d48d1c0;
    vaultsToPurge[2] = 0x0BAba84b4693BdaA667e9036D5219B496e5AA9fB;
    vaultsToPurge[3] = 0x597457006AB0bEBF296436C40b04705d165ac4cE;
    vaultsToPurge[4] = 0xe51af0BA747B9C464057B9099040f4Df0B29a7dE;
    vaultsToPurge[5] = 0xA2fFe6ed599E8F7aac8047F5Ee0De3D83De1B320;
    vaultsToPurge[6] = 0x9C0d5B0dBA4a7C40d6ff260c762249f800FE8fe9;
    vaultsToPurge[7] = 0xeE69418fB9c5eEfA3521B170Fdd112273Bd5052A;
    vaultsToPurge[8] = 0xaC275B83C2dEdE03AA814D26bC4ce84972059B69;
  }

  function _getVaultsToPurgeForUSDCe() internal pure returns (address[] memory vaultsToPurge) {
    vaultsToPurge = new address[](1);
    vaultsToPurge[0] = 0x75653eE8aE9A14Da2ebAFFB0Cb294693F5D103eb;
  }
}
