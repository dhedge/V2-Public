# Oracle Liveness Check

## Purpose

Minimizes oracle price front-running on deposits. When enabled for an asset, deposits revert if that asset's oracle price is older than the configured threshold.

Useful for volatile-asset vaults where a stale oracle price could let an attacker deposit at an outdated price ahead of an expected price movement.

## Configuration

Freshness is configured **per asset** via `assetMaxPriceAge` in `AssetHandler`:

```solidity
assetHandler.setAssetMaxPriceAge(asset, 60); // 60 seconds
```

- `0` (default) disables the check for that asset.
- A positive value enables it: the asset's price must be no older than that many seconds.

There is no minimum or maximum bound on the value.

## Where it's enforced

- **Deposits** (`PoolLogic`): `totalFundValueWithMaxAge` checks every supported asset; reverts `dh37` if any flagged asset's price is stale.
- **EasySwapperV2 DYTM withdrawals**: checks the withdrawal output asset only; reverts `stale outputAsset price`.

Not enforced on standard `PoolLogic` withdrawals or on `tokenPrice` calculations.

## Example

Pool holds an ETH leveraged position, with `assetMaxPriceAge` set to `60` seconds for ETH only:

| Position | Description              | Oracle Timestamp | assetMaxPriceAge |
| -------- | ------------------------ | ---------------- | ---------------- |
| Aave     | Lends WETH, borrows USDC | T-0 (current)    | 0 (not set)      |
| USDC     | Stablecoin               | T-30 minutes     | 0 (not set)      |
| ETH      | Volatile asset           | T-5 minutes      | 60 seconds       |

**Deposit reverts with `dh37`** — only ETH has `assetMaxPriceAge` set, and its price (300s old) exceeds the 60s threshold. The Aave and USDC timestamps are ignored.

The depositor must refresh the ETH oracle price before depositing. In practice, bundle an oracle update (e.g. Pyth `updatePriceFeeds`) with the deposit in a single multicall.
