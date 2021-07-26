// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./Proxy.sol";
import "./Address.sol";
import "./HasLogic.sol";

/**
 * @title BaseUpgradeabilityProxy
 * @dev This contract implements a proxy that allows to change the
 * implementation address to which it will delegate.
 * Such a change is called an implementation upgrade.
 */
contract BaseUpgradeabilityProxy is Proxy {
  /**
   * @dev Emitted when the implementation is upgraded.
   * @param implementation Address of the new implementation.
   */
  event Upgraded(address indexed implementation);

  /**
   * @dev Storage slot with the address of the current implementation.
   * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
   * validated in the constructor.
   */
  bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  /**
   * @dev Storing type of the proxy, 1 for managerLogic, 2 for pool.
   */
  bytes32 internal constant PROXY_TYPE = 0x1000000000000000000000000000000000000000000000000000000000000000;

  /**
   * @dev Returns the current implementation.
   * @return impl Address of the current implementation
   */
  function _implementation() internal view override returns (address) {
    address factory;
    bytes32 slot = IMPLEMENTATION_SLOT;
    assembly {
      factory := sload(slot)
    }

    // Begin custom modification
    if (factory == address(0x0)) return address(0x0); // If factory not initialized return empty

    return HasLogic(factory).getLogic(_proxyType());
  }

  /// @dev Return the proxy type.
  /// @return proxyType Return type of the proxy.
  function _proxyType() internal view returns (uint8 proxyType) {
    bytes32 slot = PROXY_TYPE;
    assembly {
      proxyType := sload(slot)
    }
  }

  /**
   * @dev Upgrades the proxy to a new implementation.
   * @param newImplementation Address of the new implementation.
   */
  function _upgradeTo(address newImplementation) internal {
    _setImplementation(newImplementation);
    emit Upgraded(newImplementation);
  }

  /**
   * @dev Sets the implementation address of the proxy.
   * @param newImplementation Address of the new implementation.
   */
  function _setImplementation(address newImplementation) internal {
    require(OpenZeppelinUpgradesAddress.isContract(newImplementation), "Cannot set implementation to EOA");

    bytes32 slot = IMPLEMENTATION_SLOT;

    assembly {
      sstore(slot, newImplementation)
    }
  }

  /**
   * @dev Sets type of the proxy.
   * @param proxyType type of the proxy.
   */
  function _setProxyType(uint8 proxyType) internal {
    bytes32 slot = PROXY_TYPE;

    assembly {
      sstore(slot, proxyType)
    }
  }
}
