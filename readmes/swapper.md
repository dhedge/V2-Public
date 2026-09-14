# Swapper

The Swapper is the router-whitelisting swap contract used by EasySwapperV2, WithdrawalVault and EasyLimitBuyManager
(PoolLimitOrderManager reaches it through EasySwapperV2). `EasySwapperV2ContractGuard` and the guards implementing
`ISwapDataConsumingGuard` decode its swap structs to validate manager-supplied swap data. It takes ready-made aggregator
calldata, forwards it to a whitelisted router, refunds unspent input, enforces `minDestAmount` on its own balance delta
and pays `msg.sender`.

It was moved here from the flatcoin-v1 repository, which now only keeps the pieces FlatZapper inherits
(`TokenTransferMethods`, `SwapperStructs`, `ISwapper`). This repository is the source of truth for the contract and its
upgrades.

- Source: `contracts/swappers/swapper/` (Solidity 0.8.28, OpenZeppelin v5, ERC-7201 namespaced storage).
- 0.7.6 consumers use `contracts/interfaces/flatMoney/swapper/ISwapper.sol`, which mirrors the ABI with the structs
  nested in the interface.
- Tests: `test/integration/ffi/common/swapper/`, run with `pnpm test:ffi` (Base fork, see below).

## Deployments

The proxy and its ProxyAdmin have the same address on every chain (Ethereum, Optimism, Arbitrum, Polygon, Base, HyperEVM
and Plasma):

| Contract   | Address                                      |
| ---------- | -------------------------------------------- |
| Proxy      | `0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D` |
| ProxyAdmin | `0xAB201cBa56F6061d18C38EF62e1d644234a846bF` |

The Swapper owner (`addRouter`, `removeRouter`, `rescueFunds`, `setWrappedNativeToken`) and the ProxyAdmin owner (which
executes upgrades) are both the chain's dHEDGE DAO Safe. Ownership was verified on-chain on 2026-09-11 at 03:07 UTC:

| Chain    | Swapper owner                                | ProxyAdmin owner |
| -------- | -------------------------------------------- | ---------------- |
| Ethereum | `0x5a76f841bFe5182f04bf511fC0Ecf88C27189FCB` | same             |
| Optimism | `0x90b1a66957914EbbE7a8df254c0c1E455972379C` | same             |
| Arbitrum | `0x13471A221D6A346556723842A1526C603Dc4d36B` | same             |
| Polygon  | `0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4` | same             |
| Base     | `0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100` | same             |
| HyperEVM | `0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100` | same             |
| Plasma   | `0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100` | same             |

Every chain runs the implementation built from this repository; its address is recorded as `Swapper` in
`publish/<chain>/prod/versions.json`. Compared with the original flatcoin-v1 deployment it refunds unspent source tokens
to the caller and tops the router allowance up to the maximum instead of increasing it by the maximum, which reverted
whenever any allowance remained.

## Supported routers

Routers are whitelisted per chain by the Swapper owner via `addRouter(bytes32 routerKey, address router)`. To list every
router ever added, filter the contract logs for the `RouterAdded` event
(`0x64f648ff7e0f6e86ecb0b40dbf60a10fbb6bcc7ef4be78027cd91bf57c22c485`).

| Router key      | Router address                               | Chains                                                        |
| --------------- | -------------------------------------------- | ------------------------------------------------------------- |
| `ONE_INCH`      | `0x111111125421cA6dc452d289314280a0f8842A65` | Ethereum, Optimism, Arbitrum, Polygon, Base                   |
| `PARASWAP_V6`   | `0x6A000F20005980200259B80c5102003040001068` | Ethereum, Optimism, Arbitrum, Polygon, Base                   |
| `KYBER_SWAP_V2` | `0x6131B5fae19EA4f9D964eAc0408E4408b66337b5` | Ethereum, Optimism, Arbitrum, Polygon, Base, HyperEVM, Plasma |

HyperEVM and Plasma only have KyberSwap whitelisted. Router state was verified on-chain with `getRouter` on 2026-09-10.

