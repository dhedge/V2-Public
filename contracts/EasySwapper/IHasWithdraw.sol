// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EasySwapperWithdrawer.sol";

interface IHasWithdraw {
  function withdraw(
    address pool,
    uint256 fundTokenAmount,
    IERC20 withdrawalAsset,
    uint256 expectedAmountOut,
    EasySwapperWithdrawer.WithdrawProps memory withdrawProps
  ) external;
}
