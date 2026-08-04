// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {EasySwapperV2} from "contracts/swappers/easySwapperV2/EasySwapperV2.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {MockSafe} from "test/integration/utils/foundry/MockSafe.sol";

abstract contract EasySwapperV2CustomCooldownWhitelistTestSetup is BackboneSetup {
  PoolLogic private testPool;
  MockSafe private safe;
  address public safeSigner = makeAddr("safeSigner");

  function setUp() public virtual override {
    super.setUp();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "Test Vault",
        _fundSymbol: "TV",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );

    safe = new MockSafe();
    safe.setOwner(safeSigner, true);
  }

  function _whitelistSetting(
    address _toWhitelist,
    bool _whitelisted
  ) private pure returns (EasySwapperV2.WhitelistSetting[] memory settings) {
    settings = new EasySwapperV2.WhitelistSetting[](1);
    settings[0] = EasySwapperV2.WhitelistSetting({toWhitelist: _toWhitelist, whitelisted: _whitelisted});
  }

  function _transferOwnershipToSafe() private {
    vm.prank(owner);
    easySwapperV2Proxy.transferOwnership(address(safe));
  }

  function test_eoa_owner_can_setCustomCooldownWhitelist() public {
    vm.prank(owner);
    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(address(testPool), true));

    assertTrue(easySwapperV2Proxy.customCooldownDepositsWhitelist(address(testPool)));
  }

  function test_safe_owner_can_setCustomCooldownWhitelist() public {
    _transferOwnershipToSafe();

    vm.prank(address(safe));
    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(address(testPool), true));

    assertTrue(easySwapperV2Proxy.customCooldownDepositsWhitelist(address(testPool)));
  }

  function test_safe_signer_can_setCustomCooldownWhitelist() public {
    _transferOwnershipToSafe();

    vm.prank(safeSigner);
    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(address(testPool), true));

    assertTrue(easySwapperV2Proxy.customCooldownDepositsWhitelist(address(testPool)));
  }

  function test_safe_signer_can_remove_from_customCooldownWhitelist() public {
    _transferOwnershipToSafe();

    vm.startPrank(safeSigner);
    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(address(testPool), true));
    assertTrue(easySwapperV2Proxy.customCooldownDepositsWhitelist(address(testPool)));

    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(address(testPool), false));
    vm.stopPrank();

    assertFalse(easySwapperV2Proxy.customCooldownDepositsWhitelist(address(testPool)));
  }

  function test_revert_setCustomCooldownWhitelist_random_caller_when_owner_is_safe() public {
    _transferOwnershipToSafe();

    address random = makeAddr("random");

    vm.prank(random);
    vm.expectRevert("not owner or Safe owner");
    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(address(testPool), true));
  }

  /// @dev No revert string asserted: with an EOA owner the `isOwner` call fails the compiler's
  ///      extcodesize check, which reverts with empty data outside the try/catch boundary.
  function test_revert_setCustomCooldownWhitelist_random_caller_when_owner_is_eoa() public {
    address random = makeAddr("random");

    vm.prank(random);
    vm.expectRevert();
    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(address(testPool), true));
  }

  function test_revert_safe_signer_setCustomCooldownWhitelist_not_a_vault() public {
    _transferOwnershipToSafe();

    vm.prank(safeSigner);
    vm.expectRevert("not a vault");
    easySwapperV2Proxy.setCustomCooldownWhitelist(_whitelistSetting(makeAddr("notAVault"), true));
  }

  /// @dev Safe signer access is scoped to the custom cooldown whitelist only.
  function test_revert_safe_signer_setCustomCooldown() public {
    _transferOwnershipToSafe();

    vm.prank(safeSigner);
    vm.expectRevert("Ownable: caller is not the owner");
    easySwapperV2Proxy.setCustomCooldown(600);
  }
}
