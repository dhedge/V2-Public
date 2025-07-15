// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IPyth {
  // A price with a degree of uncertainty, represented as a price +- a confidence interval.
  //
  // The confidence interval roughly corresponds to the standard error of a normal distribution.
  // Both the price and confidence are stored in a fixed-point numeric representation,
  // `x * (10^expo)`, where `expo` is the exponent.
  //
  // Please refer to the documentation at https://docs.pyth.network/consumers/best-practices for how
  // to how this price safely.
  struct Price {
    // Price
    int64 price;
    // Confidence interval around the price
    uint64 conf;
    // Price exponent
    int32 expo;
    // Unix timestamp describing when the price was published
    uint256 publishTime;
  }

  /// @notice Update price feeds with given update messages.
  /// This method requires the caller to pay a fee in wei; the required fee can be computed by calling
  /// `getUpdateFee` with the length of the `updateData` array.
  /// Prices will be updated if they are more recent than the current stored prices.
  /// The call will succeed even if the update is not the most recent.
  /// @dev Reverts if the transferred fee is not sufficient or the updateData is invalid.
  /// @param updateData Array of price update data.
  function updatePriceFeeds(bytes[] calldata updateData) external payable;

  function latestPriceInfoPublishTime(bytes32 priceId) external view returns (uint64);

  /// @notice Returns the price that is no older than `age` seconds of the current time.
  /// @dev This function is a sanity-checked version of `getPriceUnsafe` which is useful in
  /// applications that require a sufficiently-recent price. Reverts if the price wasn't updated sufficiently
  /// recently.
  /// @return price - please read the documentation of PythStructs.Price to understand how to use this safely.
  function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price);

  /// @notice Returns the price of a price feed without any sanity checks.
  /// @dev This function returns the most recent price update in this contract without any recency checks.
  /// This function is unsafe as the returned price update may be arbitrarily far in the past.
  ///
  /// Users of this function should check the `publishTime` in the price to ensure that the returned price is
  /// sufficiently recent for their application. If you are considering using this function, it may be
  /// safer / easier to use either `getPrice` or `getPriceNoOlderThan`.
  /// @return price - please read the documentation of PythStructs.Price to understand how to use this safely.
  function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
}
