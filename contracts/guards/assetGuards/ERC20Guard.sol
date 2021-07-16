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

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../IGuard.sol";
import "../IAssetGuard.sol";
import "../../utils/TxDataUtils.sol";
import "../../interfaces/IERC20Extended.sol"; // includes decimals()
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IManaged.sol";

/// @title Generic ERC20 asset guard
/// @dev Asset type = 0
/// @dev A generic ERC20 guard asset is Not stakeable ie. no 'getWithdrawStakedTx()' function
contract ERC20Guard is TxDataUtils, IGuard, IAssetGuard {
  using SafeMathUpgradeable for uint256;

  event Approve(address fundAddress, address manager, address spender, uint256 amount, uint256 time);

  /// @notice Transaction guard for approving assets
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param _poolManagerLogic Pool address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in PoolLogic
  function txGuard(
    address _poolManagerLogic,
    address, // to
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType // transaction type
    )
  {
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("approve(address,uint256)"))) {
      address spender = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);

      address factory = poolManagerLogic.factory();
      address spenderGuard = IHasGuardInfo(factory).getGuard(spender);
      require(spenderGuard != address(0) && spenderGuard != address(this), "unsupported spender approval"); // checks that the spender is an approved address

      emit Approve(
        poolManagerLogic.poolLogic(),
        IManaged(_poolManagerLogic).manager(),
        spender,
        amount,
        block.timestamp
      );

      txType = 1; // 'Approve' type
      return txType;
    }
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @dev Withdrawal processing is not applicable for this guard
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return withdrawContracts and
  /// @return txData are used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address // to
  )
    external
    view
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      address[] memory withdrawContracts,
      bytes[] memory txData
    )
  {
    withdrawAsset = asset;
    uint256 totalAssetBalance = getBalance(pool, asset);
    withdrawBalance = totalAssetBalance.mul(portion).div(10**18);
    return (withdrawAsset, withdrawBalance, withdrawContracts, txData);
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include any external balance in staking contracts
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view virtual override returns (uint256 balance) {
    // The base ERC20 guard has no externally staked tokens
    balance = IERC20(asset).balanceOf(pool);
  }

  /// @notice Returns the decimal of the managed asset
  function getDecimals(address asset) external view virtual override returns (uint256 decimals) {
    decimals = IERC20Extended(asset).decimals();
  }

  /// @notice Necessary check for remove asset
  /// @param pool Address of the pool
  /// @param asset Address of the remove asset
  function removeAssetCheck(address pool, address asset) external view virtual override {
    uint256 balance = getBalance(pool, asset);
    // Allowing some dust
    require(balance <= 10000, "clear your position first");
  }
}
