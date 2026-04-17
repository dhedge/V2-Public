# Easy Limit Buys Specification

This document specifies the off-chain infrastructure required to support the `EasyLimitBuyManager` smart contract, enabling users to place limit buy orders for dHEDGE vaults.

## Overview

Easy Limit Buys allows users to:

1. **Buy the Dip**: Execute vault deposits when an asset's price drops below a threshold
2. **Buy the Breakout**: Execute vault deposits when an asset's price rises above a threshold

Users sign EIP-712 messages off-chain using Permit2. Orders are stored in a backend order book. Keepers monitor prices and execute orders on-chain when conditions are met.

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────────┐
│   Frontend  │────▶│  Order Book API  │────▶│  EasyLimitBuyManager    │
│   (User)    │     │    (Backend)     │     │    (Smart Contract)     │
└─────────────┘     └──────────────────┘     └─────────────────────────┘
       │                    │                           ▲
       │                    │                           │
       │ Sign EIP-712       │                           │
       │ via Permit2        │                    ┌──────┴──────┐
       │                    │                    │   Keeper    │
       ▼                    ▼                    │   Service   │
 ┌───────────┐       ┌────────────┐              └─────────────┘
 │  Wallet   │       │   Redis/   │                     │
 │ (signing) │       │ Database   │◀────────────────────┘
 └───────────┘       └────────────┘        Price monitoring
```

## Data Structures

### LimitBuyOrder (Signed by User)

```typescript
interface LimitBuyOrder {
  owner: string; // User address that created the order
  targetVault: string; // dHEDGE vault address to deposit into
  pricingAsset: string; // Asset whose price triggers execution (e.g., WBTC, WETH)
  minTriggerPriceD18: bigint; // Lower bound (0 = no lower bound) - 18 decimals
  maxTriggerPriceD18: bigint; // Upper bound (max uint256 = no upper bound) - 18 decimals
  slippageToleranceBps: number; // 1-500 (0.01% - 5%)
}
```

### Permit2 TokenPermissions

```typescript
interface TokenPermissions {
  token: string; // Input token address (e.g., USDC, WETH)
  amount: bigint; // Amount to spend
}
```

### Full Signed Message (EIP-712)

```typescript
interface PermitWitnessTransferFrom {
  permitted: TokenPermissions;
  spender: string; // EasyLimitBuyManager contract address
  nonce: bigint; // Unique nonce for replay protection
  deadline: bigint; // Unix timestamp when signature expires
  witness: LimitBuyOrder; // The limit buy order details
}
```

### ZapData (Built by Keeper at Execution Time)

When input token is not a deposit asset, keeper builds this struct with fresh swap data:

```typescript
interface ZapData {
  aggregatorData: {
    routerKey: string; // e.g., "ODOS_V3" as bytes32
    swapData: string; // Encoded swap calldata from aggregator
  };
  destData: {
    destToken: string; // Must be deposit asset of target vault
    minDestAmount: bigint; // Minimum swap output (anti-slippage)
  };
}
```

---

## Backend Specification

### Order Book API

#### Endpoints

| Method | Endpoint                | Description                |
| ------ | ----------------------- | -------------------------- |
| POST   | `/orders`               | Submit a new signed order  |
| GET    | `/orders`               | List orders (filterable)   |
| GET    | `/orders/:orderHash`    | Get order details          |
| DELETE | `/orders/:orderHash`    | Cancel order (soft delete) |
| GET    | `/orders/user/:address` | Get all orders for a user  |

#### POST /orders - Submit Order

**Request Body:**

```typescript
{
  order: LimitBuyOrder;
  permit: {
    token: string;
    amount: string; // Decimal string
    nonce: string; // Decimal string (random 256-bit)
    deadline: number; // Unix timestamp
  }
  signature: string; // Hex-encoded EIP-712 signature (65 bytes)
  chainId: number;
}
```

**Validations:**

1. Verify signature matches owner
2. Verify user has approved Permit2 for the token
3. Verify user has sufficient token balance
4. Verify target vault is valid dHEDGE pool
5. Verify slippage is within 1-500 bps
6. Verify deadline is in the future
7. Verify nonce hasn't been used in Permit2
8. Verify deadline does not exceed maximum validity period (e.g., 30 days)

**Note on Deadlines:** The backend should enforce a maximum order validity period (e.g., 30 days) to prevent indefinitely-hanging orders. A scheduled job should periodically mark expired orders (where `deadline < now`) as `expired` to keep the active order set clean and improve keeper query performance.

**Response:**

```typescript
{
  orderHash: string;
  status: "active" | "filled" | "cancelled" | "expired";
  createdAt: string;
}
```

#### GET /orders

**Query Parameters:**

- `status`: Filter by status
- `targetVault`: Filter by vault
- `pricingAsset`: Filter by pricing asset
- `owner`: Filter by owner
- `chainId`: Filter by chain

**Response:**

```typescript
{
  orders: Array<{
    orderHash: string;
    order: LimitBuyOrder;
    permit: PermitDetails;
    status: string;
    createdAt: string;
    filledAt?: string;
    txHash?: string;
  }>;
  pagination: {
    page: number;
    limit: number;
    total: number;
  }
}
```

### Order Database Schema

```sql
CREATE TABLE limit_buy_orders (
  id SERIAL PRIMARY KEY,
  order_hash CHAR(66) UNIQUE NOT NULL,      -- bytes32 as hex
  chain_id INTEGER NOT NULL,

  -- Order details
  owner CHAR(42) NOT NULL,
  target_vault CHAR(42) NOT NULL,
  pricing_asset CHAR(42) NOT NULL,
  min_trigger_price_d18 NUMERIC(78) NOT NULL,
  max_trigger_price_d18 NUMERIC(78) NOT NULL,
  slippage_tolerance_bps INTEGER NOT NULL,

  -- Permit details
  input_token CHAR(42) NOT NULL,
  input_amount NUMERIC(78) NOT NULL,
  nonce NUMERIC(78) NOT NULL,
  deadline BIGINT NOT NULL,

  -- Signature
  signature TEXT NOT NULL,

  -- Status
  status VARCHAR(20) DEFAULT 'active',  -- active, filled, cancelled, expired

  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  filled_at TIMESTAMP,
  tx_hash CHAR(66),

  -- Indexes
  INDEX idx_status (status),
  INDEX idx_owner (owner),
  INDEX idx_pricing_asset (pricing_asset),
  INDEX idx_chain_status (chain_id, status)
);
```

### Keeper Service

The keeper service monitors prices and executes orders when conditions are met.

#### Price Monitoring

```typescript
interface PriceMonitor {
  // Subscribe to price updates for assets with active orders
  subscribePriceFeeds(assets: string[]): void;

