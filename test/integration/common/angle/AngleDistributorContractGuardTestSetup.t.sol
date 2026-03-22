// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {AngleDistributorContractGuard} from "contracts/guards/contractGuards/AngleDistributorContractGuard.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

import {Test} from "forge-std/Test.sol";

abstract contract AngleDistributorContractGuardTestSetup is Test {
  /// @dev Configuration for testing a reward token
  struct RewardTokenTestConfig {
    address token; // The actual token received (aToken for AAVE types, raw token for REGULAR)
    address wrappedToken; // The wrapped version (for WRAPPED_* types), address(0) if none
    AngleDistributorContractGuard.RewardTokenType tokenType;
  }

  address internal immutable vault;
  address internal immutable aaveLendingPool;
  bytes internal claimData;

  RewardTokenTestConfig[] internal rewardTokenConfigs;

  constructor(address _vault, address _aaveLendingPool, bytes memory _claimData) {
    vault = _vault;
    aaveLendingPool = _aaveLendingPool;
    claimData = _claimData;
  }

  /// @dev Child contracts must call this in their constructor to add reward token configs
  function _addRewardTokenConfig(RewardTokenTestConfig memory _config) internal {
    rewardTokenConfigs.push(_config);
  }

  /// @dev Deploys contract guard with all configured reward tokens
  function _deployContractGuard(PoolFactory _poolFactory) internal {
    AngleDistributorContractGuard.RewardTokenConfig[]
      memory guardConfigs = new AngleDistributorContractGuard.RewardTokenConfig[](rewardTokenConfigs.length);

    for (uint256 i; i < rewardTokenConfigs.length; ++i) {
      // For WRAPPED_* types, the guard receives the wrapped token address
      // For non-wrapped types, the guard receives the actual token address
      address guardToken = rewardTokenConfigs[i].wrappedToken != address(0)
        ? rewardTokenConfigs[i].wrappedToken
        : rewardTokenConfigs[i].token;

      guardConfigs[i] = AngleDistributorContractGuard.RewardTokenConfig({
        token: guardToken,
        tokenType: rewardTokenConfigs[i].tokenType
      });
    }

    AngleDistributorContractGuard contractGuard = new AngleDistributorContractGuard(aaveLendingPool, guardConfigs);

    vm.startPrank(_poolFactory.owner());
    Governance(_poolFactory.governanceAddress()).setContractGuard(
      EthereumConfig.ANGLE_DISTRIBUTOR_CONTRACT,
      address(contractGuard)
    );
    vm.stopPrank();
  }

  function test_can_claim_rewards_for_vault() public virtual {
    PoolManagerLogic poolManagerLogic = PoolManagerLogic(PoolLogic(vault).poolManagerLogic());

    // Capture balances before claim
    uint256[] memory balancesBefore = new uint256[](rewardTokenConfigs.length);
    uint256[] memory wrappedBalancesBefore = new uint256[](rewardTokenConfigs.length);
    for (uint256 i; i < rewardTokenConfigs.length; ++i) {
      balancesBefore[i] = IERC20(rewardTokenConfigs[i].token).balanceOf(vault);
      if (rewardTokenConfigs[i].wrappedToken != address(0)) {
        wrappedBalancesBefore[i] = IERC20(rewardTokenConfigs[i].wrappedToken).balanceOf(vault);
        assertEq(wrappedBalancesBefore[i], 0, "wrappedToken balance should be zero before claim");
      }
    }
    uint256 totalFundValueBefore = poolManagerLogic.totalFundValue();

    // Execute claim
    vm.prank(poolManagerLogic.manager());
    PoolLogic(vault).execTransaction(EthereumConfig.ANGLE_DISTRIBUTOR_CONTRACT, claimData);

    // Verify balances after claim
    for (uint256 i; i < rewardTokenConfigs.length; ++i) {
      uint256 balanceAfter = IERC20(rewardTokenConfigs[i].token).balanceOf(vault);

      // For wrapped types, wrapped token balance should stay zero (unwrapped during claim)
      if (rewardTokenConfigs[i].wrappedToken != address(0)) {
        uint256 wrappedBalanceAfter = IERC20(rewardTokenConfigs[i].wrappedToken).balanceOf(vault);
        assertEq(wrappedBalanceAfter, 0, "wrappedToken balance should stay zero after claim");
      }

      // Actual token balance should increase
      assertGt(balanceAfter, balancesBefore[i], "token balance did not increase");
    }

    // Verify TVL increased
    uint256 totalFundValueAfter = poolManagerLogic.totalFundValue();
    assertGt(totalFundValueAfter, totalFundValueBefore, "totalFundValue did not increase");
  }
}
