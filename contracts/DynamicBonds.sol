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

import "./utils/AddressHelper.sol";
import "./interfaces/IERC20Extended.sol";

/// @title DynamicBonds
contract DynamicBonds is OwnableUpgradeable, PausableUpgradeable {
  using SafeMathUpgradeable for uint256;
  using AddressHelper for address;

  event SetBondTerms(uint256 payoutAvailable, uint256 expiryTimestamp);
  event UpdateBondOption(uint256 index, BondOption bondOption);
  event UpdateBondOptions(uint256[] index, BondOption[] bondOption);
  event AddBondOptions(BondOption[] bondOptions);
  event Deposit(address indexed user, uint256 bondId, uint256 payoutAmount, BondOption bondOption);
  event Claim(address indexed user, uint256 bondId);

  struct BondOption {
    uint256 price; // payout token sell prices in deposit token decimals.
    uint256 lockPeriod; // payout token lock period in seconds.
  }
  struct BondTerms {
    // the sale settings
    uint256 payoutAvailable; // amount of payout available to sell for the sale period
    uint256 expiryTimestamp; // when the sale period expires
    BondOption[] bondOptions; // payout sell options. e.g. 0: price for 1 week lockup, 1: price for 1 month lockup, 2: price for 6 months lockup, 3: price for 1 year lockup
  }
  struct Bond {
    // an instance of a bond that’s been issued to a user
    address bondOwner; // bond purchaser
    uint256 lockAmount; // payout token amount that is locked for the user
    BondOption bondOption; // bond option(price and lock period) at which the bond was purchased
    uint256 lockStartedAt; // lock start timestamp
    bool claimed; // if the payout token has been claimed by the user
  }
  struct BondView {
    uint256 bondId;
    // an instance of a bond that’s been issued to a user
    address bondOwner; // bond purchaser
    uint256 lockAmount; // payout token amount that is locked for the user
    BondOption bondOption; // bond option(price and lock period) at which the bond was purchased
    uint256 lockStartedAt; // lock start timestamp
    bool claimed; // if the payout token has been claimed by the user
  }

  address public depositToken; // token paid for principal eg. USDC
  address public payoutToken; // inflow token eg. DHT
  address public treasury; // receives payout token
  uint256 public depositTotal;
  uint256 public debtTotal; // tracks the total amount of owed payout tokens
  uint256 public bondNumber; // tracks total number of issued bonds

  BondTerms public bondTerms;
  mapping(uint256 => Bond) public bonds; // get an issued bond
  mapping(address => uint256[]) public userBonds; // get the list of all user issued bond IDs

  uint256 public minBondPrice; // safety to ensure a very low price isn’t set accidentally
  uint256 public maxPayoutAvailable; // safety to ensure a high sell amount isn’t set accidentally

  uint256 private _payoutTokenUnit;

  function initialize(
    address _depositToken,
    address _payoutToken,
    address _treasury,
    uint256 _minBondPrice,
    uint256 _maxPayoutAvailable
  ) external initializer {
    __Ownable_init();
    __Pausable_init();

    depositToken = _depositToken;
    payoutToken = _payoutToken;
    treasury = _treasury;
    minBondPrice = _minBondPrice;
    maxPayoutAvailable = _maxPayoutAvailable;

    _payoutTokenUnit = 10**IERC20Extended(_payoutToken).decimals();
  }

  // ========== VIEWS ==========

  function bondOptions() external view returns (BondOption[] memory) {
    return bondTerms.bondOptions;
  }

  function getUserBonds(address _user) external view returns (BondView[] memory bondsArray) {
    uint256[] memory bondIds = userBonds[_user];
    bondsArray = new BondView[](bondIds.length);
    for (uint256 i = 0; i < bondIds.length; i++) {
      Bond memory bond = bonds[bondIds[i]];
      bondsArray[i] = BondView({
        bondId: bondIds[i],
        bondOwner: bond.bondOwner,
        lockAmount: bond.lockAmount,
        bondOption: bond.bondOption,
        lockStartedAt: bond.lockStartedAt,
        claimed: bond.claimed
      });
    }
  }

  // ========== MUTATIVE FUNCTIONS ==========

  /// @notice Update treasury
  /// @dev owner can set a new treasury address
  /// @param _treasury new treasury address
  function setTreasury(address _treasury) external onlyOwner {
    treasury = _treasury;
  }

  /// @notice Update minimum principal price
  /// @dev owner can update the minimum principal price
  /// @param _minBondPrice minimum principal price
  function setMinBondPrice(uint256 _minBondPrice) external onlyOwner {
    minBondPrice = _minBondPrice;
  }

  /// @notice Update maximum payout available
  /// @dev owner can update the maximum payout available
  /// @param _maxPayoutAvailable maximum payout available
  function setMaxPayoutAvailable(uint256 _maxPayoutAvailable) external onlyOwner {
    maxPayoutAvailable = _maxPayoutAvailable;
  }

  /// @notice Initializes the bond terms
  /// @dev only owner can set bond terms
  /// @param _payoutAvailable available payout amount
  /// @param _expiryTimestamp expired timestamp
  function setBondTerms(uint256 _payoutAvailable, uint256 _expiryTimestamp) external onlyOwner {
    require(_payoutAvailable <= maxPayoutAvailable, "exceed max available payout");
    require(_expiryTimestamp > block.timestamp, "invalid expiry timestamp");

    bondTerms.payoutAvailable = _payoutAvailable;
    bondTerms.expiryTimestamp = _expiryTimestamp;

    emit SetBondTerms(_payoutAvailable, _expiryTimestamp);
  }

  /// @notice add bond options
  /// @dev only owner can set bond terms
  /// @param _bondOptions bond options
  function addBondOptions(BondOption[] memory _bondOptions) external onlyOwner {
    for (uint256 i = 0; i < _bondOptions.length; i++) {
      require(_bondOptions[i].price >= minBondPrice, "too low payout price");
      bondTerms.bondOptions.push(_bondOptions[i]);
    }

    emit AddBondOptions(_bondOptions);
  }

  /// @notice update bond option
  /// @dev only owner can set bond terms
  /// @param _index bond option index
  /// @param _bondOption bond option
  function _updateBondOption(uint256 _index, BondOption memory _bondOption) internal {
    require(_index < bondTerms.bondOptions.length, "invalid index");
    require(_bondOption.price >= minBondPrice, "too low payout price");
    bondTerms.bondOptions[_index] = _bondOption;
  }

  /// @notice update bond option
  /// @dev only owner can set bond terms
  /// @param _index bond option index
  /// @param _bondOption bond option
  function updateBondOption(uint256 _index, BondOption memory _bondOption) external onlyOwner {
    _updateBondOption(_index, _bondOption);

    emit UpdateBondOption(_index, _bondOption);
  }

  /// @notice update bond options
  /// @dev only owner can set bond terms
  /// @param _indexes bond option index list
  /// @param _bondOptions bond options list
  function updateBondOptions(uint256[] memory _indexes, BondOption[] memory _bondOptions) external onlyOwner {
    require(_indexes.length == _bondOptions.length, "length doesn't match");
    for (uint256 i = 0; i < _indexes.length; i++) {
      _updateBondOption(_indexes[i], _bondOptions[i]);
    }

    emit UpdateBondOptions(_indexes, _bondOptions);
  }

  /// @notice Creates a new bond for the user
  /// @param _payoutAmount payout amount
  /// @param _bondOptionIndex bond option index
  function deposit(
    uint256 _maxDepositAmount,
    uint256 _payoutAmount,
    uint256 _bondOptionIndex
  ) external {
    require(block.timestamp <= bondTerms.expiryTimestamp, "expired");
    require(_payoutAmount <= bondTerms.payoutAvailable, "insufficient available payout");
    require(_bondOptionIndex < bondTerms.bondOptions.length, "invalid bond option index");

    BondOption memory bondOption = bondTerms.bondOptions[_bondOptionIndex];
    require(bondOption.price >= minBondPrice, "too low payout price");
    uint256 needToPay = _payoutAmount.mul(bondOption.price).div(_payoutTokenUnit);
    require(needToPay <= _maxDepositAmount, "deposit amount exceeded");
    depositToken.tryAssemblyCall(
      abi.encodeWithSelector(IERC20Extended.transferFrom.selector, msg.sender, treasury, needToPay)
    );

    bonds[bondNumber] = Bond({
      bondOwner: msg.sender,
      lockAmount: _payoutAmount,
      bondOption: bondOption,
      lockStartedAt: block.timestamp,
      claimed: false
    });

    userBonds[msg.sender].push(bondNumber);
    bondTerms.payoutAvailable = bondTerms.payoutAvailable.sub(_payoutAmount);
    depositTotal = depositTotal.add(needToPay);
    debtTotal = debtTotal.add(_payoutAmount);

    emit Deposit(msg.sender, bondNumber, _payoutAmount, bondOption);

    bondNumber++;
  }

  /// @notice Transfers lockAmount to bondOwner after lockEndTimestamp
  /// @param _bondId bond index
  function claim(uint256 _bondId) external {
    require(_bondId < bondNumber, "invalid bond index");

    Bond storage bond = bonds[_bondId];
    require(bond.bondOwner == msg.sender, "unauthorized");
    require(bond.lockStartedAt.add(bond.bondOption.lockPeriod) <= block.timestamp, "locked");
    require(!bond.claimed, "already claimed");

    bond.claimed = true;
    debtTotal = debtTotal.sub(bond.lockAmount);
    payoutToken.tryAssemblyCall(abi.encodeWithSelector(IERC20Extended.transfer.selector, msg.sender, bond.lockAmount));

    emit Claim(msg.sender, _bondId);
  }

  /// @notice Withdraw ERC20 tokens
  /// @dev owner can withdraw any erc20 tokens
  /// @param _token ERC20 token address
  /// @param _amount ERC20 token amount to withdraw
  function forceWithdraw(address _token, uint256 _amount) external onlyOwner {
    _token.tryAssemblyCall(abi.encodeWithSelector(IERC20Extended.transfer.selector, msg.sender, _amount));
  }
}
