pragma solidity ^0.6.2;

interface IAddressResolver {
    function getAddress(bytes32 name) external view returns (address);
}
