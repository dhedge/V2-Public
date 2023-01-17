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
pragma experimental ABIEncoderV2;

import "../../utils/TxDataUtils.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/aave/IAaveIncentivesControllerV3.sol";

/// @title Transaction guard for Aave's incentives v3 RewardController contract
contract AaveIncentivesControllerV3Guard is TxDataUtils, IGuard {
  event Claim(address fundAddress, address stakingContract, uint256 time);

  /// @notice Transaction guard for Aave incentives v3 RewardController
  /// @dev It supports claimRewards functionality
  /// @param _poolManagerLogic the pool manager logic
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data
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
      bool isPublic
    )
  {
    bytes4 method = getMethod(data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    if (method == IAaveIncentivesControllerV3.claimRewards.selector) {
      // https://github.com/aave/aave-v3-periphery/blob/master/contracts/rewards/RewardsController.sol#L122
      (, , address claimTo, address reward) = abi.decode(getParams(data), (address, uint256, address, address));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(reward), "unsupported reward asset");
      require(claimTo == poolLogic, "recipient is not pool");

      emit Claim(poolLogic, to, block.timestamp);

      txType = 7; // `Claim` type
      isPublic = true;
    }
  }
}
