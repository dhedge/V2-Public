// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {ERC20Guard} from "../ERC20Guard.sol";
import {IFToken} from "../../../interfaces/fluid/IFToken.sol";

contract FluidTokenAssetGuard is ERC20Guard {
  using SafeMath for uint256;

  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _portion,
    address /* _to */
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    uint256 totalAssetBalance = getBalance(_pool, _asset);

    withdrawAsset = IFToken(_asset).asset();

    if (totalAssetBalance > 0) {
      uint256 assetWithdrawBalance = totalAssetBalance.mul(_portion).div(1e18);

      transactions = new MultiTransaction[](1);
      // Another way is to redeem directly to _to address
      transactions[0].to = _asset;
      transactions[0].txData = abi.encodeWithSelector(IFToken.redeem.selector, assetWithdrawBalance, _pool, _pool);
    }

    // Note that `withdrawBalance` is 0 because PoolLogic will handle the withdrawn portion from Fluid
    return (withdrawAsset, withdrawBalance, transactions);
  }
}
