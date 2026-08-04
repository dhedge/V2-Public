# Chamber

Chamber (formerly dHEDGE) is an onchain platform for vault-based asset management, deployed across multiple EVM chains. A single vault can hold tokenized stocks, commodities and crypto, so a manager can run one strategy across all of them against a transparent, verifiable track record.

This repository contains the protocol's smart contracts.

**Non-custodial.** Depositors retain ownership of their funds at all times; a vault manager can direct capital but never withdraw it.

**Onchain guardrails.** The Guard System bounds what a manager may do with depositor capital, protocol by protocol and asset by asset.

**Permissionless.** Anyone can create a vault, manage a strategy, or deposit into one, without gatekeepers.

> **Note on naming.** The rebrand from dHEDGE to Chamber changed the name and positioning only. Vault addresses, share tokens, the DHT token and all contract APIs are unchanged, so the code, deployment configs and repository paths in this repo continue to use the `dHEDGE`/`dhedge` naming.

This repository is under active development.

## Documentation

- [Chamber Docs](https://docs.chamberfi.com) — protocol, integration and manager documentation
- [`./readmes/`](./readmes/) — technical notes on the contracts in this repository

## Links

| Resource   | Link                                             |
| ---------- | ------------------------------------------------ |
| App        | [chamberfi.com](https://chamberfi.com)           |
| X          | [@chamberfi](https://x.com/chamberfi)            |
| Discord    | [discord.gg/BAWTbRA](https://discord.gg/BAWTbRA) |
| Bug bounty | [Immunefi](https://immunefi.com/bounty/dhedge)   |
