// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EasyLimitBuyTestSetup} from "test/integration/common/limitOrders/limitBuys/EasyLimitBuyTestSetup.t.sol";
import {OdosAPIHelper} from "test/integration/common/odos/OdosAPIHelper.sol";

import {EasyLimitBuyManager} from "contracts/limitOrders/EasyLimitBuyManager.sol";
import {EasyLimitBuyTypeHashLib} from "contracts/limitOrders/EasyLimitBuyTypeHashLib.sol";
import {ISignatureTransfer} from "contracts/interfaces/permit2/ISignatureTransfer.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IEasySwapperV2} from "contracts/swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/// @notice Abstract test setup for EasyLimitBuyManager zap tests with Odos integration
/// @dev Requires FFI to fetch swap data from Odos API
abstract contract EasyLimitBuyZapTestSetup is EasyLimitBuyTestSetup, OdosAPIHelper {
  // ============ Zap-specific Config ============

  /// @notice Non-deposit asset for testing zap (e.g., WETH when vault accepts USDC)
  address public zapInputToken;

  /// @notice Amount of zap input token for testing
  uint256 public zapInputAmount;

  /// @notice Chain ID for Odos API
  uint256 public chainId;

  constructor(
    address _poolFactory,
    address _usdc,
    address _targetVault,
    address _pricingAsset,
    address _easySwapperV2,
    address _zapInputToken,
    uint256 _zapInputAmount,
    uint256 _chainId
  ) EasyLimitBuyTestSetup(_poolFactory, _usdc, _targetVault, _pricingAsset, _easySwapperV2) {
    zapInputToken = _zapInputToken;
    zapInputAmount = _zapInputAmount;
    chainId = _chainId;
  }

  function setUp() public virtual override {
    super.setUp();
    __OdosAPIHelper_init(true);

    // Give user the zap input token
    deal(zapInputToken, user, zapInputAmount * 10);

    // User approves Permit2 to spend the zap input token
    vm.prank(user);
    IERC20(zapInputToken).approve(EthereumConfig.PERMIT2, type(uint256).max);
  }

  // ============================================
  // InvalidDepositAssetConfig Tests
  // ============================================

  /// @notice Test with no zap but input token is not deposit asset
  function test_revert_no_zap_input_not_deposit_asset() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Create execution with non-deposit token but no swap data (empty zap)
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedZapExecution(
      zapInputToken,
      zapInputAmount,
      currentPrice > 100e18 ? currentPrice - 100e18 : 0,
      currentPrice + 100e18,
      DEFAULT_SLIPPAGE_BPS,
      EasyLimitBuyManager.ZapData({
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32(0), swapData: ""}),
        destData: ISwapper.DestData({destToken: IERC20(address(0)), minDestAmount: 0})
      })
    );

    vm.prank(keeper);
    // Reverts because input is not deposit asset and no zap data provided
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.InvalidDepositAssetConfig.selector,
        false, // useZap
        zapInputToken,
        address(0), // zapDestToken
        false // inputIsDepositAsset
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice Test with zap but input token IS deposit asset (should just deposit directly)
  function test_revert_zap_input_is_deposit_asset() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Use dummy swap data (not calling Odos API since same-token swaps would fail)
    // The validation happens before the swap, so we just need any non-empty swap data
    bytes memory swapData = hex"deadbeef";

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedZapExecutionWithToken(
      usdc,
      USER_DEPOSIT_AMOUNT,
      currentPrice > 100e18 ? currentPrice - 100e18 : 0,
      currentPrice + 100e18,
      DEFAULT_SLIPPAGE_BPS,
      _buildZapData(usdc, swapData)
    );

    vm.prank(keeper);
    // Reverts because input IS deposit asset but swap data was provided
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.InvalidDepositAssetConfig.selector,
        true, // useZap
        usdc,
        usdc, // zapDestToken
        true // inputIsDepositAsset
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  /// @notice Test with zap but dest token is not deposit asset
  function test_revert_zap_dest_not_deposit_asset() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Get swap data for zapInputToken -> zapInputToken (wrong dest)
    (, bytes memory swapData) = _getOdosSwapData(zapInputToken, zapInputAmount);

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedZapExecution(
      zapInputToken,
      zapInputAmount,
      currentPrice > 100e18 ? currentPrice - 100e18 : 0,
      currentPrice + 100e18,
      DEFAULT_SLIPPAGE_BPS,
      EasyLimitBuyManager.ZapData({
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32("ODOS_V3"), swapData: swapData}),
        destData: ISwapper.DestData({destToken: IERC20(zapInputToken), minDestAmount: 0}) // Wrong: dest is not deposit asset
      })
    );

    vm.prank(keeper);
    // Reverts because dest token is not deposit asset
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.InvalidDepositAssetConfig.selector,
        true, // useZap
        zapInputToken,
        zapInputToken, // zapDestToken (same as input - not deposit asset)
        false // inputIsDepositAsset
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  // ============================================
  // Empty Swap Data Tests
  // ============================================

  /// @notice Test with empty swap data when zap is needed (input not deposit asset)
  function test_revert_empty_swap_data_when_zap_needed() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Create order with non-deposit token but no swap data
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedZapExecution(
      zapInputToken,
      zapInputAmount,
      currentPrice > 100e18 ? currentPrice - 100e18 : 0,
      currentPrice + 100e18,
      DEFAULT_SLIPPAGE_BPS,
      EasyLimitBuyManager.ZapData({
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32(0), swapData: ""}),
        destData: ISwapper.DestData({destToken: IERC20(address(0)), minDestAmount: 0})
      })
    );

    vm.prank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.InvalidDepositAssetConfig.selector,
        false, // useZap (empty swap data)
        zapInputToken,
        address(0),
        false // inputIsDepositAsset
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  // ============================================
  // Wrong Swap Data Tests
  // ============================================

  /// @notice Test with swap data that specifies wrong dest token
  function test_revert_swap_data_wrong_dest_token() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Get valid swap data for zapInputToken -> usdc
    (, bytes memory swapData) = _getOdosSwapData(zapInputToken, zapInputAmount);

    // But claim dest token is zapInputToken (wrong)
    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedZapExecution(
      zapInputToken,
      zapInputAmount,
      currentPrice > 100e18 ? currentPrice - 100e18 : 0,
      currentPrice + 100e18,
      DEFAULT_SLIPPAGE_BPS,
      EasyLimitBuyManager.ZapData({
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32("ODOS_V3"), swapData: swapData}),
        destData: ISwapper.DestData({destToken: IERC20(zapInputToken), minDestAmount: 0}) // Wrong dest
      })
    );

    vm.prank(keeper);
    // This should revert because declared dest token doesn't match deposit asset requirements
    vm.expectRevert(
      abi.encodeWithSelector(
        EasyLimitBuyManager.InvalidDepositAssetConfig.selector,
        true,
        zapInputToken,
        zapInputToken,
        false
      )
    );
    easyLimitBuyManager.fillLimitBuyBatch(executions);
  }

  // ============================================
  // Successful Zap Deposit Tests
  // ============================================

  /// @notice Test successful zap execution with Odos swap data
  /// @dev This test may fail with "Slippage Limit Exceeded" when forked block state
  ///      diverges significantly from current market conditions used by Odos API.
  ///      The test validates the integration flow works when conditions are favorable.
  function test_fill_limit_buy_with_zap() public {
    uint256 currentPrice = _getCurrentPricingAssetPrice();

    // Get swap data for zapInputToken -> usdc (returns expected USDC output)
    (uint256 expectedUsdcOutput, bytes memory swapData) = _getOdosSwapData(zapInputToken, zapInputAmount);

    (EasyLimitBuyManager.LimitBuyExecution[] memory executions, , ) = _createSignedZapExecution(
      zapInputToken,
      zapInputAmount,
      currentPrice > 100e18 ? currentPrice - 100e18 : 0,
      currentPrice + 100e18,
      50, // 0.5%
      _buildZapData(usdc, swapData)
    );

    // Get expected vault tokens using depositQuote with the expected USDC from swap
    uint256 expectedVaultTokens = IEasySwapperV2(easySwapperV2).depositQuote(targetVault, usdc, expectedUsdcOutput);

    uint256 userZapTokenBefore = IERC20(zapInputToken).balanceOf(user);
    uint256 userVaultBefore = IERC20(targetVault).balanceOf(user);

    vm.prank(keeper);
    easyLimitBuyManager.fillLimitBuyBatch(executions);

    // User's zap token should decrease
    assertEq(
      userZapTokenBefore - IERC20(zapInputToken).balanceOf(user),
      zapInputAmount,
      "User zap token should decrease"
    );

    // User should receive ~expected vault tokens (0.5% relative tolerance)
    assertApproxEqRel(
      IERC20(targetVault).balanceOf(user) - userVaultBefore,
      expectedVaultTokens,
      0.005e18, // 0.5%
      "User should receive expected vault tokens"
    );
  }

  // ============================================
  // Internal Helpers
  // ============================================

  /// @notice Get swap data from Odos API
  /// @dev Uses 5% slippage to handle market volatility in FFI testing
  /// @return outputAmount Expected output amount in destination token
  /// @return swapData Encoded swap data for Odos router
  function _getOdosSwapData(
    address _srcToken,
    uint256 _srcAmount
  ) internal returns (uint256 outputAmount, bytes memory swapData) {
    OdosFunctionStruct memory params = OdosFunctionStruct({
      srcAmount: _srcAmount,
      srcToken: _srcToken,
      destToken: usdc,
      user: address(easyLimitBuyManager),
      slippage: 5 // Use 5% slippage for FFI tests to handle market volatility
    });
    // Force refresh to get fresh swap data rather than using stale cached data
    (outputAmount, swapData) = getDataFromOdos(params, chainId, true, "v3");
  }

  /// @notice Build ZapData struct
  function _buildZapData(
    address _destToken,
    bytes memory _swapData
  ) internal pure returns (EasyLimitBuyManager.ZapData memory) {
    return
      EasyLimitBuyManager.ZapData({
        aggregatorData: ISwapper.AggregatorData({routerKey: bytes32("ODOS_V3"), swapData: _swapData}),
        destData: ISwapper.DestData({destToken: IERC20(_destToken), minDestAmount: 0})
      });
  }

  /// @notice Create signed execution for zap
  function _createSignedZapExecution(
    address _inputToken,
    uint256 _amount,
    uint256 _minPrice,
    uint256 _maxPrice,
    uint16 _slippageBps,
    EasyLimitBuyManager.ZapData memory _zapData
  )
    internal
    view
    returns (EasyLimitBuyManager.LimitBuyExecution[] memory executions_, bytes32 orderHash_, bytes memory signature_)
  {
    return
      _createSignedZapExecutionForUser(
        userPrivateKey,
        _inputToken,
        _amount,
        _minPrice,
        _maxPrice,
        _slippageBps,
        0,
        _zapData
      );
  }

  function _createSignedZapExecutionWithToken(
    address _inputToken,
    uint256 _amount,
    uint256 _minPrice,
    uint256 _maxPrice,
    uint16 _slippageBps,
    EasyLimitBuyManager.ZapData memory _zapData
  )
    internal
    view
    returns (EasyLimitBuyManager.LimitBuyExecution[] memory executions_, bytes32 orderHash_, bytes memory signature_)
  {
    return
      _createSignedZapExecutionForUser(
        userPrivateKey,
        _inputToken,
        _amount,
        _minPrice,
        _maxPrice,
        _slippageBps,
        0,
        _zapData
      );
  }

  function _createSignedZapExecutionForUser(
    uint256 _privateKey,
    address _inputToken,
    uint256 _amount,
    uint256 _minPrice,
    uint256 _maxPrice,
    uint16 _slippageBps,
    uint256 _nonce,
    EasyLimitBuyManager.ZapData memory _zapData
  )
    internal
    view
    returns (EasyLimitBuyManager.LimitBuyExecution[] memory executions_, bytes32 orderHash_, bytes memory signature_)
  {
    address signer = vm.addr(_privateKey);
    EasyLimitBuyTypeHashLib.LimitBuyOrder memory order = _buildOrder(
      signer,
      targetVault,
      _minPrice,
      _maxPrice,
      _slippageBps
    );
    orderHash_ = EasyLimitBuyTypeHashLib.hashLimitBuyOrder(order);
    uint256 deadline = block.timestamp + 1 hours;

    signature_ = _signPermitWithWitnessForToken(_privateKey, _inputToken, _amount, _nonce, deadline, order);
    executions_ = _buildZapExecutions(order, _inputToken, _amount, _nonce, deadline, signature_, _zapData);
  }

  function _signPermitWithWitnessForToken(
    uint256 _privateKey,
    address _token,
    uint256 _amount,
    uint256 _nonce,
    uint256 _deadline,
    EasyLimitBuyTypeHashLib.LimitBuyOrder memory _order
  ) internal view returns (bytes memory) {
    EasyLimitBuyTypeHashLib.LimitBuyTypedData memory typedData = EasyLimitBuyTypeHashLib.LimitBuyTypedData({
      domain: EasyLimitBuyTypeHashLib.EIP712Domain({
        name: "Permit2",
        chainId: block.chainid,
        verifyingContract: EthereumConfig.PERMIT2
      }),
      message: EasyLimitBuyTypeHashLib.PermitWitnessTransferFrom({
        permitted: EasyLimitBuyTypeHashLib.TokenPermissions({token: _token, amount: _amount}),
        spender: address(easyLimitBuyManager),
        nonce: _nonce,
        deadline: _deadline,
        witness: _order
      })
    });

    bytes32 digest = EasyLimitBuyTypeHashLib.getDigest(typedData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
    return abi.encodePacked(r, s, v);
  }

  function _buildZapExecutions(
    EasyLimitBuyTypeHashLib.LimitBuyOrder memory _order,
    address _inputToken,
    uint256 _amount,
    uint256 _nonce,
    uint256 _deadline,
    bytes memory _signature,
    EasyLimitBuyManager.ZapData memory _zapData
  ) internal pure returns (EasyLimitBuyManager.LimitBuyExecution[] memory executions_) {
    ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
      permitted: ISignatureTransfer.TokenPermissions({token: _inputToken, amount: _amount}),
      nonce: _nonce,
      deadline: _deadline
    });

    executions_ = new EasyLimitBuyManager.LimitBuyExecution[](1);
    executions_[0] = EasyLimitBuyManager.LimitBuyExecution({
      order: _order,
      permit: permit,
      signature: _signature,
      zapData: _zapData
    });
  }
}
