// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {PoolFactory} from "contracts/PoolFactory.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {Governance} from "contracts/Governance.sol";
import {FluidMerkleDistributorContractGuard} from "contracts/guards/contractGuards/fluid/FluidMerkleDistributorContractGuard.sol";
import {IFluidMerkleDistributor} from "contracts/interfaces/fluid/IFluidMerkleDistributor.sol";

abstract contract FluidRewardsTestSetup is Test {
  string private network;
  uint256 private immutable forkBlockNumber;
  PoolLogic private immutable vaultToTestClaim;
  address private immutable fluidMerkleDistributor;
  address private immutable FLUID;
  bytes private txData;

  constructor(
    string memory _network,
    uint256 _forkBlockNumber,
    address _vaultToTestClaim,
    address _fluidMerkleDistributor,
    address _FLUID,
    bytes memory _txData
  ) {
    network = _network;
    forkBlockNumber = _forkBlockNumber;
    vaultToTestClaim = PoolLogic(_vaultToTestClaim);
    fluidMerkleDistributor = _fluidMerkleDistributor;
    FLUID = _FLUID;
    txData = _txData;
  }

  function setUp() public virtual {
    vm.createSelectFork(network, forkBlockNumber);

    FluidMerkleDistributorContractGuard fluidMerkleDistributorContractGuard = new FluidMerkleDistributorContractGuard();

    PoolFactory poolFactory = PoolFactory(vaultToTestClaim.factory());
    Governance governance = Governance(poolFactory.governanceAddress());
    vm.prank(poolFactory.owner());
    governance.setContractGuard(fluidMerkleDistributor, address(fluidMerkleDistributorContractGuard));
  }

  function test_can_claim_fluid_rewards() public {
    assertEq(PoolLogic(FLUID).balanceOf(address(vaultToTestClaim)), 0, "FLUID balance should be 0 before claim");

    address poolManagerLogic = vaultToTestClaim.poolManagerLogic();
    address manager = PoolManagerLogic(poolManagerLogic).manager();

    vm.prank(manager);
    vaultToTestClaim.execTransaction(fluidMerkleDistributor, txData);

    assertGt(PoolLogic(FLUID).balanceOf(address(vaultToTestClaim)), 0, "FLUID balance should be greater than 0");
  }

  function test_revert_claim_when_recipient_is_not_pool() public {
    address poolManagerLogic = vaultToTestClaim.poolManagerLogic();
    address manager = PoolManagerLogic(poolManagerLogic).manager();

    vm.prank(manager);
    vm.expectRevert("recipient is not pool");
    vaultToTestClaim.execTransaction(
      fluidMerkleDistributor,
      abi.encodeWithSelector(
        IFluidMerkleDistributor.claim.selector,
        address(0x123), // Invalid recipient
        0, // cumulativeAmount
        uint8(1), // positionType
        bytes32(0), // positionId
        0, // cycle
        new bytes32[](0), // merkleProof
        "" // metadata
      )
    );
  }

  function test_revert_claim_when_position_type_is_not_lending() public {
    address poolManagerLogic = vaultToTestClaim.poolManagerLogic();
    address manager = PoolManagerLogic(poolManagerLogic).manager();

    vm.prank(manager);
    vm.expectRevert("only lending");
    vaultToTestClaim.execTransaction(
      fluidMerkleDistributor,
      abi.encodeWithSelector(
        IFluidMerkleDistributor.claim.selector,
        vaultToTestClaim, // Valid recipient
        0, // cumulativeAmount
        uint8(2), // Invalid positionType (not lending)
        bytes32(0), // positionId
        0, // cycle
        new bytes32[](0), // merkleProof
        "" // metadata
      )
    );
  }
}
