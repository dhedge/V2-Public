# Perp Protocol Leveraged Long and Short Position + V3 Style LP'ing

This document will eventually form a readme and will be cleaned and updated.

# What is Perp

Perp is a protocol that allows a `trader` to deposit collateral and then using that collateral known in Perp as Buying Power (BP) to take out long and short leveraged positions AND/OR provide leveraged liquidity. How leveraged depends on how much BP a trader has.

The long and short positions can remain open indefinitely, they don't expire, hence the name perpetuals (note: they can be liquidated). To incentivise their maintenance by the trader and incentivise counterparty positions a fee is paid from the long to short holders OR short to long holders each day depending on the direction of the market. If there is not enough open interest to balance the long and short open positions, an extra fee is paid to the side that has the least liquidity from the side with the most. These fees are not settled until some onchain action occurs, but we can know the pro rata amount owing.

Buying Power can also be used to provide liquidity leveraged liquidity to special Uniswap v3 pools. The liquidity for these pools are managed through Perps Clearing house. I.E to add or remove liquidity it must be done through perp (Note: Not 100% sure about this).

So in short on Perp, traders can:

1. "Trade" - Take out leveraged long and short tokens against collateral that pay a daily funding rate
2."Pools" - Provide v3 liquidity in `v` pools.

## Questions

1. Can I add liquidity to perp pools via Uniswap (or can those tokens only be transferred to uniswap via Clearing House)
2. What happens if I mint vLiquidity and someone buys vTokens on uniswap and then I get liquidated?
3. Is there a referral program? `referralCode`


## Important Links

- Perp.com
- https://github.com/perpetual-protocol/perp-lushan/blob/main/contracts/interface/IVault.sol
- https://github.com/perpetual-protocol/perp-lushan/blob/main/contracts/interface/IClearingHouse.sol
- Perp Pools https://info.uniswap.org/#/optimism/tokens/0xc84da6c8ec7a57cd10b939e79eaf9d2d17834e04
- Current ClearingHouse impl (to get abi) https://optimistic.etherscan.io/address/0x9b96d189958c5be5e4a5d5280b5b58ad610db157#code

- Contract Addresses OVM - https://metadata.perp.exchange/v2/optimism.json

## Summary

It looks like Perp has been designed to expose an api that encourages composition and extension.

To begin a trader must deposit USDC into IVault.sol, this is used as collateral and creates Buying Power (BP).
After that the trader will always be interacting with IClearingHouse.sol (AFAIK). This includes opening and modifying positions and providing liquidity.

It also seems like they support some kind of `referralCode`.

## Notes:

Oracles: They use a combination of Chainlink and Band Oracles
BP: stands for buying power (bp) borrowed from DYDX.
Everything is Cross collateralised per account. An account is known as a `trader`

### Balance
Perp exposes a helper function that gives us us a traders net position USD.

Balance: ClearingHouse.sol
 - function getAccountValue(address trader) external view returns (int256);
 -- returns the net value of a traders long/short position in usdc
 -- Includes the usd value of LP positions
 -- Perp do some mitigations of price manipulation
 -- We can revisit the risk after initial implementation


### Depositing
Depositing: When depositing we are interacting with IVault.sol. Minimum first deposit is $100 usdc
https://github.com/perpetual-protocol/perp-lushan/blob/main/contracts/interface/IVault.sol
Function: deposit(address beneficiary, uint256 amount) ***
https://optimistic.etherscan.io/tx/0x7e143409cf8bdcd7a2c583223583b77b3ebd016923151e8d91f919e3741001b9
Note: You can get the ClearingHouse address from the IVault.getClearingHouse()


### Long & Short Position
Short+Long of Asset1: Opening a Long and short of the same asset Will net out the position long subtract short
Short+short of Asset1: Will add the shorts into one position.
Long+Long of Asset1:Will add the longs into one position.

Closing Positions:

- If under collateralised need to liquidate
- To reduce a long or short position we need to take out the opposite position relative to the investors portion.
For instance if the trader has a 3eth long position to close 33% of it we need to take a short of 1eth
This will return 1/3 of the buying power back to the trader
- We then need to withdraw the investors 33% portion of the collateral (usdc) from the IVault.Sol