  // Called when a new price is received
  onPriceUpdate(asset: string, priceD18: bigint): void;

  // Get current price from PoolFactory.getAssetPrice()
  getCurrentPrice(asset: string): Promise<bigint>;
}
```

#### Execution Logic

```typescript
async function processOrders() {
  // 1. Get all active orders grouped by pricing asset
  const ordersByAsset = await getActiveOrdersByPricingAsset();

  for (const [asset, orders] of ordersByAsset) {
    const currentPrice = await getCurrentPrice(asset);

    // 2. Filter executable orders
    const executableOrders = orders.filter(
      (order) =>
        currentPrice >= order.minTriggerPriceD18 &&
        currentPrice <= order.maxTriggerPriceD18 &&
        order.deadline > Date.now() / 1000,
    );

    if (executableOrders.length === 0) continue;

    // 3. Check if zap is needed and fetch swap data
    for (const order of executableOrders) {
      const depositAssets = await getVaultDepositAssets(order.targetVault);
      const needsZap = !depositAssets.includes(order.inputToken);

      if (needsZap) {
        // Determine destination token (first deposit asset)
        const destToken = depositAssets[0];
        order.zapData = await fetchSwapData(order, destToken);
      }
    }

    // 4. Build batch execution
    const executions = executableOrders.map(buildExecution);

    // 5. Execute on-chain (use fillLimitBuySafeBatch for resilience)
    const tx = await easyLimitBuyManager.fillLimitBuySafeBatch(executions);

    // 6. Process results and update database
    await processExecutionResults(tx, executableOrders);
  }
}
```

#### Swap Data Fetch

For orders requiring zap (input token ≠ deposit asset), keeper fetches swap data at execution time:

```typescript
async function fetchSwapData(order: Order, destToken: string): Promise<ZapData> {
  // Fetch quote from aggregator (e.g., Odos)
  const quote = await odosApi.quote({
    chainId: order.chainId,
    inputTokens: [{ tokenAddress: order.inputToken, amount: order.inputAmount }],
    outputTokens: [{ tokenAddress: destToken, proportion: 1 }],
    userAddr: EASY_LIMIT_BUY_MANAGER_ADDRESS,
    slippageLimitPercent: 5,
  });

  const assembled = await odosApi.assemble({
    userAddr: EASY_LIMIT_BUY_MANAGER_ADDRESS,
    pathId: quote.pathId,
  });

  return {
    aggregatorData: {
      routerKey: ethers.encodeBytes32String("ODOS_V3"),
      swapData: assembled.transaction.data,
    },
    destData: {
      destToken: destToken,
      minDestAmount: (BigInt(quote.outputTokens[0].amount) * 95n) / 100n, // 5% slippage
    },
  };
}
```

#### Error Handling

Listen for `LimitBuyFillFailed` events to handle failures gracefully:

```typescript
easyLimitBuyManager.on("LimitBuyFillFailed", (orderHash, owner, reason) => {
  // Decode reason and decide:
  // - PriceConditionNotMet: Keep order active, retry later
  // - InvalidSignature: Mark invalid, notify user
  // - Expired permit: Mark expired
  // - Insufficient balance: Mark failed, notify user
});
```

---

## Frontend Specification

### Order Creation Flow

```
1. User selects vault
2. User enters order parameters
3. Frontend builds EIP-712 typed data
4. User signs with wallet
5. Frontend submits to Order Book API
6. Frontend shows order in "Active Orders" list
```

### EIP-712 Signing

#### Type Definitions

```typescript
const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

