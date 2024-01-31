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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Transaction type events used in pool execTransaction() contract guards
/// @dev Gradually migrate to these events as we update / add new contract guards
interface ITransactionTypes {
  // Transaction Types in execTransaction()
  // 1. Approve: Approving a token for spending by different address/contract
  // 2. Exchange: Exchange/trade of tokens eg. Uniswap, Synthetix
  // 3. AddLiquidity: Add liquidity
  event AddLiquidity(address poolLogic, address pair, bytes params, uint256 time);
  // 4. RemoveLiquidity: Remove liquidity
  event RemoveLiquidity(address poolLogic, address pair, bytes params, uint256 time);
  // 5. Stake: Stake tokens into a third party contract (eg. Sushi yield farming)
  event Stake(address poolLogic, address stakingToken, address to, uint256 amount, uint256 time);
  // 6. Unstake: Unstake tokens from a third party contract (eg. Sushi yield farming)
  event Unstake(address poolLogic, address stakingToken, address to, uint256 amount, uint256 time);
  // 7. Claim: Claim rewards tokens from a third party contract (eg. SUSHI & MATIC rewards)
  event Claim(address poolLogic, address stakingContract, uint256 time);
  // 8. UnstakeAndClaim: Unstake tokens and claim rewards from a third party contract
  // 9. Deposit: Aave deposit tokens -> get Aave Interest Bearing Token
  // 10. Withdraw: Withdraw tokens from Aave Interest Bearing Token
  // 11. SetUserUseReserveAsCollateral: Aave set reserve asset to be used as collateral
  // 12. Borrow: Aave borrow tokens
  // 13. Repay: Aave repay tokens
  // 14. SwapBorrowRateMode: Aave change borrow rate mode (stable/variable)
  // 15. RebalanceStableBorrowRate: Aave rebalance stable borrow rate
  // 16. JoinPool: Balancer join pool
  // 17. ExitPool: Balancer exit pool
  // 18. Deposit: EasySwapper Deposit
  // 19. Withdraw: EasySwapper Withdraw
  // 20. Mint: Uniswap V3 Mint position
  // 21. IncreaseLiquidity: Uniswap V3 increase liquidity position
  // 22. DecreaseLiquidity: Uniswap V3 decrease liquidity position
  // 23. Burn: Uniswap V3 Burn position
  // 24. Collect: Uniswap V3 collect fees
  // 25. Multicall: Uniswap V3 Multicall
  // 26. Lyra: open position
  // 27. Lyra: close position
  // 28. Lyra: force close position
  // 29. Futures: Market
  // 30. AddLiquidity: Single asset add liquidity (eg. Stargate)
  event AddLiquiditySingle(address fundAddress, address asset, address liquidityPool, uint256 amount, uint256 time);
  // 31. RemoveLiquidity: Single asset remove liquidity (eg. Stargate)
  event RemoveLiquiditySingle(address fundAddress, address asset, address liquidityPool, uint256 amount, uint256 time);
  // 32. Redeem Deprecated Synths into sUSD
  event SynthRedeem(address poolAddress, IERC20[] synthProxies);
  // 33. Synthetix V3 transactions
  event SynthetixV3Event(address poolLogic, uint256 txType);
  // 34. Sonne: Mint
  event SonneMintEvent(address indexed fundAddress, address asset, address cToken, uint256 amount, uint256 time);
  // 35. Sonne: Redeem
  event SonneRedeemEvent(address indexed fundAddress, address asset, address cToken, uint256 amount, uint256 time);
  // 36. Sonne: Redeem Underlying
  event SonneRedeemUnderlyingEvent(
    address indexed fundAddress,
    address asset,
    address cToken,
    uint256 amount,
    uint256 time
  );
  // 37. Sonne: Borrow
  event SonneBorrowEvent(address indexed fundAddress, address asset, address cToken, uint256 amount, uint256 time);
  // 38. Sonne: Repay
  event SonneRepayEvent(address indexed fundAddress, address asset, address cToken, uint256 amount, uint256 time);
  // 39. Sonne: Comptroller Enter Markets
  event SonneEnterMarkets(address indexed poolLogic, address[] cTokens, uint256 time);
  // 40. Sonne: Comptroller Exit Market
  event SonneExitMarket(address indexed poolLogic, address cToken, uint256 time);

  // Enum representing Transaction Types
  enum TransactionType {
    NotUsed, // 0
    Approve, // 1
    Exchange, // 2
    AddLiquidity, // 3
    RemoveLiquidity, // 4
    Stake, // 5
    Unstake, // 6
    Claim, // 7
    UnstakeAndClaim, // 8
    AaveDeposit, // 9
    AaveWithdraw, // 10
    AaveSetUserUseReserveAsCollateral, // 11
    AaveBorrow, // 12
    AaveRepay, // 13
    AaveSwapBorrowRateMode, // 14
    AaveRebalanceStableBorrowRate, // 15
    BalancerJoinPool, // 16
    BalancerExitPool, // 17
    EasySwapperDeposit, // 18
    EasySwapperWithdraw, // 19
    UniswapV3Mint, // 20
    UniswapV3IncreaseLiquidity, // 21
    UniswapV3DecreaseLiquidity, // 22
    UniswapV3Burn, // 23
    UniswapV3Collect, // 24
    UniswapV3Multicall, // 25
    LyraOpenPosition, // 26
    LyraClosePosition, // 27
    LyraForceClosePosition, // 28
    KwentaFuturesMarket, // 29
    AddLiquiditySingle, // 30
    RemoveLiquiditySingle, // 31
    MaiTx, // 32
    LyraAddCollateral, // 33
    LyraLiquidatePosition, // 34
    KwentaPerpsV2Market, // 35
    RedeemSynth, // 36
    SynthetixV3CreateAccount, // 37
    SynthetixV3DepositCollateral, // 38
    SynthetixV3WithdrawCollateral, // 39
    SynthetixV3DelegateCollateral, // 40
    SynthetixV3MintUSD, // 41
    SynthetixV3BurnUSD, // 42
    SynthetixV3Multicall, // 43
    XRamCreateVest, // 44
    XRamExitVest, // 45
    SynthetixV3Wrap, // 46
    SynthetixV3Unwrap, // 47
    SynthetixV3BuySynth, // 48
    SynthetixV3SellSynth, // 49
    SonneMint, // 50
    SonneRedeem, // 51
    SonneRedeemUnderlying, // 52
    SonneBorrow, // 53
    SonneRepay, // 54
    SonneComptrollerEnterMarkets, // 55
    SonneComptrollerExitMarket, // 56
    SynthetixV3UndelegateCollateral // 57
  }
}
