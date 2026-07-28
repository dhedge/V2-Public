// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {LiquifiRewardsContractGuard, IUnverifiedLiquifiClaimer} from "contracts/guards/contractGuards/LiquifiRewardsContractGuard.sol";
import {DeploymentDryRunEthereum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunEthereum.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {Governance} from "contracts/Governance.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";

contract SimulateStakedENAClaimTest is DeploymentDryRunEthereum {
  address public constant UNVERIFIED_LIQUIFI_CLAIMER = 0xA4D47A2ca5F11175323155E1258bB15932f0534C;
  IERC20 public constant STAKED_ENA = IERC20(0x8bE3460A480c80728a8C4D7a5D5303c85ba7B3b9);
  uint256 public constant SIMULATION_FORK_BLOCK_NUMBER = 25072620;
  uint256 public constant MIN_STAKED_ENA_TO_RECEIVE = 111326660000000000000000;

  constructor() DeploymentDryRunEthereum(SIMULATION_FORK_BLOCK_NUMBER, new address[](0)) {}

  function setUp() public override {
    super.setUp();

    LiquifiRewardsContractGuard contractGuard = new LiquifiRewardsContractGuard();

    vm.startPrank(poolFactory.owner());
    Governance(poolFactory.governanceAddress()).setContractGuard(UNVERIFIED_LIQUIFI_CLAIMER, address(contractGuard));
    vm.stopPrank();
  }

  function test_simulate_claim_staked_ENA_rewards() public {
    PoolLogic pendledsUSDe = PoolLogic(EthereumConfig.mPT_sUSDe);
    PoolManagerLogic poolManagerLogic = PoolManagerLogic(pendledsUSDe.poolManagerLogic());

    uint256 tokenPriceBefore = pendledsUSDe.tokenPrice();
    uint256 stakedENABalanceBefore = STAKED_ENA.balanceOf(address(pendledsUSDe));
    assertEq(stakedENABalanceBefore, 0);

    address[] memory beneficiaries = new address[](1);
    beneficiaries[0] = EthereumConfig.mPT_sUSDe;

    uint256[] memory awardAmounts = new uint256[](1);
    awardAmounts[0] = MIN_STAKED_ENA_TO_RECEIVE;

    uint256[] memory claimAmounts = new uint256[](1);
    claimAmounts[0] = MIN_STAKED_ENA_TO_RECEIVE;

    uint32[] memory releaseTimes = new uint32[](1);
    releaseTimes[0] = 1775833200;

    uint32[] memory unlockTimes = new uint32[](1);
    unlockTimes[0] = 0;

    bytes32[][] memory proofs = new bytes32[][](1);
    proofs[0] = new bytes32[](17);
    proofs[0][0] = 0x163e1313298ae70a0c753142a936612c4a2f0c65cace1837b78d25c31fc9c7b7;
    proofs[0][1] = 0x40937ebe1836627083786a3a4f128d8b86cab45a117c6c4ae3b5d55e4a9f7f61;
    proofs[0][2] = 0xc9b1bcef614f478a48d0230a961b1f7c84f8e87632a94c593efbd2493ea9e644;
    proofs[0][3] = 0x1c7295f1d313b46b1cb31ebb7ca7acaa50fe1e69aba2737f50bd374496bc470f;
    proofs[0][4] = 0xe800037bc31ca5d049bb2523cc0c774db1f797481b846598bc772a2bfbb01cfe;
    proofs[0][5] = 0xd36d19c6ed01bc8ee32c86968020c79607ec8e55f929b3ec4961b35bfdaf8f62;
    proofs[0][6] = 0x38245d7a83c9f473a934b91a00b1a34c3c88b445414e4d0a3ab0c9b15828c0a6;
    proofs[0][7] = 0xbe5d36520d61fc7eafe84728c4db48bed1b6a60f463b5c581293b6a3613658ac;
    proofs[0][8] = 0xfc82cccd0891cd1e95c6972cc45b5c67e504455dac7419b1069250bcd963e377;
    proofs[0][9] = 0x28709fe76c51b57430e331a390c0a5134472c5a2a3d0a9f06bf3dd7f6e5ad1cd;
    proofs[0][10] = 0x3038da45140c5d3b05dfeedaf75b892a2dfe46148775edba791564dfc6dd3bc8;
    proofs[0][11] = 0x92e177eba2f6f43671d152bacde119e23be538ff30ee3285c46cd6211943dde2;
    proofs[0][12] = 0xefaee81eb360c0c8cf3971a64dbc63707db6a1776d75eea14d6f0f8395bdfd4c;
    proofs[0][13] = 0xba411365bc8e3dc00aed7fc88e3afff522041c24141ae4491dc02f4d20ae88d0;
    proofs[0][14] = 0x1d78b531439a4e155c3414992a2b3d5162c34c2746717d8a7725859ea4d2e9d8;
    proofs[0][15] = 0x8b717dff8f004d25b3243cac564cb5157a021fb618ea64c299662e3bde953aa4;
    proofs[0][16] = 0x516996a4e80b7a64ad618ecb17045af988f903ae87080e27e89b7b8c8f74883e;

    bytes memory data = abi.encodeWithSelector(
      IUnverifiedLiquifiClaimer.batchClaimTokens.selector,
      beneficiaries,
      awardAmounts,
      claimAmounts,
      releaseTimes,
      unlockTimes,
      proofs
    );

    vm.prank(poolManagerLogic.trader());
    pendledsUSDe.execTransaction(UNVERIFIED_LIQUIFI_CLAIMER, data);

    uint256 tokenPriceAfter = pendledsUSDe.tokenPrice();
    uint256 stakedENABalanceAfter = STAKED_ENA.balanceOf(address(pendledsUSDe));
    assertEq(stakedENABalanceAfter, MIN_STAKED_ENA_TO_RECEIVE);
    assertEq(tokenPriceBefore, tokenPriceAfter);
  }
}
