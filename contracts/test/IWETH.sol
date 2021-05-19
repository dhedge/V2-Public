pragma solidity ^0.6.2;

interface IWETH {
    function deposit() external payable;
    function approve(address guy, uint wad) external returns (bool);
    function transfer(address dst, uint wad) external returns (bool);
}