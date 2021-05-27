pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestUSDT is ERC20 {
  constructor(uint256 totalSupply) public ERC20("Test USDT", "tUSDT") {
    _setupDecimals(6);
    _mint(msg.sender, totalSupply.mul(10**uint256(decimals())));
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}

contract TestUSDC is ERC20 {
  constructor(uint256 totalSupply) public ERC20("Test USDC", "tUSDC") {
    _setupDecimals(6);
    _mint(msg.sender, totalSupply.mul(10**uint256(decimals())));
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}

contract TestWETH is ERC20 {
  constructor(uint256 totalSupply) public ERC20("Test WETH", "tWETH") {
    _mint(msg.sender, totalSupply.mul(10**uint256(decimals())));
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}
