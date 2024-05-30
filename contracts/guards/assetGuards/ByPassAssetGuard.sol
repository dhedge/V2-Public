// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IAssetGuard.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IERC20Extended.sol"; // includes decimals()
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IManaged.sol";

/// @title Modified ERC20Guard
/// @dev Asset type = 999
/// @dev A special guard which can be used to rescue stuck tokens in a pool with non-transferable assets.
///      The non-transferable asset should have this as their guard.
contract ByPassAssetGuard is TxDataUtils, IGuard, IAssetGuard {
  using SafeMathUpgradeable for uint256;

  event Approve(address fundAddress, address manager, address spender, uint256 amount, uint256 time);

  /// @notice Transaction guard for approving assets
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param _poolManagerLogic Pool address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in PoolLogic
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address, // to
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);

    if (method == bytes4(keccak256("approve(address,uint256)"))) {
      address spender = convert32toAddress(getInput(data, 0));
      uint256 amount = uint256(getInput(data, 1));

      IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);

      address factory = poolManagerLogic.factory();
      address spenderGuard = IHasGuardInfo(factory).getContractGuard(spender);
      require(spenderGuard != address(0) && spenderGuard != address(this), "unsupported spender approval"); // checks that the spender is an approved address

      emit Approve(
        poolManagerLogic.poolLogic(),
        IManaged(_poolManagerLogic).manager(),
        spender,
        amount,
        block.timestamp
      );

      txType = 1; // 'Approve' type
    }

    return (txType, false);
  }

  /// @notice Creates transaction data for withdrawing tokens
  /// @dev Withdrawal processing is not applicable for this guard
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address // to
  )
    external
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    withdrawAsset = asset;
    uint256 totalAssetBalance = getBalance(pool, asset);
    withdrawBalance = totalAssetBalance.mul(portion).div(10 ** 18);
    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns the balance of the managed asset
  /// @dev This returns 0 as we don't want the withdrawProcessing to be halted
  ///      due to positive balance of the asset.
  /// @return balance The asset balance of given pool
  function getBalance(address, address) public view virtual override returns (uint256 balance) {
    return 0;
  }

  /// @notice Returns the decimal of the managed asset
  /// @param asset Address of the managed asset
  /// @return decimals The decimal of given asset
  function getDecimals(address asset) external view virtual override returns (uint256 decimals) {
    decimals = IERC20Extended(asset).decimals();
  }

  /// @notice Necessary check for remove asset
  /// @param pool Address of the pool
  /// @param asset Address of the remove asset
  function removeAssetCheck(address pool, address asset) public view virtual override {
    uint256 balance = getBalance(pool, asset);
    require(balance == 0, "cannot remove non-empty asset");
  }
}
