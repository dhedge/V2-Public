// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "../../interfaces/guards/IGuard.sol";

contract ClosedContractGuard is IGuard {
  /// @notice Doesn't allow any transactions on the contract
  /// @dev Can be used as a stub to deprecate contract guard as Governance's setContractGuard doesn't accept address(0) as a guard address
  function txGuard(
    address,
    address,
    bytes calldata
  ) external pure override returns (uint16, bool) {
    return (0, false);
  }
}
