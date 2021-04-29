pragma solidity ^0.6.2;

interface ISynthAddressProxy {
    function target() external view returns (address synthAsset);
}