`RouterProcessor` keeps a special case for the legacy Paraswap v5 router: when the router key is exactly `PARASWAP`, the
input approval goes to the router's `TokenTransferProxy` (resolved via `getTokenTransferProxy()`) instead of the router.
The production key is `PARASWAP_V6`, whose router pulls tokens itself, so this path is not taken on any chain.

## Using `swap(InOutData)`

`InOutData` groups the source tokens by transfer method (`srcData`) and names one destination token with a minimum
amount (`destData`). Every source token carries its own aggregator calldata (`routerKey` + `swapData`), so one call can
route USDC through 1inch and DAI through Paraswap into rETH.

```solidity
struct InOutData {
  SrcData[] srcData; // one entry per transfer method used
  DestData destData; // { IERC20 destToken; uint256 minDestAmount; }
}

struct SrcData {
  SrcTokenSwapDetails[] srcTokenSwapDetails; // { IERC20 token; uint256 amount; AggregatorData { bytes32 routerKey; bytes swapData; } }
  TransferMethodData transferMethodData; // { TransferMethod method; bytes methodData; }
}
```

- `ALLOWANCE`: the caller has approved the Swapper, `methodData` is empty.
- `PERMIT2`: `methodData` is an ABI-encoded `Permit2EncodedData` whose `encodedData` is a `Permit2SingleTransfer` or
  `Permit2BatchTransfer` (see `SwapperStructs.sol`). The Swapper checks the received amounts match the swap data.
- `NATIVE`: exactly one source entry for the wrapped native token; `msg.value` must equal its `amount` and is wrapped.
  Sending value without a `NATIVE` entry reverts.
- The aggregator calldata must be quoted with the Swapper as the sender and receiver of the swap.
- `minDestAmount` is the caller's slippage protection and is checked on the Swapper's balance delta, so tokens sent to the
  contract by third parties are never counted (and can be recovered with `rescueFunds`).

## Upgrading

The Swapper is upgraded with the standard Hardhat upgrade task (see [upgrades.md](./upgrades.md)) through the `swapper`
job:

```bash
# dry run: compiles, validates the storage layout and prints the ProxyAdmin it would use
pnpm hardhat upgrade --network base --swapper true

# deploys and verifies the new implementation, then proposes ProxyAdmin.upgradeAndCall from the protocol DAO Safe
pnpm hardhat upgrade --network base --execute true --swapper true
```

The job differs from the other upgrade jobs in one way: the upgrade targets the Swapper's dedicated ProxyAdmin
(OpenZeppelin v5, so `upgradeAndCall`) instead of the protocol's shared ProxyAdmin. The job reads the ProxyAdmin address
from the proxy and proposes from the protocol DAO Safe, which owns it on every chain just like the shared ProxyAdmin.
The proxy and its implementations are tracked in the OpenZeppelin manifests (`.openzeppelin/<network>.json`) like every
other proxy.

## Tests

`test/integration/ffi/common/swapper/` holds the chain-agnostic integration tests imported from flatcoin-v1, trimmed to
the routers enabled in production: 1inch v6, Paraswap v6 and KyberSwap v2. Following the repo's test layout, the shared
setup takes a `ChainConfig` (fork alias and block, test tokens and their Chainlink feeds) through its constructor and
the API helper builds aggregator URLs from the forked chain id, so a per-chain entry file only supplies those values.
The only entry today is `test/integration/ffi/8453/swapper/SwapperTest_FFI_Base.t.sol`.

The tests deploy a fresh Swapper on the fork and swap through the routers using the committed swapdata cache in
`swapdatas-cache/swapper/<chainId>.json`, so no API keys are needed. The cache is bound to the fork block and to the
Swapper proxy address that results from `admin` deploying the ProxyAdmin, implementation and proxy in that order.
Entries are keyed by fork block, so changing tokens, amounts or the block makes the tests refetch the missing entries,
which needs `ONE_INCH_API_KEY` set (Paraswap and KyberSwap need no key). Populate the cache with `--threads 1` right
after bumping the fork block in the entry file to the latest block: the aggregators quote against live state, so an
older fork misses the 1% slippage bound, and parallel tests rewrite the whole cache file and lose each other's entries.
