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
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../EasySwapper/DhedgeEasySwapper.sol";
import "../../EasySwapper/EasySwapperStructs.sol";

/// @title Transaction guard for Dhedge EasySwapper
contract EasySwapperGuard is TxDataUtils, IGuard {
  using SafeMathUpgradeable for uint256;

  event Deposit(address fundAddress, address depositAsset, uint256 time);
  event Withdraw(address fundAddress, address from, address withdrawalAsset, uint256 time);

  /// @notice Transaction guard for EasySwapper - used for Toros
  /// @dev It supports Deposit, and Withdraw
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address easySwapper, // to
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType,
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    // The pool the manager is operating against
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    if (method == DhedgeEasySwapper.deposit.selector) {
      // I.e asset == EthBear2x
      (address assetToReceive, , , , ) = abi.decode(getParams(data), (address, address, uint256, address, uint256));

      require(poolManagerLogicAssets.isSupportedAsset(assetToReceive), "unsupported asset");

      emit Deposit(poolLogic, assetToReceive, block.timestamp);
      txType = 18; // Deposit: EasySwapper Deposit
    } else if (method == DhedgeEasySwapper.withdraw.selector) {
      // I.e from == EthBear2x
      (address withdrawingFrom, , address withdrawAsset, ) = abi.decode(
        getParams(data),
        (address, uint256, address, uint256)
      );
      require(poolManagerLogicAssets.isSupportedAsset(withdrawAsset), "unsupported asset");

      emit Withdraw(poolLogic, withdrawingFrom, withdrawAsset, block.timestamp);
      txType = 19; // Withdraw: EasySwapper Withdraw
    } else if (method == DhedgeEasySwapper.withdrawSUSD.selector) {
      // I.e from == EthBear2x
      (address withdrawingFrom, , , ) = abi.decode(getParams(data), (address, uint256, address, uint256));
      (, , , EasySwapperStructs.SynthetixProps memory synthetixProps, , ) = DhedgeEasySwapper(payable(easySwapper))
        .withdrawProps();
      address susd = address(synthetixProps.sUSDProxy);
      require(poolManagerLogicAssets.isSupportedAsset(susd), "unsupported asset");

      emit Withdraw(poolLogic, withdrawingFrom, susd, block.timestamp);
      txType = 19; // Withdraw: EasySwapper Withdraw
    } else if (method == DhedgeEasySwapper.withdrawIntermediate.selector) {
      // I.e from == EthBear2x
      (address withdrawingFrom, , , address withdrawAsset, ) = abi.decode(
        getParams(data),
        (address, uint256, address, address, uint256)
      );
      require(poolManagerLogicAssets.isSupportedAsset(withdrawAsset), "unsupported asset");

      emit Withdraw(poolLogic, withdrawingFrom, withdrawAsset, block.timestamp);
      txType = 19; // Withdraw: EasySwapper Withdraw
    }

    return (txType, false);
  }
}
