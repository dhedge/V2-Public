// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IERC20Extended.sol";

/// @title Private token swap
/// @notice Allows for fixed exchange rate swaps of an original token to an exchange token
/// @notice Only a specified user account can interact with the contract
/// @notice User can withdraw original token balance also
contract PrivateTokenSwap is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using Math for uint256;

  // The original token that can be swapped
  IERC20 public originalToken;

  // The exchange token that can be received in the swap
  IERC20 public exchangeToken;

  // The fixed price at which the original token can be exchanged for the exchange token
  uint256 public exchangeRate;
  uint256 public constant EXCHANGE_RATE_DECIMALS = 18;

  // The user that is alone able to call the withdraw and swap functions
  address public user;

  constructor(
    IERC20 _originalToken,
    IERC20 _exchangeToken,
    uint256 _exchangeRate,
    address _user
  ) {
    originalToken = _originalToken;
    exchangeToken = _exchangeToken;
    exchangeRate = _exchangeRate; // 18 decimals
    user = _user;
  }

  // Only the user specified in the contract can interact with it
  modifier onlyUser() {
    require(msg.sender == user, "Only user can interact");
    _;
  }

  // ----- User functions ----- //

  /// @notice Allows the user to withdraw the original token but only if there are exchange tokens in the contract
  /// @dev The exchangeBalance check prevents further withdrawals after the swap.
  function withdraw() public onlyUser {
    uint256 exchangeBalance = exchangeToken.balanceOf(address(this));
    require(exchangeBalance > 0, "No exchange token balance");

    uint256 originalBalance = originalToken.balanceOf(address(this));

    uint256 exchangeRateAdjusted = getExchangeRateAdjusted();
    uint256 withdrawalAmountMax = exchangeBalance.mul(10**EXCHANGE_RATE_DECIMALS).div(exchangeRateAdjusted);

    originalToken.safeTransfer(user, withdrawalAmountMax.min(originalBalance));
  }

  /// @notice Allows the user to exchange their original token for the exchange token at the fixed price
  /// @notice It takes as much as possible from the user's wallet of the original token to swap
  function swapAll() public onlyUser {
    uint256 originalBalance = originalToken.balanceOf(msg.sender);
    uint256 exchangeBalance = exchangeToken.balanceOf(address(this));
    uint256 exchangeRateAdjusted = getExchangeRateAdjusted();

    uint256 exchangeAmountMax = originalBalance.mul(exchangeRateAdjusted).div(10**EXCHANGE_RATE_DECIMALS);

    if (exchangeBalance >= exchangeAmountMax) {
      // Swap the full balance of originalToken from user's wallet
      originalToken.safeTransferFrom(user, address(this), originalBalance);
      exchangeToken.safeTransfer(user, exchangeAmountMax);
    } else {
      // Swap the full balance of exchangeToken
      originalToken.safeTransferFrom(
        msg.sender,
        address(this),
        exchangeBalance.mul(10**EXCHANGE_RATE_DECIMALS).div(exchangeRateAdjusted)
      );
      exchangeToken.safeTransfer(msg.sender, exchangeBalance);
    }
  }

  // ----- Owner functions ----- //

  /// @notice Allows the contract owner to withdraw any ERC20 token in the contract
  function withdrawAdmin(IERC20 _token, uint256 _amount) public onlyOwner {
    _token.safeTransfer(msg.sender, _amount);
  }

  function setExchangeRate(uint256 _exchangeRate) public onlyOwner {
    require(exchangeRate > 0, "Invalid exchange rate");
    exchangeRate = _exchangeRate;
  }

  // ----- Public functions ----- //

  /// @notice Gets a decimals adjusted exchange rate
  function getExchangeRateAdjusted() public view returns (uint256 exchangeRateAdjusted) {
    uint256 originalTokenUnit = 10**IERC20Extended(address(originalToken)).decimals();
    uint256 exchangeTokenUnit = 10**IERC20Extended(address(exchangeToken)).decimals();
    exchangeRateAdjusted = exchangeRate.mul(exchangeTokenUnit).div(originalTokenUnit);
    require(exchangeRateAdjusted > 0, "Invalid exchange rate");
  }
}
