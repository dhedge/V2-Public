// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

/// @title Interface for making arbitrary calls during swap
interface IAggregationExecutor {
  /// @notice propagates information about original msg.sender and executes arbitrary data
  function execute(address msgSender) external payable returns (uint256); // 0x4b64e492
}

/// @title Clipper interface subset used in swaps
interface IClipperExchange {
  struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  function sellEthForToken(
    address outputToken,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 goodUntil,
    address destinationAddress,
    Signature calldata theSignature,
    bytes calldata auxiliaryData
  ) external payable;

  function sellTokenForEth(
    address inputToken,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 goodUntil,
    address destinationAddress,
    Signature calldata theSignature,
    bytes calldata auxiliaryData
  ) external;

  function swap(
    address inputToken,
    address outputToken,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 goodUntil,
    address destinationAddress,
    Signature calldata theSignature,
    bytes calldata auxiliaryData
  ) external;
}

interface IAggregationRouterV6 {
  struct SwapDescription {
    address srcToken; // IERC20
    address dstToken; // IERC20
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
  }

  /**
   * @notice Performs a swap, delegating all calls encoded in `data` to `executor`. See tests for usage examples.
   * @dev Router keeps 1 wei of every token on the contract balance for gas optimisations reasons.
   *      This affects first swap of every token by leaving 1 wei on the contract.
   * @param executor Aggregation executor that executes calls described in `data`.
   * @param desc Swap description.
   * @param data Encoded calls that `caller` should execute in between of swaps.
   * @return returnAmount Resulting token amount.
   * @return spentAmount Source token amount.
   */
  function swap(
    IAggregationExecutor executor,
    SwapDescription calldata desc,
    bytes calldata data
  ) external payable returns (uint256 returnAmount, uint256 spentAmount);

  /**
   * @notice Swaps `amount` of the specified `token` for another token using an Unoswap-compatible exchange's pool,
   *         with a minimum return specified by `minReturn`.
   * @param token The address of the token to be swapped.
   * @param amount The amount of tokens to be swapped.
   * @param minReturn The minimum amount of tokens to be received after the swap.
   * @param dex The address of the Unoswap-compatible exchange's pool.
   * @return returnAmount The actual amount of tokens received after the swap.
   */
  function unoswap(
    uint256 token, // Address
    uint256 amount,
    uint256 minReturn,
    uint256 dex // Address
  ) external returns (uint256 returnAmount);

  /**
   * @notice Swaps `amount` of the specified `token` for another token using two Unoswap-compatible exchange pools (`dex` and `dex2`) sequentially,
   *         with a minimum return specified by `minReturn`.
   * @param token The address of the token to be swapped.
   * @param amount The amount of tokens to be swapped.
   * @param minReturn The minimum amount of tokens to be received after the swap.
   * @param dex The address of the first Unoswap-compatible exchange's pool.
   * @param dex2 The address of the second Unoswap-compatible exchange's pool.
   * @return returnAmount The actual amount of tokens received after the swap through both pools.
   */
  function unoswap2(
    uint256 token, // Address
    uint256 amount,
    uint256 minReturn,
    uint256 dex, // Address
    uint256 dex2 // Address
  ) external returns (uint256 returnAmount);

  /**
   * @notice Swaps `amount` of the specified `token` for another token using three Unoswap-compatible exchange pools
   *         (`dex`, `dex2`, and `dex3`) sequentially, with a minimum return specified by `minReturn`.
   * @param token The address of the token to be swapped.
   * @param amount The amount of tokens to be swapped.
   * @param minReturn The minimum amount of tokens to be received after the swap.
   * @param dex The address of the first Unoswap-compatible exchange's pool.
   * @param dex2 The address of the second Unoswap-compatible exchange's pool.
   * @param dex3 The address of the third Unoswap-compatible exchange's pool.
   * @return returnAmount The actual amount of tokens received after the swap through all three pools.
   */
  function unoswap3(
    uint256 token, // Address
    uint256 amount,
    uint256 minReturn,
    uint256 dex, // Address
    uint256 dex2, // Address
    uint256 dex3 // Address
  ) external returns (uint256 returnAmount);

