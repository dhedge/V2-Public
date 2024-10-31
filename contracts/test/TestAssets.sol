// SPDX-License-Identifier: MIT
// solhint-disable-next-line one-contract-per-file
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

contract TestUSDT is ERC20 {
  using SafeMathUpgradeable for uint256;

  constructor(uint256 totalSupply) ERC20("Test USDT", "tUSDT") {
    _setupDecimals(6);
    _mint(msg.sender, totalSupply.mul(10 ** uint256(decimals())));
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}

contract TestUSDC is ERC20 {
  using SafeMathUpgradeable for uint256;

  constructor(uint256 totalSupply) ERC20("Test USDC", "tUSDC") {
    _setupDecimals(6);
    _mint(msg.sender, totalSupply.mul(10 ** uint256(decimals())));
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}

contract TestWETH is ERC20 {
  using SafeMathUpgradeable for uint256;

  constructor(uint256 totalSupply) ERC20("Test WETH", "tWETH") {
    _mint(msg.sender, totalSupply.mul(10 ** uint256(decimals())));
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}

contract ERC20Asset is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    _mint(msg.sender, 1000e18);
  }

  function burnAll(address owner) public {
    _burn(owner, balanceOf(owner));
  }
}

contract TestAssetWithFallback is ERC20 {
  using SafeMathUpgradeable for uint256;

  uint256 internal dummyVar;

  constructor(uint256 totalSupply) ERC20("Test Fallback Asset", "tFALL") {
    _mint(msg.sender, totalSupply.mul(10 ** uint256(decimals())));
  }

  /* solhint-disable */
  fallback() external {
    // Loop to consume all gas
    while (true) {
      ++dummyVar;
    }
  }
  /* solhint-enable */

  function burnAll(address owner) public {
    _burn(owner, balanceOf(owner));
  }

  function mint(address account, uint256 amount) public {
    _mint(account, amount);
  }
}
