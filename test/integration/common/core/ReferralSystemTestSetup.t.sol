// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @notice Interface for ReferralManager (0.8.28 contract) to use in 0.7.6 tests
interface IReferralManagerTest {
  function initialize(address _poolFactory) external;
  function setVaultReferralShare(address _vault, uint256 _shareNumerator) external;
  function setManagerReferralShare(uint256 _shareNumerator) external;
  function getReferralShare(address _vault, address _manager) external view returns (uint256 shareNumerator);
  function vaultReferralShare(address _vault) external view returns (uint256);
  function managerReferralShare(address _manager) external view returns (uint256);
  function MAX_SHARE() external view returns (uint256);
}

/// @notice Abstract contract for testing ReferralSystem functionality
/// @dev Tests ReferralManager configuration, access control, share resolution, and deposit integration
abstract contract ReferralSystemTestSetup is BackboneSetup {
  // ============ Error Selectors ============
  bytes4 internal constant NOT_VALID_VAULT_SELECTOR = bytes4(keccak256("NotValidVault(address)"));
  bytes4 internal constant NOT_VAULT_MANAGER_SELECTOR = bytes4(keccak256("NotVaultManager(address,address)"));
  bytes4 internal constant SHARE_TOO_HIGH_SELECTOR = bytes4(keccak256("ShareTooHigh(uint256,uint256)"));

  /// @dev ReferralManager proxy
  IReferralManagerTest public referralManagerProxy;

  /// @dev Test pool and its manager logic
  PoolLogic internal testPool;
  PoolManagerLogic internal testPoolManagerLogic;

  /// @dev Test referrer address
  address public referrer = makeAddr("referrer");

  /// @dev DAO fee configuration (from PoolFactory defaults)
  uint256 internal daoFeeNumerator = 10; // 10%
  uint256 internal daoFeeDenominator = 100;

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    // Deploy ReferralManager (0.8.28 contract)
    address referralManager = deployCode("ReferralManager.sol:ReferralManager");
    referralManagerProxy = IReferralManagerTest(
      address(new TransparentUpgradeableProxy(referralManager, proxyAdmin, ""))
    );
    referralManagerProxy.initialize(address(poolFactoryProxy));

    // Set ReferralManager in PoolFactory
    poolFactoryProxy.setReferralManager(address(referralManagerProxy));

    // Create test pool with USDC as deposit asset
    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});

    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "ReferralTestManager",
        _fundName: "ReferralTestPool",
        _fundSymbol: "REFTEST",
        _performanceFeeNumerator: 0,
        _managerFeeNumerator: 0,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );

    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    vm.stopPrank();

    vm.label(address(testPool), "ReferralTestPool");
    vm.label(address(referralManagerProxy), "ReferralManager");
    vm.label(referrer, "Referrer");
  }

  // ========== REFERRAL MANAGER UNIT TESTS ==========

  function test_referral_setVaultReferralShare_success() public {
    uint256 share = 5000; // 50%

    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(address(testPool), share);

    assertEq(referralManagerProxy.vaultReferralShare(address(testPool)), share, "Vault referral share should be set");
  }

  function test_referral_setVaultReferralShare_max_share() public {
    uint256 maxShare = referralManagerProxy.MAX_SHARE();

    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(address(testPool), maxShare);

    assertEq(
      referralManagerProxy.vaultReferralShare(address(testPool)),
      maxShare,
      "Should allow setting MAX_SHARE (100%)"
    );
  }

  function test_referral_setVaultReferralShare_zero() public {
    // First set a non-zero share
    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(address(testPool), 5000);

    // Then set it back to zero
    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(address(testPool), 0);

    assertEq(referralManagerProxy.vaultReferralShare(address(testPool)), 0, "Vault referral share should be disabled");
  }

  function test_referral_setVaultReferralShare_reverts_not_manager() public {
    vm.expectRevert(abi.encodeWithSelector(NOT_VAULT_MANAGER_SELECTOR, investor, address(testPool)));

    vm.prank(investor);
    referralManagerProxy.setVaultReferralShare(address(testPool), 5000);
  }

  function test_referral_setVaultReferralShare_reverts_invalid_vault() public {
    address fakeVault = makeAddr("fakeVault");

    vm.expectRevert(abi.encodeWithSelector(NOT_VALID_VAULT_SELECTOR, fakeVault));

    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(fakeVault, 5000);
  }

  function test_referral_setVaultReferralShare_reverts_share_too_high() public {
    uint256 maxShare = referralManagerProxy.MAX_SHARE();
    uint256 invalidShare = maxShare + 1;

    vm.expectRevert(abi.encodeWithSelector(SHARE_TOO_HIGH_SELECTOR, invalidShare, maxShare));

    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(address(testPool), invalidShare);
  }

  function test_referral_setManagerReferralShare_success() public {
    uint256 share = 3000; // 30%

    vm.prank(manager);
    referralManagerProxy.setManagerReferralShare(share);

    assertEq(referralManagerProxy.managerReferralShare(manager), share, "Manager referral share should be set");
  }

  function test_referral_setManagerReferralShare_max_share() public {
    uint256 maxShare = referralManagerProxy.MAX_SHARE();

    vm.prank(manager);
    referralManagerProxy.setManagerReferralShare(maxShare);

    assertEq(referralManagerProxy.managerReferralShare(manager), maxShare, "Should allow setting MAX_SHARE (100%)");
  }

  function test_referral_setManagerReferralShare_zero() public {
    // First set a non-zero share
    vm.prank(manager);
    referralManagerProxy.setManagerReferralShare(5000);

    // Then set it back to zero
    vm.prank(manager);
    referralManagerProxy.setManagerReferralShare(0);

    assertEq(referralManagerProxy.managerReferralShare(manager), 0, "Manager referral share should be disabled");
  }

  function test_referral_setManagerReferralShare_reverts_share_too_high() public {
    uint256 maxShare = referralManagerProxy.MAX_SHARE();
    uint256 invalidShare = maxShare + 1;

    vm.expectRevert(abi.encodeWithSelector(SHARE_TOO_HIGH_SELECTOR, invalidShare, maxShare));

    vm.prank(manager);
    referralManagerProxy.setManagerReferralShare(invalidShare);
  }

  // ========== SHARE RESOLUTION TESTS ==========

  function test_referral_getReferralShare_vault_priority() public {
    uint256 vaultShare = 7000; // 70%
    uint256 managerShare = 3000; // 30%

    vm.startPrank(manager);
    referralManagerProxy.setManagerReferralShare(managerShare);
    referralManagerProxy.setVaultReferralShare(address(testPool), vaultShare);
    vm.stopPrank();

    uint256 resolvedShare = referralManagerProxy.getReferralShare(address(testPool), manager);

    assertEq(resolvedShare, vaultShare, "Vault-specific share should take priority over manager's global share");
  }

  function test_referral_getReferralShare_fallback_to_manager() public {
    uint256 managerShare = 4000; // 40%

    vm.prank(manager);
    referralManagerProxy.setManagerReferralShare(managerShare);

    // No vault-specific share set
    uint256 resolvedShare = referralManagerProxy.getReferralShare(address(testPool), manager);

    assertEq(resolvedShare, managerShare, "Should fallback to manager's global share when vault share is 0");
  }

  function test_referral_getReferralShare_zero_when_none_set() public view {
    // No shares set
    uint256 resolvedShare = referralManagerProxy.getReferralShare(address(testPool), manager);

    assertEq(resolvedShare, 0, "Should return 0 when no share is configured");
  }

  function test_referral_getReferralShare_zero_when_no_referral_manager() public {
    // Even if a share was configured, removing the ReferralManager should return 0
    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(address(testPool), 5000);

    // Remove ReferralManager from PoolFactory
    vm.prank(owner);
    poolFactoryProxy.setReferralManager(address(0));

    // PoolManagerLogic.getReferralShare() should return 0 when no ReferralManager is set
    uint256 resolvedShare = testPoolManagerLogic.getReferralShare();

    assertEq(resolvedShare, 0, "Should return 0 when no ReferralManager is configured in factory");
  }

  // ========== DEPOSIT INTEGRATION TESTS ==========

  function test_referral_deposit_with_referrer_receives_fee() public {
    // Set entry fee and referral share
    _setEntryFee(100); // 1%
    _setVaultReferralShare(5000); // 50% of manager's portion

    uint256 depositAmount = 1000e6; // 1000 USDC

    uint256 referrerBalanceBefore = testPool.balanceOf(referrer);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    assertEq(referrerBalanceBefore, 0, "Referrer balance should be zero before deposit");

    _makeDepositWithReferrer(testPool, investor, usdcData.asset, depositAmount, referrer);

    uint256 referrerBalanceAfter = testPool.balanceOf(referrer);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);

    // Entry fee = 1% of deposit value = 10e6 (scaled to 1e18)
    // Entry fee tokens = 10e6 * 1e12 = 10e18
    uint256 entryFee = (depositAmount * 1e12 * 100) / 10000;
    // DAO gets 10% of entry fee
    uint256 daoFee = (entryFee * daoFeeNumerator) / daoFeeDenominator;
    // Manager gets remaining 90%
    uint256 managerFee = entryFee - daoFee;
    // Referrer gets 50% of manager's fee
    uint256 referrerFee = (managerFee * 5000) / 10000;
    uint256 expectedManagerFee = managerFee - referrerFee;

    assertEq(daoBalanceAfter, daoBalanceBefore + daoFee, "DAO should receive expected fee");
    assertEq(managerBalanceAfter, managerBalanceBefore + expectedManagerFee, "Manager should receive reduced fee");
    assertEq(referrerBalanceAfter, referrerFee, "Referrer should receive expected fee from manager's portion");
  }

  function test_referral_deposit_no_referrer_no_fee() public {
    // Set entry fee and referral share
    _setEntryFee(100); // 1%
    _setVaultReferralShare(5000); // 50%

    uint256 depositAmount = 1000e6;

    uint256 referrerBalanceBefore = testPool.balanceOf(referrer);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);

    // Deposit without referrer (address(0))
    _makeDepositWithReferrer(testPool, investor, usdcData.asset, depositAmount, address(0));

    uint256 referrerBalanceAfter = testPool.balanceOf(referrer);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);

    assertEq(referrerBalanceAfter, referrerBalanceBefore, "Referrer should receive nothing when not specified");

    // Manager should receive full manager portion (entry fee - dao fee)
    uint256 entryFee = (depositAmount * 1e12 * 100) / 10000;
    uint256 daoFee = (entryFee * daoFeeNumerator) / daoFeeDenominator;
    uint256 managerFee = entryFee - daoFee;

    assertEq(
      managerBalanceAfter,
      managerBalanceBefore + managerFee,
      "Manager should receive full fee when no referrer"
    );
  }

  function test_referral_deposit_referrer_but_no_share_set() public {
    // Set entry fee but NO referral share
    _setEntryFee(100); // 1%

    uint256 depositAmount = 1000e6;

    uint256 referrerBalanceBefore = testPool.balanceOf(referrer);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);

    _makeDepositWithReferrer(testPool, investor, usdcData.asset, depositAmount, referrer);

    uint256 referrerBalanceAfter = testPool.balanceOf(referrer);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);

    assertEq(referrerBalanceAfter, referrerBalanceBefore, "Referrer should receive nothing when share is 0");

    // Manager should receive full manager portion
    uint256 entryFee = (depositAmount * 1e12 * 100) / 10000;
    uint256 daoFee = (entryFee * daoFeeNumerator) / daoFeeDenominator;
    uint256 managerFee = entryFee - daoFee;

    assertEq(
      managerBalanceAfter,
      managerBalanceBefore + managerFee,
      "Manager should receive full fee when referral disabled"
    );
  }

  function test_referral_deposit_100_percent_share() public {
    // Set entry fee and 100% referral share
    _setEntryFee(100); // 1%
    _setVaultReferralShare(10000); // 100%

    uint256 depositAmount = 1000e6;

    assertEq(testPool.balanceOf(referrer), 0, "Referrer balance should be zero before deposit");
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    _makeDepositWithReferrer(testPool, investor, usdcData.asset, depositAmount, referrer);

    uint256 referrerBalanceAfter = testPool.balanceOf(referrer);
    uint256 managerBalanceAfter = testPool.balanceOf(manager);
    uint256 daoBalanceAfter = testPool.balanceOf(dao);

    uint256 entryFee = (depositAmount * 1e12 * 100) / 10000;
    uint256 daoFee = (entryFee * daoFeeNumerator) / daoFeeDenominator;
    uint256 managerFee = entryFee - daoFee;

    // Referrer gets 100% of manager's fee
    assertEq(referrerBalanceAfter, managerFee, "Referrer should receive entire manager's fee at 100% share");
    assertEq(managerBalanceAfter, managerBalanceBefore, "Manager should receive nothing at 100% referral share");
    assertEq(daoBalanceAfter, daoBalanceBefore + daoFee, "DAO fee should be unaffected by referral");
  }

  function test_referral_deposit_no_entry_fee() public {
    // No entry fee set, but referral share is set
    _setVaultReferralShare(5000); // 50%

    uint256 depositAmount = 1000e6;

    uint256 referrerBalanceBefore = testPool.balanceOf(referrer);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    _makeDepositWithReferrer(testPool, investor, usdcData.asset, depositAmount, referrer);

    // No fees should be minted when entry fee is 0
    assertEq(
      testPool.balanceOf(referrer),
      referrerBalanceBefore,
      "Referrer should receive nothing when entry fee is 0"
    );
    assertEq(testPool.balanceOf(manager), managerBalanceBefore, "Manager should receive nothing when entry fee is 0");
    assertEq(testPool.balanceOf(dao), daoBalanceBefore, "DAO should receive nothing when entry fee is 0");
  }

  function test_referral_deposit_manager_share_fallback() public {
    // Set entry fee and manager-level share (not vault-specific)
    _setEntryFee(100); // 1%

    // Set manager-level share
    vm.prank(manager);
    referralManagerProxy.setManagerReferralShare(5000); // 50%

    uint256 depositAmount = 1000e6;

    uint256 referrerBalanceBefore = testPool.balanceOf(referrer);

    _makeDepositWithReferrer(testPool, investor, usdcData.asset, depositAmount, referrer);

    uint256 referrerBalanceAfter = testPool.balanceOf(referrer);

    // Referrer should receive fee using manager's global share
    uint256 entryFee = (depositAmount * 1e12 * 100) / 10000;
    uint256 daoFee = (entryFee * daoFeeNumerator) / daoFeeDenominator;
    uint256 managerFee = entryFee - daoFee;
    uint256 referrerFee = (managerFee * 5000) / 10000;

    assertEq(
      referrerBalanceAfter,
      referrerBalanceBefore + referrerFee,
      "Referrer should receive fee via manager's global share fallback"
    );
  }

  function test_referral_deposit_100_pool_share_no_fees_transferred() public {
    // Set entry fee but 100% pool share (fees stay in pool, no transfers)
    _setEntryFee(100); // 1%
    _setVaultReferralShare(5000); // 50%

    vm.prank(manager);
    testPoolManagerLogic.setPoolFeeShareNumerator(10000); // 100% to pool

    uint256 depositAmount = 1000e6;

    uint256 referrerBalanceBefore = testPool.balanceOf(referrer);
    uint256 managerBalanceBefore = testPool.balanceOf(manager);
    uint256 daoBalanceBefore = testPool.balanceOf(dao);

    _makeDepositWithReferrer(testPool, investor, usdcData.asset, depositAmount, referrer);

    // No fees transferred when 100% goes to pool share
    assertEq(
      testPool.balanceOf(referrer),
      referrerBalanceBefore,
      "Referrer should receive nothing with 100% pool share"
    );
    assertEq(testPool.balanceOf(manager), managerBalanceBefore, "Manager should receive nothing with 100% pool share");
    assertEq(testPool.balanceOf(dao), daoBalanceBefore, "DAO should receive nothing with 100% pool share");
  }

  // ========== HELPER FUNCTIONS ==========

  function _setEntryFee(uint256 _entryFeeNumerator) internal {
    vm.startPrank(manager);
    testPoolManagerLogic.announceFeeIncrease(0, 0, _entryFeeNumerator, 0);
    skip(15 days);
    testPoolManagerLogic.commitFeeIncrease();
    vm.stopPrank();
  }

  function _setVaultReferralShare(uint256 _shareNumerator) internal {
    vm.prank(manager);
    referralManagerProxy.setVaultReferralShare(address(testPool), _shareNumerator);
  }

  function _makeDepositWithReferrer(
    PoolLogic _pool,
    address _depositor,
    address _token,
    uint256 _amount,
    address _referrer
  ) internal {
    deal(_token, _depositor, _amount);

    vm.startPrank(_depositor);
    IERC20(_token).approve(address(easySwapperV2Proxy), _amount);

    // Use EasySwapperV2 to deposit with referrer (it calls depositForWithCustomCooldown)
    bytes memory referralData = _referrer != address(0) ? abi.encode(_referrer) : bytes("");

    // Use the deposit function (not depositWithCustomCooldown) to avoid whitelist requirement
    easySwapperV2Proxy.deposit(
      address(_pool),
      IERC20(_token),
      _amount,
      0, // _expectedAmountReceived (0 means no slippage check)
      referralData
    );
    vm.stopPrank();
  }
}
