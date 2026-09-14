// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {ERC20Guard} from "./ERC20Guard.sol";
import {ICompoundV3Comet} from "../../interfaces/compound/ICompoundV3Comet.sol";

/// @title Compound V3 Comet asset guard
/// @dev Asset type = 28
/// @dev The asset oracle uses the underlying asset address eg. cUSDCv3 comet contract uses the USDC/USD oracle
contract CompoundV3CometAssetGuard is ERC20Guard {
  using SafeMath for uint256;

  /// @notice Transaction guard for a Comet, deliberately authorising nothing
  /// @dev A Comet reuses the ERC20 `approve(address,uint256)` selector to toggle account-manager
  ///      permission instead of setting an allowance, so inheriting ERC20Guard's approve authorisation
  ///      would let a manager grant a spender full rights over the pool's position, including
  ///      `withdrawFrom` to an arbitrary recipient. `PoolLogicLib` falls back to the asset guard
  ///      whenever `CompoundV3CometContractGuard` returns txType 0, which it does for `approve`.
  /// @dev Nothing legitimate is lost: supply and withdraw are authorised by the contract guard, and
  ///      supplying only needs an allowance on the base token, whose transaction targets the token
  ///      rather than the Comet.
  function txGuard(address, address, bytes calldata) external pure override returns (uint16 txType, bool) {
    return (txType, false);
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @return withdrawAsset withdrawal asset to pe processed by PoolLogic
  /// @return withdrawBalance are used to withdraw portion of asset balance to depositor
  /// @return transactions is used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _portion,
    address // _to
  )
    external
    view
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    ICompoundV3Comet comet = ICompoundV3Comet(_asset);

    uint256 totalAssetBalance = getBalance(_pool, _asset);

    withdrawAsset = comet.baseToken();

    if (totalAssetBalance > 0) {
      uint256 _assetWithdrawBalance = totalAssetBalance.mul(_portion).div(10 ** 18);

      transactions = new MultiTransaction[](1);

      transactions[0].to = address(comet);
      transactions[0].txData = abi.encodeWithSelector(
        ICompoundV3Comet.withdraw.selector,
        withdrawAsset,
        _assetWithdrawBalance
      );
    }

    // Note that `withdrawBalance` is 0 because PoolLogic will handle the withdrawn portion from Compound
    return (withdrawAsset, withdrawBalance, transactions);
  }
}