const EIP712_TYPES = {
  PermitWitnessTransferFrom: [
    { name: "permitted", type: "TokenPermissions" },
    { name: "spender", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "witness", type: "LimitBuyOrder" },
  ],
  TokenPermissions: [
    { name: "token", type: "address" },
    { name: "amount", type: "uint256" },
  ],
  LimitBuyOrder: [
    { name: "owner", type: "address" },
    { name: "targetVault", type: "address" },
    { name: "pricingAsset", type: "address" },
    { name: "minTriggerPriceD18", type: "uint256" },
    { name: "maxTriggerPriceD18", type: "uint256" },
    { name: "slippageToleranceBps", type: "uint16" },
  ],
};

const EIP712_DOMAIN = {
  name: "Permit2",
  chainId: CHAIN_ID,
  verifyingContract: PERMIT2_ADDRESS,
};
```

#### Signing Function

```typescript
async function signLimitBuyOrder(params: {
  wallet: Signer;
  inputToken: string;
  inputAmount: bigint;
  targetVault: string;
  pricingAsset: string;
  minTriggerPrice: bigint;
  maxTriggerPrice: bigint;
  slippageBps: number;
  deadline: number;
}): Promise<SignedOrder> {
  // Generate cryptographically random nonce (Permit2 uses random nonces, not sequential).
  // With 2^256 possibilities, collision is virtually impossible.
  // This also provides privacy - observers can't track how many orders a user has created.
  const nonce = BigInt(crypto.randomUUID().replace(/-/g, "").slice(0, 32));

  const limitBuyOrder = {
    owner: await params.wallet.getAddress(),
    targetVault: params.targetVault,
    pricingAsset: params.pricingAsset,
    minTriggerPriceD18: params.minTriggerPrice,
    maxTriggerPriceD18: params.maxTriggerPrice,
    slippageToleranceBps: params.slippageBps,
  };

  const permitMessage = {
    permitted: {
      token: params.inputToken,
      amount: params.inputAmount,
    },
    spender: EASY_LIMIT_BUY_MANAGER_ADDRESS,
    nonce: nonce,
    deadline: BigInt(params.deadline),
    witness: limitBuyOrder,
  };

  const signature = await wallet.signTypedData(EIP712_DOMAIN, EIP712_TYPES, permitMessage);

  return {
    order: limitBuyOrder,
    permit: {
      token: params.inputToken,
      amount: params.inputAmount.toString(),
      nonce: nonce.toString(),
      deadline: params.deadline,
    },
    signature,
  };
}
```

### UI Components

#### Order Form

```
┌─────────────────────────────────────────────────┐
│  Create Limit Buy Order                         │
├─────────────────────────────────────────────────┤
│  Target Vault: [Dropdown - dHEDGE vaults]       │
│                                                 │
│  Input Token:  [Dropdown - USDC, WETH, etc]     │
│  Amount:       [Input - token amount]           │
│                                                 │
│  Pricing Asset: [Dropdown - WBTC, WETH, etc]    │
│                                                 │
│  Order Type:   ○ Buy the Dip                    │
│                ○ Buy the Breakout               │
│                                                 │
│  Trigger Price: $[Input] (current: $X,XXX)      │
│                                                 │
│  Slippage:     [Slider 0.1% - 5%]               │
│                                                 │
│  Expires:      [Dropdown - 1h, 24h, 7d, 30d]    │
│                                                 │
│  [Expected vault tokens: ~XXX tokens]           │
│  [Network fee estimate: ~$X.XX]                 │
│                                                 │
│  [Sign & Submit Order]                          │
└─────────────────────────────────────────────────┘
```

#### Order Type Logic

**Buy the Dip:**

- `minTriggerPriceD18 = 0`
- `maxTriggerPriceD18 = userInputPrice`
- Executes when price drops TO or BELOW the user's target

**Buy the Breakout:**

- `minTriggerPriceD18 = userInputPrice`
- `maxTriggerPriceD18 = type(uint256).max`
- Executes when price rises TO or ABOVE the user's target

#### Active Orders View

```
┌─────────────────────────────────────────────────────────────────────┐
│  My Limit Orders                                                    │
├──────────┬──────────┬───────────┬─────────────┬────────────┬────────┤
│  Vault   │  Amount  │  Trigger  │  Expires    │  Status    │ Action │
├──────────┼──────────┼───────────┼─────────────┼────────────┼────────┤
│  USDy    │  1000    │  BTC<80k  │  in 6h 23m  │  ● Active  │ Cancel │
│          │  USDC    │           │             │            │        │
├──────────┼──────────┼───────────┼─────────────┼────────────┼────────┤
│  ETHy    │  0.5     │  ETH>4k   │  in 2d 4h   │  ● Active  │ Cancel │
│          │  WETH    │           │             │            │        │
├──────────┼──────────┼───────────┼─────────────┼────────────┼────────┤
│  USDy    │  500     │  BTC<75k  │  4h ago     │  ✓ Filled  │ View   │
│          │  USDC    │           │             │            │        │
└──────────┴──────────┴───────────┴─────────────┴────────────┴────────┘
```

### Order Cancellation

Users can cancel orders by:

1. **Soft cancel**: API DELETE request marks order inactive (keeper won't execute)
2. **Hard cancel**: Revoke Permit2 approval (on-chain protection)
3. **Nonce invalidation**: Call Permit2's `invalidateUnorderedNonces()` (advanced)

```typescript
// Soft cancel (API)
await api.delete(`/orders/${orderHash}`);

