pragma solidity 0.7.6;

interface IWETH {
  function deposit() external payable;

  function approve(address guy, uint256 wad) external returns (bool);

  function transfer(address dst, uint256 wad) external returns (bool);

  function balanceOf(address user) external view returns (uint256);
}
