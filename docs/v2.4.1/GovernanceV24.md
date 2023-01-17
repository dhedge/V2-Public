

# Functions:
- [`setContractGuard(address extContract, address guardAddress)`](#GovernanceV24-setContractGuard-address-address-)
- [`setAssetGuard(uint16 assetType, address guardAddress)`](#GovernanceV24-setAssetGuard-uint16-address-)
- [`setAddresses(struct GovernanceV24.ContractName[] contractNames)`](#GovernanceV24-setAddresses-struct-GovernanceV24-ContractName---)

# Events:
- [`ContractGuardSet(address extContract, address guardAddress)`](#GovernanceV24-ContractGuardSet-address-address-)
- [`AssetGuardSet(uint16 assetType, address guardAddress)`](#GovernanceV24-AssetGuardSet-uint16-address-)
- [`AddressSet(bytes32 name, address destination)`](#GovernanceV24-AddressSet-bytes32-address-)


# Function `setContractGuard(address extContract, address guardAddress)` {#GovernanceV24-setContractGuard-address-address-}
Maps an exernal contract to a guard which enables managers to use the contract


## Parameters:
- `extContract`: The third party contract to integrate

- `guardAddress`: The protections for manager third party contract interaction





# Function `setAssetGuard(uint16 assetType, address guardAddress)` {#GovernanceV24-setAssetGuard-uint16-address-}
Maps an asset type to an asset guard which allows managers to enable the asset


## Parameters:
- `assetType`: Asset type as defined in Asset Handler

- `guardAddress`: The asset guard address that allows manager interaction





# Function `setAddresses(struct GovernanceV24.ContractName[] contractNames)` {#GovernanceV24-setAddresses-struct-GovernanceV24-ContractName---}
Maps multiple contract names to destination addresses


## Parameters:
- `contractNames`: The contract names and addresses struct



