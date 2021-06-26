## `BaseUpgradeabilityProxy`



This contract implements a proxy that allows to change the
implementation address to which it will delegate.
Such a change is called an implementation upgrade.


### `_implementation() → address` (internal)



Returns the current implementation.


### `_proxyType() → uint8` (internal)





### `_upgradeTo(address newImplementation)` (internal)



Upgrades the proxy to a new implementation.


### `_setImplementation(address newImplementation)` (internal)



Sets the implementation address of the proxy.


### `_setProxyType(uint8 proxyType)` (internal)



Sets type of the proxy.



### `Upgraded(address implementation)`



Emitted when the implementation is upgraded.


