// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolLimitOrderManager} from "contracts/interfaces/IPoolLimitOrderManager.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {WithdrawalVault} from "contracts/swappers/easySwapperV2/WithdrawalVault.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";

/// @dev Live state at the fork block: ZIO VINI holds 6269.78 ETHBULL4X and its manager has a take-profit
///      limit order on all of them (pricing asset WETH, take profit $3370 while WETH trades at $2334).
///      ETHBULL4X pays WETH on redemption. VINI holds no WETH itself, so once the order executes, the only
///      WETH VINI owns sits in its limit-order WithdrawalVault, valued through the EasySwapperV2 "asset".
contract LimitOrderVaultUnrollDryRunArbitrum is DeploymentDryRunArbitrum {
  uint256 private constant FORK_BLOCK = 519056354;
  address private constant VINI = 0xB5709A177920BC8df4Bdb6F272B0F0a6E1F58B23;
  address private constant VINI_MANAGER = 0x36e4725bCb8336F0A62e33f4B08aec36Ad82Ce1c;
  address private constant POOL_LIMIT_ORDER_MANAGER = 0x26a687e8244f1866E9Aa2D400c8b9957Aa8e6Ad4;
  bytes32 private constant VINI_ORDER_ID = 0xdffeca091260127ffe59fae9633e8a4829edada15173239a45e6a854a642b863;
  /// @dev PoolLimitOrderManager.defaultSlippageTolerance on-chain; keeper calldata may not exceed it
  uint256 private constant KEEPER_SLIPPAGE = 200;

  EasySwapperV2 private easySwapper = EasySwapperV2(ArbitrumConfig.EASY_SWAPPER_V2_PROD);
  IPoolLimitOrderManager private limitOrderManager = IPoolLimitOrderManager(POOL_LIMIT_ORDER_MANAGER);
  PoolManagerLogic private viniManagerLogic;

  /// @dev Authorized PoolLimitOrderManager keeper, see publish/arbitrum/prod/versions.json
  address private constant KEEPER = 0x99c9F65a486C0567495ec58722916c73292D585f;

  address private investor = makeAddr("investor");
  uint256 private investorShares;

  constructor() DeploymentDryRunArbitrum(FORK_BLOCK, new address[](0)) {}

  function setUp() public override {
    super.setUp();

    vm.label(VINI, "VINI");
    vm.label(ArbitrumConfig.ETHBULL4X, "ETHBULL4X");
    vm.label(POOL_LIMIT_ORDER_MANAGER, "PoolLimitOrderManager");
    vm.label(address(easySwapper), "EasySwapperV2");

    viniManagerLogic = PoolManagerLogic(PoolLogic(VINI).poolManagerLogic());

    // The manager is effectively the only VINI holder; hand half of their shares to the investor
    investorShares = IERC20(VINI).balanceOf(VINI_MANAGER) / 2;
    vm.prank(VINI_MANAGER);
    IERC20(VINI).transfer(investor, investorShares);
  }

  /// @dev Deployed WithdrawalVault logic: the limit-order WETH is tracked only because VINI lists WETH itself
  function test_deployed_logic_tracks_limit_order_weth_only_through_the_vaults_own_weth_entry() public {
    uint256 wethInLimitOrderVault = _executeViniOrder();

    uint256 wethReceived = _investorExitsViaEasySwapper();

    assertEq(wethReceived, wethInLimitOrderVault - _wethIn(easySwapper.limitOrderContracts(VINI)));
    assertTrue(_investorTracksWeth(), "limit order WETH not tracked");

    _investorClaimsWithoutSwap(wethReceived);
  }

  /// @dev Deployed WithdrawalVault logic: once VINI no longer lists WETH, the limit-order WETH lands in the
  ///      investor's WithdrawalVault untracked, so neither a swap nor a claim can ever move it
  function test_deployed_logic_strands_limit_order_weth_when_vault_does_not_support_weth() public {
    uint256 wethInLimitOrderVault = _executeViniOrder();
    _managerRemovesWeth();

    uint256 wethReceived = _investorExitsViaEasySwapper();

    assertEq(wethReceived, wethInLimitOrderVault - _wethIn(easySwapper.limitOrderContracts(VINI)));
    assertFalse(_investorTracksWeth(), "limit order WETH tracked");

    vm.prank(investor);
    easySwapper.completeWithdrawal();

    assertEq(_wethIn(investor), 0, "investor received the limit order WETH");
    assertEq(_wethIn(easySwapper.withdrawalContracts(investor)), wethReceived, "WETH left the WithdrawalVault");
  }

  function test_fixed_logic_tracks_limit_order_weth_when_vault_does_not_support_weth() public {
    _upgradeWithdrawalVaultLogic();
    uint256 wethInLimitOrderVault = _executeViniOrder();
    _managerRemovesWeth();

    uint256 wethReceived = _investorExitsViaEasySwapper();

    assertEq(wethReceived, wethInLimitOrderVault - _wethIn(easySwapper.limitOrderContracts(VINI)));
    assertTrue(_investorTracksWeth(), "limit order WETH not tracked");

    _investorClaimsWithoutSwap(wethReceived);
  }

  function test_direct_withdraw_pays_limit_order_weth_to_investor_when_vault_does_not_support_weth() public {
    uint256 wethInLimitOrderVault = _executeViniOrder();
    _managerRemovesWeth();

    vm.prank(investor);
    PoolLogic(VINI).withdraw(investorShares);

    // partialWithdraw pays the pool's limit-order vault share straight to the withdrawer, nothing is left to track
    assertEq(_wethIn(investor), wethInLimitOrderVault - _wethIn(easySwapper.limitOrderContracts(VINI)));
    assertGt(_wethIn(investor), 0);
    assertEq(easySwapper.withdrawalContracts(investor), address(0));
  }

  /// @dev Every WithdrawalVault proxy reads its logic from EasySwapperV2
  function _upgradeWithdrawalVaultLogic() private {
    address withdrawalVaultLogic = address(new WithdrawalVault());
    vm.prank(easySwapper.owner());
    easySwapper.setLogic(withdrawalVaultLogic);
  }

  function _investorClaimsWithoutSwap(uint256 _expectedWeth) private {
    vm.prank(investor);
    easySwapper.completeWithdrawal();

    assertEq(_wethIn(investor), _expectedWeth);
    assertEq(_wethIn(easySwapper.withdrawalContracts(investor)), 0);
  }

  /// @dev Keeper fills VINI's take-profit order: ETHBULL4X is redeemed into VINI's limit-order vault
  /// @return wethInLimitOrderVault WETH now sitting in VINI's limit-order vault
  function _executeViniOrder() private returns (uint256 wethInLimitOrderVault) {
    (uint256 amount, , , , , ) = _viniOrder();

    uint256 ethbull4xSupportedAssets = IHasSupportedAsset(PoolLogic(ArbitrumConfig.ETHBULL4X).poolManagerLogic())
      .getSupportedAssets()
      .length;
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](ethbull4xSupportedAssets);
    for (uint256 i; i < complexAssetsData.length; ++i) {
      complexAssetsData[i].slippageTolerance = KEEPER_SLIPPAGE;
    }

    IPoolLimitOrderManager.LimitOrderExecution[] memory orders = new IPoolLimitOrderManager.LimitOrderExecution[](1);
    orders[0] = IPoolLimitOrderManager.LimitOrderExecution({
      orderId: VINI_ORDER_ID,
      complexAssetsData: complexAssetsData,
      amount: amount
    });

    // Pretend the take-profit target is hit
    vm.mockCall(
      address(poolFactory),
      abi.encodeWithSelector(PoolFactory.getAssetPrice.selector, weth),
      abi.encode(uint256(3400e18))
    );
    vm.prank(KEEPER);
    limitOrderManager.executeLimitOrders(orders);
    vm.clearMockedCalls();

    assertTrue(limitOrderManager.hasSettlementOrder(VINI), "no settlement order");
    assertEq(_wethIn(VINI), 0, "VINI holds WETH directly");
    assertEq(_wethIn(easySwapper.withdrawalContracts(VINI)), 0, "VINI single-asset vault holds WETH");

    wethInLimitOrderVault = _wethIn(easySwapper.limitOrderContracts(VINI));
    assertGt(wethInLimitOrderVault, 0, "no WETH in VINI limit-order vault");
  }

  /// @dev Passes removeAssetCheck: VINI's own WETH balance is zero and only the settlement token is
  ///      checked against open orders
  function _managerRemovesWeth() private {
    address[] memory toRemove = new address[](1);
    toRemove[0] = weth;

    vm.prank(VINI_MANAGER);
    viniManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), toRemove);

    assertFalse(viniManagerLogic.isSupportedAsset(weth));
  }

  /// @return wethReceived WETH that landed in the investor's WithdrawalVault
  function _investorExitsViaEasySwapper() private returns (uint256 wethReceived) {
    uint256 viniSupportedAssets = viniManagerLogic.getSupportedAssets().length;

    vm.startPrank(investor);
    IERC20(VINI).approve(address(easySwapper), investorShares);
    (, address withdrawalVault) = easySwapper.initWithdrawal(
      VINI,
      investorShares,
      new IPoolLogic.ComplexAsset[](viniSupportedAssets)
    );
    vm.stopPrank();

    wethReceived = _wethIn(withdrawalVault);
    assertGt(wethReceived, 0, "no WETH in investor WithdrawalVault");
  }

  function _investorTracksWeth() private view returns (bool tracked) {
    IWithdrawalVault.TrackedAsset[] memory trackedAssets = easySwapper.getTrackedAssets(investor);
    for (uint256 i; i < trackedAssets.length; ++i) {
      if (trackedAssets[i].token == weth) return trackedAssets[i].balance > 0;
    }
  }

  function _viniOrder()
    private
    view
    returns (
      uint256 amount,
      uint256 stopLossPriceD18,
      uint256 takeProfitPriceD18,
      address user,
      address pool,
      address pricingAsset
    )
  {
    (bool ok, bytes memory data) = POOL_LIMIT_ORDER_MANAGER.staticcall(
      abi.encodeWithSignature("limitOrders(bytes32)", VINI_ORDER_ID)
    );
    require(ok, "limitOrders() failed");
    (amount, stopLossPriceD18, takeProfitPriceD18, user, pool, pricingAsset) = abi.decode(
      data,
      (uint256, uint256, uint256, address, address, address)
    );
    assertEq(user, VINI);
    assertEq(pool, ArbitrumConfig.ETHBULL4X);
  }

  function _wethIn(address _account) private view returns (uint256 balance) {
    if (_account == address(0)) return 0;
    balance = IERC20(weth).balanceOf(_account);
  }
}