// Hard cancel (revoke approval - prevents ALL pending orders for that token)
await inputToken.approve(PERMIT2_ADDRESS, 0);

// Selective cancel (invalidate specific nonce)
const wordPos = nonce >> 8n;
const bitPos = nonce & 0xffn;
await permit2.invalidateUnorderedNonces(wordPos, 1n << bitPos);
```

---

## Contract Addresses

| Chain    | EasyLimitBuyManager | Permit2                                    |
| -------- | ------------------- | ------------------------------------------ |
| Ethereum | TBD                 | 0x000000000022D473030F116dDEE9F6B43aC78BA3 |
| Arbitrum | TBD                 | 0x000000000022D473030F116dDEE9F6B43aC78BA3 |
| Optimism | TBD                 | 0x000000000022D473030F116dDEE9F6B43aC78BA3 |
| Base     | TBD                 | 0x000000000022D473030F116dDEE9F6B43aC78BA3 |
| Polygon  | TBD                 | 0x000000000022D473030F116dDEE9F6B43aC78BA3 |

---

## Security Considerations

### Backend

- Validate all signatures before storing
- Rate limit order submissions per address
- Monitor for suspicious patterns (many orders with same nonce)
- Store signatures securely (they authorize fund transfers)

### Keeper

- Use private mempool or flashbots to prevent frontrunning
- Implement gas price limits
- Handle reorgs gracefully
- Monitor for Permit2 nonce invalidations

### Frontend

- Clear display of what user is signing
- Show current vs trigger price clearly
- Warn if slippage is high
- Confirm large amounts

---

## Events to Index

```solidity
event LimitBuyFilled(
  bytes32 indexed orderHash,
  address indexed user,
  address indexed targetVault,
  address inputToken,
  uint256 inputAmount,
  uint256 vaultTokensReceived
);

event LimitBuyFillFailed(bytes32 indexed orderHash, address indexed owner, bytes reason);
```

Backend should index these events to update order status and notify users.

---

## Testing Checklist

### Backend

- [ ] Order submission with valid signature
- [ ] Order submission with invalid signature (reject)
- [ ] Order retrieval by orderHash, user, status
- [ ] Order cancellation
- [ ] Duplicate nonce rejection
- [ ] Expired order handling

### Keeper

- [ ] Execute order when price condition met
- [ ] Skip order when price condition not met
- [ ] Handle failed executions gracefully
- [ ] Batch multiple orders efficiently
- [ ] Refresh zap data before execution

### Frontend

- [ ] EIP-712 signature generation
- [ ] Correct type hash computation
- [ ] Order form validation
- [ ] Display active orders
- [ ] Cancel order flow
- [ ] Zap flow when input ≠ deposit asset

### Integration

- [ ] Full flow: sign → submit → execute → verify vault tokens received
- [ ] Cancellation prevents execution
- [ ] Expired permit prevents execution
- [ ] Price boundary edge cases
