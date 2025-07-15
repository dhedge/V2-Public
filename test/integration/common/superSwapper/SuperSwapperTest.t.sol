// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DhedgeUniV3V2Router} from "contracts/routers/DhedgeUniV3V2Router.sol";
import {DhedgeSuperSwapper} from "contracts/routers/DhedgeSuperSwapper.sol";
import {IUniswapV2Router} from "contracts/interfaces/uniswapV2/IUniswapV2Router.sol";
import {IV3SwapRouter} from "contracts/interfaces/uniswapV3/IV3SwapRouter.sol";

abstract contract SuperSwapperTest is Test {
  string public network;
  address public uniV3Factory;
  address public uniV3Router;
  address[] public uniV2LikeRouters;
  address public tokenIn;
  uint256 public amountIn;
  address public tokenOut;
  address public trader = makeAddr("trader");

  // Contract instances
  DhedgeUniV3V2Router public uniV3V2Router;
  DhedgeSuperSwapper public superSwapper;

  constructor(
    string memory _network,
    address _uniV3Factory,
    address _uniV3Router,
    address[] memory _uniV2LikeRouters,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut
  ) {
    network = _network;
    uniV3Factory = _uniV3Factory;
    uniV3Router = _uniV3Router;
    uniV2LikeRouters = _uniV2LikeRouters;
    tokenIn = _tokenIn;
    amountIn = _amountIn;
    tokenOut = _tokenOut;
  }

  function setUp() public virtual {
    vm.createSelectFork(network);

    // Deploy DhedgeUniV3V2Router
    uniV3V2Router = new DhedgeUniV3V2Router(IUniswapV3Factory(uniV3Factory), IV3SwapRouter(uniV3Router));

    // Combine routers
    IUniswapV2Router[] memory routersToUse = new IUniswapV2Router[](uniV2LikeRouters.length + 1);
    for (uint256 i = 0; i < uniV2LikeRouters.length; i++) {
      routersToUse[i] = IUniswapV2Router(uniV2LikeRouters[i]);
    }
    routersToUse[uniV2LikeRouters.length] = IUniswapV2Router(address(uniV3V2Router));

    // Deploy DhedgeSuperSwapper
    superSwapper = new DhedgeSuperSwapper(routersToUse, new DhedgeSuperSwapper.RouteHint[](0));
  }

  function test_swapExactTokensForTokens_works_as_expected() public {
    // Setup: Fund the trader with tokens for swap
    deal(tokenIn, trader, amountIn);

    uint256 initialOutBalance = IERC20(tokenOut).balanceOf(trader);

    vm.startPrank(trader);

    IERC20(tokenIn).approve(address(superSwapper), amountIn);

    // Get expected output amount for comparison
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = tokenOut;

    uint256[] memory amountsOut = superSwapper.getAmountsOut(amountIn, path);
    uint256 expectedOutAmount = amountsOut[path.length - 1];

    uint256[] memory amounts = superSwapper.swapExactTokensForTokens(
      amountIn,
      expectedOutAmount,
      path,
      trader,
      block.timestamp + 60
    );

    uint256 finalOutBalance = IERC20(tokenOut).balanceOf(trader);
    uint256 actualReceived = finalOutBalance - initialOutBalance;

    assertGe(actualReceived, expectedOutAmount, "Received amount is less than minimum expected");
    assertEq(actualReceived, amounts[amounts.length - 1], "Returned amount does not match actual balance change");
    assertEq(IERC20(tokenIn).balanceOf(trader), 0, "Not all input tokens were spent");
  }
}
