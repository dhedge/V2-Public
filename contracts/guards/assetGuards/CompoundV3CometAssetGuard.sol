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
