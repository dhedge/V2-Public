// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {PoolLogic} from "../../../../contracts/PoolLogic.sol";
import {Governance} from "../../../../contracts/Governance.sol";
import {IPoolLogic} from "../../../../contracts/interfaces/IPoolLogic.sol";
import {ProxyFactory} from "../../../../contracts/upgradability/ProxyFactory.sol";
import {IERC20Extended} from "../../../../contracts/interfaces/IERC20Extended.sol";
import {AaveLendingPoolAssetGuard} from "../../../../contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";

interface IPoolLogicExtended is IPoolLogic {
  function execTransaction(address to, bytes calldata data) external returns (bool success);
}

contract AaveV3AllowanceResetTest is Test {
  string public optimismRpcUrl = vm.envString("OPTIMISM_URL");

  IPoolLogicExtended public ETHBULL3X = IPoolLogicExtended(0x32b1D1bFd4B3b0CB9FF2DcD9DAc757aA64d4cb69);
  address public poolManager = 0x813123A13d01d3F07d434673Fdc89cBBA523f14d;
  address public poolInvestor = 0x523048e60740be89aa202A09Ea32A14Cc1cd67f4;
  IERC20Extended public usdc = IERC20Extended(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
  address public aaveV3LendingPool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
  address public protocolDataProvider = 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654;

  address public dHEDGEAdminOptimism = 0x90b1a66957914EbbE7a8df254c0c1E455972379C;
  address public dHEDGEFactoryProxyOptimism = 0x5e61a079A178f0E5784107a4963baAe0c5a680c6;
  Governance public dHEDGEGovernance = Governance(0xa9F912c1dB1b844fd96192Ac3B496E9d8F445bc9);
  address public poolManagerLogicImplementation = 0xdf202683672F0de51ccfaf1faBD7111696509161;

  uint256 public constant UNLIMITED_ALLOWANCE = type(uint256).max;
  uint256 public constant HUGE_ALLOWANCE = UNLIMITED_ALLOWANCE / 2;

  function setUp() public {
    vm.createSelectFork(optimismRpcUrl);
  }

  function test_allowance_reset_after_withdrawal() public {
    uint256 usdcAllowanceAfter = _getAllowanceAfterWithdrawal(HUGE_ALLOWANCE);
    assertEq(usdcAllowanceAfter, 0);
  }

  function test_allowance_not_reset_after_withdrawal() public {
    _deployAndUpgrade();

    uint256 usdcAllowanceAfter = _getAllowanceAfterWithdrawal(HUGE_ALLOWANCE);
    assertEq(usdcAllowanceAfter, HUGE_ALLOWANCE);
  }

  function test_unlimited_allowance_does_not_halt_withdrawal() public {
    _deployAndUpgrade();

    uint256 usdcAllowanceAfter = _getAllowanceAfterWithdrawal(UNLIMITED_ALLOWANCE);

    assertLt(usdcAllowanceAfter, UNLIMITED_ALLOWANCE);
    assertGt(usdcAllowanceAfter, HUGE_ALLOWANCE);
  }

  function _getAllowanceAfterWithdrawal(uint256 _allowanceToUse) internal returns (uint256 allowanceAfter) {
    uint256 usdcAllowanceBefore = usdc.allowance(address(ETHBULL3X), aaveV3LendingPool);
    assertEq(usdcAllowanceBefore, 0);

    bytes memory data = abi.encodeWithSelector(usdc.approve.selector, aaveV3LendingPool, _allowanceToUse);
    vm.prank(poolManager);
    ETHBULL3X.execTransaction(address(usdc), data);
    assertEq(usdc.allowance(address(ETHBULL3X), aaveV3LendingPool), _allowanceToUse);

    vm.prank(poolInvestor);
    ETHBULL3X.withdraw(1e18);

    allowanceAfter = usdc.allowance(address(ETHBULL3X), aaveV3LendingPool);
  }

  function _deployAndUpgrade() internal {
    address newPoolLogicImplementation = address(new PoolLogic());

    vm.prank(dHEDGEAdminOptimism);
    ProxyFactory(dHEDGEFactoryProxyOptimism).setLogic(newPoolLogicImplementation, poolManagerLogicImplementation);

    address newAssetGuardAddress = address(new AaveLendingPoolAssetGuard(protocolDataProvider, aaveV3LendingPool));

    vm.prank(dHEDGEAdminOptimism);
    dHEDGEGovernance.setAssetGuard(8, newAssetGuardAddress);
  }
}
