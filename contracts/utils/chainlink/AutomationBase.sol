// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

contract AutomationBase {
  /**
   * @notice method that allows it to be simulated via eth_call by checking that
   * the sender is the zero address.
   */
  function _preventExecution() internal view {
    require(
      // solhint-disable-next-line avoid-tx-origin
      tx.origin == address(0) || tx.origin == address(0x1111111111111111111111111111111111111111),
      "only simulated call"
    );
  }

  /**
   * @notice modifier that allows it to be simulated via eth_call by checking
   * that the sender is the zero address.
   */
  modifier cannotExecute() {
    _preventExecution();
    _;
  }
}
