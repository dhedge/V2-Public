// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {OdosV2ContractGuard} from "contracts/guards/contractGuards/odos/OdosV2ContractGuard.sol";
import {IOdosRouterV2} from "../../../../contracts/interfaces/odos/IOdosRouterV2.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {OdosAPIHelper} from "./OdosAPIHelper.sol";

abstract contract OdosV2ContractGuardTestSetup is BackboneSetup, OdosAPIHelper {
  address private immutable odosRouterV2;

  PoolLogic private testPool;
  PoolManagerLogic internal fundManagerLogic;
  OdosV2ContractGuard private odosV2ContractGuard;
  uint256 public chainId;

  constructor(address _odosRouterV2, uint256 _chainId) {
    odosRouterV2 = _odosRouterV2;
    chainId = _chainId;
  }

  function setUp() public virtual override {
    super.setUp();
    __OdosAPIHelper_init(true);

    vm.startPrank(owner);
    // Deploy the odos contract guard.
    odosV2ContractGuard = new OdosV2ContractGuard(address(slippageAccumulator));
    // Set the odos contract guard in the governance contract.
    governance.setContractGuard({extContract: odosRouterV2, guardAddress: address(odosV2ContractGuard)});

    // Create a test dHEDGE fund with USDC and WETH enabled as deposit asset.
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](2);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
    supportedAssets[1] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    vm.startPrank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "OdosTestVault",
        _fundSymbol: "OTV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _supportedAssets: supportedAssets
      })
    );
    fundManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    deal(usdcData.asset, manager, 20000e6);
    deal(wethData.asset, manager, 2e18);
    IERC20(usdcData.asset).approve(address(testPool), 10000e6);
    testPool.deposit(usdcData.asset, 10000e6);

    bytes memory approveCallData = abi.encodeWithSelector(IERC20.approve.selector, odosRouterV2, type(uint256).max);
    testPool.execTransaction(usdcData.asset, approveCallData);
    testPool.execTransaction(wethData.asset, approveCallData);
  }

  function _getSwapData(
    bool isCompact,
    address recipient,
    address srcToken,
    uint256 srcAmount
  ) internal returns (uint256 destAmount_, bytes memory calldata_) {
    uint8 slippage = 1;
    OdosAPIHelper.OdosFunctionStruct memory params = OdosAPIHelper.OdosFunctionStruct({
      srcAmount: srcAmount,
      srcToken: srcToken,
      destToken: wethData.asset,
      user: address(recipient),
      slippage: slippage
    });
    (destAmount_, calldata_) = getDataFromOdos(params, recipient, slippage, chainId, isCompact);
  }

  function test_revert_when_txguard_caller_is_not_pool_compact() public {
    _runTxGuardTest({isCompact: true, isAfterGuard: false});
  }
  function test_revert_when_txguard_caller_is_not_pool_non_compact() public {
    _runTxGuardTest({isCompact: false, isAfterGuard: false});
  }
  function test_revert_when_aftertxguard_caller_is_not_pool_compact() public {
    _runTxGuardTest({isCompact: true, isAfterGuard: true});
  }
  function test_revert_when_aftertxguard_caller_is_not_pool_non_compact() public {
    _runTxGuardTest({isCompact: false, isAfterGuard: true});
  }

  function _runTxGuardTest(bool isCompact, bool isAfterGuard) internal {
    vm.startPrank(manager);
    (, bytes memory swapdata) = _getSwapData(isCompact, address(testPool), usdcData.asset, 100e6);
    vm.expectRevert("not pool logic");
    if (isAfterGuard) {
      odosV2ContractGuard.afterTxGuard(address(fundManagerLogic), odosRouterV2, swapdata);
    } else {
      odosV2ContractGuard.txGuard(address(fundManagerLogic), odosRouterV2, swapdata);
    }
  }

  function test_revert_when_recipient_is_not_pool_compact() public {
    _runRecipientTest(true);
  }
  function test_revert_when_recipient_is_not_pool_non_compact() public {
    _runRecipientTest(false);
  }

  function _runRecipientTest(bool isCompact) internal {
    vm.startPrank(manager);
    (, bytes memory swapdata) = _getSwapData(isCompact, address(manager), usdcData.asset, 100e6);
    vm.expectRevert("recipient is not pool");
    testPool.execTransaction(odosRouterV2, swapdata);
  }

  function test_revert_when_input_token_is_native_eth_compact() public {
    _runNativeTokenTest(true);
  }
  function test_revert_when_input_token_is_native_eth_non_compact() public {
    _runNativeTokenTest(false);
  }

  function _runNativeTokenTest(bool isCompact) internal {
    vm.startPrank(manager);
    (, bytes memory swapdata) = _getSwapData(isCompact, address(testPool), address(0), 100e6);
    vm.expectRevert("invalid input token");
    testPool.execTransaction(odosRouterV2, swapdata);
  }

  function test_revert_when_input_amount_is_0_for_entire_balance_trade_compact() public {
    _runZeroAmountTest(true);
  }
  function test_revert_when_input_amount_is_0_for_entire_balance_trade_non_compact() public {
    _runZeroAmountTest(false);
  }

  function _wipeInputAmountInMemory(bytes memory data) public pure returns (bytes memory result) {
    assembly {
      // Get the length of the input data
      let len := mload(data)

      // Allocate memory for the result (32 bytes for length, then data length)
      result := mload(0x40) // Load the free memory pointer
      mstore(0x40, add(result, len)) // Update the free memory pointer to point past the allocated memory

      mstore(result, len) // Store the length of the result

      let dataStart := add(result, 0x20) // Start after the length word

      // Copy input data into the result
      mstore(dataStart, mload(add(data, 0x20))) // Copy the actual data

      // Locate the inputAmountLength byte
      let pos := 4 // Start after the function selector

      // Locate the input token address in memory
      {
        let inputPos := shr(240, mload(add(dataStart, pos)))
        switch inputPos
        case 0x0000 {
          pos := add(pos, 2)
        }
        case 0x0001 {
          pos := add(pos, 22)
        }
        default {
          pos := add(pos, 2)
        }
      }

      // Locate the output token address in memory
      {
        let inputPos := shr(240, mload(add(dataStart, pos)))
        switch inputPos
        case 0x0000 {
          pos := add(pos, 2)
        }
        case 0x0001 {
          pos := add(pos, 22)
        }
        default {
          pos := add(pos, 2)
        }
      }

      // Now at inputAmountLength byte
      let inputAmountLen := byte(0, mload(add(dataStart, pos)))

      // Check if inputAmountLength is 0
      if iszero(inputAmountLen) {
        // If inputAmountLength is 0, do nothing (full balance, no need to wipe)
        // We return the original result (no change needed)
        mstore(0x40, add(dataStart, len)) // reset free memory pointer
        return(result, len) // Return the result with no changes
      }

      // Zero out the entire input amount (up to 256 bits or 32 bytes)
      let inputAmountStart := add(dataStart, add(pos, 1)) // skip inputAmountLength byte
      for {
        let i := 0
      } lt(i, 32) {
        i := add(i, 1)
      } {
        mstore8(add(inputAmountStart, i), 0)
      }

      // Advance free memory pointer
      mstore(0x40, add(dataStart, len))

      // Return the modified result
      return(result, len)
    }
  }

  function _runZeroAmountTest(bool isCompact) internal {
    vm.startPrank(manager);
    (, bytes memory swapdata) = _getSwapData(isCompact, address(testPool), usdcData.asset, 10000e6);
    bytes memory mData;
    if (!isCompact) {
      bytes memory params = odosV2ContractGuard.getParams(swapdata);
      IOdosRouterV2.SwapTokenInfo memory swapTokenInfo = abi.decode(params, (IOdosRouterV2.SwapTokenInfo));
      swapTokenInfo.inputAmount = 0;

      bytes memory encodedData = abi.encode(swapTokenInfo);
      mData = abi.encodePacked(odosV2ContractGuard.getMethod(swapdata), encodedData);
    } else {
      mData = _wipeInputAmountInMemory(swapdata);
    }

    vm.expectRevert("invalid input amount");
    testPool.execTransaction(odosRouterV2, mData);
  }

  function test_revert_when_dest_token_is_not_supported_compact() public {
    _runDestTokenTest(true);
  }
  function test_revert_when_dest_token_is_not_supported_non_compact() public {
    _runDestTokenTest(false);
  }

  function _runDestTokenTest(bool isCompact) internal {
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory assets;
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = wethData.asset;
    fundManagerLogic.changeAssets(assets, removeAssets);
    (, bytes memory swapdata) = _getSwapData(isCompact, address(testPool), usdcData.asset, 100e6);

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(odosRouterV2, swapdata);
  }

  function test_swap_compact() public {
    _runSwapTest(true);
  }
  function test_swap_non_compact() public {
    _runSwapTest(false);
  }

  function _runSwapTest(bool isCompact) internal {
    vm.startPrank(manager);
    (, bytes memory swapdata) = _getSwapData(isCompact, address(testPool), usdcData.asset, 100e6);
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    testPool.execTransaction(odosRouterV2, swapdata);
    uint256 valueAfter = fundManagerLogic.totalFundValue();
    assertApproxEqRel(valueBefore, valueAfter, 0.1e18);
  }
}
