// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {IERC20Extended} from "../../../../contracts/interfaces/IERC20Extended.sol";
import {IAaveV3Pool} from "../../../../contracts/interfaces/aave/v3/IAaveV3Pool.sol";

interface IPoolLogic {
  function execTransaction(address to, bytes calldata data) external returns (bool success);
}

contract AaveV3LiquidatableTest is Test {
  IPoolLogic public pool = IPoolLogic(0x749E1d46C83f09534253323A43541A9d2bBD03AF);
  address public managerAddress = 0xeFc4904b786A3836343A3A504A2A3cb303b77D64;

  IAaveV3Pool public aaveLendingPool = IAaveV3Pool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

  IERC20Extended public weth = IERC20Extended(0x4200000000000000000000000000000000000006);
  IERC20Extended public usdc = IERC20Extended(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);

  string public optimismRpcURL = vm.envString("OPTIMISM_URL");

  function setUp() public {
    vm.createSelectFork(optimismRpcURL, 121348913); // Jun-13-2024 04:36:43 PM +UTC
  }

  function testLiquidationAave() public {
    // First, simulate the pool getting 100 WETH
    deal(address(weth), address(pool), 100e18);
    assertEq(weth.balanceOf(address(pool)), 100e18);

    // Approve 100 WETH to the Aave lending pool
    bytes memory data = abi.encodeWithSelector(weth.approve.selector, address(aaveLendingPool), 100e18);
    vm.prank(managerAddress);
    pool.execTransaction(address(weth), data);

    // Supply 100 WETH to the Aave lending pool
    data = abi.encodeWithSelector(aaveLendingPool.deposit.selector, address(weth), 100e18, address(pool), 0);
    vm.prank(managerAddress);
    pool.execTransaction(address(aaveLendingPool), data);

    // Borrow the maximum USDC possible with the 100 WETH
    data = abi.encodeWithSelector(aaveLendingPool.borrow.selector, address(usdc), 275_000e6, 2, 0, address(pool));
    vm.prank(managerAddress);
    pool.execTransaction(address(aaveLendingPool), data);

    // Withdraw the maximum WETH possible
    data = abi.encodeWithSelector(aaveLendingPool.withdraw.selector, address(weth), 3.5354266145e18, address(pool));
    vm.prank(managerAddress);
    pool.execTransaction(address(aaveLendingPool), data);

    // Fast forward 1 block (Optimism)
    vm.warp(block.timestamp + 2);

    // The position is now liquidatable
    (, , , , , uint256 healthFactor) = aaveLendingPool.getUserAccountData(address(pool));
    assertLt(healthFactor, 1e18);

    deal(address(usdc), managerAddress, 200_000e6);
    uint256 wethBalanceBefore = weth.balanceOf(managerAddress);

    vm.prank(managerAddress);
    usdc.approve(address(aaveLendingPool), type(uint256).max);

    vm.prank(managerAddress);
    aaveLendingPool.liquidationCall(address(weth), address(usdc), address(pool), type(uint256).max, false);

    uint256 wethBalanceAfter = weth.balanceOf(managerAddress);
    assertGt(wethBalanceAfter, wethBalanceBefore);
  }
}