  /**
   * @notice Same as `clipperSwapTo` but uses `msg.sender` as recipient.
   * @param clipperExchange Clipper pool address.
   * @param srcToken Source token and flags.
   * @param dstToken Destination token.
   * @param inputAmount Amount of source tokens to swap.
   * @param outputAmount Amount of destination tokens to receive.
   * @param goodUntil Clipper parameter.
   * @param r Clipper order signature (r part).
   * @param vs Clipper order signature (vs part).
   * @return returnAmount Amount of destination tokens received.
   */
  function clipperSwap(
    IClipperExchange clipperExchange,
    uint256 srcToken, // Address
    address dstToken, // IERC20
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 goodUntil,
    bytes32 r,
    bytes32 vs
  ) external payable returns (uint256 returnAmount);

  /**
   * @notice Swaps `amount` of the specified `token` for another token using an Unoswap-compatible exchange's pool,
   *         sending the resulting tokens to the `to` address, with a minimum return specified by `minReturn`.
   * @param to The address to receive the swapped tokens.
   * @param token The address of the token to be swapped.
   * @param amount The amount of tokens to be swapped.
   * @param minReturn The minimum amount of tokens to be received after the swap.
   * @param dex The address of the Unoswap-compatible exchange's pool.
   * @return returnAmount The actual amount of tokens received after the swap.
   */
  function unoswapTo(
    uint256 to, // Address
    uint256 token, // Address
    uint256 amount,
    uint256 minReturn,
    uint256 dex // Address
  ) external returns (uint256 returnAmount);

  /**
   * @notice Swaps `amount` of the specified `token` for another token using two Unoswap-compatible exchange pools (`dex` and `dex2`) sequentially,
   *         sending the resulting tokens to the `to` address, with a minimum return specified by `minReturn`.
   * @param to The address to receive the swapped tokens.
   * @param token The address of the token to be swapped.
   * @param amount The amount of tokens to be swapped.
   * @param minReturn The minimum amount of tokens to be received after the swap.
   * @param dex The address of the first Unoswap-compatible exchange's pool.
   * @param dex2 The address of the second Unoswap-compatible exchange's pool.
   * @return returnAmount The actual amount of tokens received after the swap through both pools.
   */
  function unoswapTo2(
    uint256 to, // Address
    uint256 token, // Address
    uint256 amount,
    uint256 minReturn,
    uint256 dex, // Address
    uint256 dex2 // Address
  ) external returns (uint256 returnAmount);

  /**
   * @notice Swaps `amount` of the specified `token` for another token using three Unoswap-compatible exchange pools
   *         (`dex`, `dex2`, and `dex3`) sequentially, sending the resulting tokens to the `to` address, with a minimum return specified by `minReturn`.
   * @param to The address to receive the swapped tokens.
   * @param token The address of the token to be swapped.
   * @param amount The amount of tokens to be swapped.
   * @param minReturn The minimum amount of tokens to be received after the swap.
   * @param dex The address of the first Unoswap-compatible exchange's pool.
   * @param dex2 The address of the second Unoswap-compatible exchange's pool.
   * @param dex3 The address of the third Unoswap-compatible exchange's pool.
   * @return returnAmount The actual amount of tokens received after the swap through all three pools.
   */
  function unoswapTo3(
    uint256 to, // Address
    uint256 token, // Address
    uint256 amount,
    uint256 minReturn,
    uint256 dex, // Address
    uint256 dex2, // Address
    uint256 dex3 // Address
  ) external returns (uint256 returnAmount);

  /**
   * @notice Performs swap using Clipper exchange. Wraps and unwraps ETH if required.
   *         Sending non-zero `msg.value` for anything but ETH swaps is prohibited.
   * @param clipperExchange Clipper pool address.
   * @param recipient Address that will receive swap funds.
   * @param srcToken Source token and flags.
   * @param dstToken Destination token.
   * @param inputAmount Amount of source tokens to swap.
   * @param outputAmount Amount of destination tokens to receive.
   * @param goodUntil Clipper parameter.
   * @param r Clipper order signature (r part).
   * @param vs Clipper order signature (vs part).
   * @return returnAmount Amount of destination tokens received.
   */
  function clipperSwapTo(
    IClipperExchange clipperExchange,
    address payable recipient,
    uint256 srcToken, // Address
    address dstToken, // IERC20
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 goodUntil,
    bytes32 r,
    bytes32 vs
  ) external payable returns (uint256 returnAmount);
}
