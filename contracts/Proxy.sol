// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

/**
 * @dev This is an auxiliary contract meant to be assigned as the admin of a {TransparentUpgradeableProxy}. For an
 * explanation of why you would want to use this see the documentation for {TransparentUpgradeableProxy}.
 */
contract OZProxy is TransparentUpgradeableProxy {
    constructor(address _logic, address admin_, bytes memory _data) public payable TransparentUpgradeableProxy(_logic, admin_, _data) {
    }
}

