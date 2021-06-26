## `OpenZeppelinUpgradesAddress`

Utility library of inline functions on addresses

Source https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-solidity/v2.1.3/contracts/utils/Address.sol
This contract is copied here and renamed from the original to avoid clashes in the compiled artifacts
when the user imports a zos-lib contract (that transitively causes this contract to be compiled and added to the
build/artifacts folder) as well as the vanilla Address implementation from an openzeppelin version.




### `isContract(address account) → bool` (internal)

Returns whether the target address is a contract


This function will return false if invoked during the constructor of a contract,
as the code is not actually created until after the constructor finishes.



