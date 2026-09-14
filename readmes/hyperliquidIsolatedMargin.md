# Hyperliquid HIP-3 Isolated Margin Support

Status: research / not implemented. Current integration supports cross-margin perps only — `setApprovedAssets` rejects `onlyIsolated` HIP-3 assets (`HyperliquidCoreWriterContractGuard.sol`).

> **Update:** CoreWriter action 9 (register an API wallet / agent) is now whitelisted in
> `HyperliquidCoreWriterContractGuard`, gated per-pool by the Factory Owner via the
> `apiWalletEnabled` flag (`setApiWalletEnabled`, `onlyOwner`). The manager may register **any**
> agent address (no on-chain pinning).
>
> This is intended for specialised **private** vaults where on-chain accounting accuracy is not
> required: once the registered agent trades assets the valuation guards don't model, the pool's NAV
> drifts. **Asset security is preserved** — a Hyperliquid agent can only sign L1 trading actions;
> fund-moving actions (`withdraw3`, `usdSend`, `spotSend`, `approveAgent`) are user-signed and require
> the master account (the PoolLogic), so a compromised agent cannot withdraw or transfer assets out.
> Worst case is trading losses, not theft. **Caveat:** disabling the flag only blocks future
> registrations; it does not revoke an agent already registered on HyperCore (agents persist until
> overwritten or until the ~180-day expiry).
>
> This delivers an equivalent capability to the "dHEDGE-operated margin-only agent" idea below, but
> without an on-chain pin or a dHEDGE-run signing service — restriction lives in the per-pool opt-in
> and the private-vault context, not in key custody.

## The problem

Pools interact with HyperCore exclusively through the CoreWriter system contract (`0x3333...3333`), validated by `HyperliquidCoreWriterContractGuard`. CoreWriter exposes a fixed set of actions (limit order, cancels, spot send, usd class transfer, send asset, etc.) and **none of them can**:

- set leverage (`updateLeverage`)
- set cross/isolated margin mode
- add/remove margin on a live isolated position (`updateIsolatedMargin` / `topUpIsolatedOnlyMargin`)

These exist only as off-chain L1 exchange actions, signed by the account key or an approved API agent — neither of which a pool contract has. The limit order action carries no leverage field; orders open at whatever leverage is standing on the account.

### What this means for isolated positions via CoreWriter only

- Positions open at the account's standing leverage (default for a never-configured account is **undocumented** — must be verified on testnet; the local simulator reverts on unset leverage, which would make guard-only isolated unusable).
- Margin is fixed at open (`notional / leverage`). No top-up to defend liquidation price.
- De-risking is limited to reduce-only trims (which do move the liq price in higher margin tiers) and unrealized PnL (auto-applied as isolated margin).
- Loss is capped at the position's isolated margin; cross margin and other positions are untouched on liquidation (verified against HL docs).
- Transfer actions (7 / 13 / 6) only reach account-level balances (spot or a dex's cross/free balance). No CoreWriter parameter — including `subAccount` or dex IDs — can reach inside a position's isolated silo. Subaccounts can't be created or traded via CoreWriter either.

## Potential solution: dHEDGE-operated margin-only agent

Hyperliquid agents (API wallets) can sign `updateLeverage` / `updateIsolatedMargin`, and CoreWriter action 9 can register one on-chain. But **agents cannot be scoped at the protocol level** — an approved agent can sign the full trading action set, including `vaultTransfer` to an arbitrary HL vault. So the restriction must live in key custody, not on Hyperliquid:

1. Guard whitelists CoreWriter action 9, pinned to a single dHEDGE-controlled agent address (managers cannot register their own).
2. dHEDGE runs a signing service (HSM/MPC/TEE) holding the agent key. It exposes only: set leverage, add isolated margin, top-up. It refuses orders, margin removal, transfers.
3. All trading stays on the existing guarded CoreWriter path (slippage/oracle/asset checks intact).

Why this set is safe to delegate: these actions only reconfigure margin **within the pool's own account** — they cannot move funds out or place trades. Honest-service worst case is a mis-set risk parameter.

Trade-offs:

- Reintroduces a trusted off-chain signer. Policy is enforced by dHEDGE, not the protocol — a key/service **compromise** yields a full-power agent (can trade, `vaultTransfer`). Key custody is the real security boundary.
- Ops: per-pool agent registration, rotation before the ~180-day agent expiry, monitoring.

### Alternative (no trusted signer)

Whitelist only isolated markets with conservative deployer-set `maxLeverage` (readable via `perpAssetInfo`), accept fixed-at-open margin with trim-only de-risking. "Leverage choice" = listing the same underlying across markets with different caps.

## Required regardless of approach: NAV fix

`HyperliquidPositionGuard.getBalance` values perps via `accountMarginSummary` (precompile `0x80F`), which **excludes isolated positions**. Isolated equity lives in per-position `isolatedRawUsd` via the position precompile (`0x802`), which the guard never reads. Without iterating approved assets and adding isolated equity (and fixing `removeAssetCheck`), isolated positions are invisible to NAV — share mispricing and removal-check bypass.

## Open items

1. Testnet probe: does an isolated HIP-3 position open via bare CoreWriter order with no prior leverage config, and at what leverage? (Make-or-break for the no-agent path.)
2. Confirm with HL team there is no native agent scoping.
3. Confirm agent-signed `vaultTransfer` accepts arbitrary destination vaults (blast-radius assumption).
