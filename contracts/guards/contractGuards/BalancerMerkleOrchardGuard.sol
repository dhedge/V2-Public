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

import "@openzeppelin/contracts-upgradeable/math/SignedSafeMathUpgradeable.sol";

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/balancer/IBalancerMerkleOrchard.sol";

/// @notice Transaction guard for Balancer claiming distribution rewards
contract BalancerMerkleOrchardGuard is TxDataUtils, IGuard {
  using SignedSafeMathUpgradeable for int256;

  event Claim(address fundAddress, address stakingContract, uint256 time);

  /// @notice Transaction guard for Balancer V2 Merkle Orchard
  /// @dev It supports reward distribution claiming
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data. 2 for `Exchange` type
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    override
    returns (
      uint16 txType, // transaction type
      bool isPublic // can anyone execute
    )
  {
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(_poolManagerLogic);

    bytes4 method = getMethod(data);

    if (method == IBalancerMerkleOrchard.claimDistributions.selector) {
      (address claimer, , IERC20[] memory tokens) = abi.decode(
        getParams(data),
        (address, IBalancerMerkleOrchard.Claim[], IERC20[])
      );

      for (uint256 i = 0; i < tokens.length; i++) {
        require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(address(tokens[i])), "enable reward token");
      }
      address poolLogic = poolManagerLogic.poolLogic();

      require(poolLogic == claimer, "sender is not pool");

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
      isPublic = true; // anyone can execute
    }
  }
}
