// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {console} from "forge-std/console.sol";

abstract contract WithdrawalDebugTestSetup is Test {
  string public chain;
  uint256 public blockNumber;
  uint256 public amount;
  address public withdrawer;
  PoolLogic public vault;
  bytes public txData;

  constructor(
    string memory _chain,
    uint256 _blockNumber,
    address _vault,
    address _withdrawer,
    uint256 _amount,
    bytes memory _txData
  ) {
    chain = _chain;
    blockNumber = _blockNumber;
    vault = PoolLogic(_vault);
    withdrawer = _withdrawer;
    amount = _amount;
    txData = _txData;
  }

  function setUp() public virtual {
    vm.createSelectFork(chain, blockNumber);
  }

  function test_withdraw_tokens() public {
    uint256 tokenPriceBefore = vault.tokenPrice();
    uint256 vaultBalanceBefore = vault.balanceOf(withdrawer);
    uint256 amountToWithdraw = amount > 0 ? amount : vaultBalanceBefore;
    uint256 withdrawalValue = (tokenPriceBefore * amountToWithdraw) / 1e18;
    console.log("Withdrawal value:", withdrawalValue);

    vm.prank(withdrawer);
    (bool success, ) = address(vault).call(txData);
    require(success, "Withdrawal failed");

    assertEq(
      vault.balanceOf(withdrawer),
      vaultBalanceBefore - amountToWithdraw,
      "Incorrect vault balance after withdrawal"
    );
  }
}
