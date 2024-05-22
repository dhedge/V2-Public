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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./ERC20Guard.sol";
import "../../interfaces/stargate/IStargateLpStaking.sol";
import "../../interfaces/stargate/IStargatePool.sol";

/// @title Stargate LP token asset guard
/// @dev Asset type = 16
contract StargateLPAssetGuard is ERC20Guard {
  using SafeMathUpgradeable for uint256;

  struct StargatePool {
    address lpToken;
    uint256 stakingPoolId;
  }

  struct StargatePoolId {
    uint256 id;
    bool configured;
  }

  IStargateLpStaking public stargateLpStaking; // Stargate's staking staking contract

  mapping(address => StargatePoolId) public stargatePoolIds; // Stargate's staking contract Pool IDs

  event StargatePoolAdded(address indexed lpToken, uint256 indexed poolId);

  /// @notice Initialiser for the contract
  /// @dev Set up the stargatePoolIds mapping from StargateLPStaking contract
  /// @param _stargateLpStaking Stargate's staking contract (similar to Sushi's MiniChef)
  constructor(address _stargateLpStaking) {
    require(_stargateLpStaking != address(0), "invalid LP staking address");
    stargateLpStaking = IStargateLpStaking(_stargateLpStaking);
    updateStakingPoolIds();
  }

  /// @notice Public function to update staking contract pool Ids if they ever change
  function updateStakingPoolIds() public {
    require(address(stargateLpStaking) != address(0), "staking address is 0");
    for (uint256 i = 0; i < stargateLpStaking.poolLength(); i++) {
      stargatePoolIds[stargateLpStaking.poolInfo(i).lpToken] = StargatePoolId(i, true);
    }
  }

  /// @notice Creates transaction data for withdrawing staked tokens
  /// @dev The same interface can be used for other types of stakeable tokens
  /// @param pool Pool address
  /// @param asset Staked asset
  /// @param portion The fraction of total staked asset to withdraw
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the staked withdrawal transaction in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address // to
  )
    external
    view
    virtual
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    withdrawAsset = asset;
    uint256 totalAssetBalance = IERC20(asset).balanceOf(pool);
    withdrawBalance = totalAssetBalance.mul(portion).div(10 ** 18);

    StargatePoolId storage stargatePoolId = stargatePoolIds[asset];
    uint256 stakedBalance = stargateLpStaking.userInfo(stargatePoolId.id, pool).amount;

    // If there is a staked balance in the staking contract
    // Then create the withdrawal transaction data to be executed by PoolLogic
    if (stakedBalance > 0) {
      uint256 withdrawAmount = stakedBalance.mul(portion).div(10 ** 18);
      if (withdrawAmount > 0) {
        // Withdraw from staking contract
        transactions = new MultiTransaction[](1);
        transactions[0].to = address(stargateLpStaking);
        transactions[0].txData = abi.encodeWithSelector(
          IStargateLpStaking.withdraw.selector,
          stargatePoolId.id,
          withdrawAmount
        );
      }
    }
  }

  /// @notice Returns the balance of the managed asset (in underlying asset eg USDC, DAI)
  /// @dev Includes any external balance in staking contract
  /// @dev Asset needs to use price oracle of the underlying asset eg USDC, DAI etc
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    StargatePoolId storage stargatePoolId = stargatePoolIds[asset];
    require(stargatePoolId.configured, "pool ID not configured");

    uint256 stakedBalance = IStargateLpStaking(stargateLpStaking).userInfo(stargatePoolId.id, pool).amount;
    uint256 poolBalance = IERC20(asset).balanceOf(pool);
    balance = stakedBalance.add(poolBalance);

    // convert balance from LP token to underlying asset
    uint256 toUnderlyingConversion = IStargatePool(asset).amountLPtoLD(10 ** 18);
    balance = balance.mul(toUnderlyingConversion).div(10 ** 18);
  }

  /// @notice Returns decimal of the asset
  /// @dev Returns underlying asset decimals
  function getDecimals(address asset) external view override returns (uint256 decimals) {
    decimals = IStargatePool(asset).localDecimals();
  }
}
