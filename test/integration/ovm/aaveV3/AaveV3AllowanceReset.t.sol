// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {Governance} from "../../../../contracts/Governance.sol";
import {IPoolLogic} from "../../../../contracts/interfaces/IPoolLogic.sol";
import {IERC20Extended} from "../../../../contracts/interfaces/IERC20Extended.sol";
import {AaveLendingPoolAssetGuard} from "../../../../contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";

interface IPoolLogicExtended is IPoolLogic {
  function execTransaction(address to, bytes calldata data) external returns (bool success);
}

contract AaveV3AllowanceResetTest is Test {
  IPoolLogicExtended public ETHBULL3X = IPoolLogicExtended(0x32b1D1bFd4B3b0CB9FF2DcD9DAc757aA64d4cb69);
  address public poolManager = 0x813123A13d01d3F07d434673Fdc89cBBA523f14d;
  IERC20Extended public usdc = IERC20Extended(OptimismConfig.USDC);
  address public aaveV3LendingPool = OptimismConfig.AAVE_V3_LENDING_POOL;

  address public dHEDGEAdminOptimism = 0x90b1a66957914EbbE7a8df254c0c1E455972379C;
  Governance public dHEDGEGovernance = Governance(0xa9F912c1dB1b844fd96192Ac3B496E9d8F445bc9);
  uint256 public poolTokensAmount = 100e18;

  uint256 public constant UNLIMITED_ALLOWANCE = type(uint256).max;
  uint256 public constant HUGE_ALLOWANCE = UNLIMITED_ALLOWANCE / 2;

  function setUp() public {
    vm.createSelectFork("optimism", 135430168);
    deal(address(ETHBULL3X), poolManager, poolTokensAmount);
  }

  function test_allowance_not_reset_after_withdrawal() public {
    _deployLatest();

    uint256 usdcAllowanceAfter = _getAllowanceAfterWithdrawal(HUGE_ALLOWANCE);
    assertEq(usdcAllowanceAfter, HUGE_ALLOWANCE, "allowance has changed");
  }

  function test_unlimited_allowance_does_not_halt_withdrawal() public {
    _deployLatest();

    uint256 usdcAllowanceAfter = _getAllowanceAfterWithdrawal(UNLIMITED_ALLOWANCE);

    assertLt(usdcAllowanceAfter, UNLIMITED_ALLOWANCE, "allowance not lt");
    assertGt(usdcAllowanceAfter, HUGE_ALLOWANCE, "allowance not gt");
  }

  function _getAllowanceAfterWithdrawal(uint256 _allowanceToUse) internal returns (uint256 allowanceAfter) {
    bytes memory data = abi.encodeWithSelector(usdc.approve.selector, aaveV3LendingPool, _allowanceToUse);
    vm.prank(poolManager);
    ETHBULL3X.execTransaction(address(usdc), data);
    assertEq(usdc.allowance(address(ETHBULL3X), aaveV3LendingPool), _allowanceToUse, "allowance set not correct");

    vm.prank(poolManager);
    ETHBULL3X.withdraw(poolTokensAmount);

    allowanceAfter = usdc.allowance(address(ETHBULL3X), aaveV3LendingPool);
  }

  function _deployLatest() internal {
    address newAssetGuardAddress = address(
      new AaveLendingPoolAssetGuard(
        aaveV3LendingPool,
        OptimismConfig.SWAPPER,
        OptimismConfig.LEGACY_ONCHAIN_SWAP_ROUTER,
        address(0),
        address(0),
        1,
        10000,
        10000
      )
    );

    vm.prank(dHEDGEAdminOptimism);
    dHEDGEGovernance.setAssetGuard(8, newAssetGuardAddress);
  }
}
