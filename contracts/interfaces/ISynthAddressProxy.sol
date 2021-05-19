pragma solidity ^0.6.2;

interface ISynthAddressProxy {
    function target() external view returns (address synthAsset);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}
