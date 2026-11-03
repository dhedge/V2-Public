// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {ProxyAdmin} from "@openzeppelin/v3/contracts/proxy/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/v3/contracts/proxy/TransparentUpgradeableProxy.sol";

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {ForkBlocks} from "test/integration/utils/foundry/config/ForkBlocks.sol";
import {PoolTestHelpers} from "test/integration/utils/foundry/PoolTestHelpers.t.sol";

/// @notice Mainnet gas of the frontend paths on one production Ethereum vault, with this branch's
/// PoolLogic, PoolManagerLogic, PoolFactory, AssetHandler and EasySwapperV2 swapped in behind the
/// live proxies. An isolated snapshot equals the transaction's receipt gas (a replayed live deposit
/// matched to the unit), so with the vault's real asset mix these are the figures users pay.
/// @dev One concrete contract per vault below; each records to `snapshots/<ContractName>.json`.
/// The suite forks at `ForkBlocks.ETHEREUM`: after `pnpm test-freshness:repin`, `pnpm test:gas`
/// regenerates the figures.
abstract contract EthereumVaultGasSnapshotTest is PoolTestHelpers {
  uint256 internal constant NATIVE_DEPOSIT = 1 ether;

  EasySwapperV2 internal easySwapper = EasySwapperV2(EthereumConfig.EASY_SWAPPER_V2_PROD);
  address internal user = makeAddr("user");

  address internal immutable vault;
  string internal group;
  /// @dev Set for vaults whose withdrawal needs frontend-built complex asset data (DYTM positions);
  /// the withdrawal test is then skipped rather than measured on a path no user takes.
  bool internal immutable withdrawalNeedsOffchainData;

  constructor(address _vault, string memory _group, bool _withdrawalNeedsOffchainData) {
    vault = _vault;
    group = _group;
    withdrawalNeedsOffchainData = _withdrawalNeedsOffchainData;
  }

  function setUp() public virtual {
    vm.createSelectFork("ethereum", ForkBlocks.ETHEREUM);

    PoolFactory poolFactory = PoolFactory(EthereumConfig.POOL_FACTORY_PROD);
    ProxyAdmin proxyAdmin = ProxyAdmin(EthereumConfig.PROXY_ADMIN);
    vm.startPrank(EthereumConfig.OWNER);
    proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(poolFactory))), address(new PoolFactory()));
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(poolFactory.getAssetHandler())),
      address(new AssetHandler())
    );
    proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(easySwapper))), address(new EasySwapperV2()));
    poolFactory.setLogic(address(new PoolLogic()), address(new PoolManagerLogic()));
    vm.stopPrank();

    vm.deal(user, 10 ether);
  }

  /* ========== DEPOSITS ========== */

  /// @dev Deposits the vault's first deposit asset, through the custom-cooldown entry when the vault
  /// is whitelisted for it (leveraged vaults) and the plain one otherwise, as the frontend does.
  function test_gas_deposit() public {
    address asset = _depositAssets()[0];
    uint256 amount = 10 * 10 ** uint256(IERC20Extended(asset).decimals());
    deal(asset, user, amount);

    bool customCooldown = _customCooldownAllowed();

    vm.startPrank(user);
    IERC20(asset).approve(address(easySwapper), amount);
    if (customCooldown) {
      easySwapper.depositWithCustomCooldown(vault, IERC20(asset), amount, 0);
      vm.snapshotGasLastCall(group, "depositWithCustomCooldown");
    } else {
      easySwapper.deposit(vault, IERC20(asset), amount, 0);
      vm.snapshotGasLastCall(group, "deposit");
    }
    vm.stopPrank();
  }

  function test_gas_nativeDeposit() public {
    vm.skip(!_isDepositAsset(EthereumConfig.WETH));

    bool customCooldown = _customCooldownAllowed();

    vm.prank(user);
    if (customCooldown) {
      easySwapper.nativeDepositWithCustomCooldown{value: NATIVE_DEPOSIT}(vault, 0);
      vm.snapshotGasLastCall(group, "nativeDepositWithCustomCooldown");
    } else {
      easySwapper.nativeDeposit{value: NATIVE_DEPOSIT}(vault, 0);
      vm.snapshotGasLastCall(group, "nativeDeposit");
    }
  }

  /* ========== WITHDRAWAL ========== */

  /// @dev One flow, two snapshots: `completeWithdrawal` only exists after `initWithdrawal`. Withdraws
  /// 1% of the supply from a holder with no lockup, so it leaves the way every exit does.
  function test_gas_withdrawal_flow() public {
    vm.skip(withdrawalNeedsOffchainData);

    uint256 shares = PoolLogic(vault).totalSupply() / 100;
    deal(vault, user, shares);

    vm.startPrank(user);
    PoolLogic(vault).approve(address(easySwapper), shares);
    easySwapper.initWithdrawal(vault, shares, _getEmptyPoolComplexAssetsData(vault));
    vm.snapshotGasLastCall(group, "initWithdrawal");

    easySwapper.completeWithdrawal();
    vm.snapshotGasLastCall(group, "completeWithdrawal");
    vm.stopPrank();
  }

  /* ========== VALUATION AND FEES ========== */

  function test_gas_totalFundValue() public {
    _poolManagerLogic().totalFundValue();
    vm.snapshotGasLastCall(group, "totalFundValue");
  }

  function test_gas_mintManagerFee() public {
    PoolLogic(vault).mintManagerFee();
    vm.snapshotGasLastCall(group, "mintManagerFee");
  }

  /* ========== HELPERS ========== */

  function _poolManagerLogic() internal view returns (PoolManagerLogic) {
    return PoolManagerLogic(PoolLogic(vault).poolManagerLogic());
  }

  function _depositAssets() internal view returns (address[] memory) {
    return _poolManagerLogic().getDepositAssets();
  }

  function _isDepositAsset(address _asset) internal view returns (bool) {
    address[] memory assets = _depositAssets();
    for (uint256 i; i < assets.length; ++i) {
      if (assets[i] == _asset) return true;
    }
    return false;
  }

  /// @dev Read this before pranking: it calls out to the swapper, which consumes a one-shot
  /// `vm.prank`, and the measured call would then run as the test contract instead of the user.
  function _customCooldownAllowed() internal view returns (bool) {
    return easySwapper.customCooldownDepositsWhitelist(vault);
  }
}

/// @notice Leveraged vault: WETH and native ETH deposits, Aave unwind on exit.
/// forge-config: default.isolate = true
contract EthereumGasSnapshotEthereumBull3X is EthereumVaultGasSnapshotTest {
  constructor()
    EthereumVaultGasSnapshotTest(0xcE09FAD0dd5e70041402dF947aB3ECF8E430Becb, "EthereumGasSnapshotEthereumBull3X", false)
  {}
}

/// @notice The largest vault by value: sUSDe deposits, seven assets including a DYTM position, so
/// only deposit, valuation and fee mint are measured.
/// forge-config: default.isolate = true
contract EthereumGasSnapshotMStablePendledSUSDe is EthereumVaultGasSnapshotTest {
  constructor()
    EthereumVaultGasSnapshotTest(EthereumConfig.mPT_sUSDe, "EthereumGasSnapshotMStablePendledSUSDe", true)
  {}
}
