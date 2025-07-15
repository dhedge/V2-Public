// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {AcrossContractGuard} from "contracts/guards/contractGuards/across/AcrossContractGuard.sol";
import {V3SpokePoolInterface} from "contracts/interfaces/across/V3SpokePoolInterface.sol";

import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

abstract contract AcrossContractGuardTestSetup is BackboneSetup {
  address private immutable spokePool;
  address private immutable approvedDestToken;
  uint256 private immutable approvedDestChainId;

  address private destinationPoolA = makeAddr("destinationPoolA");
  address private destinationPoolB = makeAddr("destinationPoolB");

  PoolLogic private testPool;
  AcrossContractGuard private acrossContractGuard;

  constructor(address _spokePool, address _approvedDestToken, uint256 _approvedDestChainId) {
    spokePool = _spokePool;
    approvedDestToken = _approvedDestToken;
    approvedDestChainId = _approvedDestChainId;
  }

  function setUp() public virtual override {
    super.setUp();

    // Create a test dHEDGE pool with USDC enabled as deposit asset.
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.startPrank(manager);

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "AcrossVault",
        _fundSymbol: "AV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );

    deal(usdcData.asset, manager, 10000e6);
    IERC20(usdcData.asset).approve(address(testPool), 10000e6);
    testPool.deposit(usdcData.asset, 10000e6);

    vm.startPrank(owner);

    AcrossContractGuard.CrossChainBridge[] memory settings = new AcrossContractGuard.CrossChainBridge[](3);
    settings[0] = AcrossContractGuard.CrossChainBridge({
      sourcePool: address(testPool),
      destinationPool: destinationPoolA,
      sourceToken: usdcData.asset,
      destinationToken: approvedDestToken,
      destinationChainId: approvedDestChainId
    });
    settings[1] = AcrossContractGuard.CrossChainBridge({
      sourcePool: address(testPool),
      destinationPool: destinationPoolB,
      sourceToken: wethData.asset,
      destinationToken: address(0),
      destinationChainId: PolygonConfig.CHAIN_ID
    });
    settings[2] = AcrossContractGuard.CrossChainBridge({
      sourcePool: address(testPool),
      destinationPool: destinationPoolA,
      sourceToken: usdcData.asset,
      destinationToken: address(0),
      destinationChainId: approvedDestChainId
    });

    // Deploy the Across contract guard.
    acrossContractGuard = new AcrossContractGuard(settings);

    // Set the Across contract guard in the governance contract.
    governance.setContractGuard({extContract: spokePool, guardAddress: address(acrossContractGuard)});
  }

  function test_manager_can_call_depositv3_if_whitelisted_explicit_dest_token() public {
    vm.startPrank(manager);

    uint256 usdcBalanceOfPoolBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, spokePool, usdcBalanceOfPoolBefore);
    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      destinationPoolA,
      usdcData.asset,
      approvedDestToken,
      usdcBalanceOfPoolBefore,
      usdcBalanceOfPoolBefore,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdcData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: spokePool, data: supplyCallData});

    testPool.execTransactions(txs);

    uint256 usdcBalanceOfPoolAfter = IERC20(usdcData.asset).balanceOf(address(testPool));
    assertEq(usdcBalanceOfPoolAfter, 0, "USDC balance of pool should be 0 after depositV3");
  }

  function test_manager_can_call_depositv3_if_whitelisted_implicit_dest_token() public {
    vm.startPrank(manager);

    uint256 usdcBalanceOfPoolBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, spokePool, usdcBalanceOfPoolBefore);
    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      destinationPoolA,
      usdcData.asset,
      address(0),
      usdcBalanceOfPoolBefore,
      usdcBalanceOfPoolBefore,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);
    txs[0] = PoolLogic.TxToExecute({to: usdcData.asset, data: approveCallData});
    txs[1] = PoolLogic.TxToExecute({to: spokePool, data: supplyCallData});

    testPool.execTransactions(txs);

    uint256 usdcBalanceOfPoolAfter = IERC20(usdcData.asset).balanceOf(address(testPool));
    assertEq(usdcBalanceOfPoolAfter, 0, "USDC balance of pool should be 0 after depositV3");
  }

  function test_revert_when_manager_call_invalid() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.speedUpV3Deposit.selector,
      testPool,
      0,
      0,
      address(0),
      new bytes(0),
      new bytes(0)
    );

    vm.expectRevert("invalid transaction");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_depositor_not_pool() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      manager,
      destinationPoolA,
      usdcData.asset,
      approvedDestToken,
      0,
      0,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("depositor is not pool");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_input_token_not_supported() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      destinationPoolB,
      wethData.asset,
      address(0),
      0,
      0,
      PolygonConfig.CHAIN_ID,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("unsupported src token");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_custom_dst_token() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      destinationPoolA,
      usdcData.asset,
      wethData.asset,
      0,
      0,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("not approved");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_bridging_fees_too_high() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      destinationPoolA,
      usdcData.asset,
      approvedDestToken,
      10000e6,
      0,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("output too low");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_not_approved_destination_source_token() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      destinationPoolA,
      wethData.asset,
      address(0),
      0,
      0,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("not approved");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_not_approved_destination_chainId() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      destinationPoolA,
      usdcData.asset,
      address(0),
      0,
      0,
      1,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("not approved");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_not_approved_destination_pool() public {
    vm.startPrank(manager);

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      testPool,
      makeAddr("destinationPoolC"),
      usdcData.asset,
      address(0),
      0,
      0,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("not approved");
    testPool.execTransaction(spokePool, supplyCallData);
  }

  function test_revert_when_not_approved_source_pool() public {
    vm.startPrank(manager);

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    PoolLogic newPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "AcrossVault",
        _fundSymbol: "AV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );

    bytes memory supplyCallData = abi.encodeWithSelector(
      V3SpokePoolInterface.depositV3.selector,
      address(newPool),
      destinationPoolA,
      usdcData.asset,
      address(0),
      0,
      0,
      approvedDestChainId,
      address(0),
      block.timestamp,
      0,
      0,
      new bytes(0)
    );

    vm.expectRevert("not approved");
    newPool.execTransaction(spokePool, supplyCallData);
  }
}
