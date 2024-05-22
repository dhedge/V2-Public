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

import "./ERC20Guard.sol";
import "../../interfaces/IPoolFactory.sol";
import "../../interfaces/IGovernance.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/aave/IAaveProtocolDataProvider.sol";

/// @title Lending/Borrowing enabled token asset guard eg Aave
/// @dev Asset type = 4
contract LendingEnabledAssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;

  /// @notice Checks that asset can be removed from supported pool assets
  /// @dev Cannot remove asset if it's deposited in Aave
  /// @dev Additional lending / borrowing protocol checks can be added in the future
  function removeAssetCheck(address pool, address asset) public view override {
    super.removeAssetCheck(pool, asset);
    // check AAVE lending balances
    // returns address(0) if it's not supported in aave
    address factory = IPoolManagerLogic(pool).factory();
    address governance = IPoolFactory(factory).governanceAddress();

    _checkBalance(pool, asset, IGovernance(governance).nameToDestination("aaveProtocolDataProviderV2"));
    _checkBalance(pool, asset, IGovernance(governance).nameToDestination("aaveProtocolDataProviderV3"));
  }

  function _checkBalance(address pool, address asset, address aaveProtocolDataProvider) internal view {
    if (aaveProtocolDataProvider != address(0)) {
      (address aToken, address stableDebtToken, address variableDebtToken) = IAaveProtocolDataProvider(
        aaveProtocolDataProvider
      ).getReserveTokensAddresses(asset);

      if (stableDebtToken != address(0)) require(IERC20(stableDebtToken).balanceOf(pool) == 0, "repay Aave debt first");
      if (variableDebtToken != address(0))
        require(IERC20(variableDebtToken).balanceOf(pool) == 0, "repay Aave debt first");
      if (aToken != address(0)) require(IERC20(aToken).balanceOf(pool) == 0, "withdraw Aave collateral first");
    }
  }
}