Open Position:
```
{
  "method": "openPosition",
  "types": [
    "(address,bool,bool,uint256,uint256,uint256,uint160,bytes32)"
  ],
  "inputs": [
    [
      "0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB",
      false,
      true,
      {
        "type": "BigNumber",
        "hex": "0x056bca53c950291000"
      },
      {
        "type": "BigNumber",
        "hex": "0x81f50fb7093fbe"
      },
      {
        "type": "BigNumber",
        "hex": "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      },
      {
        "type": "BigNumber",
        "hex": "0x00"
      },
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ]
  ],
  "names": [
    [
      "params",
      [
        "baseToken",
        "isBaseToQuote",
        "isExactInput",
        "amount",
        "oppositeAmountBound",
        "deadline",
        "sqrtPriceLimitX96",
        "referralCode"
      ]
    ]
  ]
}
```

Close Position:

```
{
  "method": "closePosition",
  "types": [
    "(address,uint160,uint256,uint256,bytes32)"
  ],
  "inputs": [
    [
      "0x5f714B5347f0b5de9F9598E39840E176CE889b9c",
      {
        "type": "BigNumber",
        "hex": "0x00"
      },
      {
        "type": "BigNumber",
        "hex": "0x0456e7ef29501e4463"
      },
      {
        "type": "BigNumber",
        "hex": "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      },
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ]
  ],
  "names": [
    [
      "params",
      [
        "baseToken",
        "sqrtPriceLimitX96",
        "oppositeAmountBound",
        "deadline",
        "referralCode"
      ]
    ]
  ]
}
```





### LP'ing

Add Liquidity
https://optimistic.etherscan.io/tx/0xa9dc2247812db444fe6f2462e27fd6a778fcf45dbbd3ca87b67d32155be2c862
```
{
  "method": "addLiquidity",
  "types": [
    "(address,uint256,uint256,int24,int24,uint256,uint256,bool,uint256)"
  ],
  "inputs": [
    [
      "0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB",
      {
        "type": "BigNumber",
        "hex": "0x3f80c628099bdc"
      },
      {
        "type": "BigNumber",
        "hex": "0x030927f74c9de00000"
      },
      76560,
      80640,
      {
        "type": "BigNumber",
        "hex": "0x3ede34d098df6b"
      },
      {
        "type": "BigNumber",
        "hex": "0x03016272442ba80000"
      },
      false,
      {
        "type": "BigNumber",
        "hex": "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      }
    ]
  ],
  "names": [
    [
      "params",
      [
        "baseToken",
        "base",
        "quote",
        "lowerTick",
        "upperTick",
        "minBase",
        "minQuote",
        "useTakerBalance",
        "deadline"
      ]
    ]
  ]
}
```


Increase Liquidity: TODO
Decrease Liquidity: TODO


Remove Liquidity:
https://optimistic.etherscan.io/tx/0x0737f01d9bec51337283e234196ddfe472aa77743667c332aca6cc69d47640f3
```
{
  "method": "removeLiquidity",
  "types": [
    "(address,int24,int24,uint128,uint256,uint256,uint256)"
  ],
  "inputs": [
    [
      "0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB",
      76560,
      80640,
      {
        "type": "BigNumber",
        "hex": "0x8f39f5e3922fbed9"
      },
      {
        "type": "BigNumber",
        "hex": "0x3ea10a474cc0bb"
      },
      {
        "type": "BigNumber",
        "hex": "0x02fe70fa1e0681bfa0"
      },
      {
        "type": "BigNumber",
        "hex": "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      }
    ]
  ],
  "names": [
    [
      "params",
      [
        "baseToken",
        "lowerTick",
        "upperTick",
        "liquidity",
        "minBase",
        "minQuote",
        "deadline"
      ]
    ]
  ]
}
```


Rewards: Perp v2 Liquidity Mining - In perp tokens, requires claiming external contract
 -- Distributed every week


Funding Payments: Query Funding payment +/-
Each position will have a funding rate position that is negative or positive depending on the direction
This funding rate position is queryable and live/streaming

-- View functions are available that can calculate the net position of an account.


After depositing: After we deposit funds we will be interacting with ClearingHouse.sol
-- Clearing house will check how much buying power you have to make trades.
https://github.com/perpetual-protocol/perp-lushan/blob/main/contracts/interface/IClearingHouse.sol

Trading: ClearingHouse.sol (take long and short positions based on the amount of free collateral aka buying power)

LPing: ClearingHouse.sol
-- For people to be able to trade into the liquidity pools via the ClearingHouse the pool must maintain
a minimum amount of liquidity. This mitigates people manipulating the lp price?
--
-- Create an LP
-- Creating out of range lp
-- Close a portion of an LP

-- So when creating liquidity the liquidity you add is secured against collateral.
-- S

Asset Oracles some band and some chainlink






Contracts OVM - https://metadata.perp.exchange/v2/optimism.json
