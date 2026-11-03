// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {NestedVaultAssetGuard} from "contracts/guards/assetGuards/NestedVaultAssetGuard.sol";
import {AssetTypes} from "test/integration/utils/foundry/AssetTypes.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice A nested vault registered as asset type 1 is held, valued and withdrawn like any ERC20
/// but can never be enabled as a deposit asset.
contract NestedVaultAssetGuardTest is AssetTypes, PoolUnitTestSetup {
  uint16 private constant NESTED_VAULT_ASSET_TYPE = uint16(AssetTypeIncomplete.NESTED_VAULT);

  address private otherPoolPriceFeed = makeAddr("otherPoolPriceFeed");

  PoolLogic private otherPool;

  function setUp() public override {
    super.setUp();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});
    otherPool = _createFund(supportedAssets);

    _mockPriceFeed(otherPoolPriceFeed, USDC_PRICE);
    vm.startPrank(owner);
    governance.setAssetGuard({assetType: NESTED_VAULT_ASSET_TYPE, guardAddress: address(new NestedVaultAssetGuard())});
    assetHandlerProxy.addAsset(address(otherPool), NESTED_VAULT_ASSET_TYPE, otherPoolPriceFeed);
    vm.stopPrank();
  }

  function test_revert_changeAssets_adding_pool_token_as_deposit_asset() public {
    vm.prank(manager);
    vm.expectRevert("deposit not supported");
    fundManagerLogic.changeAssets(_toAssets(address(otherPool), true), new address[](0));

    assertFalse(fundManagerLogic.isSupportedAsset(address(otherPool)));
  }

  function test_changeAssets_adds_pool_token_as_non_deposit_asset() public {
    vm.prank(manager);
    fundManagerLogic.changeAssets(_toAssets(address(otherPool), false), new address[](0));

    assertTrue(fundManagerLogic.isSupportedAsset(address(otherPool)));
    assertFalse(fundManagerLogic.isDepositAsset(address(otherPool)));
  }

  function test_revert_changeAssets_enabling_held_pool_token_for_deposits() public {
    vm.startPrank(manager);
    fundManagerLogic.changeAssets(_toAssets(address(otherPool), false), new address[](0));

    vm.expectRevert("deposit not supported");
    fundManagerLogic.changeAssets(_toAssets(address(otherPool), true), new address[](0));
    vm.stopPrank();

    assertFalse(fundManagerLogic.isDepositAsset(address(otherPool)));
  }

  function test_held_pool_token_is_valued_and_paid_out_like_an_erc20() public {
    uint256 poolTokens = _acquireOtherPoolTokens(1_000e6);

    vm.prank(manager);
    fundManagerLogic.changeAssets(_toAssets(address(otherPool), false), new address[](0));
    vm.prank(manager);
    otherPool.transfer(address(fund), poolTokens);

    assertEq(fundManagerLogic.assetBalance(address(otherPool)), poolTokens);
    assertEq(fundManagerLogic.assetValue(address(otherPool)), fundManagerLogic.totalFundValue());

    // The investor is the only share holder, so withdrawing half the shares pays half the pool tokens.
    _deposit(investor, address(usdc), 1_000e6);
    vm.warp(block.timestamp + EXIT_COOLDOWN);
    _withdraw(investor, fund.balanceOf(investor) / 2);

    assertEq(otherPool.balanceOf(investor), poolTokens / 2);
    assertEq(fundManagerLogic.assetBalance(address(otherPool)), poolTokens - poolTokens / 2);
  }

  function _acquireOtherPoolTokens(uint256 _usdcAmount) private returns (uint256 poolTokens) {
    vm.startPrank(manager);
    usdc.approve(address(otherPool), _usdcAmount);
    poolTokens = otherPool.deposit(address(usdc), _usdcAmount);
    vm.stopPrank();
    vm.warp(block.timestamp + EXIT_COOLDOWN);
  }

  function _toAssets(address _asset, bool _isDeposit) private pure returns (IHasSupportedAsset.Asset[] memory assets) {
    assets = new IHasSupportedAsset.Asset[](1);
    assets[0] = IHasSupportedAsset.Asset({asset: _asset, isDeposit: _isDeposit});
  }
}
