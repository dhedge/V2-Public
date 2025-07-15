// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {WithdrawalVault} from "contracts/swappers/easySwapperV2/WithdrawalVault.sol";

/// @dev Test suites to reproduce ths issue during unroll step and to verify the fix
contract VelodromeCLUnrollTest is Test {
  address public depositor = 0x0385e595a27E2F2Fb3B481D26b48F781A4290bA8;
  address public pool = 0x423582AfB8e8693a427Bf67d76aDf9f6A8E33124;
  address public easySwapperV2Prod = 0x2Ed1bd7f66e47113672f3870308b5E867C5bb743;
  uint256 public balance;

  function setUp() public {
    // Changing block number for these tests makes them useless; do not change it
    vm.createSelectFork("optimism", 136328663);

    balance = IERC20(pool).balanceOf(depositor);
  }

  function test_revert_when_trying_to_unroll() public {
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(pool);

    vm.prank(depositor);
    vm.expectRevert();
    EasySwapperV2(easySwapperV2Prod).initWithdrawal(pool, balance, complexAssetsData);
  }

  function test_can_init_withdrawal_successfully() public {
    address withdrawalVault = address(new WithdrawalVault());

    vm.prank(EasySwapperV2(easySwapperV2Prod).owner());
    EasySwapperV2(easySwapperV2Prod).setLogic(withdrawalVault);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(pool);

    vm.prank(depositor);
    EasySwapperV2(easySwapperV2Prod).initWithdrawal(pool, balance, complexAssetsData);

    uint256 balanceAfter = IERC20(pool).balanceOf(depositor);
    assertEq(balanceAfter, 0, "Balance after initWithdrawal should be zero");
  }

  function _getEmptyPoolComplexAssetsData(
    address _pool
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    complexAssetsData = new IPoolLogic.ComplexAsset[](
      IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic()).getSupportedAssets().length
    );
  }
}
