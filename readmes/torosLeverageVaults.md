# Toros Leverage Vaults

## Ethereum Bull (ETHBULL)
Set up to accept only one deposit asset on the vault's settings side, which is WETH.

### EasySwapper Deposit assets

- **WETH**. No slippage. Makes no swaps and puts WETH directly into the vault where it gets picked by the bot and put into the Aave position.
- **USDC**. There might be slippage, as USDC -> WETH swap is required.
- **Native ETH**. No slippage as only wrapping is required.

### EasySwapper Withdraw assets
- **WETH**. Flash loan USDC to cover debt -> unlock WETH -> withdraw WETH -> swap WETH to USDC only through DhedgeUniV3V2Router -> repay flash loan -> rest WETH sent to the user. Minor slippage can occur during the swap WETH -> USDC on Uniswap V3.
- **USDC**. Flash loan USDC to cover debt -> unlock WETH -> withdraw WETH -> swap WETH to USDC only through DhedgeUniV3V2Router -> repay flash loan -> swap rest WETH to USDC (all swap routers are quoted) and send it to the user. Minor slippage can occur during the x2 swap WETH -> USDC.

## Bitcoin Bull (BTCBULL)
Set up to accept only one deposit asset on the vault's settings side, which is WBTC.

### EasySwapper Deposit assets

- **WBTC**. No slippage. Makes no swaps and puts WBTC directly into the vault where it gets picked by the bot and put into the Aave position.
- **USDC**. There might be slippage, as USDC -> WBTC swap is required.
- **Native ETH**. There might be slippage, as swap is required.

### EasySwapper Withdraw assets
- **WBTC**. Flash loan USDC to cover debt -> unlock WBTC -> withdraw WBTC -> swap WBTC to WETH quoting all swap routers -> swap WETH to USDC only through DhedgeUniV3V2Router -> repay flash loan -> swap rest WETH to WBTC (all swap routers are quoted) and send it to the user.
- **USDC**. Flash loan USDC to cover debt -> unlock WBTC -> withdraw WBTC -> swap WBTC to WETH quoting all swap routers -> swap WETH to USDC only through DhedgeUniV3V2Router -> repay flash loan -> swap rest WETH to USDC (all swap routers are quoted) and send it to the user.
