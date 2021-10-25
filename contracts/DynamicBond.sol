//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "./interfaces/IERC20Extended.sol"; // includes decimals()

/// @title DynamicBond
contract DynamicBond is OwnableUpgradeable, PausableUpgradeable {
  using SafeMathUpgradeable for uint256;
  using SafeERC20Upgradeable for IERC20Extended;

  event SetBondTerms(uint256 principalAvailable, uint256 expiryTimestamp);
  event UpdateBondPrice(uint256 index, PrincipalPrice principalPrice);
  event AddBondPrices(PrincipalPrice[] principalPrices);
  event Deposit(
    address indexed user,
    uint256 bondId,
    uint256 principalAmount,
    uint256 principalPrice,
    uint256 lockPeriod
  );
  event Claim(address indexed user, uint256 bondId);

  struct PrincipalPrice {
    uint256 price; // principal token sell prices in 18 decimals.
    uint256 lockPeriod; // principal lock period in seconds.
  }
  struct BondTerms {
    // the sale settings
    uint256 principalAvailable; // amount of principal available to sell for the sale period
    uint256 expiryTimestamp; // when the sale period expires
    PrincipalPrice[] principalPrices; // principal token sell prices in 18 decimals. e.g. 0: price for 1 week lockup, 1: price for 1 month lockup, 2: price for 6 months lockup, 3: price for 1 year lockup
  }
  struct Bond {
    // an instance of a bond that’s been issued to a user
    uint256 principalLockAmount; // amount of principal that is locked for the user
    bool principalClaimed; // if the principal has been claimed by the user
    uint256 principalPrice; // principal token price at which the bond was purchased
    address bondOwner; // bond purchaser
    uint256 lockStartTimestamp; // starting timestamp for the principal lockup
    uint256 lockEndTimestamp; // ending timestamp for the principal lockup
  }

  IERC20Extended public payoutToken; // token paid for principal eg. USDC
  IERC20Extended public principalToken; // inflow token eg. DHT
  address public treasury; // receives payout token
  uint256 public debtTotal; // tracks the total amount of owed principal tokens
  uint256 public bondNumber; // tracks total number of issued bonds

  BondTerms public bondTerms;
  mapping(uint256 => Bond) public bonds; // get an issued bond
  mapping(address => uint256[]) public userBonds; // get the list of all user issued bond IDs

  uint256 private minPrincipalPrice; // safety to ensure a very low price isn’t set accidentally
  uint256 private maxPrincipalAvailable; // safety to ensure a high sell amount isn’t set accidentally

  function initialize(
    address _payoutToken,
    address _principalToken,
    address _treasury,
    uint256 _minPrincipalPrice,
    uint256 _maxPrincipalAvailable
  ) external initializer {
    __Ownable_init();
    __Pausable_init();

    payoutToken = IERC20Extended(_payoutToken);
    principalToken = IERC20Extended(_principalToken);
    treasury = _treasury;
    minPrincipalPrice = _minPrincipalPrice;
    maxPrincipalAvailable = _maxPrincipalAvailable;
  }

  /// @notice Initializes the bond terms
  /// @dev only owner can set bond terms
  /// @param _principalAvailable avaialble principal amount
  /// @param _expiryTimestamp expired timestamp
  function setBondTerms(uint256 _principalAvailable, uint256 _expiryTimestamp) external onlyOwner {
    require(_principalAvailable <= maxPrincipalAvailable, "exceed max avaialble principal");
    bondTerms.principalAvailable = _principalAvailable;
    bondTerms.expiryTimestamp = _expiryTimestamp;

    emit SetBondTerms(_principalAvailable, _expiryTimestamp);
  }

  /// @notice add bond principal prices
  /// @dev only owner can set bond terms
  /// @param _principalPrices principal prices
  function addBondPrices(PrincipalPrice[] memory _principalPrices) external onlyOwner {
    for (uint256 i = 0; i < _principalPrices.length; i++) {
      require(_principalPrices[i].price >= minPrincipalPrice, "invalid principalPrices");
      bondTerms.principalPrices.push(_principalPrices[i]);
    }

    emit AddBondPrices(_principalPrices);
  }

  /// @notice update bond principal prices
  /// @dev only owner can set bond terms
  /// @param _index principal price index
  /// @param _principalPrice principal price
  function updateBondPrice(uint256 _index, PrincipalPrice memory _principalPrice) external onlyOwner {
    require(_index < bondTerms.principalPrices.length, "invalid index");
    require(_principalPrice.price >= minPrincipalPrice, "invalid principalPrices");
    bondTerms.principalPrices[_index] = _principalPrice;

    emit UpdateBondPrice(_index, _principalPrice);
  }

  /// @notice Creates a new bond for the user
  /// @param _principalAmount principal amount
  /// @param _principalPriceIndex principal price index
  function deposit(
    uint256 _principalAmount,
    uint256 _principalPriceIndex,
    uint256 _lockPeriod
  ) external {
    require(_principalAmount <= bondTerms.principalAvailable, "insufficient avaialble principal");
    require(_principalPriceIndex < bondTerms.principalPrices.length, "invalid principal price index");

    PrincipalPrice memory principalPrice = bondTerms.principalPrices[_principalPriceIndex];
    require(principalPrice.lockPeriod == _lockPeriod, "lock option not match");
    uint256 needToPay = _principalAmount.mul(principalPrice.price).div(1e18);
    payoutToken.transferFrom(msg.sender, treasury, needToPay);

    bonds[bondNumber] = Bond({
      principalLockAmount: _principalAmount,
      principalClaimed: false,
      principalPrice: principalPrice.price,
      bondOwner: msg.sender,
      lockStartTimestamp: block.timestamp,
      lockEndTimestamp: block.timestamp + principalPrice.lockPeriod
    });
    bondNumber++;

    userBonds[msg.sender].push(bondNumber - 1);
    bondTerms.principalAvailable -= _principalAmount;
    debtTotal += _principalAmount;

    emit Deposit(msg.sender, bondNumber - 1, _principalAmount, principalPrice.price, _lockPeriod);
  }

  /// @notice Transfers principalLockAmount to bondOwner after lockEndTimestamp
  /// @param _bondId bond index
  function claim(uint256 _bondId) external {
    require(_bondId < bondNumber, "invalid bond index");

    Bond storage bond = bonds[_bondId];
    require(bond.bondOwner == msg.sender, "unauthorized");
    require(bond.lockEndTimestamp <= block.timestamp, "locked");
    require(!bond.principalClaimed, "principal already claimed");

    bond.principalClaimed = true;
    debtTotal -= bond.principalLockAmount;
    require(principalToken.transfer(msg.sender, bond.principalLockAmount), "failed to transfer");

    emit Claim(msg.sender, _bondId);
  }

  /// @notice Withdraw ERC20 tokens
  /// @dev owner can withdraw any erc20 tokens
  /// @param _token ERC20 token address
  /// @param _amount ERC20 token amount to withdraw
  function forceWithdraw(IERC20Extended _token, uint256 _amount) external onlyOwner {
    require(_token.transfer(msg.sender, _amount), "failed to transfer");
  }

  /// @notice Update treasury
  /// @dev owner can set a new treasury address
  /// @param _treasury new treasury address
  function forceWithdraw(address _treasury) external onlyOwner {
    treasury = _treasury;
  }
}
