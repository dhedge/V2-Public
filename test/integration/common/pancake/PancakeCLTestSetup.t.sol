// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPancakeMasterChefV3} from "contracts/interfaces/pancake/IPancakeMasterChefV3.sol";
import {PancakeNonfungiblePositionGuard} from "contracts/guards/contractGuards/pancake/PancakeNonfungiblePositionGuard.sol";
import {PancakeMasterChefV3Guard} from "contracts/guards/contractGuards/pancake/PancakeMasterChefV3Guard.sol";
import {IPancakeNonfungiblePositionManager} from "contracts/interfaces/pancake/IPancakeNonfungiblePositionManager.sol";
import {PancakeCLAssetGuard} from "contracts/guards/assetGuards/pancake/PancakeCLAssetGuard.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {PancakeCLPositionValue} from "contracts/utils/pancake/PancakeCLPositionValue.sol";
import {IPancakeCLPool} from "contracts/interfaces/pancake/IPancakeCLPool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IHasAssetInfo} from "contracts/interfaces/IHasAssetInfo.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract PancakeCLTestSetup is BackboneSetup {
  using PancakeCLPositionValue for IPancakeNonfungiblePositionManager;

  // Test contracts and addresses
  address[] internal accounts = [manager, investor];

  // Deposit tokens
  address internal immutable USDCAddr;
  IERC20 internal immutable USDC;
  address internal immutable WETHAddr;
  IERC20 internal immutable WETH;

  // Pancake specific addresses and contracts
  address internal immutable NFTPositionManagerAddr;
  address internal immutable MasterChefAddr;
  address internal immutable CAKEAddr;
  IERC20 internal immutable CAKE;
  IPancakeNonfungiblePositionManager internal immutable nonfungiblePositionManager;

  PoolLogic internal fund;
  PoolManagerLogic internal fundManagerLogic;
  PancakeNonfungiblePositionGuard internal pancakeContractGuard;
  PancakeCLAssetGuard internal pancakeAssetGuard;
  PancakeMasterChefV3Guard internal pancakeMasterChefV3Guard;

  constructor(address _nFTPositionManagerAddr, address _masterChefAddr, address _cAKEAddr) {
    USDCAddr = usdcData.asset;
    USDC = IERC20(usdcData.asset);
    WETHAddr = wethData.asset;
    WETH = IERC20(wethData.asset);

    NFTPositionManagerAddr = _nFTPositionManagerAddr;
    MasterChefAddr = _masterChefAddr;
    CAKEAddr = _cAKEAddr;
    CAKE = IERC20(_cAKEAddr);
    nonfungiblePositionManager = IPancakeNonfungiblePositionManager(_nFTPositionManagerAddr);
  }

  function setUp() public virtual override {
    super.setUp();
    vm.startPrank(owner);
    // Deploy the Pancake CL contract and asset guards.
    pancakeContractGuard = new PancakeNonfungiblePositionGuard(address(nftTrackerStorageProxy), MasterChefAddr);
    pancakeMasterChefV3Guard = new PancakeMasterChefV3Guard(address(nftTrackerStorageProxy));
    pancakeAssetGuard = new PancakeCLAssetGuard(MasterChefAddr);

    // Set the Pancake CL asset guard in the governance contract.
    governance.setAssetGuard({
      assetType: uint16(AssetTypeIncomplete.PANCAKE_CL),
      guardAddress: address(pancakeAssetGuard)
    });

    // Set the Pancake CL contract guard in the governance contract.
    governance.setContractGuard({extContract: NFTPositionManagerAddr, guardAddress: address(pancakeContractGuard)});
    governance.setContractGuard({extContract: MasterChefAddr, guardAddress: address(pancakeMasterChefV3Guard)});

    // Create a test dHEDGE fund with USDC and WETH enabled as deposit asset.
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](3);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: USDCAddr, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: WETHAddr, isDeposit: true});
    supportedAssets[2] = IHasSupportedAsset.Asset({asset: NFTPositionManagerAddr, isDeposit: false});

    // Add assets to the asset handler.
    assetHandlerProxy.addAsset({
      asset: NFTPositionManagerAddr,
      assetType: uint16(AssetTypeIncomplete.PANCAKE_CL),
      aggregator: address(usdPriceAggregator)
    });

    vm.startPrank(manager);

    fund = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "manager",
        _fundName: "PancakeCLTest",
        _fundSymbol: "PCT",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );

    fundManagerLogic = PoolManagerLogic(fund.poolManagerLogic());

    _dealTokens();
    USDC.approve(address(fund), type(uint256).max);
    WETH.approve(address(fund), type(uint256).max);

    fund.deposit(USDCAddr, 2_000e6);
    fund.deposit(WETHAddr, 2e18);
  }

  function test_pancakeCL_mint_and_stake() public {
    // Make a deposit into the fund.
    vm.startPrank(manager);

    uint256 valueBefore = fundManagerLogic.totalFundValue();

    uint256 tokenId = _mint();

    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertApproxEqRel(valueBefore, valueAfter, 0.1e18);

    _stake(tokenId);

    uint256 valueAfterStake = fundManagerLogic.totalFundValue();
    assertEq(valueAfter, valueAfterStake);
  }

  function test_pancakeCL_transfer_to_other_address() public {
    // Make a deposit into the fund.
    vm.startPrank(manager);

    uint256 tokenId = _mint();
    //transfer to manager
    bytes memory safeTransferCallData = abi.encodeWithSelector(
      bytes4(keccak256("safeTransferFrom(address,address,uint256)")),
      address(fund),
      manager,
      tokenId
    );
    vm.expectRevert(bytes("to is not staking address"));
    fund.execTransaction(NFTPositionManagerAddr, safeTransferCallData);
  }

  function test_pancakeCL_transfer_from_other_address() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    //transfer from wrong address
    bytes memory safeTransferCallData = abi.encodeWithSelector(
      bytes4(keccak256("safeTransferFrom(address,address,uint256)")),
      manager,
      MasterChefAddr,
      tokenId
    );
    vm.expectRevert(bytes("from is not pool"));
    fund.execTransaction(NFTPositionManagerAddr, safeTransferCallData);
  }

  function test_pancakeCL_mint_and_increase() public {
    // Make a deposit into the fund.
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    IPancakeNonfungiblePositionManager.IncreaseLiquidityParams memory params = IPancakeNonfungiblePositionManager
      .IncreaseLiquidityParams({
        tokenId: tokenId,
        amount0Desired: 1e18,
        amount1Desired: 1_000e6,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory increaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.increaseLiquidity.selector,
      params
    );
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    fund.execTransaction(NFTPositionManagerAddr, increaseCallData);
    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertApproxEqRel(valueBefore, valueAfter, 0.1e18);
  }

  function test_pancakeCL_increase_other_position() public {
    // Make a deposit into the fund.
    vm.startPrank(manager);
    _mint();
    IPancakeNonfungiblePositionManager.IncreaseLiquidityParams memory params = IPancakeNonfungiblePositionManager
      .IncreaseLiquidityParams({
        tokenId: 232951,
        amount0Desired: 1e18,
        amount1Desired: 1_000e6,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory increaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.increaseLiquidity.selector,
      params
    );
    vm.expectRevert(bytes("position is not in track"));
    fund.execTransaction(NFTPositionManagerAddr, increaseCallData);
  }

  function test_pancakeCL_mint_and_decrease() public {
    // Make a deposit into the fund.
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 usdcBalanceBefore = USDC.balanceOf(address(fund));
    uint256 wethBalanceBefore = WETH.balanceOf(address(fund));
    (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
    IPancakeNonfungiblePositionManager.DecreaseLiquidityParams
      memory decreaseParams = IPancakeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity / 2,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory decreaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.decreaseLiquidity.selector,
      decreaseParams
    );

    IPancakeNonfungiblePositionManager.CollectParams memory collectParams = IPancakeNonfungiblePositionManager
      .CollectParams({
        tokenId: tokenId,
        recipient: address(fund),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      });
    bytes memory collectCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.collect.selector,
      collectParams
    );

    bytes[] memory calls = new bytes[](2);
    calls[0] = decreaseCallData;
    calls[1] = collectCallData;

    bytes memory multicallData = abi.encodeWithSelector(IMulticall.multicall.selector, calls);
    fund.execTransaction(NFTPositionManagerAddr, multicallData);

    uint256 valueAfter = fundManagerLogic.totalFundValue();

    assertApproxEqRel(valueBefore, valueAfter, 0.1e18);
    assertGt(USDC.balanceOf(address(fund)), usdcBalanceBefore);
    assertGt(WETH.balanceOf(address(fund)), wethBalanceBefore);
  }

  function test_pancakeCL_mint_and_burn() public {
    // Make a deposit into the fund.
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
    IPancakeNonfungiblePositionManager.DecreaseLiquidityParams
      memory decreaseParams = IPancakeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory decreaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.decreaseLiquidity.selector,
      decreaseParams
    );

    IPancakeNonfungiblePositionManager.CollectParams memory collectParams = IPancakeNonfungiblePositionManager
      .CollectParams({
        tokenId: tokenId,
        recipient: address(fund),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      });
    bytes memory collectCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.collect.selector,
      collectParams
    );

    bytes memory burnCallData = abi.encodeWithSelector(IPancakeNonfungiblePositionManager.burn.selector, tokenId);

    bytes[] memory calls = new bytes[](3);
    calls[0] = decreaseCallData;
    calls[1] = collectCallData;
    calls[2] = burnCallData;

    bytes memory multicallData = abi.encodeWithSelector(IMulticall.multicall.selector, calls);
    fund.execTransaction(NFTPositionManagerAddr, multicallData);

    uint256 valueAfter = fundManagerLogic.totalFundValue();

    assertApproxEqRel(valueBefore, valueAfter, 0.1e18);
    //no token left after burn
    vm.expectRevert(bytes("EnumerableSet: index out of bounds"));
    nonfungiblePositionManager.tokenOfOwnerByIndex(address(fund), 0);
  }

  function test_pancakeCL_collect_from_staked() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    IPancakeNonfungiblePositionManager.CollectParams memory params = IPancakeNonfungiblePositionManager.CollectParams({
      tokenId: tokenId,
      recipient: address(fund),
      amount0Max: type(uint128).max,
      amount1Max: type(uint128).max
    });
    bytes memory collectCallData = abi.encodeWithSelector(IPancakeNonfungiblePositionManager.collect.selector, params);
    fund.execTransaction(MasterChefAddr, collectCallData);
  }

  function test_pancakeCL_decrease_from_staked() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
    IPancakeNonfungiblePositionManager.DecreaseLiquidityParams
      memory decreaseParams = IPancakeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity / 2,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory decreaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.decreaseLiquidity.selector,
      decreaseParams
    );

    IPancakeNonfungiblePositionManager.CollectParams memory collectParams = IPancakeNonfungiblePositionManager
      .CollectParams({
        tokenId: tokenId,
        recipient: address(fund),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      });
    bytes memory collectCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.collect.selector,
      collectParams
    );
    bytes memory harvestCallData = abi.encodeWithSelector(
      IPancakeMasterChefV3.harvest.selector,
      tokenId,
      address(fund)
    );
    bytes[] memory calls = new bytes[](3);
    calls[0] = decreaseCallData;
    calls[1] = collectCallData;
    calls[2] = harvestCallData;

    bytes memory multicallData = abi.encodeWithSelector(IMulticall.multicall.selector, calls);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    uint256 usdcBalanceBefore = USDC.balanceOf(address(fund));
    fund.execTransaction(MasterChefAddr, multicallData);
    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertApproxEqRel(valueBefore, valueAfter, 0.1e18);
    assertGt(USDC.balanceOf(address(fund)), usdcBalanceBefore);
  }

  function test_pancakeCL_decrease_without_collect_last() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
    IPancakeNonfungiblePositionManager.DecreaseLiquidityParams
      memory decreaseParams = IPancakeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity / 2,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory decreaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.decreaseLiquidity.selector,
      decreaseParams
    );

    bytes memory harvestCallData = abi.encodeWithSelector(
      IPancakeMasterChefV3.harvest.selector,
      tokenId,
      address(fund)
    );
    bytes[] memory calls = new bytes[](2);
    calls[0] = decreaseCallData;
    calls[1] = harvestCallData;

    bytes memory multicallData = abi.encodeWithSelector(IMulticall.multicall.selector, calls);
    vm.expectRevert(bytes("no collect after decrease"));
    fund.execTransaction(MasterChefAddr, multicallData);
  }

  function test_pancakeCL_decrease_only() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
    IPancakeNonfungiblePositionManager.DecreaseLiquidityParams
      memory decreaseParams = IPancakeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity / 2,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory decreaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.decreaseLiquidity.selector,
      decreaseParams
    );

    vm.expectRevert(bytes("invalid transaction"));
    fund.execTransaction(MasterChefAddr, decreaseCallData);

    bytes[] memory calls = new bytes[](1);
    calls[0] = decreaseCallData;

    bytes memory multicallData = abi.encodeWithSelector(IMulticall.multicall.selector, calls);
    vm.expectRevert(bytes("no collect after decrease"));
    fund.execTransaction(MasterChefAddr, multicallData);
  }

  function test_pancakeCL_burn_from_staked() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
    IPancakeNonfungiblePositionManager.DecreaseLiquidityParams
      memory decreaseParams = IPancakeNonfungiblePositionManager.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp + 1000
      });
    bytes memory decreaseCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.decreaseLiquidity.selector,
      decreaseParams
    );

    IPancakeNonfungiblePositionManager.CollectParams memory collectParams = IPancakeNonfungiblePositionManager
      .CollectParams({
        tokenId: tokenId,
        recipient: address(fund),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      });
    bytes memory collectCallData = abi.encodeWithSelector(
      IPancakeNonfungiblePositionManager.collect.selector,
      collectParams
    );
    bytes memory harvestCallData = abi.encodeWithSelector(
      IPancakeMasterChefV3.harvest.selector,
      tokenId,
      address(fund)
    );
    bytes memory burnCallData = abi.encodeWithSelector(IPancakeNonfungiblePositionManager.burn.selector, tokenId);
    bytes[] memory calls = new bytes[](4);
    calls[0] = harvestCallData;
    calls[1] = decreaseCallData;
    calls[2] = collectCallData;
    calls[3] = burnCallData;

    bytes memory multicallData = abi.encodeWithSelector(IMulticall.multicall.selector, calls);
    uint256 valueBefore = fundManagerLogic.totalFundValue();

    fund.execTransaction(MasterChefAddr, multicallData);
    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertApproxEqRel(valueBefore, valueAfter, 0.1e18);
    //no token left after burn
    vm.expectRevert(bytes("Invalid token ID"));
    nonfungiblePositionManager.positions(tokenId);
  }

  function test_pancakeCL_harvest_reward() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    skip(1 days);
    bytes memory harvestCallData = abi.encodeWithSelector(
      IPancakeMasterChefV3.harvest.selector,
      tokenId,
      address(fund)
    );
    fund.execTransaction(MasterChefAddr, harvestCallData);
    //no rewards in current setup
    // uint256 balance = CAKE.balanceOf(address(fund));
    // assertGt(balance, 0);
  }

  function test_pancakeCL_unstake() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    bytes memory withdrawCallData = abi.encodeWithSelector(
      IPancakeMasterChefV3.withdraw.selector,
      tokenId,
      address(fund)
    );
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    fund.execTransaction(MasterChefAddr, withdrawCallData);
    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertEq(valueBefore, valueAfter);
  }

  function test_pancakeCL_withdraw_after_minted() public {
    vm.startPrank(manager);
    _mint();
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 poolBalance = IERC20(address(fund)).balanceOf(manager);
    skip(1 days);
    uint256 balanceWETHBefore = WETH.balanceOf(manager);
    uint256 balanceUSDCBefore = USDC.balanceOf(manager);
    fund.withdraw(poolBalance / 2);
    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertApproxEqRel(valueBefore / 2, valueAfter, 0.1e18);
    uint256 balanceWETHAfter = WETH.balanceOf(manager);
    uint256 balanceUSDCAfter = USDC.balanceOf(manager);
    assertGt(balanceWETHAfter, balanceWETHBefore);
    uint256 totalValueReceived = _assetValue(
      address(poolFactoryProxy),
      WETHAddr,
      balanceWETHAfter - balanceWETHBefore
    ) + _assetValue(address(poolFactoryProxy), USDCAddr, balanceUSDCAfter - balanceUSDCBefore);
    assertApproxEqRel(valueBefore / 2, totalValueReceived, 0.1e18);
  }

  function test_pancakeCL_withdraw_after_staked() public {
    vm.startPrank(manager);
    uint256 tokenId = _mint();
    _stake(tokenId);
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 poolBalance = IERC20(address(fund)).balanceOf(manager);
    skip(1 days);
    uint256 balanceWETHBefore = WETH.balanceOf(manager);
    uint256 balanceUSDCBefore = USDC.balanceOf(manager);
    fund.withdraw(poolBalance / 2);
    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertApproxEqRel(valueBefore / 2, valueAfter, 0.1e18);
    uint256 balanceWETHAfter = WETH.balanceOf(manager);
    uint256 balanceUSDCAfter = USDC.balanceOf(manager);
    assertGt(balanceWETHAfter, balanceWETHBefore);
    uint256 totalValueReceived = _assetValue(
      address(poolFactoryProxy),
      WETHAddr,
      balanceWETHAfter - balanceWETHBefore
    ) + _assetValue(address(poolFactoryProxy), USDCAddr, balanceUSDCAfter - balanceUSDCBefore);
    assertApproxEqRel(valueBefore / 2, totalValueReceived, 0.1e18);
  }

  function _dealTokens() internal {
    for (uint256 i; i < accounts.length; ++i) {
      deal(accounts[i], 100e18);
      deal(USDCAddr, accounts[i], 2_000e6);
      deal(WETHAddr, accounts[i], 2e18);
    }
  }

  function _mint() internal returns (uint256 tokenId) {
    int24 tick = _getCurrentTick(address(WETH), address(USDC), 100);
    IPancakeNonfungiblePositionManager.MintParams memory params = IPancakeNonfungiblePositionManager.MintParams({
      token0: address(WETH),
      token1: address(USDC),
      fee: 100,
      tickLower: tick - 100,
      tickUpper: tick + 100,
      amount0Desired: 1e18,
      amount1Desired: 1_000e6,
      amount0Min: 0,
      amount1Min: 0,
      recipient: address(fund),
      deadline: block.timestamp + 1000
    });

    bytes memory approveCallData = abi.encodeWithSelector(
      IERC20.approve.selector,
      NFTPositionManagerAddr,
      type(uint256).max
    );
    bytes memory mintCallData = abi.encodeWithSelector(IPancakeNonfungiblePositionManager.mint.selector, params);

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](3);
    txs[0] = PoolLogic.TxToExecute({to: address(USDC), data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: address(WETH), data: approveCallData});
    txs[2] = PoolLogic.TxToExecute({to: NFTPositionManagerAddr, data: mintCallData});

    fund.execTransactions(txs);
    tokenId = nonfungiblePositionManager.tokenOfOwnerByIndex(address(fund), 0);
  }

  function _stake(uint256 tokenId) internal {
    //stake NFT position
    bytes memory safeTransferCallData = abi.encodeWithSelector(
      bytes4(keccak256("safeTransferFrom(address,address,uint256)")),
      address(fund),
      MasterChefAddr,
      tokenId
    );
    fund.execTransaction(NFTPositionManagerAddr, safeTransferCallData);
  }

  function _getCurrentTick(address token0, address token1, uint24 fee) internal view returns (int24) {
    (, int24 tick, , , , , ) = IPancakeCLPool(
      IUniswapV3Factory(nonfungiblePositionManager.factory()).getPool(token0, token1, fee)
    ).slot0();
    return tick;
  }

  function _assetValue(address factory, address token, uint256 amount) internal view returns (uint256) {
    uint256 tokenPriceInUsd = IHasAssetInfo(factory).getAssetPrice(token);
    return (tokenPriceInUsd * amount) / (10 ** IERC20Extended(token).decimals());
  }
}
