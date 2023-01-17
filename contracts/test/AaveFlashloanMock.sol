// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IAaveFlashloanReceiver {
  function executeOperation(
    address[] memory assets,
    uint256[] memory amounts,
    uint256[] memory premiums,
    address originator,
    bytes memory params
  ) external returns (bool success);
}

contract AaveFlashloanMock {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  function flashLoan(
    address receiverAddress,
    address[] memory assets,
    uint256[] memory amounts,
    uint256[] memory, // modes
    address, // onBehalfOf,
    bytes memory params,
    uint16 // referralCode
  ) external {
    for (uint256 i = 0; i < assets.length; i++) {
      IERC20(assets[i]).safeTransfer(receiverAddress, amounts[i]);
    }

    // mock 0.1% premiums
    uint256[] memory premiums = new uint256[](assets.length);
    for (uint256 i = 0; i < assets.length; i++) {
      premiums[i] = amounts[i].div(1000);
    }

    require(
      IAaveFlashloanReceiver(receiverAddress).executeOperation(assets, amounts, premiums, msg.sender, params),
      "failed to execute operation"
    );

    for (uint256 i = 0; i < assets.length; i++) {
      IERC20(assets[i]).safeTransferFrom(receiverAddress, address(this), amounts[i].add(premiums[i]));
    }
  }
}
