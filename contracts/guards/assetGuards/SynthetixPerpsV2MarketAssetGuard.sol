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
//
// TODO: Intended for whitelisted vaults only. Not open to any vault.

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./ClosedAssetGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "../../interfaces/synthetix/IPerpsV2Market.sol";
import "../../interfaces/synthetix/IPerpsV2MarketSettings.sol";
import "../../interfaces/synthetix/IAddressResolver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title PerpsV2Market (Synthetix) Asset Guard
/// @dev Asset type = 102
/// @dev A wallet/user can only have one position per market
contract SynthetixPerpsV2MarketAssetGuard is ClosedAssetGuard {
  using SafeMath for uint256;
  using SignedSafeMath for int128;
  using SignedSafeMath for int256;

  IAddressResolver public immutable addressResolver;
  address public immutable susdProxy;

  // During withdrawal, temporary maximum leverage of 3x is permitted
  // while the delayed offchain transaction is executed to reduce the perp position.
  // Any higher leverage than this could risk liquidation of the position during the temporary period.
  uint8 private constant MAX_LEVERAGE_DURING_WITHDRAWAL = 3;

  struct Withdrawal {
    uint256 positionValue;
    int256 reduceDelta;
    uint256 margin;
    uint256 marginPortion;
    // These are the fees for closing this portion of the position
    // We account for it so that withdrawing doesn't negatively impact the performance of the pool
    uint256 tradeFee;
    uint256 keeperFee;
  }

  constructor(IAddressResolver _addressResolver, address _susdProxy) {
    addressResolver = IAddressResolver(_addressResolver);
    susdProxy = _susdProxy;
  }

  // 1     = 100%
  // 0.1   = 10%
  // 0.01  = 1%
  // 0.001 = 0.1%
  // To get the uint value it's just `* 10^18`. For example,
  // DESIRED_FILL_PRICE_DELTA = 0.001 * 10^18
  //                          = 1000000000000000
  // Note: Synthetix changed from priceImpactDelta https://sips.synthetix.io/sips/sip-2004/
  uint256 public constant DESIRED_FILL_PRICE_DELTA = 500000000000000000; // 0.5%

  /// @notice Simulates the perps trade so we get exact amounts out
  /// @dev when a trade is executed in PerpV2 (as opposed to Futures) fillPrice is used
  /// @dev fillPrice is the spot price adjusted by the skew of the market
  /// @param pool Pool address
  /// @param asset PerpsV2Market
  /// @param reduceDelta the trade size
  /// @return postTradeMargin the amount of margin the account will have post trade
  /// @return tradeFee the cost of the trade
  /// @return keeperFee the cost of the keeper to execute the delayed trade
  function _postTradeDetails(
    address pool,
    address asset,
    int256 reduceDelta
  )
    internal
    view
    returns (
      uint256 postTradeMargin,
      uint256 tradeFee,
      uint256 keeperFee
    )
  {
    (uint256 fillPrice, ) = IPerpsV2Market(asset).fillPrice(reduceDelta);
    IPerpsV2Market.Status status;
    (postTradeMargin, , , , tradeFee, status) = IPerpsV2Market(asset).postTradeDetails(
      reduceDelta,
      fillPrice,
      IPerpsV2Market.OrderType.Offchain,
      pool
    );
    require(status == IPerpsV2Market.Status.Ok, "Cannot modify position");

    keeperFee = IPerpsV2MarketSettings(addressResolver.getAddress("PerpsV2MarketSettings")).minKeeperFee();
  }

  function _buildTransactions(
    Withdrawal memory withdrawal,
    address asset,
    address withdrawerAddress
  ) internal view returns (MultiTransaction[] memory transactions) {
    uint256 marginSubFee = withdrawal.marginPortion > withdrawal.tradeFee.add(withdrawal.keeperFee)
      ? withdrawal.marginPortion.sub(withdrawal.tradeFee).sub(withdrawal.keeperFee)
      : 0;
    // There can still be margin inside the contract even if there is no open position
    if (marginSubFee > 0) {
      // reduceDelta is a signed Int, for a short reduceDelta will be > 0 and for a long < 0
      if (withdrawal.reduceDelta == 0) {
        // No open position
        transactions = new MultiTransaction[](2);
        // Withdraws margin to the pool
        transactions[0].to = asset;
        // https://github.com/Synthetixio/synthetix/blob/master/contracts/interfaces/IPerpsV2Market.sol#L81
        transactions[0].txData = abi.encodeWithSelector(IPerpsV2Market.transferMargin.selector, -int256(marginSubFee));

        // Erc20.transfer of margin to withdrawer
        transactions[1].to = susdProxy;
        transactions[1].txData = abi.encodeWithSelector(IERC20.transfer.selector, withdrawerAddress, marginSubFee);
      } else {
        // Submits a delayed order to close portion of position
        uint256 desiredFillPrice; // Synthetix has changed it's price impact config and is no longer using priceImpactDelta https://sips.synthetix.io/sips/sip-2004/
        // Calculate the max allowed slippage based on DESIRED_FILL_PRICE_DELTA setting for closing position
        {
          bool invalid;
          (desiredFillPrice, invalid) = IPerpsV2Market(asset).fillPrice(withdrawal.reduceDelta);
          require(!invalid, "perp v2 fill price is invalid");
        }

        // There's an open position
        transactions = new MultiTransaction[](3);
        // Withdraws margin to the pool
        transactions[0].to = asset;
        // https://github.com/Synthetixio/synthetix/blob/master/contracts/interfaces/IPerpsV2Market.sol#L81
        transactions[0].txData = abi.encodeWithSelector(IPerpsV2Market.transferMargin.selector, -int256(marginSubFee));

        // Erc20.transfer of margin to withdrawer
        transactions[1].to = susdProxy;
        transactions[1].txData = abi.encodeWithSelector(IERC20.transfer.selector, withdrawerAddress, marginSubFee);

        if (withdrawal.reduceDelta > 0) {
          // Partially close short
          desiredFillPrice = desiredFillPrice.add(desiredFillPrice.mul(DESIRED_FILL_PRICE_DELTA).div(100e18)); // accept some slippage (higher fill price)
        } else {
          // Partially close long
          desiredFillPrice = desiredFillPrice.sub(desiredFillPrice.mul(DESIRED_FILL_PRICE_DELTA).div(100e18)); // accept some slippage (lower fill price)
        }
        transactions[2].to = asset;
        // https://github.com/Synthetixio/synthetix/blob/master/contracts/interfaces/IPerpsV2Market.sol#L85
        transactions[2].txData = abi.encodeWithSelector(
          IPerpsV2Market.submitOffchainDelayedOrderWithTracking.selector,
          withdrawal.reduceDelta,
          desiredFillPrice,
          "0x4448454447450000000000000000000000000000000000000000000000000000" // DHEDGE
        );
      }
    }
  }

  /// @notice Creates transaction data for reducing a futures position by the portion
  /// @param pool Pool address
  /// @param asset PerpsV2Market
  /// @param portion The fraction of total future asset to withdraw
  /// @return withdrawAsset and
  /// @return withdrawBalance are used to withdraw portion of asset balance to investor
  /// @return transactions is used to execute the reduction of the futures position in PoolLogic
  function withdrawProcessing(
    address pool,
    address asset,
    uint256 portion,
    address withdrawerAddress
  )
    external
    view
    virtual
    override
    returns (
      address withdrawAsset,
      uint256 withdrawBalance,
      MultiTransaction[] memory transactions
    )
  {
    require(IPerpsV2Market(asset).delayedOrders(pool).sizeDelta == 0, "delayed order in progress");

    // This should nearly never happen, should always be previously liquidated by keeper.
    if (IPerpsV2Market(asset).canLiquidate(pool)) {
      transactions = new MultiTransaction[](1);
      transactions[0].to = asset;
      transactions[0].txData = abi.encodeWithSelector(IPerpsV2Market.liquidatePosition.selector, pool);
      return (withdrawAsset, withdrawBalance, transactions);
    }

    // When a user withdraws, we close their portion of the future position (modifyPosition)
    // Then we withdraw their portion of the margin to the pool (transferMargin)
    // Then we withdraw their porition of the margin to the user (transfer)
    // If this withdraw would cause the positions margin to drop below minMargin we (closePosition) and (withdrawAllMargin)
    Withdrawal memory withdrawal; // Note: this struct helps with stack too deep error

    IPerpsV2Market.Position memory position = IPerpsV2Market(asset).positions(pool);
    withdrawal.reduceDelta = -position.size.mul(int256(portion)).div(10**18);

    if (withdrawal.reduceDelta == 0) {
      // `remainingMargin` uses the spot price rather than the fill price
      // If there is a position open (that needs to be reduced) this value is not accurate as it uses the spot price
      // To calculate the pnl instead of the fillPrice. remainingMargin == margin + pnl;
      {
        bool invalid;
        (withdrawal.margin, invalid) = IPerpsV2Market(asset).remainingMargin(pool);
        withdrawal.marginPortion = withdrawal.margin.mul(portion).div(10**18);
        require(!invalid, "perp v2 margin is invalid");
      }
    } else {
      // TODO: Perps v2 have been deprecated requiring closure of positions for withdrawal processing. Should be handled somehow.
      // This is as a result on increased fees for Atomic orders in https://sips.synthetix.io/sccp/sccp-295/
      // If the pool has just margin without a futures position, this is ok.
      {
        uint256 postTradeMargin;
        // Simulates the trade at the current fillPrice (spot adjusted for skew)
        (postTradeMargin, withdrawal.tradeFee, withdrawal.keeperFee) = _postTradeDetails(
          pool,
          asset,
          withdrawal.reduceDelta
        );

        // The solution to handle delayed closing of positions, temporarily lowers the margin without closing the position (delayed close)
        // Therefore the leverage is temporarily increased before the delayed transaction to partially close the position is executed.
        // We want to make sure that the leverage does not exceed a threshold to risk liquidation.
        // We block withdrawal sizes that would temporarily increase leverage >3x.

        // The margin returned from postTradeDetails is sans Fee. The totalMargin pre trade is this plus the fee.
        withdrawal.margin = postTradeMargin.add(withdrawal.tradeFee);
        withdrawal.marginPortion = withdrawal.margin.mul(portion).div(10**18);

        // Make sure that the withdrawal doesn't temporarily increase the leverage beyond 3x
        if (position.size >= 0) {
          withdrawal.positionValue = uint256(position.size).mul(position.lastPrice).div(10**18);
        } else {
          withdrawal.positionValue = uint256(-position.size).mul(position.lastPrice).div(10**18);
        }
        require(
          withdrawal.positionValue < postTradeMargin.sub(withdrawal.marginPortion).mul(MAX_LEVERAGE_DURING_WITHDRAWAL),
          "perp v2 withdrawal too large"
        );
      }
    }
    {
      uint256 minMargin = IPerpsV2MarketSettings(addressResolver.getAddress("PerpsV2MarketSettings"))
        .minInitialMargin();
      // Safeguard
      require(
        withdrawal.marginPortion >= withdrawal.tradeFee.add(withdrawal.keeperFee),
        "Fee is more than margin portion"
      );

      // If there is an open position and the withdraw brings the margin under the minimum margin we close the whole position
      // This returns the funds to the pool. Where they will be distributed to the withdrawer upstream.
      if (
        withdrawal.reduceDelta != 0 &&
        (withdrawal.margin.sub(withdrawal.marginPortion) < minMargin || portion == 10**18)
      ) {
        // Can't handle this scenario with the delayed offchain transaction
        // Assumes that for whitelisted vaults, there will always be enough margin above the minimum
        revert("margin will be below minimum");
        // TODO: Add handling for closing positions entirely
        // transactions = new MultiTransaction[](2);
        // transactions[0].to = asset;
        // transactions[0].txData = abi.encodeWithSelector(IPerpsV2Market.closePosition.selector, PRICE_IMPACT_DELTA);
        // transactions[1].to = asset;
        // transactions[1].txData = abi.encodeWithSelector(IPerpsV2Market.withdrawAllMargin.selector);
        // return (withdrawAsset, withdrawBalance, transactions);
      }
    }

    transactions = _buildTransactions(withdrawal, asset, withdrawerAddress);

    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice Returns the sUSD value of the Future if it was closed now
  /// @param pool address of the pool
  /// @param asset address of the asset
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    IPerpsV2Market perpsMarket = IPerpsV2Market(asset);
    (balance, ) = perpsMarket.remainingMargin(pool);
    int128 positionSize = perpsMarket.positions(pool).size;
    if (positionSize != 0) {
      (uint256 fee, ) = perpsMarket.orderFee(-(positionSize), IPerpsV2Market.OrderType.Offchain);
      // In this case it should have been liquidated
      return fee > balance ? 0 : balance.sub(fee);
    }
  }

  /// @notice Returns decimal of the PerpsV2Market Asset
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }
}
