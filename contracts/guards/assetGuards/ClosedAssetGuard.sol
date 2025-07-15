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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IAssetGuard.sol";
import "../../interfaces/guards/IGuard.sol";

// This should be the base for all AssetGuards that are not ERC20 or are ERC20 but should not be transferrable
abstract contract ClosedAssetGuard is TxDataUtils, IGuard, IAssetGuard {
  /// @notice Doesn't allow any transactions uses separate contract guard that should be migrated here
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @return txType transaction type described in PoolLogic
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address,
    address,
    bytes calldata
  )
    external
    pure
    virtual
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    return (txType, false);
  }

  /// @notice Returns the balance of the managed asset
  /// @dev May include any external balance in staking contracts
  /// @return balance The asset balance of given pool for the given asset
  function getBalance(address, address) public view virtual override returns (uint256) {
    revert("not implemented");
  }

  /// @notice Necessary check for remove asset
  /// @param pool Address of the pool
  /// @param asset Address of the remove asset
  function removeAssetCheck(address pool, address asset) public view virtual override {
    uint256 balance = getBalance(pool, asset);
    require(balance == 0, "cannot remove non-empty asset");
  }

  function withdrawProcessing(
    address,
    address,
    uint256,
    address
  ) external virtual override returns (address, uint256, MultiTransaction[] memory) {
    revert("not implemented");
  }
}
