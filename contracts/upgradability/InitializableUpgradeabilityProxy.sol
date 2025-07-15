// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {BaseUpgradeabilityProxy} from "./BaseUpgradeabilityProxy.sol";
import {AddressHelper} from "../utils/AddressHelper.sol";

/**
 * @title InitializableUpgradeabilityProxy
 * @dev Extends BaseUpgradeabilityProxy with an initializer for initializing
 * implementation and init data.
 */
contract InitializableUpgradeabilityProxy is BaseUpgradeabilityProxy {
  using AddressHelper for address;

  /**
   * @dev Contract initializer.
   * @param _factory Address of the factory containing the implementation.
   * @param _data Data to send as msg.data to the implementation to initialize the proxied contract.
   * It should include the signature and the parameters of the function to be called, as described in
   * https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
   * This parameter is optional, if no data is given the initialization call to proxied contract will be skipped.
   */
  function initialize(address _factory, bytes memory _data, uint8 _proxyType) public payable {
    require(_implementation() == address(0), "Impl not zero");
    assert(IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
    _setImplementation(_factory);
    _setProxyType(_proxyType);
    if (_data.length > 0) {
      _implementation().tryAssemblyDelegateCall(_data);
    }
  }
}
