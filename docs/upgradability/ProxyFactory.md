This contract is used to deploy the proxy contract.

# Functions:
- [`setLogic(address _poolLogic, address _poolManagerLogic)`](#ProxyFactory-setLogic-address-address-)
- [`getLogic(uint8 _proxyType)`](#ProxyFactory-getLogic-uint8-)
- [`deploy(bytes _data, uint8 _proxyType)`](#ProxyFactory-deploy-bytes-uint8-)

# Events:
- [`ProxyCreated(address proxy)`](#ProxyFactory-ProxyCreated-address-)




# Function `setLogic(address _poolLogic, address _poolManagerLogic)` {#ProxyFactory-setLogic-address-address-}
Setting logic address for both poolLogic and poolManagerLogic


## Parameters:
- `_poolLogic`: address of the pool logic

- `_poolManagerLogic`: address of the pool manager logic



# Function `getLogic(uint8 _proxyType) → address` {#ProxyFactory-getLogic-uint8-}
Return logic address of the pool or the pool manager logic




# Function `deploy(bytes _data, uint8 _proxyType) → address` {#ProxyFactory-deploy-bytes-uint8-}
Deploy proxy contract external call








# Event `ProxyCreated(address proxy)` {#ProxyFactory-ProxyCreated-address-}
No description

