// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/ProxyAdmin.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";

abstract contract DeploymentDryRunTest is Test {
  address public depositor = makeAddr("depositor");

  string public network;
  uint256 public forkBlockNumber;

  address public immutable usdc;
  address public immutable weth;
  address public immutable wbtc;

  PoolFactory public immutable poolFactory;
  address public immutable nftTracker;
  address public immutable slippageAccumulator;
  address public immutable usdPriceAggregator;

  ProxyAdmin public immutable proxyAdmin;

  address[] private torosVaultsToCheck;
  uint256[] private tokenPricesBeforeTheUpgrade;

  constructor(
    string memory _network,
    uint256 _forkBlockNumber,
    address[] memory _vaultsToTest,
    address _usdc,
    address _weth,
    address _wbtc,
    address _poolFactory,
    address _nftTracker,
    address _slippageAccumulator,
    address _usdPriceAggregator,
    address _proxyAdmin
  ) {
    network = _network;
    forkBlockNumber = _forkBlockNumber;

    _setVaultsToTest(_vaultsToTest);

    // Few blue chips tokens, not used in tests at the moment
    usdc = _usdc;
    weth = _weth;
    wbtc = _wbtc;

    // Other core and periphery contracts can be read from PoolFactory
    poolFactory = PoolFactory(_poolFactory);

    // Below contracts can not be read from PoolFactory, but may require to be used for deployments
    nftTracker = _nftTracker;
    slippageAccumulator = _slippageAccumulator;
    usdPriceAggregator = _usdPriceAggregator;
    proxyAdmin = ProxyAdmin(_proxyAdmin);
  }

  function setUp() public virtual {
    vm.createSelectFork(network, forkBlockNumber);

    vm.label(usdc, "USDC");
    vm.label(weth, "WETH");
    vm.label(wbtc, "WBTC");
    vm.label(address(poolFactory), "PoolFactory");
    vm.label(nftTracker, "DhedgeNftTrackerStorage");
    vm.label(slippageAccumulator, "SlippageAccumulator");
    vm.label(usdPriceAggregator, "USDPriceAggregator");

    for (uint256 i; i < torosVaultsToCheck.length; ++i) {
      tokenPricesBeforeTheUpgrade.push(PoolLogic(torosVaultsToCheck[i]).tokenPrice());
    }
  }

  function test_token_prices_should_stay_same_after_new_deployment() public view {
    for (uint256 i; i < torosVaultsToCheck.length; ++i) {
      assertEq(
        PoolLogic(torosVaultsToCheck[i]).tokenPrice(),
        tokenPricesBeforeTheUpgrade[i],
        string(abi.encodePacked("tokenPrice mismatch for vault: ", _addressToString(torosVaultsToCheck[i])))
      );
    }
  }

  function test_deposits_should_work_after_new_deployment() public {
    for (uint256 i; i < torosVaultsToCheck.length; ++i) {
      uint256 tokenPriceBefore = PoolLogic(torosVaultsToCheck[i]).tokenPrice();
      _depositIntoVault(torosVaultsToCheck[i]);
      uint256 tokenPriceAfter = PoolLogic(torosVaultsToCheck[i]).tokenPrice();
      assertEq(
        tokenPriceAfter,
        tokenPriceBefore,
        string(
          abi.encodePacked("after deposit tokenPrice mismatch for vault: ", _addressToString(torosVaultsToCheck[i]))
        )
      );
    }
  }

  // TODO: Add more stuff to test, suggestions are welcome

  function _setVaultsToTest(address[] memory vaults) internal {
    for (uint256 i; i < vaults.length; ++i) {
      torosVaultsToCheck.push(vaults[i]);
    }
  }

  function _findDepositAsset(address _vault) internal view returns (address depositAsset) {
    PoolManagerLogic poolManagerLogic = PoolManagerLogic(PoolLogic(_vault).poolManagerLogic());
    PoolManagerLogic.Asset[] memory supportedAssets = poolManagerLogic.getSupportedAssets();

    for (uint256 i; i < supportedAssets.length; ++i) {
      if (supportedAssets[i].isDeposit) return supportedAssets[i].asset;
    }
  }

  function _depositIntoVault(address _vault) internal {
    address depositAsset = _findDepositAsset(_vault);
    uint8 depositAssetDecimals = ERC20(depositAsset).decimals();
    uint256 depositAssetPriceD18 = poolFactory.getAssetPrice(depositAsset);
    uint256 amountToDeposit = (1000e18 * (10 ** depositAssetDecimals)) / depositAssetPriceD18; // $1000 worth of deposit asset
    deal(depositAsset, depositor, amountToDeposit);
    vm.startPrank(depositor);
    ERC20(depositAsset).approve(_vault, amountToDeposit);
    uint256 sharesMinted = PoolLogic(_vault).deposit(depositAsset, amountToDeposit);
    vm.stopPrank();
    uint256 sharesBalance = ERC20(_vault).balanceOf(depositor);
    assertEq(sharesMinted, sharesBalance, "sharesMinted mismatch");
  }

  function _addressToString(address _addr) internal pure returns (string memory) {
    bytes32 value = bytes32(uint256(uint160(_addr)));
    bytes memory alphabet = "0123456789abcdef";

    bytes memory str = new bytes(42);
    str[0] = "0";
    str[1] = "x";

    for (uint256 i = 0; i < 20; i++) {
      str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
      str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
    }

    return string(str);
  }
}
