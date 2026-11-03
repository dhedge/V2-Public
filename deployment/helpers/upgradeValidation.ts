import { ValidationOptions } from "@openzeppelin/upgrades-core";

/**
 * Validation kinds acknowledged for the 0.7.6 proxies built on OpenZeppelin 3.4 upgradeable.
 * upgrades-core checks that an initializer calls every parent initializer. The 3.4 `__X_init`
 * functions reach ContextUpgradeable only through the empty `__Context_init_unchained`, which the
 * check does not count, so every 3.4-based contract, ERC20Upgradeable and ERC721Upgradeable
 * included, is reported as missing that call. Non-abstract bases that leave initialisation to the
 * deriving contract (ProxyFactory, DhedgeStakingV2Storage, VaultProxyFactory) are reported as
 * having no initializer. Both are harmless here: `__Context_init` sets no state, and each of those
 * bases is initialised by the deriving contract's `initializer` function.
 */
export const OZ_V3_INITIALIZER_KINDS: NonNullable<ValidationOptions["unsafeAllow"]> = [
  "missing-initializer",
  "missing-initializer-call",
];
