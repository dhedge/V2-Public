# GMX Perps

This document outlines the integration process for GMX Perps, focusing primarily on functionality relevant to a dHEDGE integration.

The `GmxExchangeRouterContractGuard` supports the creation of `MarketIncrease` and `MarketDecrease` orders, enabling the opening, adjustment, and closure of perpetual positions. The integration also includes other features, such as claiming functions (e.g., `claimFundingFees`).

## Resources

Key information for this integration can be found in the following resources:

- [Contracts repo](https://github.com/gmx-io/gmx-synthetics) and [ABIs](https://github.com/gmx-io/gmx-synthetics/tree/main/deployments/arbitrum)
- [GMX documentation](https://gmx-docs.io/docs/intro)
- [Frontend repo](https://github.com/gmx-io/gmx-interface)

### Example Transactions

- **[Request Market Increase](https://arbiscan.io/tx/0x6ef2ef35d2dfa9839e06f799939a0cc324920af2603c629cbf83c06bb420d855):**  
  This is a `multicall` comprising:  
  1. `sendWnt`  
  2. `sendTokens`  
  3. `createOrder (OrderType.MarketIncrease)`  

- **[Request Market Decrease](https://arbiscan.io/tx/0x31e5e8d8810f8afe72fbe1d8d1749f45fe7d46b55da7de309053ea262b0ca7bd):**  
  This is a `multicall` comprising:  
  1. `sendWnt`  
  2. `createOrder (OrderType.MarketDecrease)`  

- **[Claim Funding Fees](https://arbiscan.io/tx/0x7da47db60a98286324c959f638fad3d59e16bd1f19d6b3999e5b9366a1d6d314):**  
  A transaction to claim accrued funding fees.

---

### How to Create Orders

The general process for creating orders in the GMX UI is as follows:

1. **`sendWnt`:** Wraps ETH from the user’s account (EOA address) and transfers it to the [orderVault](https://arbiscan.io/address/0x31ef83a530fde1b38ee9a18093a333d8bbbc40d5#code) as the execution fee.  
2. **`sendTokens`:** Transfers collateral to the `orderVault`. (no need for `OrderType.MarketDecrease`)
3. **`createOrder`:** Uses the wrapped ETH and collateral amounts in the `orderVault` to create an order, which adjusts margin and position size.  

**Note:** These transactions must be executed together in a `multicall` via the [ExchangeRouter](https://arbiscan.io/address/0x69c527fc77291722b52649e45c838e41be8bf5d5). If not, the tokens sent to the `orderVault` may be accessible to other users creating orders.
in the **`createOrder`**, `initialCollateralDeltaAmount` and `executionFee` will be calculated and [recorded](https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/order/OrderUtils.sol#L81) by the token amounts sent to the `orderVault`

Once an order is created, it is recorded in the `dataStore`, and then keepers later execute it. For this integration, `sendTokens` is used to send WETH instead of calling `sendWnt`.

Hence in our integration,

- for `OrderType.MarketDecrease`, txs in a multicall are:
  1. `sendTokens`  for Execution Fee
  2. `createOrder (OrderType.MarketDecrease)`

- for `OrderType.MarketDecrease`, txs in a multicall are:
  1. `sendTokens` for Execution Fee
  2. `sendTokens`  for Collateral Delta Amount
  3. `createOrder (OrderType.MarketIncrease)`  

---

#### Margin and Position Size

- **`OrderType.MarketIncrease`:**  
  - Both `order.numbers.sizeDeltaUsd` and `order.numbers.initialCollateralDeltaAmount` are **added** to the original values.  
- **`OrderType.MarketDecrease`:**  
  - Both `order.numbers.sizeDeltaUsd` and `order.numbers.initialCollateralDeltaAmount` are **subtracted** from the original values.  

---

## ContractGuard

### GmxExchangeRouterContractGuard

This component facilitates the creation, adjustment, and closure of perpetual orders, as well as claiming fees. Supported operations via the [ExchangeRouter](https://arbiscan.io/address/0x69c527fc77291722b52649e45c838e41be8bf5d5) include:  

- `createOrder` (via `multicall`)  
- `claimFundingFees`  
- `claimCollateral`  
- `cancelOrder`  

---

## AssetGuard

### GmxPerpMarketAssetGuard

The `getBalance` function calculates the USD value of the GMX asset by considering:  

1. **Active positions:** The value of collateral in active GMX positions, including price impact and profit/loss.  
2. **Pending orders:** Deposited collateral in market increase orders, plus execution fees for all orders.  
3. **Funding fees:** Accrued fees that can be claimed.  

---
