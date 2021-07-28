

# Functions:
- [`setContractGuard(address extContract, address guardAddress)`](#Governance-setContractGuard-address-address-)
- [`setAssetGuard(uint16 assetType, address guardAddress)`](#Governance-setAssetGuard-uint16-address-)
- [`setAddresses(struct Governance.ContractName[] contractNames)`](#Governance-setAddresses-struct-Governance-ContractName---)

# Events:
- [`ContractGuardSet(address extContract, address guardAddress)`](#Governance-ContractGuardSet-address-address-)
- [`AssetGuardSet(uint16 assetType, address guardAddress)`](#Governance-AssetGuardSet-uint16-address-)
- [`AddressSet(bytes32 name, address destination)`](#Governance-AddressSet-bytes32-address-)


# Function `setContractGuard(address extContract, address guardAddress)` {#Governance-setContractGuard-address-address-}
Maps an exernal contract to a guard which enables managers to use the contract


## Parameters:
- `extContract`: The third party contract to integrate

- `guardAddress`: The protections for manager third party contract interaction





# Function `setAssetGuard(uint16 assetType, address guardAddress)` {#Governance-setAssetGuard-uint16-address-}
Maps an asset type to an asset guard which allows managers to enable the asset


## Parameters:
- `assetType`: Asset type as defined in Asset Handler

- `guardAddress`: The asset guard address that allows manager interaction





# Function `setAddresses(struct Governance.ContractName[] contractNames)` {#Governance-setAddresses-struct-Governance-ContractName---}
Maps multiple contract names to destination addresses


## Parameters:
- `contractNames`: The contract names and addresses struct



# Event `ContractGuardSet(address extContract, address guardAddress)` {#Governance-ContractGuardSet-address-address-}
No description

# Event `AssetGuardSet(uint16 assetType, address guardAddress)` {#Governance-AssetGuardSet-uint16-address-}
No description

# Event `AddressSet(bytes32 name, address destination)` {#Governance-AddressSet-bytes32-address-}
No description

