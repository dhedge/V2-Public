Kwenta Cross Margin Futures

https://docs.kwenta.io/using-kwenta/futures/susd-futures/cross-margin/faq
https://docs.kwenta.io/using-kwenta/futures/susd-futures/cross-margin/order-types

Is basically a wrapper around single margin synth futures. It has the added benefit of being able to store and execute Limit, Take Profit and Stop Loss Orders via Gelato. Unfortunately this requires the MarginBase contract to be funded with Eth (to pay gelato) something a manager cannot current do. I think Cross Margin is a bit of a misnomer but it could be my understanding. The individual futuresMarket positions do not share a margin in the same way as they would say in FTX.

MarginBase https://optimistic.etherscan.io/address/0x8e43BF1910ad1461EEe0Daca10547c7e6d9D2f36

MarginAccountFactory - newAccount() - https://optimistic.etherscan.io/tx/0x4752b7ce8b97f246bc4562865f7a517bf23f982a78c00a5f38c13109f44a505c
Creates an instance of MarginBase contract for the user. It's actualyl a proxy to an implementation the same way Pools are for a managers pool

Approve your MarginBase instance contract for sUSD - https://optimistic.etherscan.io/tx/0xf7c19eb1c1210b129a7a244be5b29140d08b9279aebf20e85230f1970951c813

Deposit SUSD as margin into MarginBase Instance - https://optimistic.etherscan.io/tx/0x00a31c319edadd5d3048689ca6519c305d03c3ee0c6d569413a51b9cf57d7813

Open Margin Position - https://optimistic.etherscan.io/tx/0x8399d04efc19a406caed5f55a8e0b066361c1e972b593f7a09014292dd663170 - This effective takes some marging from the MarginBase deposits it into the FuturesMarket and executes ModifyPosition.

Close Position - https://optimistic.etherscan.io/tx/0x557527e8679d67c3ff16669953ef9b41f3afceb143fa2231f2fcacf3e852fa7d - Closes position and moves out margin from futures market back to MarginBase

Open Limit Order - https://optimistic.etherscan.io/tx/0x51768333900a3b8bd16a9fe5adae1c54477a8f0eed28c639992c6b53345bbfa2 - Puts margin on reserve and sets up order that can be executed by keeper. Also automatically sends 0.01eth for Keeper fee.

Cancel Limit Order - https://optimistic.etherscan.io/tx/0x5020106a7f96941e4327506f18bbaa5988c458e161251f94077a63c9fd8b1ac3 - Doesn't automatically return keeper fee need to withdraw


Withdraw keeper fee - https://optimistic.etherscan.io/tx/0x76ec159c1a561500d8ec570d942748623784b7b54f4747a68a59031da9c7e8b2

Withdraw Cross Margin - https://optimistic.etherscan.io/tx/0x117514373f0a5067b329030532727f813563ddb0e8dc7add9164d468976d9312
